import json
import tempfile
import unittest
from pathlib import Path

from Training.finetune_gemma_270m import digest, validate_records


def record(scenario_id="scenario-1", action_ids=None):
    action_ids = action_ids or ["retry"]
    return {
        "scenarioID": scenario_id,
        "messages": [
            {"role": "system", "content": "System instruction"},
            {"role": "user", "content": "Diagnostic"},
            {
                "role": "assistant",
                "content": json.dumps(
                    {
                        "title": "Retry",
                        "message": "Try again.",
                        "actionIDs": action_ids,
                    }
                ),
            },
        ],
    }


class FineTuningValidationTests(unittest.TestCase):
    def test_valid_records_return_unique_ids(self):
        records = [record("one"), record("two", ["retry", "open-settings"])]

        self.assertEqual(validate_records(records, "training"), {"one", "two"})

    def test_empty_duplicate_and_malformed_records_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "empty"):
            validate_records([], "training")
        with self.assertRaisesRegex(ValueError, "duplicate"):
            validate_records([record("same"), record("same")], "training")

        malformed_messages = record()
        malformed_messages["messages"][0]["role"] = "user"
        with self.assertRaisesRegex(ValueError, "message sequence"):
            validate_records([malformed_messages], "training")

        malformed_response = record()
        malformed_response["messages"][-1]["content"] = "not-json"
        with self.assertRaises(json.JSONDecodeError):
            validate_records([malformed_response], "training")

        with self.assertRaisesRegex(ValueError, "action selection"):
            validate_records([record(action_ids=["a", "b", "c", "d"])], "training")

    def test_digest_is_stable(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "data.jsonl"
            path.write_bytes(b"swiftmend\n")

            self.assertEqual(
                digest(path),
                "20064a3cacb67a7ec199cc8068363f0b6c83460ffc066586866e275cd8c76af9",
            )


if __name__ == "__main__":
    unittest.main()
