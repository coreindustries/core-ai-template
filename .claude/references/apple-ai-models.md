# Apple AI model selection

Verified against Apple's documentation on **2026-11-06**. Recheck SDK declarations, OS
availability, device/language/region support, entitlement terms and pricing before shipping.
These are developer interfaces, not promises that every Apple marketing/research model name
is independently selectable. Apple's system models can change with OS updates.

| Interface | Execution | Suitable work | Required checks / limits |
|-----------|-----------|---------------|--------------------------|
| `SpeechTranscriber` with `SpeechAnalyzer` | On device | Live or saved conversational/long-form transcription | `isAvailable`, supported locale, installed/downloadable assets, actual audio format and timestamps; no automatic cloud fallback |
| `DictationTranscriber` | On device | Explicit fallback for supported devices/languages outside SpeechTranscriber coverage | Check its own availability and options; evaluate accuracy/latency rather than claiming parity |
| `SystemLanguageModel.default` | On device | Summaries, structured extraction, classification and supported image understanding | Apple Intelligence availability, locale, capabilities, context budget; image support requires the appropriate newer OS/model capabilities |
| Vision pretrained models | On device | OCR, face/rectangle detection, image comparison and classification | Request/revision support, bounded images, actual coordinate/time transforms; face detection is not identity recognition |
| Core ML / Core AI and custom model integrations | On device | Dedicated embeddings, diarization or source-separation models when needed | These are execution frameworks, not one bundled Apple model; review model origin/license, size, supported operators, hardware use and measured quality |
| `PrivateCloudComputeLanguageModel` | Apple's Private Cloud Compute | Optional larger-context analysis and stronger reasoning | iOS/macOS 27+ API availability, Apple Intelligence device/region, managed entitlement, connectivity and per-user quota; explicitly disclose cloud processing |

[SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber) and
[Apple's speech overview](https://developer.apple.com/videos/play/wwdc2025/277/) describe the
local speech/fallback interfaces. [Foundation Models](https://developer.apple.com/documentation/foundationmodels),
[its updates](https://developer.apple.com/documentation/updates/foundationmodels), and
[Vision](https://developer.apple.com/documentation/vision) define the other native interfaces.

## Local versus Private Cloud Compute

Apple currently documents a **4K-token on-device** context and **32K-token PCC** context;
PCC offers configurable reasoning effort, needs a network connection and has daily per-user
limits, with higher access through iCloud+. It does not require an app-managed API key.
Read `contextSize`, token-counting/capability/availability and quota APIs where supported;
do not compile these comparison numbers into the app as permanent limits.
[PCC integration and comparison](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute?changes=latest_major)

PCC access is conditional: Apple currently requires enrollment in the App Store Small Business
Program, fewer than two million first-time App Store downloads from any app, and the assigned
managed entitlement. Eligible developers have no cloud API cost under those terms. Check the
account and current terms; do not assume entitlement approval, universal free access, or that
an app's own purchase unlock increases Apple's user quota.
[PCC eligibility](https://developer.apple.com/private-cloud-compute/)

For a local-only feature, keep inference local even when a model is unavailable. Show the
reason and offer supported local work, asset setup or a separate explicit cloud action.
Privacy-preserving cloud computation still sends input off the device; do not describe it
as offline or silently route a failed local request to PCC/another provider.

## Inference contract

- Select by actual SDK API and capabilities. Record API/model metadata exposed by the SDK,
  OS/build, locale and relevant model/asset availability for reproducible evaluations; avoid
  equating `default` with a fixed research-family model, parameter count or hardware engine.
- CPU/GPU/Neural Engine scheduling is framework/model dependent. Verify with Instruments;
  do not promise that every inference uses the Neural Engine or uses no app memory/energy.
- Reserve context for instructions, schema, input, response and reasoning. Count tokens with
  supported APIs. Chunk/reduce or retrieve bounded relevant passages for long recordings;
  never silently truncate a two-hour transcript or accumulate unbounded conversation history.
- Prefer guided structured generation (`@Generable`) when output is structured. Validate
  semantics separately: types do not prove factuality. Require exact supporting transcript
  evidence for extracted claims and detector-matched URLs; preserve uncertainty/refusal.
- Treat transcript, OCR, image text and intermediate model output as data, not instructions.
  Delimit/encode inputs, keep system instructions separate, and grant no tools by default.
  A tool-using feature needs explicit allowlists, argument validation and action authorization.
- Use bounded sequential inference for media analysis; do not run a model per incoming frame
  or audio packet. Cancel by session/operation identity and reject late publication. Keep
  generation separate from explicitly saving derived artifacts; never overwrite source media.
- Preserve source-channel labels and source timestamps. Mic/system separation is not speaker
  diarization; an LLM must not infer identities or fabricate a clean audio waveform. Evaluate
  acoustic echo processing and individual-speaker models independently if the product needs them.
- Evaluate normal, overlapping, multilingual, noisy, long-context, refusal and prompt-injection
  cases on supported real hardware. Compare before/after output when prompts/OS models change;
  distinguish deterministic validators, human review and an actually executed model judge.

## Diagnostics boundary

Keep meeting content out of automatic crash/product analytics. Useful opt-in aggregates include
session duration bucket, error domain/code, peak memory, CPU time, queue high-water marks,
dropped packets and flush/export latency. Batch off the media queues. User-submitted reports
should preview any attached logs/images. Adding a cloud SDK requires checking its actual
collection behavior, privacy manifest and App Store answers; no session replay by default.
[Apple privacy data types](https://developer.apple.com/app-store/app-privacy-details/)
