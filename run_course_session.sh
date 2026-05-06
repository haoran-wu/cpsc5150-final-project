#!/bin/bash
# Run the full pipeline directly inside the course OnDemand Jupyter terminal.
# Example:
#   bash run_course_session.sh small
#   bash run_course_session.sh all

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DATASET_SIZE="${1:-small}"

mkdir -p results checkpoints logs

echo "=== Course Jupyter Session Pipeline ==="
echo "Working directory: $SCRIPT_DIR"
echo "Dataset size: $DATASET_SIZE"
echo "Start time: $(date)"
echo

python scripts/run_smt.py

if [ "$DATASET_SIZE" = "all" ]; then
  for SIZE in small medium large; do
    echo
    echo "--- Training and evaluating $SIZE ---"
    python scripts/train_dpo.py \
      --dataset "data/dataset_${SIZE}.json" \
      --output "checkpoints/${SIZE}" \
      --epochs 5 \
      --lr 5e-5 \
      --beta 0.1 \
      --per_device_train_batch_size 2 \
      --gradient_accumulation_steps 4 \
      --max_length 512 \
      --use_sft

    python scripts/evaluate.py --checkpoint "checkpoints/${SIZE}" --model_size "$SIZE"
  done
else
  python scripts/train_dpo.py \
    --dataset "data/dataset_${DATASET_SIZE}.json" \
    --output "checkpoints/${DATASET_SIZE}" \
    --epochs 5 \
    --lr 5e-5 \
    --beta 0.1 \
    --per_device_train_batch_size 2 \
    --gradient_accumulation_steps 4 \
    --max_length 512 \
    --use_sft

  python scripts/evaluate.py --checkpoint "checkpoints/${DATASET_SIZE}" --model_size "$DATASET_SIZE"
fi

echo
echo "Done: $(date)"
