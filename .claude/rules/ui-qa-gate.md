---
paths:
  - "**/*.{html,css,scss,jsx,tsx,vue,svelte}"
  - "**/components/**"
  - "**/pages/**"
  - "**/app/**"
---

# UI / E2E QA Gate

**Scope:** Any change that produces or alters user-visible output: UI components, flags that show or hide content, API responses the frontend consumes, generated images or documents. The delivery-contract evidence format is in `delivery-contract.md`; this rule says what counts as proof.

Why: generation code and unit tests can pass while the artifact never reaches the screen, because the display path was never exercised.

## The gate

Before marking the feature complete, drive the real surface (the browser, or the endpoint a user actually hits) and confirm the artifact appears. A fixture page or mocked network is not the real surface.

- Use the project's browser-automation suite in headed mode for visual features; a headless pass is insufficient. Run it against the real running app at the viewports that matter (phone and desktop).
- For non-visual features (API responses, scheduled output), hit the real endpoint or read the row the UI depends on. "The code generates X" is not evidence; "I opened the UI and saw X" is.

## What to verify

- The artifact exists where expected (database row, file, API response).
- The user path can reach it: not blocked by a flag, an auth gate or a routing gap.
- It is rendered, not just stored.

Record the check in the PR's Real Proof section (for example "opened the page, confirmed the item appeared, screenshot attached").
