# Gemma 3 270M experiment

This directory contains the reproducible, gated experiment used to test whether
a specialized Gemma 3 270M model could replace the 1B local baseline. The strict
same-environment comparison and the target-device benchmark passed on
2026-08-29, so the verified 270M CPU configuration is now the package default.

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
uv run --python 3.12 --with litert-torch==0.9.4 \
  python Training/export_gemma_270m_litert.py \
  --model /tmp/swiftmend-gemma-270m/merged \
  --tokenizer /path/to/pinned/tokenizer.model \
  --output /tmp/swiftmend-gemma-270m/litert
```

The helper calls the converter through Python so `externalize_embedder=False`
is passed as a Boolean rather than command-line text. It also applies the
Gemma 270M key/value cache dimensions and a verified stop policy containing
only `<end_of_turn>` and EOS token 1. The checkpoint's generation configuration
also names token 106 as EOS; accepting that token as an unconditional runtime
stop allowed LiteRT-LM to terminate constrained JSON one character before the
closing brace. The explicit metadata keeps validation fail-closed instead of
repairing malformed model output.

The resulting graph is verified on the macOS CPU backend. LiteRT-LM's Apple GPU
path still emits only `<pad>` for this converted artifact, so do not configure
the 270M candidate with `--backend gpu`.

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
  --backend cpu \
  --output /tmp/swiftmend-1b-report.json

swift run SwiftMendBenchmark \
  --model /tmp/swiftmend-gemma-270m/litert/model.litertlm \
  --manifest /tmp/swiftmend-gemma-270m/model-manifest.json \
  --split test \
  --backend cpu \
  --output /tmp/swiftmend-270m-report.json
```

Each report embeds the artifact digest and execution environment. The
comparison tool refuses mismatched environments, identical artifacts, or model
roles other than a 1B baseline and 270M candidate. Use `--cpu-threads` when an
exact CPU thread count needs to be part of the recorded environment.

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

There are deliberately no default tolerances. The 2026-08-29 local reports
passed the strictest no-regression values: zero accuracy or JSON loss, zero
fallback increase, and latency and memory ratios of 1.0. The 270M candidate
scored 100% recovery accuracy and valid JSON with zero fallback; the 1B
baseline scored 21.4%, 92.9%, and 7.1%, respectively. The 270M p95 latency was
1.70 seconds versus 4.26 seconds, and peak memory was 1,883 MiB versus
2,844 MiB.

The separately approved iPhone 17 Pro run exercised the same 14 held-out test
scenarios with the exact candidate checksum through LiteRT-LM 0.16.0 on CPU. It
reproduced 100% recovery accuracy and valid JSON with zero fallback, a 2.09
second p95 latency, and 1,427 MiB peak memory. Every selected action belonged to
its developer-approved catalog, and the report contained no API key, local
path, or raw model response. The same-environment Mac comparison establishes
the strict five-gate no-regression result; the iPhone run establishes target
runtime behavior.

The package now exposes the verified artifact as
`LocalGemmaModelDescriptor.swiftMendGemma3_270MRecovery` and provides
`LocalGemmaConfiguration.swiftMendGemma3_270MRecovery(modelURL:cacheURL:)` for
explicit CPU configuration. The general configuration now selects the same
verified 270M/CPU combination by default. The 1B/GPU baseline remains available
through explicit model and backend arguments. The 270M artifact is rejected if
paired with the GPU backend.
