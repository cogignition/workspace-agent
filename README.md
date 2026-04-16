# WorkspaceAgent

A native macOS menu-bar app that triages Gmail using a local LLM and the [Google Workspace CLI (`gws`)](https://github.com/googleworkspace/cli). Zero API cost. Zero data exfiltration. Everything runs on-device.

## Requirements

- macOS 14+
- Apple Silicon Mac (M1 or later), 16 GB+ RAM
- [`gws`](https://github.com/googleworkspace/cli) CLI installed and authenticated
- A GGUF model file (see [Models](#models))

## Install

```bash
git clone https://github.com/cogignition/workspace-agent
cd workspace-agent
./script/build_and_run.sh
```

The script compiles, bundles a `.app`, kills any previous instance, and launches. Logs stream via `log stream`.

## Setup

1. Click the menu bar icon → **Settings**
2. **General** — set your `gws` binary path (e.g. `/opt/homebrew/bin/gws`)
3. **Model** — point to a `.gguf` file (see below)
4. Click **Run Email Triage**

## Models

Download to a volume with sufficient free space:

```bash
# Gemma 3 12B Q8 (~12 GB) — fast, fits in 16 GB RAM
hf download bartowski/google_gemma-3-12b-it-GGUF --include "*Q8_0*" --local-dir /path/to/models

# Gemma 4 26B-A4B Q8 (~25 GB) — MoE, fits in 36 GB RAM
hf download bartowski/google_gemma-4-26B-A4B-it-GGUF --include "*Q8_0*" --local-dir /path/to/models
```

Requires `hf` CLI: `pip3 install --break-system-packages huggingface_hub`

## Architecture

```
App.swift                         MenuBarExtra + digest Window + Settings
├── Models/
│   ├── AppState.swift            @Observable state, long-lived services
│   ├── Email.swift               Codable model matching gws +triage JSON
│   └── EmailDigest.swift         Priority-grouped digest output
└── Services/
    ├── InferenceEngine.swift     actor — loads GGUF, streams tokens, auto-unload timer
    ├── GWSService.swift          actor — shells out to gws CLI
    └── EmailTriageService.swift  @MainActor orchestrator: fetch → prompt → infer → digest
```

## Triage Pipeline

1. **Fetch** — `gws gmail +triage --format json` returns id, from, subject, date
2. **Format** — emails serialized to compact JSON for the prompt
3. **Infer** — local LLM produces structured JSON ranking each email 1–5
4. **Parse** — `TriageResult` decoded, merged back onto email structs
5. **Digest** — sorted, grouped into Reply Now / Review Today / Can Wait

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| gws path | `/usr/local/bin/gws` | Path to gws binary |
| Model path | — | Path to `.gguf` file |
| Max emails | 50 | Emails per triage run |
| Keep model loaded | 5 min | Unload timeout (0 = immediate, good for cron) |
| Custom prompt | — | Override the system prompt; use `{emails_json}` placeholder |

## Cron Usage

Set **Keep model loaded** to **Unload immediately** so the model frees ~12 GB RAM after each run, then trigger via launchd or cron:

```bash
open /path/to/WorkspaceAgent.app  # launches and runs on open if configured
```

## Building from Source

```bash
# Debug (default)
./script/build_and_run.sh

# Release
./script/build_and_run.sh release

# Clean
./script/build_and_run.sh clean
```

Requires Xcode 16+ / Swift 6 toolchain. Open in Xcode: `open Package.swift`.

## Dependencies

| Package | Purpose |
|---------|---------|
| [LocalLLMClient](https://github.com/tattn/LocalLLMClient) | llama.cpp Swift wrapper |
| [gws](https://github.com/googleworkspace/cli) | Google Workspace CLI (runtime) |
