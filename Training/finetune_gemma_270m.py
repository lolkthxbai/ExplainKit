import argparse
import hashlib
import importlib.metadata
import json
import os
import platform
from pathlib import Path

MODEL_ID = "google/gemma-3-270m-it"
MODEL_REVISION = "ac82b4e820549b854eebf28ce6dedaf9fdfa17b3"


def parse_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--training-data", required=True, type=Path)
    parser.add_argument("--validation-data", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--epochs", type=float, default=5)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument(
        "--device",
        choices=("auto", "cuda", "mps"),
        default="auto",
        help="Training accelerator. Auto prefers CUDA, then Apple MPS.",
    )
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


def select_training_backend(torch_module, requested):
    cuda_available = torch_module.cuda.is_available()
    mps = getattr(torch_module.backends, "mps", None)
    mps_available = mps is not None and mps.is_available()

    if requested == "cuda":
        if not cuda_available:
            raise RuntimeError("CUDA was requested but is not available.")
        return "cuda"
    if requested == "mps":
        if not mps_available:
            raise RuntimeError("MPS was requested but is not available.")
        return "mps"
    if cuda_available:
        return "cuda"
    if mps_available:
        return "mps"
    raise RuntimeError("Training requires either a CUDA GPU or Apple MPS.")


def verify_model_access(download, gated_error_type):
    try:
        return download(
            repo_id=MODEL_ID,
            filename="config.json",
            revision=MODEL_REVISION,
            token=True,
        )
    except gated_error_type as error:
        raise RuntimeError(
            f"Accept the Gemma license at https://huggingface.co/{MODEL_ID} "
            "for the account used by this training environment."
        ) from error


def main():
    # Transformers 5's asynchronous safetensors loader can crash while
    # materializing Gemma weights on Apple Silicon. Sequential loading is
    # deterministic and avoids that native loader failure.
    os.environ.setdefault("HF_DEACTIVATE_ASYNC_LOAD", "1")

    import torch
    from datasets import load_dataset
    from huggingface_hub import get_token, hf_hub_download
    from huggingface_hub.errors import GatedRepoError
    from peft import LoraConfig
    from trl import SFTConfig, SFTTrainer

    arguments = parse_arguments()
    training_backend = select_training_backend(torch, arguments.device)
    if not get_token():
        raise RuntimeError(
            "A Hugging Face login or HF_TOKEN is required after accepting the Gemma license."
        )
    verify_model_access(hf_hub_download, GatedRepoError)

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
    use_bfloat16 = training_backend == "cuda" and torch.cuda.is_bf16_supported()
    use_float16 = training_backend == "cuda" and not use_bfloat16
    model_dtype = (
        torch.bfloat16
        if use_bfloat16
        else torch.float16
        if use_float16
        else torch.float32
    )
    training_configuration = SFTConfig(
        output_dir=str(arguments.output / "checkpoints"),
        num_train_epochs=arguments.epochs,
        per_device_train_batch_size=2,
        per_device_eval_batch_size=2,
        gradient_accumulation_steps=4,
        learning_rate=2e-4,
        warmup_steps=0.1,
        eval_strategy="epoch",
        save_strategy="epoch",
        logging_steps=1,
        max_length=1024,
        packing=False,
        bf16=use_bfloat16,
        fp16=use_float16,
        optim="adamw_torch_fused" if training_backend == "cuda" else "adamw_torch",
        dataloader_pin_memory=training_backend == "cuda",
        seed=arguments.seed,
        data_seed=arguments.seed,
        report_to="none",
        model_init_kwargs={
            "revision": MODEL_REVISION,
            "dtype": model_dtype,
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
        "trainingBackend": training_backend,
        "accelerator": (
            torch.cuda.get_device_name(0)
            if training_backend == "cuda"
            else "Apple Metal Performance Shaders"
        ),
        "cudaVersion": torch.version.cuda,
        "mpsBuilt": torch.backends.mps.is_built(),
        "mpsAvailable": torch.backends.mps.is_available(),
        "hfAsyncLoadDisabled": os.environ.get("HF_DEACTIVATE_ASYNC_LOAD") == "1",
        "platform": platform.platform(),
        "architecture": platform.machine(),
        "packages": {
            package: importlib.metadata.version(package)
            for package in (
                "accelerate",
                "datasets",
                "peft",
                "torch",
                "transformers",
                "trl",
            )
        },
    }
    (arguments.output / "training-manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
