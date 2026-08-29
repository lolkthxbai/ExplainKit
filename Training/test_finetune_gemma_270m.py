import json
import tempfile
import unittest
from pathlib import Path

from Training.finetune_gemma_270m import (
    digest,
    select_training_backend,
    validate_records,
    verify_model_access,
)


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

    def test_training_backend_prefers_cuda_then_mps(self):
        self.assertEqual(
            select_training_backend(FakeTorch(cuda=True, mps=True), "auto"),
            "cuda",
        )
        self.assertEqual(
            select_training_backend(FakeTorch(cuda=False, mps=True), "auto"),
            "mps",
        )
        with self.assertRaisesRegex(RuntimeError, "CUDA was requested"):
            select_training_backend(FakeTorch(cuda=False, mps=True), "cuda")
        with self.assertRaisesRegex(RuntimeError, "either a CUDA GPU or Apple MPS"):
            select_training_backend(FakeTorch(cuda=False, mps=False), "auto")

    def test_model_access_preflight_pins_revision_and_explains_the_license(self):
        calls = []

        def successful_download(**arguments):
            calls.append(arguments)
            return "/cache/config.json"

        self.assertEqual(
            verify_model_access(successful_download, FakeGatedRepoError),
            "/cache/config.json",
        )
        self.assertEqual(
            calls,
            [
                {
                    "repo_id": "google/gemma-3-270m-it",
                    "filename": "config.json",
                    "revision": "ac82b4e820549b854eebf28ce6dedaf9fdfa17b3",
                    "token": True,
                }
            ],
        )

        def blocked_download(**arguments):
            raise FakeGatedRepoError()

        with self.assertRaisesRegex(RuntimeError, "Accept the Gemma license"):
            verify_model_access(blocked_download, FakeGatedRepoError)


class FakeAccelerator:
    def __init__(self, available):
        self.available = available

    def is_available(self):
        return self.available

    def is_bf16_supported(self):
        return False


class FakeBackends:
    def __init__(self, mps):
        self.mps = FakeAccelerator(mps)


class FakeTorch:
    def __init__(self, cuda, mps):
        self.cuda = FakeAccelerator(cuda)
        self.backends = FakeBackends(mps)


class FakeGatedRepoError(Exception):
    pass


if __name__ == "__main__":
    unittest.main()
