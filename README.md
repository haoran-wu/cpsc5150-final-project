# Final Project: Using SMT for Guardrailing LLMs

Fine-tunes TinyLlama-1.1B on dependency-status (26 U.S.C. § 152) datasets using LoRA SFT,
then evaluates outputs against a Z3 SMT formalization.

## Hardware requirements

- GPU: 1× with ≥16 GB VRAM (tested on A100/V100)
- RAM: 32 GB
- Disk: ~10 GB for model weights

## Setup

```bash
pip install -r requirements.txt
```

If the HPC environment requires a CUDA-specific PyTorch wheel, install the
matching `torch==2.3.1` build first, then install the remaining pinned packages.

## Step 1 — SMT evaluation (no GPU needed)

```bash
python scripts/run_smt.py
# Output: results/smt_verdicts.json
```

## Step 2 — Training (run on HPC via SLURM)

```bash
# Create the SLURM log directory first:
mkdir -p logs

# Submit one job per dataset size (SFT via --use_sft flag):
sbatch run_train.sh small
sbatch run_train.sh medium
sbatch run_train.sh large

# Or run all three sequentially (for testing):
bash run_train.sh all
```

If you are using the course OnDemand Jupyter GPU session instead of `sbatch`,
run the project directly in the terminal:

```bash
bash run_course_session.sh all
```

## Step 3 — Evaluation

```bash
python scripts/evaluate.py --checkpoint checkpoints/small  --model_size small
python scripts/evaluate.py --checkpoint checkpoints/medium --model_size medium
python scripts/evaluate.py --checkpoint checkpoints/large  --model_size large
# Output: results/raw_outputs_{size}.jsonl, results/summary_table_{size}.txt
```

## Output files

| File | Description |
|------|-------------|
| `results/smt_verdicts.json` | Z3 double-query verdicts for all 6 fact patterns |
| `results/summary_table_{size}.txt` | Formatted summary table per model size |
| `results/summary_tables.txt` | All three tables combined (submission copy) |

`scripts/evaluate.py` also writes `results/raw_outputs_{size}.jsonl` when run;
these generated logs are not tracked in GitHub because the submitted summary
tables contain the model verdicts required for grading.

## Submission

If Gradescope asks for a GitHub submission, submit this repository link. The
repository contains the required datasets, training/evaluation code, SMT files,
report, and summary tables. Large generated checkpoints and logs are excluded.

## Notes

- All dependency versions in `requirements.txt` are pinned for reproducibility.
- Exemption amount: **$5,000** (consistent with Project 4 SMT specification)
- `case6_sophie.smt2` extends `base_152.smt2` with `is_eligible_foster_child` (§152(f)(1)(C))
- Training uses LoRA SFT (r=16, α=32, 4-bit NF4 quantization); `--use_sft` flag is passed to `train_dpo.py`
- `run_train.sh` uses paths relative to the repository root; it no longer depends on a lab-specific home directory.
