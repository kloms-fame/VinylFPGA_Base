# MV playback resilience and compact storage

User authorization: implement stutter repair, optimize MV assets, minimize FPGA resources, and build the original `prj/VinylFPGA.al` through bitgen. The preceding analysis and this request establish the implementation scope; no additional approval checkpoint is needed for reversible implementation and verification.

## Selected design

Store pairs of RGB565 pixels in one SDRAM word inside the existing MV region [1228800,1459200). Six 38400-word frames occupy the same 230400 words as the previous three RGB888 frames. The SD contract stays 320x240 RGB565LE, 10 fps, 300 sectors per frame; no image quality loss or extra BRAM. A parameterized scheduler tracks six bank tags and a ready bitmap; select the newest due completed frame at vblank and protect displayed, queued and in-flight banks across restart/cancellation.

The SD player packs four bytes per output token. The shared SDRAM writer uses all four byte lanes only for MV; other graphics retain their low-byte protection, and audio keeps its existing byte masks. MV addresses do not overlap the audio byte-lane ring. Preselect bank base before the existing two-bit indexed frame-controller interface. In composite reads, one MV word advances two screen pixels, including the hidden background cursor; total command count becomes 268800. Video-clock unpacking consumes one FIFO word for an MV pixel pair, one per background pixel, preserving the existing one-cycle return pipeline and all picture boundaries.

Keep existing audio LOW/HIGH, strict audio priority, single-sector CMD17/SPI, clocks, pins and implementation strategies. Proactive audio refill, CMD18 and faster external SPI are deferred to avoid unrelated risk. Existing three-bank behavior remains available via default parameters for legacy callers; production explicitly enables six-bank packed mode.

Alternatives: only optimize SPI/control bubbles (low state cost but cannot cover 220 ms token delays); lower audio protection (known regression); reuse cover regions (larger UI/lifecycle risk). Compact MV storage provides the clearest benefit without new memory or reduced quality.

## Verification and limits

First reproduce old three-slot failure in a six-bank fill/hold test. Check exact packed bytes, every RGB565 output pixel, MV/background row boundaries, full-screen output counts, graphics masks, bank/address bounds, cancellation/Seek/pause/EOF and old format compatibility. Repeat the previous 220 ms single-sector and 400 ms slow-window tests with no extra display holds after queue warmup; preserve a longer out-of-budget case that safely holds/catches up. Check original 4.9 s audio budget case and actual top integration. Run ModelSim and retain waveform evidence. Build original .al, inspect fresh stage markers/databases, final setup/hold, resources and bit identity. Do not call a generated bit board-verified.

Six banks offer finite resilience (about five future 100 ms frames when full), not a guarantee against unlimited card stalls or sustained insufficient throughput. Original author static frames remain static. Native 10 fps is preserved.

## Stage handoff

current_stage=design; goal=bounded MV stalls absorbed using same SDRAM; confirmed_constraints=EG4S20BG256, existing clocks/ADC/SDC/strategies, audio guard intact; artifacts=this spec and implementation plan; decision=implement compact six-bank buffering; blocking_reason=none; next_action=failing tests then RTL, integration, original-project build.
