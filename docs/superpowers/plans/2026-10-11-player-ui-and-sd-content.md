# VinylFPGA Playback UI and SD Content Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents are available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finalize the selection/playback UI and move song text, lyrics, and playback backgrounds to versioned TF-card assets, then validate four independent tracks.

**Architecture:** Keep rendering and media control in the existing FPGA pipeline. A PC packer converts source files to compact, fixed-format PCM, RGB565 video, text and background assets; the FPGA loads sidecars before playback and does not decode common media containers or UTF-8.

**Tech Stack:** Verilog RTL, Python, FFmpeg, Pillow, FAT32/SD SPI, SDRAM, Anlogic TD and SynthPilot MCP.

---

## Chunk 1: Selection and Playback UI

### Task 1: Add focused UI verification

**Files:**
- Create: `sim/tb_playback_progress.v`
- Create: `sim/tb_playback_page.v`
- Create: `sim/tb_browse_info_osd.v`
- Create: `sim/tb_lrc_five_osd.v`
- Create: `sim/run_player_ui.do`

- [ ] **Step 1: Write progress boundary checks**

Check elapsed samples at 0, half duration, exact end, and beyond end. Expected fills are 0, approximately 160, 320, and 320 pixels.

- [ ] **Step 2: Write progress-pixel checks**

Drive a patterned input background through `playback_page`. Check x=15 and x=336 remain untouched, x=16 is the first progress pixel, and at fill=320 x=335 is filled. Check fill=0 leaves the underlying RGB unchanged across the whole bar rectangle.

- [ ] **Step 3: Write browsing metadata checks**

Check the new selection row displays song number, title, artist, and `MM:SS` duration, truncates title/artist at glyph boundaries with an ellipsis, and never overwrites the duration field.

- [ ] **Step 4: Add the targeted ModelSim runner**

Compile the four testbenches with the project include paths and run them from `sim/run_player_ui.do`. Expected result: all checks pass and `$finish` exits with code zero.

### Task 2: Add the confirmed glyph advances

**Files:**
- Modify: `tools/gen_lrc_assets.py`
- Modify: `src/display/song_font_rom.v` (generated output)
- Modify: `src/display/song_text_rom.v` (generated output)
- Modify: `src/display/playback_page.v`
- Modify: `src/display/lrc_five_osd.v`
- Modify: `src/include/song_text_geom.vh` (generated output)
- Modify: `src/top_tf_hdmi_audio.v`

- [ ] **Step 1: Extend glyph metric and wrapping checks**

Add cases for narrow/wide Latin glyphs, digits, ASCII space, ideographic space, Chinese glyphs, and mixed-script LRC wrapping. Expected advances: Latin/digits 7–9 px, both spaces 5 px, Chinese/full-width 16 px. Verify English breaks at spaces when possible, a word wider than 256 px splits only at glyph boundaries, Chinese wraps at glyph boundaries, and no visual line exceeds 256 px.

- [ ] **Step 2: Enforce lyric-group limits in the PC generator**

Represent each timestamp as one logical lyric group with one or more visual segments. Keep all segments on the same timestamp and highlight state. Reject groups with more than five visual rows, more than 51 glyph references on a visual row, or a row wider than 256 px; report the source file and timestamp instead of truncating.

- [ ] **Step 3: Emit advance and visual-line metadata**

Keep the existing 16×16 glyph bitmap. Emit the advance beside each local glyph and precomputed visual-line glyph references/offsets so subsequent text starts at the accumulated advance, not at `glyph_index × 16`. Replace the generator's current fixed 16-glyph logical-line assumption with the confirmed width-based wrapping and group limits. Widen the generated logical/visual-row representation and top-level connections so a 256 px row can carry up to 51 glyph references; update `song_text_rom.v`, `lrc_five_osd.v`, and `top_tf_hdmi_audio.v` together instead of truncating to the existing 128-bit/16-glyph path.

- [ ] **Step 4: Render title/artist/lyric glyphs by accumulated x position**

Use the same advance semantics for playback title, artist, and lyrics. Render all wrapped segments for the active timestamp with the same highlight state, preserve frame-synchronous five-row scrolling, and skip to the latest active timestamp after a time jump. Preserve the shared synchronous font read and its one-cycle RGB/DE/VS/x alignment.

- [ ] **Step 5: Verify wrapping, resource, and timing behavior**

Run generator reproducibility and wrapping checks plus the focused UI ModelSim runner. Confirm the generated glyph map and line layout are deterministic, no visual row exceeds 256 px, same-timestamp segments highlight together, over-limit groups fail with a useful diagnostic, and current 16 px Chinese spacing is unchanged.

### Task 3: Set the playback time and progress geometry

**Files:**
- Modify: `src/include/playback_layout.vh`
- Modify: `src/display/playback_progress.v`
- Modify: `src/display/playback_page.v`
- Modify: `src/top_tf_hdmi_audio.v`
- Test: `sim/tb_playback_progress.v`
- Test: `sim/tb_playback_page.v`

- [ ] **Step 1: Change progress fill to a 9-bit 0..320 value**

Update the progress numerator/divider output and all ports/registers that carry `progress_fill`. Clamp elapsed to total, return 0 for unknown/zero duration, and force exactly 320 when elapsed is at or beyond total.

- [ ] **Step 2: Move the bar to x=16 and width=320**

Update `PLAYBACK_PROGRESS_X/W`; remove the inset border/track rectangle. Draw only filled progress over the incoming image/background so the unfilled segment stays transparent.

- [ ] **Step 3: Format elapsed and remaining time**

Display elapsed `MM:SS` aligned left and remaining `-MM:SS` aligned right above the bar, where remaining time is `max(total-elapsed, 0)`. Keep selection duration as total `MM:SS`; use the same compact glyph advances and prevent overlap. Extend `tb_playback_page` to verify exact formatting and alignment at zero, mid-song, end, and unknown/zero duration; end time must show `00:00` remaining and unknown duration must follow the documented fallback without overflowing either side.

- [ ] **Step 4: Remove playback information panels**

Replace opaque panel/border painting in `playback_page` with transparent composition. Keep the MV/cover rectangle and waveform/OSD priority unchanged.

- [ ] **Step 5: Run focused UI verification**

Run: `vsim -c -do sim/run_player_ui.do`

Expected: the UI testbenches pass with no off-by-one at x=335 or fill=320, and no frame/black background is drawn behind the progress or lyric region.

### Task 4: Add the selection-page information row

**Files:**
- Create: `src/display/browse_info_osd.v`
- Modify: `src/top_tf_hdmi_audio.v`
- Modify: `sim/tb_browse_info_osd.v`
- Modify: `prj/VinylFPGA.al` if the project source list requires explicit registration

- [ ] **Step 1: Define a fixed-width OSD interface**

Pass focused song ID, title/artist glyph data and lengths, and duration derived from the focused PCM byte count. Keep video timing and one-cycle font alignment explicit.

- [ ] **Step 2: Draw one bottom row without a panel**

Render `序号 歌名 歌手` and total duration on the central-cover selection page. Use the accumulated glyph advances from Task 2. Reserve duration space first; shorten title/artist with an ellipsis at a glyph boundary.

- [ ] **Step 3: Integrate only in browse mode**

Add the OSD after the selected cover/video composition and gate it off during playback, boot, diagnostic, and invalid-display states.

- [ ] **Step 4: Run the browse OSD and page tests**

Run: `vsim -c -do sim/run_player_ui.do`

Expected: row contents follow focused song changes, duration follows that song's PCM size, and the overlay does not change cover pixels outside the row.

### Task 5: Establish the first implementation gate

**Files:**
- Review: `prj/VinylFPGA.al`
- Review: `src/top_tf_hdmi_audio.v`
- Evidence: `doc/项目分析_20261009/` (new dated phase report)

- [ ] **Step 1: Run existing visual and text regressions**

Run: `python tools/verify_visual_feedback.py` and `python tools/verify_lrc_assets_repro.py`.

Expected: both report PASS; generated font assets remain reproducible.

- [ ] **Step 2: Run the fixed native implementation flow**

Build the current source with the same TD `area_prior → seed 5 place → route → fix_hold → final` procedure used for the baseline. Use SynthPilot `td_build(end_step=opt_gate)` only as a quick diagnostic.

- [ ] **Step 3: Compare like-for-like resource/timing reports**

Record Slice, PLB, LUT, BRAM9K, DSP, Setup/Hold WNS/TNS, and failing endpoints against the current baseline. Do not accept gate-only QoR as route signoff.

- [ ] **Step 4: Commit the UI phase**

Commit the focused tests, generator/RTL changes, project registration, and dated evidence report together after the native route passes.

---

## Chunk 2: TF Card Content, Runtime Loading, and Four-Track Acceptance

### Task 6: Build the manifest-driven PC media pipeline

**Files:**
- Create: `songs.json` (release input template)
- Create: `tools/song_media_pack.py`
- Modify: `tools/vinyl_packer.py`
- Modify: `tools/mv_pack.py`
- Create: `tools/test_song_media_pack.py`

- [ ] **Step 1: Add manifest and preflight validation**

Read exactly four track records with stable IDs 0–3 and three background sources. Validate every referenced source path, title, artist, LRC encoding, duplicate ID, required external tool, and target FAT volume. Add a dry-run mode that reports planned outputs, byte totals, per-track hashes, sidecar sizes, and remaining card capacity without writing a flashable image.

- [ ] **Step 2: Convert audio and cover assets**

Use FFmpeg to convert each source audio to signed 48 kHz, 16-bit, mono little-endian PCM. Preserve the current cover conversion behavior while reporting its output dimensions and hash. Record the exact PCM sample count and duration used as the timing authority for that track.

- [ ] **Step 3: Convert MV sources to the fixed playback format**

Decode common video inputs, center-crop while preserving aspect ratio to 320×240, resample to 10 fps, and encode top-down RGB565LE. Set target frames to `ceil(audio_samples / 4800)`, trim excess frames, and clone the final decoded frame when short. Reject empty/unreadable video and report conversion details per track.

- [ ] **Step 4: Convert and preview the three backgrounds**

Center-crop each source to 4:3, apply configurable Gaussian pre-blur, resize to 160×120, and encode RGB565LE. Emit a preview PNG and verify each payload is exactly 38,400 bytes; the combined image payload must be exactly 115,200 bytes.

- [ ] **Step 5: Test packer decisions and resource accounting**

Use tiny deterministic media fixtures to check crop, frame-rate conversion, audio-master trim/pad, RGB565 byte order, background dimensions, manifest errors, and card-capacity rejection. Verify repeated runs produce identical hashes and that the dry-run detects the current directory-entry limit before creating the final card image.

### Task 7: Add sidecar packaging and INDEX v3 compatibility

**Files:**
- Modify: `tools/vinyl_packer.py`
- Modify: `tools/test_vinyl_packer.py`
- Modify: `src/include/song_index_defs.vh`
- Modify: `src/SD/song_index_db.v`
- Modify: `sim/tb_song_index_db.v`
- Evidence: `doc/项目分析_20261009/` (new dated format/compatibility report)

- [ ] **Step 1: Serialize TEXT.BIN and BG.BIN with checked headers**

Write the four track text sections, local glyph/advance table, title/artist references, timestamp groups, and wrapped visual rows into `TEXT.BIN`. Write exactly three consecutive 160×120 RGB565LE payloads into `BG.BIN`. Include magic, format version, lengths/counts, and payload CRCs as specified. Reject any per-track glyph, reference, timestamp, visual-row, or line-width limit before emitting final outputs.

- [ ] **Step 2: Emit INDEX v3 descriptors and checksum**

Keep the 64-byte header and four 64-byte entries. Populate the reserved header offsets for TEXT/BG first clusters, byte sizes, and CRC32. Implement the specified v3 header-and-entry `index_crc32` coverage without altering the v1/v2 entry CRC semantics.

- [ ] **Step 3: Preserve v1/v2 media behavior**

Extend the index database parser to accept v1, v2, and v3. Keep existing title/media entry interpretation for v1/v2; for v3 validate all descriptor ranges before use. Missing/invalid sidecars must lead to the specified placeholders and must never create an unchecked cluster or byte address.

- [ ] **Step 4: Add binary-format compatibility tests**

Extend `test_vinyl_packer.py` and `tb_song_index_db.v` with byte-exact CRC vectors, valid v1/v2/v3 records, corrupted header/entry/sidecar CRCs, out-of-range descriptors, and maximum four-track count. Verify the final root listing contains the 15 required 8.3 files within the first 16 directory entries.

- [ ] **Step 5: Record measured format and memory boundaries**

Compare the implemented serialization sizes against the four real LRC files and the 4,096-reference/192-glyph limits. Recheck the SDRAM address map and reserve a non-overlapping background region before runtime-loader integration; update the dated report with measured card, SDRAM, and BRAM estimates.

### Task 8: Load focused track text from TF before playback

**Files:**
- Modify: `src/SD/fat32_file_streamer.v`
- Modify: `src/SD/fat32_media_loader.v`
- Modify: `src/SD/media_supervisor.v`
- Create: `src/SD/fat32_sidecar_loader.v` (if existing stream interfaces cannot safely serve sidecars)
- Create: `src/display/song_text_ram.v`
- Modify: `src/top_tf_hdmi_audio.v`
- Create: `sim/tb_fat32_sidecar_loader.v`
- Create: `sim/tb_song_text_ram.v`
- Modify: `prj/VinylFPGA.al` if explicit source registration is required

- [ ] **Step 1: Add bounded sidecar reads on the existing FAT stream**

Reuse the existing FAT file-stream path where possible. Read the requested track section by validated cluster/offset/length, enforce sidecar size and address bounds, check CRC, and surface completion, timeout, and error status. Do not add a second independent SD command master.

- [ ] **Step 2: Preload text on browse focus changes**

When the focused song ID changes, request that track's title, artist, glyphs, and lyric tables into the active text RAM. Use latest-focus-wins semantics: an in-flight obsolete read may finish, but its data cannot commit; then service the newest pending focus ID. Publish metadata only after the matching track ID has completed validation. Show the documented loading/error placeholder while unavailable; never show the previous track's title or lyrics for the new focus.

- [ ] **Step 3: Gate playback start on matching text readiness**

If the user confirms the currently focused track while its text load is in progress, hold the start transition until `text_ready` matches that song ID or a bounded load error is raised. Preserve the existing media error/recovery path and permit audio playback with the documented no-lyrics fallback when the text resource is invalid.

- [ ] **Step 4: Test FAT traversal, bounds, and replacement semantics**

Simulate fragmented TEXT.BIN clusters, final partial sectors, valid and invalid CRCs, read timeouts, rapid focus changes during a load, and confirm during loading. Verify only the newest focus ID is published, obsolete load completion cannot overwrite it, no playback start uses mismatched metadata, and no stale track text leaks through an error.

### Task 9: Replace playback text ROMs with runtime text assets

**Files:**
- Modify: `src/display/lrc_five_osd.v`
- Modify: `src/display/song_text_rom.v` (remove runtime dependency or retain only compatibility fallback)
- Modify: `src/display/song_font_rom.v` (replace static content dependency with active text RAM lookup)
- Modify: `src/display/song_text_geom.vh` (generated/static assumptions)
- Modify: `src/top_tf_hdmi_audio.v`
- Modify: `sim/tb_lrc_five_osd.v`
- Modify: `prj/VinylFPGA.al` if explicit source registration is required

- [ ] **Step 1: Connect runtime glyph and lyric tables to the renderer**

Read active-track glyph bitmap, advance, timestamp, group, and visual-row tables from the validated text RAM. Preserve one-cycle synchronous glyph timing and explicit RGB/DE/VS alignment. Ensure the existing static song text/font ROM contents are not required for v3 assets.

- [ ] **Step 2: Verify focus-to-playback continuity**

Show the focused title/artist on the browse row from the loaded dynamic assets, then reuse the same loaded track data after playback starts. Check that song changes replace the previous track atomically at a frame boundary and that an absent/invalid LRC displays the agreed placeholder.

- [ ] **Step 3: Run four-track text acceptance in simulation**

Load all four packaged text sections in sequence. Check UTF-8 source decoding on the PC side, glyph identity, title/artist, timestamp activation, mixed Chinese/English advances, five-row scrolling, same-timestamp wrapped groups, and the newest-line behavior after a time jump.

- [ ] **Step 4: Run the text-stage native route gate**

Run the same fixed native route used for the UI baseline. Compare PLB, LUT, BRAM9K, DSP, setup/hold WNS/TNS, and failing endpoints. Confirm that dynamic active-track text replaces rather than duplicates static ROM storage, and stop before background work if the BRAM net increase exceeds five blocks or any resource/timing gate fails.

### Task 10: Preload and display three selectable playback backgrounds

**Files:**
- Create: `src/SD/background_preloader.v`
- Create: `src/display/playback_bg_layer.v`
- Modify: `src/io/ui_event_bridge.v`
- Modify: `src/top_tf_hdmi_audio.v`
- Modify: `src/include/playback_layout.vh`
- Create: `sim/tb_background_preloader.v`
- Create: `sim/tb_playback_bg_layer.v`
- Modify: `sim/tb_ui_event_bridge.v` (or the existing key-event test)
- Modify: `prj/VinylFPGA.al` if explicit source registration is required

- [ ] **Step 1: Confirm a non-overlapping SDRAM reservation**

Use the current design's address map and actual read/write widths to reserve space for exactly 115,200 bytes of background payload. Document the base/end range and prove it does not overlap MV, cover, audio, or frame-buffer storage before enabling writes.

- [ ] **Step 2: Preload and validate all background slots**

Read the three images from BG.BIN before playback, validate dimensions, exact payload length, and CRC, then set an independent valid bit for each slot. On an invalid slot, keep the other valid images usable and use the specified solid-color fallback if none are valid.

- [ ] **Step 3: Add nearest-neighbor 4× background composition**

Scale source coordinates by dividing the 640×480 display coordinates by four. Use a small source-row/pixel cache so each RGB565 source pixel is reused for its 4×4 output block. Place the background below the central MV/cover and all text/waveform overlays; commit buffer/index changes at frame start.

- [ ] **Step 4: Route KEY6 as one debounced press event**

Map `exp_key_n[5]` / GPIOB_15 / H1 as KEY6 to the playback-page background selector. A debounced press edge advances 0→1→2→0 once; holding does not repeat, another change requires release then press, and browse/boot/error pages ignore it.

- [ ] **Step 5: Verify pixels, key behavior, and resource impact**

Check all four corners and 4× replication boundaries for each background. Check CRC failure fallback, invalid slots, KEY6 bounce/hold/release, no automatic change, and unchanged song time/MV state. Run a same-flow native route and enforce the BRAM/PLB/timing gates before continuing.

### Task 11: Run four independent tracks through full acceptance

**Files:**
- Input: `songs.json` and the user's four independent audio, cover, MV, LRC, and three background source assets
- Output: `dist/card/` (final FAT card image and `INDEX.json` report)
- Evidence: `doc/项目分析_20261009/` (final acceptance report)
- Modify: project test/packaging scripts only if acceptance exposes a reproducible defect

- [ ] **Step 1: Freeze the four-track manifest and package report**

Verify every song has distinct expected audio/video/LRC inputs and record source/output SHA-256, duration, PCM sample count, MV frame count, title, artist, and card-space totals. Resolve all packer warnings and confirm the final card image fits the target TF volume.

- [ ] **Step 2: Run progressive SD throughput and recovery trials**

Using the final bitstream and card, test 30-second, 3-minute, then full-length playback with simultaneous PCM/MV reads. Include worst-case fragmented files and track switches. Record SPI payload throughput, audio underruns, missing/late MV frames, timeout recovery, and card/cluster layout. If 10 fps fails, measure the documented lower-rate fallback and regenerate/retest all MV assets.

- [ ] **Step 3: Accept each track's user-facing behavior**

For all four tracks, verify cold start, browse metadata, play, pause, seek, song change, wrapped lyrics, progress endpoints, remaining time, background changes, EOF, and missing/corrupt-resource fallback. Confirm changing only `songs.json` media/LRC/background inputs produces a new card image that works with the same bitstream.

- [ ] **Step 4: Complete native route and board signoff**

Run the complete fixed native route on the final source, record resource/timing reports and failing endpoints, generate the final bitstream and hash, then perform board cold-start and full-length acceptance. Keep the SynthPilot gate build as a diagnostic only; do not substitute it for routed signoff.

- [ ] **Step 5: Commit the release evidence**

Commit the final packer outputs needed for reproducibility, format documentation, route/board evidence, and acceptance checklist. Keep large generated audio/video/card binaries out of Git unless the repository's release policy explicitly requires them.
