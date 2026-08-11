import unittest

from _lib.work_contract import WorkContractError, normalize_work_contract


class WorkContractNormalizationTest(unittest.TestCase):
    def test_current_v5_build_is_canonical(self):
        contract = normalize_work_contract(
            {
                "status": "active",
                "build": {
                    "contract_version": 5,
                    "lifecycle_state": "iterating",
                    "acceptance": {
                        "iteration_checks": ["typecheck"],
                        "final_checks": ["tests", "build"],
                    },
                },
            }
        )
        self.assertEqual(contract.lifecycle_state, "iterating")
        self.assertEqual(contract.display_stage, 2)
        self.assertEqual(contract.final_checks, ("tests", "build"))
        self.assertFalse(contract.is_legacy)

    def test_v4_aliases_are_normalized(self):
        contract = normalize_work_contract(
            {
                "stage": 2,
                "lifecycle_state": "final_check",
                "build": {
                    "contract_version": 4,
                    "lifecycle_state": "final_check",
                    "acceptance": {
                        "iteration_checks": ["typecheck"],
                        "final_checks": ["tests"],
                        "required_checks": ["tests"],
                    },
                },
            }
        )
        self.assertEqual(contract.lifecycle_state, "final_check")
        self.assertEqual(contract.final_checks, ("tests",))
        self.assertIn("required_checks", contract.compatibility)
        self.assertIn("top_level_build_lifecycle", contract.compatibility)

    def test_v2_required_checks_become_final_checks(self):
        contract = normalize_work_contract(
            {
                "build": {
                    "contract_version": 2,
                    "lifecycle_state": "building",
                    "acceptance": {"required_checks": ["tests"]},
                }
            }
        )
        self.assertEqual(contract.final_checks, ("tests",))
        self.assertEqual(contract.iteration_checks, ())

    def test_stage_only_legacy_state_is_projected(self):
        contract = normalize_work_contract({"stage": 1, "status": "active"})
        self.assertEqual(contract.lifecycle_state, "designing")
        self.assertIn("stage_lifecycle", contract.compatibility)

    def test_lifecycle_only_legacy_state_can_be_projected(self):
        contract = normalize_work_contract(
            {"status": "closed", "lifecycle_state": "complete"}
        )
        self.assertEqual(contract.lifecycle_state, "complete")
        self.assertEqual(contract.display_stage, 4)

    def test_conflicting_legacy_lifecycles_fail_closed(self):
        with self.assertRaisesRegex(WorkContractError, "不一致"):
            normalize_work_contract(
                {
                    "lifecycle_state": "building",
                    "build": {
                        "contract_version": 4,
                        "lifecycle_state": "iterating",
                        "acceptance": {
                            "iteration_checks": [],
                            "final_checks": ["tests"],
                            "required_checks": ["tests"],
                        },
                    },
                }
            )

    def test_v5_rejects_old_aliases(self):
        with self.assertRaisesRegex(WorkContractError, "required_checks"):
            normalize_work_contract(
                {
                    "build": {
                        "contract_version": 5,
                        "lifecycle_state": "building",
                        "acceptance": {
                            "iteration_checks": [],
                            "final_checks": ["tests"],
                            "required_checks": ["tests"],
                        },
                    }
                }
            )

    def test_invalid_version_and_types_fail_closed(self):
        for value in (True, "future", 6):
            with self.subTest(value=value), self.assertRaises(WorkContractError):
                normalize_work_contract(
                    {
                        "build": {
                            "contract_version": value,
                            "lifecycle_state": "building",
                            "acceptance": {"final_checks": ["tests"]},
                        }
                    }
                )


if __name__ == "__main__":
    unittest.main()
