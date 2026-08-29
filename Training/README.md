# Gemma 3 270M experiment

This directory contains the reproducible, gated experiment for testing whether a specialized Gemma 3 270M model can replace the 1B local baseline. The 270M model is not the default and must not be shipped unless it passes the comparison gate on the same held-out scenarios.

The model repositories are license-gated. Accept the Gemma license on Hugging
Face and authenticate with `hf auth login` or provide `HF_TOKEN` only in the
training environment; never add a token to this repository.

## 1. Export the versioned data

```sh
swift run SwiftMendDatasetTool --split training --output /tmp/swiftmend-train.jsonl
swift run SwiftMendDatasetTool --split validation --output /tmp/swiftmend-validation.jsonl
```

The default v2 dataset exports 42 training and 14 validation records across all
seven categories. Its 14 test records stay held out. V1 remains bundled so old
results can be reproduced, but it is not the default training source.

## 2. Train the adapter

Use a managed CUDA image such as Kaggle or Colab with PyTorch already matched
to its CUDA runtime. The requirements keep that installed PyTorch when it is
2.5 or newer, while pinning the higher-level training libraries. The generated
manifest records the actual GPU, CUDA, and package versions.

```sh
python -m venv .venv
. .venv/bin/activate
python -m pip install -r Training/requirements.txt
HF_TOKEN=... python Training/finetune_gemma_270m.py \
  --training-data /tmp/swiftmend-train.jsonl \
  --validation-data /tmp/swiftmend-validation.jsonl \
  --output /tmp/swiftmend-gemma-270m \
  --device cuda
```

Apple silicon can run the same LoRA experiment locally through PyTorch MPS.
MPS training uses float32 because mixed-precision support differs from CUDA:

```sh
python3.12 -m venv /tmp/swiftmend-training-venv
. /tmp/swiftmend-training-venv/bin/activate
python -m pip install -r Training/requirements.txt
python Training/finetune_gemma_270m.py \
  --training-data /tmp/swiftmend-train.jsonl \
  --validation-data /tmp/swiftmend-validation.jsonl \
  --output /tmp/swiftmend-gemma-270m \
  --device mps
```

The script pins `google/gemma-3-270m-it` to a specific revision, saves the LoRA
adapter and merged weights, and records the dataset hashes, accelerator,
training backend, operating system, architecture, and package versions in
`training-manifest.json`. `--device auto` prefers CUDA and then MPS.

## 3. Convert the merged model to LiteRT-LM

Download `tokenizer.model` from the same pinned Gemma revision used for
training. The text-only checkpoint reports `gemma3_text`, which LiteRT-Torch
does not recognize as a model type, and its default JSON tokenizer cannot be
used by LiteRT-LM 0.16 constrained decoding. Both overrides are required:

```sh
uv tool install litert-torch==0.9.4
litert-torch export_hf \
  --model=/tmp/swiftmend-gemma-270m/merged \
  --output_dir=/tmp/swiftmend-gemma-270m/litert \
  --externalize_embedder \
  --litert_lm_model_type_override=gemma3 \
  --tokenizer_path_override=/path/to/pinned/tokenizer.model
```

The 2026-08-29 local run is blocked at this boundary. The merged PyTorch model
produced valid, accurate recovery actions for 13 of 14 held-out scenarios on
MPS. The LiteRT-LM artifact produced by LiteRT-Torch 0.9.4 emitted only
`<pad>` with both the Swift benchmark and the `litert-lm` 0.16.1 CLI. The
same day's nightly converter, 0.10.0.dev20260829, could not package against
the published `litert-lm-builder` 0.16.1 schema. Do not treat either converted
artifact as a candidate or switch the app away from the verified 1B model.

Create an immutable descriptor for the exact converted artifact. Replace the
revision placeholder with the SHA-256 printed for `training-manifest.json`:

```sh
shasum -a 256 /tmp/swiftmend-gemma-270m/training-manifest.json
swift run SwiftMendModelTool \
  --model /tmp/swiftmend-gemma-270m/litert/model.litertlm \
  --id swiftmend/gemma-3-270m-recovery \
  --revision <training-manifest-sha256> \
  --parameter-count 270000000 \
  --output /tmp/swiftmend-gemma-270m/model-manifest.json
```

Run both models against the held-out test split on the same machine, OS,
LiteRT-LM version, and backend:

```sh
swift run SwiftMendBenchmark \
  --model /path/to/gemma3-1b-it-int4.litertlm \
  --split test \
  --backend gpu \
  --output /tmp/swiftmend-1b-report.json

swift run SwiftMendBenchmark \
  --model /tmp/swiftmend-gemma-270m/litert/model.litertlm \
  --manifest /tmp/swiftmend-gemma-270m/model-manifest.json \
  --split test \
  --backend gpu \
  --output /tmp/swiftmend-270m-report.json
```

Each report embeds the artifact digest and execution environment. The
comparison tool refuses mismatched environments, identical artifacts, or model
roles other than a 1B baseline and 270M candidate.

## 4. Apply an explicit comparison tolerance

```sh
swift run SwiftMendCompare \
  --baseline /tmp/swiftmend-1b-report.json \
  --candidate /tmp/swiftmend-270m-report.json \
  --max-accuracy-drop <agreed-fraction> \
  --max-json-drop <agreed-fraction> \
  --max-fallback-increase <agreed-fraction> \
  --max-latency-ratio <agreed-ratio> \
  --max-memory-ratio <agreed-ratio>
```

There are deliberately no default tolerances. A switch requires an explicit product decision and a passing report.
