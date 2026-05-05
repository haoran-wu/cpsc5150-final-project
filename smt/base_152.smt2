(set-logic ALL)
(set-option :produce-models true)

; Base model for 26 U.S.C. §152(a)-(d).
; Scope: one taxpayer and one candidate dependent.
; The model is intentionally scenario-driven rather than fully universal.

; Numeric facts
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

; Relationship facts
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

; Personal status facts
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

; Tie-breaker and competing claimant facts
(declare-const has_competing_claimant Bool)
(declare-const taxpayer_is_parent Bool)
(declare-const competing_claimant_is_parent Bool)
(declare-const both_claimants_are_parents Bool)
(declare-const no_parent_claims Bool)
(declare-const other_taxpayer_can_claim_candidate_as_qc Bool)

; Multiple support and handicapped-income facts
(declare-const no_one_person_provided_over_half_support Bool)
(declare-const support_from_eligible_group_over_half Bool)
(declare-const all_other_10_percent_contributors_released_claim Bool)
(declare-const sheltered_workshop_medical_care_reason Bool)
(declare-const sheltered_workshop_income_incident_to_medical_care Bool)

; Domain constraints
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

; §152(c)(2)
(define-fun qc_relationship () Bool
  (or is_child
      is_descendant_of_child
      is_sibling
      is_descendant_of_sibling))

; §152(c)(3)
(define-fun qc_age_test () Bool
  (or is_disabled
      (and (< candidate_age taxpayer_age)
           (or (< candidate_age 19)
               (and is_student (< candidate_age 24))))))

; §152(c)(4)
(define-fun qc_tie_breaker_ok () Bool
  (or
    (not has_competing_claimant)
    (and taxpayer_is_parent (not competing_claimant_is_parent))
    (and both_claimants_are_parents
         (or (> months_with_taxpayer months_with_competing_parent)
             (and (= months_with_taxpayer months_with_competing_parent)
                  (> taxpayer_agi competing_taxpayer_agi))))
    (and no_parent_claims
         (> taxpayer_agi competing_taxpayer_agi))
    (and (not taxpayer_is_parent)
         (not both_claimants_are_parents)
         (not no_parent_claims)
         (> taxpayer_agi competing_taxpayer_agi))))

; §152(c)(1)
(define-fun qualifying_child () Bool
  (and qc_relationship
       (> months_same_abode 6)
       qc_age_test
       (<= candidate_self_support_percent 50)
       (or (not filed_joint_return) joint_return_only_for_refund)
       qc_tie_breaker_ok))

; §152(d)(2)
(define-fun qr_relationship () Bool
  (or is_child
      is_descendant_of_child
      is_sibling
      is_descendant_of_sibling
      is_parent
      is_ancestor
      is_step_parent
      is_niece_or_nephew
      is_aunt_or_uncle
      is_in_law
      (and is_household_member_full_year
           (not was_taxpayer_spouse_any_time_during_year))))

; §152(d)(4)
(define-fun sheltered_workshop_excludable () Bool
  (and is_disabled
       sheltered_workshop_medical_care_reason
       sheltered_workshop_income_incident_to_medical_care))

(define-fun countable_gross_income () Int
  (ite sheltered_workshop_excludable
       (- gross_income sheltered_workshop_income)
       gross_income))

; §152(d)(3)
(define-fun qr_support_test () Bool
  (or (> taxpayer_support_percent 50)
      (and no_one_person_provided_over_half_support
           support_from_eligible_group_over_half
           (> taxpayer_support_percent 10)
           all_other_10_percent_contributors_released_claim)))

; §152(b)(3)(B)
(define-fun adopted_child_exception () Bool
  (and is_adopted_child
       same_abode_and_household_for_adopted_child_exception
       taxpayer_is_us_citizen_or_national))

; §152(b)(3)
(define-fun nationality_ok () Bool
  (or is_us_citizen_or_national
      is_us_resident
      is_contiguous_country_resident
      adopted_child_exception))

; §152(d)(1)
(define-fun qualifying_relative () Bool
  (and qr_relationship
       (< countable_gross_income exemption_amount)
       qr_support_test
       (not qualifying_child)
       (not other_taxpayer_can_claim_candidate_as_qc)))

; §152(a) + §152(b)(2) + §152(b)(3)
(define-fun dependent () Bool
  (and (or qualifying_child qualifying_relative)
       nationality_ok
       (not filed_joint_return)))

; §152(b)(1): auxiliary output for the one-candidate model.
(define-fun can_candidate_claim_dependents () Bool
  (not dependent))
