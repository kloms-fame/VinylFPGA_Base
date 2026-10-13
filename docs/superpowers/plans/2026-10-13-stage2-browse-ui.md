# Stage 2 Song Browsing Interface Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a low-resource song browsing information bar while preserving the stage 1 playback page and existing media pipeline.

**Architecture:** Reuse the existing `song_text_rom`, `song_font_rom` raster path, and `playback_progress` total-time ASCII output. Select a frame-coherent browsing song ID in the video domain, and add a mutually exclusive browse renderer inside `playback_page` with a dimmed cover background, metadata, duration, and song markers. No new font ROM, line buffer, arithmetic conversion block, or pixel-clock multiplier is introduced.

**Tech Stack:** Verilog RTL, Anlogic Tang Dynasty, SynthPilot MCP, existing native TD build scripts.

---

## Files and responsibilities

- Modify `src/top_tf_hdmi_audio.v`: select the UI song ID, qualify browse mode, and connect the existing metadata/time buses to the shared renderer.
- Modify `src/display/playback_page.v`: preserve playback rendering and add the approved browse bar/metadata/indicator using the existing font and one-cycle video pipeline.
- Create `doc/阶段二_选歌浏览界面人工验收.md`: board-side SRAM programming and manual acceptance checklist.
- Create an isolated synthesis/build snapshot under `prj/resource_opt_verified_20261005/`; keep generated files out of tracked RTL.

## Chunk 1: Shared browse rendering

- [x] Confirm the existing text-ROM ASCII mapping, metadata packing, pixel pipeline latency, and browse/play mode sources.
- [x] Add frame-coherent browse song selection and connect the unified ID to `song_text_rom` and `playback_page`.
- [x] Implement the approved 576×41 bottom bar, track label, 360-pixel title/artist area with 8-pixel separator, total time, and four song markers while retaining stage 1 playback behavior.
- [x] Keep blanking black, delay mode/coordinates/video controls consistently with the existing font read, and avoid additional ROMs or variable multiply/divide operations.

## Chunk 2: Verification and handoff

- [x] Run `git diff --check` and review the focused RTL diff.
- [x] Freeze an isolated source snapshot and use SynthPilot for RTL analysis and `opt_gate` synthesis; inspect area and timing reports.
- [ ] Run the project native route/build flow from an immutable snapshot, launch bit generation in the background after route success, and do not block implementation work on bitgen completion.
- [x] Write the Chinese manual acceptance guide covering cold boot, four song selections, text readability, total-time refresh, mode transitions, stage 1 playback regression, and video blanking.
- [ ] Report the synthesis/implementation evidence and give the user the bitfile location and acceptance steps. Do not commit until the user confirms manual board acceptance.
