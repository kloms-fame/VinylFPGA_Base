# KEY6 lyric focus implementation plan

User approved five-line / current-line focus switching on 2026-10-22 and authorized implementation through a compiled bitstream using the original project.

**Goal:** KEY6 toggles the current lyric's visibility mode with minimal added logic.

**Architecture:** Add a KEY6 event toggle in the 50 MHz UI bridge. Synchronize it into playback_page, consume events only during playback, and publish the requested mode at frame start. Reuse the existing current-row selection to suppress neighboring glyph requests in focus mode. Keep the six-row cache, scroll handshake, font ROM, audio, pins, constraints and project strategy.

**Behavior:** Default five lines; preserve mode across pause, seek, tracks and page changes; ignore browse-page events; reset restores five lines. Preserve the prelude center preview and NO LYRICS. Focus follows the existing current-row scrolling position. No NVM setting is added.

**Tech Stack:** Verilog-2005, Icarus, ModelSim where available, Anlogic TD 6.2.168116, EG4S20BG256.

## Tasks

- [x] Write key-to-display and rendering regression; prove baseline fails because KEY6 does not hide neighboring rows.
- [x] Add lyric_focus_tgl, frame-synchronous mode state, and focus_only row gating; tie new inputs in existing test fixtures.
- [x] Run focused tests, existing key decode, lyric boundaries, UI/page and top integration regressions. Review CDC, reset and scroll boundaries.
- [x] Build original project configuration starting with seed 6; reject its negative timing, compare physical seeds on the same gate DB, then persist passing seed 7 and rebuild original project. Final setup +0.143 ns / hold +0.037 ns, zero TNS.
- [x] Record source hashes, bit hash, resource deltas, build evidence and hardware acceptance instructions in report 29 and release_manifest.json. Physical programming remains for user acceptance.

New sequential state follows explicit zero initialization and reset, one register per always block. Existing surrounding coding style is retained; no unrelated RTL cleanup.

Plan and four-file production diff received independent read-only review. No blocking issue was found. Playback acceptance deliberately follows the existing background control: evaluate page enable when the synchronized event is consumed. Stable browse events and events consumed after leaving playback are drained without changing the mode.

Build outputs must be fresh and bound to this source revision. No physical FPGA programming or SD-card write is part of this request.
