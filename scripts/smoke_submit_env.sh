#!/bin/bash
# Clean-environment smoke test for submission reproducibility.
# Run from the project root on a GPU node:
#   bash scripts/smoke_submit_env.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

module load miniconda 2>/dev/null || true

python -m venv .venv_submit_test
source .venv_submit_test/bin/activate

python -m pip install --upgrade pip
python -m pip install -r requirements.txt

{
  echo "=== ENV ==="
  hostname
  which python
  python --version
  python -m pip show torch transformers trl peft bitsandbytes datasets accelerate z3-solver rich | sed -n '1,180p'

  echo "=== GPU ==="
  nvidia-smi || true
  python - <<'PY'
import torch
print("torch", torch.__version__)
print("cuda_available", torch.cuda.is_available())
print("cuda_count", torch.cuda.device_count())
if torch.cuda.is_available():
    print("gpu_name", torch.cuda.get_device_name(0))
PY

  echo "=== SMT ==="
  python scripts/run_smt.py

  echo "=== SMALL TRAIN/EVAL ==="
  python scripts/train_dpo.py \
    --dataset data/dataset_small.json \
    --output checkpoints_submit_test/small \
    --epochs 1 \
    --lr 5e-5 \
    --per_device_train_batch_size 1 \
    --gradient_accumulation_steps 1 \
    --max_length 512 \
    --use_sft

  python scripts/evaluate.py \
    --checkpoint checkpoints_submit_test/small \
    --model_size small \
    --max_new_tokens 120
} 2>&1 | tee submit_env_smoke.log
