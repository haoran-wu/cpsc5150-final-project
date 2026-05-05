"""
run_smt.py — Double-query SMT evaluation for 6 evaluation fact patterns.

For each case, two independent Z3 solver runs determine the verdict:
  Q1: facts + assert dependent      → sat means dependent CAN be true
  Q2: facts + assert (not dependent) → sat means dependent CAN be false

Verdict table:
  Q1=sat, Q2=unsat → Yes  (necessarily dependent)
  Q1=unsat, Q2=sat → No   (necessarily not dependent)
  Q1=sat,   Q2=sat → Ambiguous (underconstrained — both readings are possible)
  Q1=unsat, Q2=unsat → Spec bug / inconsistent facts (should not occur)
  unknown in either → Unknown
"""

import json
import os
from pathlib import Path
from z3 import Solver, parse_smt2_file, BoolRef, is_true


def double_query(smt_path: str, dependent_fn_name: str = "dependent") -> dict:
    """
    Run double-query on an SMT2 file.
    Returns a dict with q1, q2, and verdict.
    """
    smt_path = str(smt_path)

    # Q1: can dependent = true?
    s1 = Solver()
    s1.from_file(smt_path)
    # Extract the dependent() function value by asserting it
    s1.push()
    # We need to assert the dependent function. Since from_file already loaded all
    # definitions, we add the assertion via a string.
    s1.from_string("(assert dependent)")
    r1 = s1.check()
    q1_sat = str(r1) == "sat"

    # Q2: can (not dependent) = true?
    s2 = Solver()
    s2.from_file(smt_path)
    s2.from_string("(assert (not dependent))")
    r2 = s2.check()
    q2_sat = str(r2) == "sat"

    if q1_sat and not q2_sat:
        verdict = "Yes"
    elif not q1_sat and q2_sat:
        verdict = "No"
    elif q1_sat and q2_sat:
        verdict = "Ambiguous"
    elif str(r1) == "unknown" or str(r2) == "unknown":
        verdict = "Unknown"
    else:
        verdict = "Spec-bug (unsat/unsat)"

    return {
        "q1_result": str(r1),
        "q2_result": str(r2),
        "verdict": verdict,
    }


def main():
    project_root = Path(__file__).resolve().parent.parent
    smt_dir = project_root / "smt"
    results_dir = project_root / "results"
    results_dir.mkdir(exist_ok=True)

    cases = [
        {
            "case_id": "case1_alex",
            "description": "Alex, 17, lives with aunt full-time, aunt pays all expenses.",
            "smt_file": smt_dir / "case1_alex.smt2",
        },
        {
            "case_id": "case2_maria",
            "description": "Maria, 25, grad student in university housing, stipend covers living expenses.",
            "smt_file": smt_dir / "case2_maria.smt2",
        },
        {
            "case_id": "case3_james",
            "description": "James, 15, lives with parents during school year, summers with grandparents.",
            "smt_file": smt_dir / "case3_james.smt2",
        },
        {
            "case_id": "case4_linda",
            "description": "Linda, 45, lives with adult daughter, earns $5,000, daughter provides >50% support.",
            "smt_file": smt_dir / "case4_linda.smt2",
        },
        {
            "case_id": "case5_carlos",
            "description": "Carlos, 19, dropped out, earns $8,000, parents provide majority of support.",
            "smt_file": smt_dir / "case5_carlos.smt2",
        },
        {
            "case_id": "case6_sophie",
            "description": "Sophie, 16, foster family provides all support. SMT extended with is_eligible_foster_child.",
            "smt_file": smt_dir / "case6_sophie.smt2",
        },
    ]

    results = []
    print("=" * 60)
    print("SMT Double-Query Evaluation — 26 U.S.C. § 152(a)-(d)")
    print("Exemption amount: $5,000 (consistent with Project 4)")
    print("=" * 60)

    for case in cases:
        print(f"\n[{case['case_id']}]")
        print(f"  {case['description']}")
        qr = double_query(case["smt_file"])
        print(f"  Q1 (assert dependent):       {qr['q1_result']}")
        print(f"  Q2 (assert not dependent):   {qr['q2_result']}")
        print(f"  >> Verdict: {qr['verdict']}")

        results.append({
            "case_id": case["case_id"],
            "description": case["description"],
            "q1_assert_dependent": qr["q1_result"],
            "q2_assert_not_dependent": qr["q2_result"],
            "smt_verdict": qr["verdict"],
        })

    out_path = results_dir / "smt_verdicts.json"
    with open(out_path, "w") as f:
        json.dump(results, f, indent=2)
    print(f"\nResults saved to {out_path}")


if __name__ == "__main__":
    main()
