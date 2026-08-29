import argparse
import json
from pathlib import Path


def parse_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True, type=Path)
    parser.add_argument("--tokenizer", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def build_metadata_override(chat_template):
    return "\n".join(
        (
            "start_token { token_ids { ids: 2 } }",
            'stop_tokens { token_str: "<end_of_turn>" }',
            "stop_tokens { token_ids { ids: 1 } }",
            "max_num_tokens: 4096",
            "llm_model_type { gemma3 {} }",
            f"jinja_prompt_template: {json.dumps(chat_template)}",
            "",
        )
    )


def validate_inputs(model_path, tokenizer_path):
    config_path = model_path / "config.json"
    chat_template_path = model_path / "chat_template.jinja"
    if not config_path.is_file() or not chat_template_path.is_file():
        raise ValueError("Merged model is missing config.json or chat_template.jinja")
    if not tokenizer_path.is_file():
        raise ValueError("Pinned SentencePiece tokenizer is missing")
    config = json.loads(config_path.read_text(encoding="utf-8"))
    if config.get("model_type") != "gemma3_text":
        raise ValueError("Expected the merged Gemma 3 text checkpoint")
    return chat_template_path.read_text(encoding="utf-8")


def main():
    arguments = parse_arguments()
    chat_template = validate_inputs(arguments.model, arguments.tokenizer)

    from litert_torch.generative.export_hf.export import export

    export(
        model=str(arguments.model),
        output_dir=str(arguments.output),
        externalize_embedder=False,
        k_ts_idx=3,
        v_ts_idx=2,
        litert_lm_model_type_override="gemma3",
        litert_lm_llm_metadata_override=build_metadata_override(chat_template),
        tokenizer_path_override=str(arguments.tokenizer),
    )


if __name__ == "__main__":
    main()
