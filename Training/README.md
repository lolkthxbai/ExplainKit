# Gemma 3 270M experiment

This directory contains the reproducible, gated experiment for testing whether a specialized Gemma 3 270M model can replace the 1B local baseline. The 270M model is not the default and must not be shipped unless it passes the comparison gate on the same held-out scenarios.

The model repositories are license-gated. Accept the Gemma license on Hugging Face and provide `HF_TOKEN` only in the training environment; never add it to this repository.

## 1. Export the versioned data

```sh
swift run SwiftMendDatasetTool --split training --output /tmp/swiftmend-train.jsonl
swift run SwiftMendDatasetTool --split validation --output /tmp/swiftmend-validation.jsonl
```

The v1 dataset has one training, one validation, and one held-out test scenario per category. That is enough to validate the pipeline, not enough evidence for a production model decision. Expand and review v2 before treating the fine-tune as more than an experiment.

## 2. Train the adapter on a CUDA machine

```sh
python -m venv .venv
. .venv/bin/activate
python -m pip install -r Training/requirements.txt
HF_TOKEN=... python Training/finetune_gemma_270m.py \
  --training-data /tmp/swiftmend-train.jsonl \
  --validation-data /tmp/swiftmend-validation.jsonl \
  --output /tmp/swiftmend-gemma-270m
```

The script pins `google/gemma-3-270m-it` to a specific revision, saves the LoRA adapter and merged weights, and records dataset hashes in `training-manifest.json`.

## 3. Convert the merged model to LiteRT-LM

```sh
uv tool install litert-torch-nightly
litert-torch export_hf \
  --model=/tmp/swiftmend-gemma-270m/merged \
  --output_dir=/tmp/swiftmend-gemma-270m/litert \
  --externalize_embedder
```

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
