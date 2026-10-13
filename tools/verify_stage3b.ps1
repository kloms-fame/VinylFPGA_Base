param([string]$IcarusDirectory = 'D:/iverilog/bin')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $env:TEMP 'vinyl_stage3b_verification'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
Push-Location -LiteralPath $projectRoot
try {
    $pageFiles = @('src/display/playback_background.v','src/display/playback_page.v','src/display/lrc_five_osd.v','src/display/song_font_rom.v','src/display/ascii_font_rom.v','src/io/ui_event_bridge.v','src/io/browse_fsm.v')
    $tests = @(
        @{Name='tb_playback_background'; Files=@('src/display/playback_background.v','sim/tb_playback_background.v')},
        @{Name='tb_stage3a_page'; Files=@('sim/tb_stage3a_page.v') + $pageFiles},
        @{Name='tb_stage3b_page'; Files=@('sim/tb_stage3b_page.v','sim/tb_stage3a_page.v') + $pageFiles},
        @{Name='tb_background_frame_select'; Files=@('src/video/background_frame_select.v','sim/tb_background_frame_select.v')},
        @{Name='tb_background_cache_loader'; Files=@('src/video/background_cache_loader.v','sim/tb_background_cache_loader.v')},
        @{Name='tb_background_cache_full_frame'; Files=@('src/video/background_cache_loader.v','sim/tb_background_cache_full_frame.v')},
        @{Name='tb_background_sector_mux'; Files=@('src/video/background_sector_mux.v','sim/tb_background_sector_mux.v')},
        @{Name='tb_background_index'; Files=@('src/SD/song_index_db.v','sim/tb_background_index.v')},
        @{Name='tb_song_index_db'; Files=@('src/SD/song_index_db.v','sim/tb_song_index_db.v')},
        @{Name='tb_stage3b_raster_read'; Files=@('src/video/background_raster_address.v','src/SD/frame_fifo_read.v','sim/tb_stage3b_raster_read.v')},
        @{Name='tb_stage3b_shared_writer'; Files=@('src/video/background_cache_loader.v','src/video/background_sector_mux.v','src/video/mv_stream_player.v','src/SD/frame_fifo_write.v','src/sync_2ff.v','sim/tb_stage3b_shared_writer.v')},
        @{Name='tb_frame_fifo_read_pace'; Files=@('src/video/background_raster_address.v','src/SD/frame_fifo_read.v','sim/tb_frame_fifo_read_pace.v')},
        @{Name='tb_frame_fifo_write'; Files=@('src/SD/frame_fifo_write.v','sim/tb_frame_fifo_write.v')}
    )
    foreach ($case in $tests) {
        $simulationPath = Join-Path $outputDirectory ($case.Name + '.vvp')
        & (Join-Path $IcarusDirectory 'iverilog.exe') -g2005 -I src/include -s $case.Name -o $simulationPath @($case.Files)
        if ($LASTEXITCODE -ne 0) { throw ('COMPILE_FAILED ' + $case.Name) }
        & (Join-Path $IcarusDirectory 'vvp.exe') $simulationPath
        if ($LASTEXITCODE -ne 0) { throw ('SIM_FAILED ' + $case.Name) }
    }
    python tools/test_pack_backgrounds.py
    if ($LASTEXITCODE -ne 0) { throw 'PC_BACKGROUND_TEST_FAILED' }
    python tools/vinyl_packer.py verify --image 'doc/资源/sd卡/stage3b/card_STAGE3B.img'
    if ($LASTEXITCODE -ne 0) { throw 'IMAGE_READBACK_FAILED' }
    Write-Output 'STAGE3B_VERIFICATION_PASS'
} finally { Pop-Location }
