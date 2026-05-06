"""
evaluate.py — Run fine-tuned models on the 6 evaluation fact patterns.

Usage:
    python scripts/evaluate.py --checkpoint checkpoints/small  --model_size small
    python scripts/evaluate.py --checkpoint checkpoints/medium --model_size medium
    python scripts/evaluate.py --checkpoint checkpoints/large  --model_size large

Outputs:
    results/raw_outputs_{model_size}.jsonl  — one JSON record per case
    results/summary_table_{model_size}.txt  — formatted summary table

Decoding is deterministic: do_sample=False, greedy decoding.
"""

import argparse
import json
import re
import os
from pathlib import Path

import torch
from peft import PeftModel
from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig


SYSTEM_PROMPT = (
    "You are a legal assistant specializing in U.S. federal tax law. "
    "Answer questions about dependency status under 26 U.S.C. § 152(a)-(d) "
    "with accurate legal reasoning."
)

FACT_PATTERNS = [
    {
        "case_id": "case1_alex",
        "prompt": (
            "Alex is 17 years old, lives with his aunt full-time, and his aunt pays all of his "
            "living expenses. His parents live in a different state and provide no financial support. "
            "Does Alex qualify as a dependent under 26 U.S.C. § 152(a)-(d)? "
            "Begin your response with exactly 'Answer: Yes' or 'Answer: No', then explain your reasoning."
        ),
        "smt_verdict": "Yes",
    },
    {
        "case_id": "case2_maria",
        "prompt": (
            "Maria is a 25-year-old graduate student who lives in university housing. Her parents "
            "pay her tuition but she covers all other living expenses through a graduate stipend. "
            "Does Maria qualify as a dependent under 26 U.S.C. § 152(a)-(d)? "
            "Begin your response with exactly 'Answer: Yes' or 'Answer: No', then explain your reasoning."
        ),
        "smt_verdict": "No",
    },
    {
        "case_id": "case3_james",
        "prompt": (
            "James is 15 years old and lives with his parents during the school year, but spends "
            "summers with his grandparents. His parents claim him on their taxes and provide all "
            "of his financial support. Does James qualify as a dependent under 26 U.S.C. § 152(a)-(d)? "
            "Begin your response with exactly 'Answer: Yes' or 'Answer: No', then explain your reasoning."
        ),
        "smt_verdict": "Yes",
    },
    {
        "case_id": "case4_linda",
        "prompt": (
            "Linda is 45 years old, lives with her adult daughter, and earned $5,000 this year "
            "from part-time work. Her daughter provides more than half of Linda's total support "
            "for the year. Does Linda qualify as a dependent under 26 U.S.C. § 152(a)-(d)? "
            "Begin your response with exactly 'Answer: Yes' or 'Answer: No', then explain your reasoning."
        ),
        "smt_verdict": "No",
    },
    {
        "case_id": "case5_carlos",
        "prompt": (
            "Carlos is a 19-year-old who dropped out of college after one semester. He lives with "
            "his parents, works part-time earning $8,000 per year, but his parents still provide "
            "the majority of his financial support. Does Carlos qualify as a dependent under "
            "26 U.S.C. § 152(a)-(d)? Begin your response with exactly 'Answer: Yes' or 'Answer: No', then explain your reasoning."
        ),
        "smt_verdict": "No",
    },
    {
        "case_id": "case6_sophie",
        "prompt": (
            "Sophie is 16 years old, lives with a foster family, and has no contact with her "
            "biological parents. The foster family provides all of her financial support. "
            "Does Sophie qualify as a dependent under 26 U.S.C. § 152(a)-(d)? "
            "Begin your response with exactly 'Answer: Yes' or 'Answer: No', then explain your reasoning."
        ),
        "smt_verdict": "Yes",
    },
]


def parse_label(raw_output: str) -> str:
    """
    Extract Yes/No from model output.
    Primary: look for structured 'Answer: Yes' or 'Answer: No' at the start.
    Fallback: look for yes/no as the very first word.
    Returns 'Yes', 'No', or 'Unclear'.
    """
    text = raw_output.strip()
    # Primary: structured answer token
    m = re.match(r'^\s*Answer\s*:\s*(Yes|No)\b', text, re.IGNORECASE)
    if m:
        return m.group(1).capitalize()
    # Fallback: first word of response
    first_word = text.split()[0].lower().rstrip(".,;:") if text.split() else ""
    if first_word == "yes":
        return "Yes"
    if first_word == "no":
        return "No"
    # Some model outputs ignore the requested "Answer:" prefix but clearly state
    # the legal conclusion in the first sentence.
    first_sentence = re.split(r'[.!?]\s+', text, maxsplit=1)[0].lower()
    yes_patterns = [
        r'\bqualif(?:y|ies)\s+as\s+(?:a\s+)?dependent\b',
        r'\bis\s+(?:a\s+)?(?:legal\s+)?dependent\b',
        r'\bmeets\s+the\s+requirements\b',
    ]
    no_patterns = [
        r'\bdoes\s+not\s+qualif(?:y|ies)\b',
        r'\bnot\s+(?:a\s+)?(?:legal\s+)?dependent\b',
        r'\bfails?\s+(?:the\s+)?requirements\b',
    ]
    if any(re.search(p, first_sentence) for p in no_patterns):
        return "No"
    if any(re.search(p, first_sentence) for p in yes_patterns):
        return "Yes"
    return "Unclear"


def determine_status(parsed_label: str, smt_verdict: str) -> str:
    """Map (model label, smt verdict) to Correct / Error / Ambiguous."""
    if smt_verdict == "Ambiguous" or parsed_label == "Unclear":
        return "Ambiguous"
    if parsed_label == smt_verdict:
        return "Correct"
    return "Error"


def load_model(checkpoint_dir: str):
    """Load fine-tuned PEFT model + tokenizer from checkpoint directory."""
    print(f"  Loading tokenizer...", flush=True)
    tokenizer = AutoTokenizer.from_pretrained(checkpoint_dir, use_fast=True)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    print(f"  Loading base model in bf16 (no quantization)...", flush=True)
    base_model_id = "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
    base_model = AutoModelForCausalLM.from_pretrained(
        base_model_id,
        torch_dtype=torch.bfloat16,
        device_map="cuda:0",
    )
    print(f"  Loading PEFT adapter...", flush=True)
    model = PeftModel.from_pretrained(base_model, checkpoint_dir)
    model.eval()
    print(f"  Model ready.", flush=True)
    return model, tokenizer


def run_inference(model, tokenizer, prompt_text: str, max_new_tokens: int = 300) -> str:
    """Run deterministic greedy decoding."""
    chat = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": prompt_text},
    ]
    input_text = tokenizer.apply_chat_template(
        chat, tokenize=False, add_generation_prompt=True
    )
    inputs = tokenizer(input_text, return_tensors="pt").to(model.device)

    with torch.no_grad():
        output_ids = model.generate(
            **inputs,
            do_sample=False,        # deterministic greedy decoding
            temperature=1.0,        # ignored when do_sample=False; set for clarity
            max_new_tokens=max_new_tokens,
            pad_token_id=tokenizer.pad_token_id,
        )

    # Decode only the newly generated tokens
    new_tokens = output_ids[0][inputs["input_ids"].shape[1]:]
    return tokenizer.decode(new_tokens, skip_special_tokens=True).strip()


def format_summary_table(records: list, model_size: str) -> str:
    lines = [
        f"Summary Table — Model Size: {model_size}",
        "=" * 70,
        f"{'Fact Pattern':<20} {'Model Output':<15} {'SMT Verdict':<15} {'Status'}",
        "-" * 70,
    ]
    for r in records:
        lines.append(
            f"{r['case_id']:<20} {r['parsed_label']:<15} {r['smt_verdict']:<15} {r['status']}"
        )
    correct = sum(1 for r in records if r["status"] == "Correct")
    lines += ["-" * 70, f"Correct: {correct}/{len(records)}"]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", required=True, help="Path to fine-tuned checkpoint")
    parser.add_argument("--model_size", required=True,
                        choices=["small", "medium", "large"],
                        help="Which model size this checkpoint corresponds to")
    parser.add_argument("--max_new_tokens", type=int, default=300)
    args = parser.parse_args()

    project_root = Path(__file__).resolve().parent.parent
    results_dir = project_root / "results"
    results_dir.mkdir(exist_ok=True)

    # Load SMT verdicts if available
    smt_path = results_dir / "smt_verdicts.json"
    smt_verdicts = {}
    if smt_path.exists():
        with open(smt_path) as f:
            for entry in json.load(f):
                smt_verdicts[entry["case_id"]] = entry["smt_verdict"]

    print(f"Loading model from: {args.checkpoint}")
    model, tokenizer = load_model(args.checkpoint)

    records = []
    print(f"\nRunning evaluation (model_size={args.model_size})...")
    for case in FACT_PATTERNS:
        print(f"  [{case['case_id']}]", end=" ", flush=True)
        raw = run_inference(model, tokenizer, case["prompt"], args.max_new_tokens)
        parsed = parse_label(raw)
        # Use live SMT verdict if available, else use preloaded default
        smt_v = smt_verdicts.get(case["case_id"], case["smt_verdict"])
        status = determine_status(parsed, smt_v)
        print(f"→ {parsed} | SMT: {smt_v} | {status}")

        records.append({
            "model_size": args.model_size,
            "case_id": case["case_id"],
            "prompt": case["prompt"],
            "raw_output": raw,
            "parsed_label": parsed,
            "smt_verdict": smt_v,
            "status": status,
        })

    # Save raw outputs
    raw_out = results_dir / f"raw_outputs_{args.model_size}.jsonl"
    with open(raw_out, "w") as f:
        for r in records:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"\nRaw outputs saved to {raw_out}")

    # Save summary table for this model size
    table = format_summary_table(records, args.model_size)
    table_path = results_dir / f"summary_table_{args.model_size}.txt"
    with open(table_path, "w") as f:
        f.write(table)
    print(f"Summary table saved to {table_path}")
    print("\n" + table)

    # Rebuild combined summary_tables.txt from all completed runs (for submission)
    combined_path = results_dir / "summary_tables.txt"
    combined_parts = []
    for size in ["small", "medium", "large"]:
        part_path = results_dir / f"summary_table_{size}.txt"
        if part_path.exists():
            combined_parts.append(part_path.read_text())
    if combined_parts:
        with open(combined_path, "w") as f:
            f.write("\n\n".join(combined_parts))
        print(f"Combined summary tables saved to {combined_path}")


if __name__ == "__main__":
    main()
