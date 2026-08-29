import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("export_gemma_270m_litert.py")
SPEC = importlib.util.spec_from_file_location("export_gemma_270m_litert", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ExportGemma270MLiteRTTests(unittest.TestCase):
    def test_metadata_uses_the_verified_stop_policy(self):
        metadata = MODULE.build_metadata_override("{{ bos_token }}\n")

        self.assertEqual(metadata.count("stop_tokens"), 2)
        self.assertIn('token_str: "<end_of_turn>"', metadata)
        self.assertIn("token_ids { ids: 1 }", metadata)
        self.assertNotIn("ids: 106", metadata)
        self.assertIn(json.dumps("{{ bos_token }}\n"), metadata)

    def test_inputs_require_the_pinned_text_checkpoint_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = root / "merged"
            model.mkdir()
            tokenizer = root / "tokenizer.model"
            tokenizer.write_bytes(b"tokenizer")
            (model / "config.json").write_text(
                json.dumps({"model_type": "gemma3_text"}), encoding="utf-8"
            )
            (model / "chat_template.jinja").write_text(
                "{{ bos_token }}", encoding="utf-8"
            )

            self.assertEqual(
                MODULE.validate_inputs(model, tokenizer),
                "{{ bos_token }}",
            )


if __name__ == "__main__":
    unittest.main()
