"""
train_dpo.py — Fine-tune TinyLlama-1.1B with Direct Preference Optimization (DPO).

Usage:
    python scripts/train_dpo.py --dataset data/dataset_small.json  --output checkpoints/small
    python scripts/train_dpo.py --dataset data/dataset_medium.json --output checkpoints/medium
    python scripts/train_dpo.py --dataset data/dataset_large.json  --output checkpoints/large

Requirements: transformers, trl, peft, bitsandbytes, datasets, torch
See requirements.txt for pinned versions tested with the TRL APIs used here.

Hardware: tested on single GPU with >=16GB VRAM.
If OOM with DPO, try --gradient_accumulation_steps 4 or --per_device_train_batch_size 1.
Fallback: if DPO still OOM, use --use_sft flag to switch to supervised fine-tuning on chosen only.
"""

import argparse
import json
import os
from pathlib import Path

import torch
from datasets import Dataset
from peft import LoraConfig, get_peft_model, prepare_model_for_kbit_training
from transformers import (
    AutoModelForCausalLM,
    AutoTokenizer,
    BitsAndBytesConfig,
    TrainingArguments,
)


BASE_MODEL = "TinyLlama/TinyLlama-1.1B-Chat-v1.0"

SYSTEM_PROMPT = (
    "You are a legal assistant specializing in U.S. federal tax law. "
    "Answer questions about dependency status under 26 U.S.C. § 152(a)-(d) "
    "with accurate legal reasoning."
)


def format_prompt(example: dict, tokenizer) -> dict:
    """
    Convert a preference example into TinyLlama chat format.
    Returns the prompt plus chosen/rejected completions in DPOTrainer format.
    """
    user_msg = example["prompt"]

    prompt_text = tokenizer.apply_chat_template(
        [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_msg},
        ],
        tokenize=False,
        add_generation_prompt=True,
    )

    # DPOTrainer expects: prompt = context, chosen/rejected = completions only.
    # It internally concatenates prompt+completion to compute the loss.
    # Do NOT include prompt_text in chosen/rejected or it will be seen twice.
    return {
        "prompt": prompt_text,
        "chosen": example["chosen"] + tokenizer.eos_token,
        "rejected": example["rejected"] + tokenizer.eos_token,
    }


def load_dataset_from_json(path: str, tokenizer) -> Dataset:
    with open(path) as f:
        raw = json.load(f)

    formatted = [format_prompt(ex, tokenizer) for ex in raw]
    return Dataset.from_list(formatted)


def build_lora_config() -> LoraConfig:
    return LoraConfig(
        r=16,
        lora_alpha=32,
        target_modules=["q_proj", "v_proj", "k_proj", "o_proj"],
        lora_dropout=0.05,
        bias="none",
        task_type="CAUSAL_LM",
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", required=True, help="Path to JSON dataset file")
    parser.add_argument("--output", required=True, help="Directory to save checkpoint")
    parser.add_argument("--model", default=BASE_MODEL, help="Base model name or path")
    parser.add_argument("--epochs", type=int, default=5)
    parser.add_argument("--lr", type=float, default=5e-5)
    parser.add_argument("--beta", type=float, default=0.1, help="DPO beta parameter")
    parser.add_argument("--per_device_train_batch_size", type=int, default=2)
    parser.add_argument("--gradient_accumulation_steps", type=int, default=4)
    parser.add_argument("--max_length", type=int, default=512)
    parser.add_argument("--use_sft", action="store_true",
                        help="Fallback: use SFT on chosen only instead of DPO")
    args = parser.parse_args()

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Loading base model: {args.model}")
    bnb_config = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_use_double_quant=True,
        bnb_4bit_quant_type="nf4",
        bnb_4bit_compute_dtype=torch.bfloat16,
    )

    tokenizer = AutoTokenizer.from_pretrained(args.model, use_fast=True)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token
    tokenizer.padding_side = "left"

    model = AutoModelForCausalLM.from_pretrained(
        args.model,
        quantization_config=bnb_config,
        device_map="auto",
        torch_dtype=torch.bfloat16,
    )
    model = prepare_model_for_kbit_training(model)
    model = get_peft_model(model, build_lora_config())
    model.print_trainable_parameters()

    print(f"Loading dataset: {args.dataset}")
    dataset = load_dataset_from_json(args.dataset, tokenizer)
    print(f"Dataset size: {len(dataset)} examples")

    if args.use_sft:
        from trl import SFTTrainer

        print("Using SFT mode (chosen only).")
        # SFT needs full prompt+completion string (unlike DPO which separates them).
        sft_dataset = Dataset.from_list([
            {"text": ex["prompt"] + ex["chosen"]} for ex in dataset
        ])
        training_args = TrainingArguments(
            output_dir=str(output_dir),
            num_train_epochs=args.epochs,
            per_device_train_batch_size=args.per_device_train_batch_size,
            gradient_accumulation_steps=args.gradient_accumulation_steps,
            learning_rate=args.lr,
            bf16=True,
            logging_steps=10,
            save_strategy="epoch",
            report_to="none",
            gradient_checkpointing=True,
        )
        trainer = SFTTrainer(
            model=model,
            tokenizer=tokenizer,
            train_dataset=sft_dataset,
            args=training_args,
            dataset_text_field="text",
            max_seq_length=args.max_length,
        )
    else:
        from trl import DPOTrainer
        try:
            from trl import DPOConfig
        except ImportError as exc:
            raise ImportError(
                "This TRL version does not expose DPOConfig. "
                "Use --use_sft or install a compatible TRL release."
            ) from exc

        print("Using DPO mode.")
        dpo_config = DPOConfig(
            beta=args.beta,
            output_dir=str(output_dir),
            num_train_epochs=args.epochs,
            per_device_train_batch_size=args.per_device_train_batch_size,
            gradient_accumulation_steps=args.gradient_accumulation_steps,
            learning_rate=args.lr,
            bf16=True,
            logging_steps=10,
            save_strategy="epoch",
            report_to="none",
            gradient_checkpointing=True,
            max_length=args.max_length,
            max_prompt_length=256,
            remove_unused_columns=False,
        )
        trainer = DPOTrainer(
            model=model,
            ref_model=None,       # None → use the initial frozen copy as reference
            processing_class=tokenizer,
            train_dataset=dataset,
            args=dpo_config,
        )

    print("Starting training...")
    trainer.train()

    print(f"Saving final checkpoint to {output_dir}")
    trainer.save_model(str(output_dir))
    tokenizer.save_pretrained(str(output_dir))
    print("Done.")


if __name__ == "__main__":
    main()
