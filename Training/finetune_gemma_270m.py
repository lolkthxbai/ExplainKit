import argparse
import hashlib
import json
import os
from pathlib import Path

import torch
from datasets import load_dataset
from peft import LoraConfig
from trl import SFTConfig, SFTTrainer


MODEL_ID = "google/gemma-3-270m-it"
MODEL_REVISION = "ac82b4e820549b854eebf28ce6dedaf9fdfa17b3"


def parse_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--training-data", required=True, type=Path)
    parser.add_argument("--validation-data", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--epochs", type=float, default=5)
    parser.add_argument("--seed", type=int, default=42)
    return parser.parse_args()


def digest(path):
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def validate_records(dataset, label):
    if len(dataset) == 0:
        raise ValueError(f"{label} dataset is empty")
    scenario_ids = set()
    for record in dataset:
        scenario_id = record.get("scenarioID")
        messages = record.get("messages")
        if not scenario_id or scenario_id in scenario_ids:
            raise ValueError(f"{label} contains an empty or duplicate scenario ID")
        if not isinstance(messages, list) or [item.get("role") for item in messages] != [
            "system",
            "user",
            "assistant",
        ]:
            raise ValueError(f"{scenario_id} has an invalid message sequence")
        response = json.loads(messages[-1]["content"])
        if set(response) != {"title", "message", "actionIDs"}:
            raise ValueError(f"{scenario_id} has an invalid assistant response")
        if not 1 <= len(response["actionIDs"]) <= 3:
            raise ValueError(f"{scenario_id} has an invalid action selection")
        scenario_ids.add(scenario_id)
    return scenario_ids


def main():
    arguments = parse_arguments()
    if not torch.cuda.is_available():
        raise RuntimeError("This reproducible training path requires a CUDA GPU runtime.")
    if not os.environ.get("HF_TOKEN"):
        raise RuntimeError("HF_TOKEN is required after accepting the Gemma license.")

    files = {
        "train": str(arguments.training_data),
        "validation": str(arguments.validation_data),
    }
    datasets = load_dataset("json", data_files=files)
    training_ids = validate_records(datasets["train"], "training")
    validation_ids = validate_records(datasets["validation"], "validation")
    if not training_ids.isdisjoint(validation_ids):
        raise ValueError("Training and validation scenario IDs overlap")

    arguments.output.mkdir(parents=True, exist_ok=True)
    use_bfloat16 = torch.cuda.is_bf16_supported()
    training_configuration = SFTConfig(
        output_dir=str(arguments.output / "checkpoints"),
        num_train_epochs=arguments.epochs,
        per_device_train_batch_size=2,
        per_device_eval_batch_size=2,
        gradient_accumulation_steps=4,
        learning_rate=2e-4,
        warmup_ratio=0.1,
        eval_strategy="epoch",
        save_strategy="epoch",
        logging_steps=1,
        max_length=1024,
        packing=False,
        bf16=use_bfloat16,
        fp16=not use_bfloat16,
        seed=arguments.seed,
        data_seed=arguments.seed,
        report_to="none",
        model_init_kwargs={
            "revision": MODEL_REVISION,
            "dtype": torch.bfloat16 if use_bfloat16 else torch.float16,
        },
    )
    trainer = SFTTrainer(
        model=MODEL_ID,
        args=training_configuration,
        train_dataset=datasets["train"],
        eval_dataset=datasets["validation"],
        peft_config=LoraConfig(
            task_type="CAUSAL_LM",
            r=8,
            lora_alpha=16,
            lora_dropout=0.05,
            target_modules="all-linear",
            bias="none",
        ),
    )
    trainer.train()
    adapter_path = arguments.output / "adapter"
    merged_path = arguments.output / "merged"
    trainer.model.save_pretrained(adapter_path)
    merged_model = trainer.model.merge_and_unload()
    merged_model.save_pretrained(merged_path, safe_serialization=True)
    trainer.processing_class.save_pretrained(merged_path)

    manifest = {
        "modelID": MODEL_ID,
        "modelRevision": MODEL_REVISION,
        "trainingDataSHA256": digest(arguments.training_data),
        "validationDataSHA256": digest(arguments.validation_data),
        "trainingScenarioCount": len(training_ids),
        "validationScenarioCount": len(validation_ids),
        "epochs": arguments.epochs,
        "seed": arguments.seed,
    }
    (arguments.output / "training-manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
