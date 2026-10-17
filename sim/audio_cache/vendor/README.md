# Vendor model checks

Run from PowerShell at the repository root:

```powershell
& ./sim/audio_cache/vendor/run_vendor_mask.ps1
```

The script uses ModelSim SE 10.6e (`D:/modeltech64_10.6e/win64`), not the older Altera OEM simulator found first on PATH. Override `-ModelSimRoot`, `-TdRoot`, or `-OutputDirectory` when needed. Compilation, generated libraries, the downloaded model, and transcripts go to `%TEMP%/vinyl_vendor_mask_isolation_20261016` by default. No synthesis sources are replaced or decrypted.

The production `audio_sdram_arbiter.v` is connected to the unmodified, protected Anlogic `sdr_as_ram`, `sdr_wrrd`, and `sdr_init_ref` controller sources. The test uses an independent physical SDRAM bus model, rather than replacing the controller user interface with ideal RAM.

The physical model is the Micron MT48LC2M32B2 Verilog bus functional model, version 2.1 dated 2002-06-06, with the same four-bank, 2048-row, 256-column, 32-bit geometry as EM638325. It is fetched from the [FreeCores SDR controller repository](https://raw.githubusercontent.com/freecores/sdr_ctrl/master/verif/model/mt48lc2m32b2.v), preserving the Micron copyright and model header. The exact downloaded bytes must have SHA256 `F4A9D4392AAB3E6765D201D86DCD1350B9D1F5D6ADD016BBC5C79DA1E1AC5060`; the script rejects a different hash. The model is not redistributed in this repository.

Checks observed on 2026-10-16:

- Actual protected controller propagates dynamic write masks to physical DQM. It also propagates them during reads, so DQM must return to zero before admitting reads.
- Actual arbiter preserves the active write mask through queued physical write data, then clears it after 16 quiet memory clocks. The inactive client's mask is deliberately changed immediately after the application write burst.
- Graphics writes with `0001` preserve all 32 preexisting PCM bytes; audio writes with `1110` preserve all 96 RGB bytes; graphics rewrites preserve the new PCM. Model storage is checked after every writer.
- All 32 subsequent full-lane physical read words match the combined RGB/PCM content in the model's specified output window.
- Actual production staging wrapper plus TD `EG_PHY_BRAM32K` model passes 512-byte reads and writes in both directions at 100/125 MHz. `DP16K`, width `16`, `NOREG`, active-high chip select, and output-clock-enable tied high match the behavioral one-cycle read contract. Disabled CS holds output and prevents writes. Include `work.glbl` as another simulation top.

This test is **not EM638325 timing signoff**. With the unchanged Micron model defaults and an ideal 180-degree shifted SDRAM clock, 8/32 application-side return samples are Z at BL4 boundaries, although all physical read words and stored bytes are correct. The transcript explicitly reports this observation separately from the byte-isolation PASS. Timing of the real Etron device, FPGA input path, and PLL phase must be assessed with its proper model or hardware. No production clock/latency changes were made from this supplementary model result. The authoritative Etron device documentation is [EM638325 revision 3.2](https://etron.com/wp-content/uploads/2022/04/EM638325_Rev-3.2.pdf).

The controller's power counter takes approximately 1.049 ms to initialize at 125 MHz. `Sdr_busy` alone does not cover every trailing write/read beat; the explicit quiet interval and returned-data activity are required for the mask and owner transition.

Pass markers are `PASS encrypted controller:` in `vendor_mask.log` and `PASS actual EG_PHY_BRAM32K` in `vendor_stage.log`. The script requires both markers and a successful simulator command.
