(set-logic ALL)
(set-option :produce-models true)

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

(declare-const has_competing_claimant Bool)
(declare-const taxpayer_is_parent Bool)
(declare-const competing_claimant_is_parent Bool)
(declare-const both_claimants_are_parents Bool)
(declare-const no_parent_claims Bool)
(declare-const other_taxpayer_can_claim_candidate_as_qc Bool)

(declare-const no_one_person_provided_over_half_support Bool)
(declare-const support_from_eligible_group_over_half Bool)
(declare-const all_other_10_percent_contributors_released_claim Bool)
(declare-const sheltered_workshop_medical_care_reason Bool)
(declare-const sheltered_workshop_income_incident_to_medical_care Bool)

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

; Case 5: Carlos — 19yo, dropped out of college after one semester (not a student).
; Lives with parents, works part-time earning $8,000/year.
; Parents still provide majority of financial support.
; Exemption = $5,000 (from Project 4 base_152.smt2).
; QC: age 19, not student, not disabled → age test fails (19 is not < 19).
; QR: gross_income $8,000 >> $5,000 exemption → income test fails.
; Hypothesis: No

(assert (= candidate_age 19))
(assert (= taxpayer_age 48))
(assert (= gross_income 8000))
(assert (= sheltered_workshop_income 0))
(assert (= exemption_amount 5000))
(assert (= candidate_self_support_percent 30))  ; parents still provide majority
(assert (= taxpayer_support_percent 70))
(assert (= taxpayer_agi 65000))
(assert (= competing_taxpayer_agi 0))
(assert (= months_same_abode 12))
(assert (= months_with_taxpayer 12))
(assert (= months_with_competing_parent 0))

(assert is_child)
(assert (not is_descendant_of_child))
(assert (not is_sibling))
(assert (not is_descendant_of_sibling))
(assert (not is_parent))
(assert (not is_ancestor))
(assert (not is_step_parent))
(assert (not is_niece_or_nephew))
(assert (not is_aunt_or_uncle))
(assert (not is_in_law))
(assert is_household_member_full_year)
(assert (not was_taxpayer_spouse_any_time_during_year))

(assert (not is_student))    ; dropped out — no longer enrolled
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
(assert taxpayer_is_parent)
(assert (not competing_claimant_is_parent))
(assert (not both_claimants_are_parents))
(assert (not no_parent_claims))
(assert (not other_taxpayer_can_claim_candidate_as_qc))

(assert (not no_one_person_provided_over_half_support))
(assert (not support_from_eligible_group_over_half))
(assert (not all_other_10_percent_contributors_released_claim))
(assert (not sheltered_workshop_medical_care_reason))
(assert (not sheltered_workshop_income_incident_to_medical_care))

(echo "=== Case 5: Carlos ===")

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
