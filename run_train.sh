#!/bin/bash
# IMPORTANT: create the logs/ directory before submitting with sbatch.
# SLURM resolves --output/--error paths before the script executes,
# so the directory must already exist at submission time:
#   mkdir -p logs && sbatch run_train.sh small
#
#SBATCH --job-name=sft_train
#SBATCH --partition=gpu
#SBATCH --gres=gpu:rtx_5000_ada:1
#SBATCH --account=pi_xy48
#SBATCH --mem=32G
#SBATCH --cpus-per-task=4
#SBATCH --time=04:00:00
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err

# Usage: sbatch run_train.sh small | sbatch run_train.sh medium | sbatch run_train.sh large
# Or run all three sequentially: bash run_train.sh all

set -e

# Activate conda environment
module load miniconda
conda activate ~/project_pi_xy48/hw646/ycrc_conda/envs/llm

DATASET_SIZE=${1:-small}
PROJECT_DIR="/home/hw646/project_pi_xy48/hw646/Final Project"

echo "=== SFT Training ==="
echo "Dataset size : $DATASET_SIZE"
echo "Project dir  : $PROJECT_DIR"
echo "GPU          : $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo 'N/A')"
echo "Start time   : $(date)"

mkdir -p "$PROJECT_DIR/logs"

if [ "$DATASET_SIZE" = "all" ]; then
    for SIZE in small medium large; do
        echo ""
        echo "--- Training on $SIZE dataset ---"
        python "$PROJECT_DIR/scripts/train_dpo.py" \
            --dataset "$PROJECT_DIR/data/dataset_${SIZE}.json" \
            --output  "$PROJECT_DIR/checkpoints/${SIZE}" \
            --epochs 5 \
            --lr 5e-5 \
            --beta 0.1 \
            --per_device_train_batch_size 2 \
            --gradient_accumulation_steps 4 \
            --max_length 512 \
            --use_sft
    done
else
    python "$PROJECT_DIR/scripts/train_dpo.py" \
        --dataset "$PROJECT_DIR/data/dataset_${DATASET_SIZE}.json" \
        --output  "$PROJECT_DIR/checkpoints/${DATASET_SIZE}" \
        --epochs 5 \
        --lr 5e-5 \
        --beta 0.1 \
        --per_device_train_batch_size 2 \
        --gradient_accumulation_steps 4 \
        --max_length 512 \
        --use_sft
fi

echo ""
echo "Training complete: $(date)"
