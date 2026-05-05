# Report: Using SMT for Guardrailing LLMs on 26 U.S.C. § 152

**Hardware**: 1× NVIDIA RTX 5000 Ada (16 GB VRAM), 32 GB RAM, SLURM/bouchet HPC.
**Software**: Python 3.11, transformers 4.57.1, trl 0.24.0, peft 0.17.1, bitsandbytes 0.49.2, z3-solver 4.16.0.

## SMT Evaluation

Six fact patterns were encoded in SMT-LIB2 by extending `base_152.smt2` from Project 4 using a **double-query** methodology: one solver asserts `(assert dependent)`, a second asserts `(assert (not dependent))`. sat/unsat→**Yes**; unsat/sat→**No**; sat/sat→**Ambiguous**. This avoids the spurious-model problem of a single `get-value` call on underconstrained facts.

Exemption amount is **$5,000** (Project 4 default). Linda's $5,000 gross income fails the strict `<` inequality → **No**; Carlos's $8,000 also → **No**. Sophie required an extension: `base_152.smt2` omits §152(f)(1)(C) foster child, so `is_eligible_foster_child` was declared with `(assert (=> is_eligible_foster_child is_child))` → **Yes**.

Verdicts: alex=Yes, maria=No, james=Yes, linda=No, carlos=No, sophie=Yes.

## Fine-Tuning Method

**LoRA SFT** (Option A) was chosen over DPO (Option B) for two reasons. First, the dataset is small (10–50 examples), and DPO's KL penalty requires sufficient preference contrast to remain stable — at this scale, DPO showed training instability with mode collapse on the large dataset. Second, SFT on chosen responses trains the model to produce well-reasoned legal analysis directly, without requiring the model to simultaneously maximize the margin between chosen and rejected, which adds optimization complexity. Memory cost is controlled with 4-bit NF4 quantization and LoRA (r=16, α=32, 0.41% trainable parameters). The tradeoff is that SFT does not explicitly penalize rejected responses, so errors encoded in the rejected examples are not directly trained away — only the correct pattern is reinforced.

---

## Dataset Ablation and Model Behavior

SFT fine-tuning consistently achieves **3/6** across all three dataset sizes:

| Fact Pattern | Small (10) | Medium (20) | Large (50) | SMT Verdict |
|---|---|---|---|---|
| case1_alex | Yes ✓ | Yes ✓ | Yes ✓ | Yes |
| case2_maria | Yes ✗ | Yes ✗ | Yes ✗ | No |
| case3_james | Yes ✓ | Yes ✓ | Yes ✓ | Yes |
| case4_linda | Yes ✗ | Yes ✗ | Yes ✗ | No |
| case5_carlos | Yes ✗ | Yes ✗ | Yes ✗ | No |
| case6_sophie | Yes ✓ | Yes ✓ | Yes ✓ | Yes |
| **Correct** | **3/6** | **3/6** | **3/6** | — |

Dataset size had no measurable effect within the 10–50 example range. The model correctly handles all three Yes-verdict cases (Alex: qualifying child under 19; James: qualifying child with parental support; Sophie: eligible foster child under §152(f)(1)(C)) but fails uniformly on all three No-verdict cases across every dataset size.

The consistent error pattern reveals a **Yes-biased heuristic**: the model anchors on surface cues ("parents provide support," "lives with family") and outputs "Yes" without applying the statutory gates. For Maria (25yo), it bypasses the age-and-student threshold in §152(c)(3). For Carlos (19yo, $8,000 income), it ignores the gross-income test in §152(d)(1)(B). For Linda ($5,000 income exactly at the exemption limit), it misses the strict `<` inequality in §151(d).

These failures are not corrected by adding more training data because all dataset sizes contain similar paraphrased examples — the model needs examples that force explicit application of numerical thresholds, which requires either a larger base model with stronger arithmetic reasoning or a different training signal (e.g., chain-of-thought with step-by-step statutory analysis). The SMT guardrail catches all three errors precisely, confirming the value of formal verification as a post-hoc check on model outputs.
