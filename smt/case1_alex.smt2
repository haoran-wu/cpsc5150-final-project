; Case 1: Alex — 17yo, lives with aunt full-time, aunt pays all expenses.
; Parents live in a different state and provide no financial support.
;
; Analysis:
;   QC: aunt is the taxpayer. Alex is her nephew → descendant_of_sibling (aunt's sibling's child).
;       Residency: full year (12 months). Age: 17 < 19. Self-support: 0%. No joint return.
;       Tie-breaker: no competing claimant (parents don't claim, provide no support).
;   QR: is_niece_or_nephew = true, but qualifying_child = true so QR = false by §152(d)(1) exclusion.
;   Hypothesis: Yes (QC via descendant_of_sibling).
;
; Double-query verdict logic:
;   Q1 sat + Q2 unsat → Yes (necessarily dependent)
;   Q1 unsat + Q2 sat → No
;   Q1 sat + Q2 sat  → Ambiguous

(set-logic ALL)
(set-option :produce-models true)

; === Numeric facts ===
(declare-const candidate_age Int)
(declare-const taxpayer_age Int)
(declare-const gross_income Int)
(declare-const sheltered_workshop_income Int)
(declare-const exemption_amount Int)
(declare-const candidate_self_support_percent Int)
(declare-const taxpayer_support_percent Int)
(declare-const taxpayer_agi Int)
(declare-const competing_taxpayer_agi Int)
(declare-const months_same_abode Int)
(declare-const months_with_taxpayer Int)
(declare-const months_with_competing_parent Int)

; === Relationship facts ===
(declare-const is_child Bool)
(declare-const is_descendant_of_child Bool)
(declare-const is_sibling Bool)
(declare-const is_descendant_of_sibling Bool)
(declare-const is_parent Bool)
(declare-const is_ancestor Bool)
(declare-const is_step_parent Bool)
(declare-const is_niece_or_nephew Bool)
(declare-const is_aunt_or_uncle Bool)
(declare-const is_in_law Bool)
(declare-const is_household_member_full_year Bool)
(declare-const was_taxpayer_spouse_any_time_during_year Bool)

; === Personal status facts ===
(declare-const is_student Bool)
(declare-const is_disabled Bool)
(declare-const filed_joint_return Bool)
(declare-const joint_return_only_for_refund Bool)
(declare-const is_us_citizen_or_national Bool)
(declare-const is_us_resident Bool)
(declare-const is_contiguous_country_resident Bool)
(declare-const is_adopted_child Bool)
(declare-const same_abode_and_household_for_adopted_child_exception Bool)
(declare-const taxpayer_is_us_citizen_or_national Bool)

; === Tie-breaker and competing claimant facts ===
(declare-const has_competing_claimant Bool)
(declare-const taxpayer_is_parent Bool)
(declare-const competing_claimant_is_parent Bool)
(declare-const both_claimants_are_parents Bool)
(declare-const no_parent_claims Bool)
(declare-const other_taxpayer_can_claim_candidate_as_qc Bool)

; === Multiple support and sheltered workshop facts ===
(declare-const no_one_person_provided_over_half_support Bool)
(declare-const support_from_eligible_group_over_half Bool)
(declare-const all_other_10_percent_contributors_released_claim Bool)
(declare-const sheltered_workshop_medical_care_reason Bool)
(declare-const sheltered_workshop_income_incident_to_medical_care Bool)

; === Domain constraints ===
(assert (<= 0 candidate_age))
(assert (<= 0 taxpayer_age))
(assert (<= 0 gross_income))
(assert (<= 0 sheltered_workshop_income))
(assert (<= 0 exemption_amount))
(assert (and (<= 0 candidate_self_support_percent) (<= candidate_self_support_percent 100)))
(assert (and (<= 0 taxpayer_support_percent) (<= taxpayer_support_percent 100)))
(assert (and (<= 0 months_same_abode) (<= months_same_abode 12)))
(assert (and (<= 0 months_with_taxpayer) (<= months_with_taxpayer 12)))
(assert (and (<= 0 months_with_competing_parent) (<= months_with_competing_parent 12)))

; === §152 definitions (from base_152.smt2) ===

(define-fun qc_relationship () Bool
  (or is_child is_descendant_of_child is_sibling is_descendant_of_sibling))

(define-fun qc_age_test () Bool
  (or is_disabled
      (and (< candidate_age taxpayer_age)
           (or (< candidate_age 19)
               (and is_student (< candidate_age 24))))))

(define-fun qc_tie_breaker_ok () Bool
  (or
    (not has_competing_claimant)
    (and taxpayer_is_parent (not competing_claimant_is_parent))
    (and both_claimants_are_parents
         (or (> months_with_taxpayer months_with_competing_parent)
             (and (= months_with_taxpayer months_with_competing_parent)
                  (> taxpayer_agi competing_taxpayer_agi))))
    (and no_parent_claims (> taxpayer_agi competing_taxpayer_agi))
    (and (not taxpayer_is_parent)
         (not both_claimants_are_parents)
         (not no_parent_claims)
         (> taxpayer_agi competing_taxpayer_agi))))

(define-fun qualifying_child () Bool
  (and qc_relationship
       (> months_same_abode 6)
       qc_age_test
       (<= candidate_self_support_percent 50)
       (or (not filed_joint_return) joint_return_only_for_refund)
       qc_tie_breaker_ok))

(define-fun qr_relationship () Bool
  (or is_child is_descendant_of_child is_sibling is_descendant_of_sibling
      is_parent is_ancestor is_step_parent is_niece_or_nephew is_aunt_or_uncle is_in_law
      (and is_household_member_full_year (not was_taxpayer_spouse_any_time_during_year))))

(define-fun sheltered_workshop_excludable () Bool
  (and is_disabled sheltered_workshop_medical_care_reason
       sheltered_workshop_income_incident_to_medical_care))

(define-fun countable_gross_income () Int
  (ite sheltered_workshop_excludable
       (- gross_income sheltered_workshop_income)
       gross_income))

(define-fun qr_support_test () Bool
  (or (> taxpayer_support_percent 50)
      (and no_one_person_provided_over_half_support
           support_from_eligible_group_over_half
           (> taxpayer_support_percent 10)
           all_other_10_percent_contributors_released_claim)))

(define-fun adopted_child_exception () Bool
  (and is_adopted_child same_abode_and_household_for_adopted_child_exception
       taxpayer_is_us_citizen_or_national))

(define-fun nationality_ok () Bool
  (or is_us_citizen_or_national is_us_resident is_contiguous_country_resident
      adopted_child_exception))

(define-fun qualifying_relative () Bool
  (and qr_relationship
       (< countable_gross_income exemption_amount)
       qr_support_test
       (not qualifying_child)
       (not other_taxpayer_can_claim_candidate_as_qc)))

(define-fun dependent () Bool
  (and (or qualifying_child qualifying_relative)
       nationality_ok
       (not filed_joint_return)))

; === Case 1: Alex scenario assertions ===
(assert (= candidate_age 17))
(assert (= taxpayer_age 35))
(assert (= gross_income 0))
(assert (= sheltered_workshop_income 0))
(assert (= exemption_amount 5000))
(assert (= candidate_self_support_percent 0))
(assert (= taxpayer_support_percent 100))
(assert (= taxpayer_agi 55000))
(assert (= competing_taxpayer_agi 0))
(assert (= months_same_abode 12))
(assert (= months_with_taxpayer 12))
(assert (= months_with_competing_parent 0))

(assert (not is_child))
(assert (not is_descendant_of_child))
(assert (not is_sibling))
(assert is_descendant_of_sibling)   ; Alex is nephew: aunt's sibling's child
(assert (not is_parent))
(assert (not is_ancestor))
(assert (not is_step_parent))
(assert is_niece_or_nephew)         ; for QR pathway
(assert (not is_aunt_or_uncle))
(assert (not is_in_law))
(assert is_household_member_full_year)
(assert (not was_taxpayer_spouse_any_time_during_year))

(assert (not is_student))
(assert (not is_disabled))
(assert (not filed_joint_return))
(assert (not joint_return_only_for_refund))
(assert is_us_citizen_or_national)
(assert (not is_us_resident))
(assert (not is_contiguous_country_resident))
(assert (not is_adopted_child))
(assert (not same_abode_and_household_for_adopted_child_exception))
(assert taxpayer_is_us_citizen_or_national)

(assert (not has_competing_claimant))
(assert (not taxpayer_is_parent))
(assert (not competing_claimant_is_parent))
(assert (not both_claimants_are_parents))
(assert no_parent_claims)
(assert (not other_taxpayer_can_claim_candidate_as_qc))

(assert (not no_one_person_provided_over_half_support))
(assert (not support_from_eligible_group_over_half))
(assert (not all_other_10_percent_contributors_released_claim))
(assert (not sheltered_workshop_medical_care_reason))
(assert (not sheltered_workshop_income_incident_to_medical_care))

; === Double-query ===
(echo "=== Case 1: Alex ===")
(echo "--- Q1: Can dependent = true? ---")
(push)
(assert dependent)
(check-sat)
(get-value (qualifying_child qualifying_relative dependent))
(pop)

(echo "--- Q2: Can dependent = false? ---")
(push)
(assert (not dependent))
(check-sat)
(pop)

; Verdict table:
;   Q1=sat, Q2=unsat → Yes (necessarily dependent)
;   Q1=unsat, Q2=sat → No
;   Q1=sat, Q2=sat   → Ambiguous (underconstrained)
;   Q1=unsat, Q2=unsat → spec bug / inconsistent facts
