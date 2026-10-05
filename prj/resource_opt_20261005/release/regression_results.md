### tb_bmp_read_stability
PASS: valid scan finds sector 0
PASS: valid scan reports one image
PASS: valid load has no error
PASS: valid load writes 8 pixels
PASS: bad DIB reports ERR_HEADER
PASS: bad planes reports ERR_HEADER
PASS: hort file_len reports ERR_HEADER
PASS: xel stream reports ERR_TRUNCATED
PASS:  BMP fast-skip lands on sector 2
PASS: fast-skip finds the valid image
PASS:  SD response reports ERR_TIMEOUT
PASS: scan timeout reports ERR_TIMEOUT
PASS: or scan is not falsely timed out
PASS: bmp_read stability tests completed
### tb_cluster_offset_equiv
PASS: 262144 cluster offset cases, all BPB byte values
### tb_fat32_file_streamer
PASS: FAT32 fragmented FAT chain
### tb_fat32_media_loader
PASS: FAT32 media loader scan/load/pixel pipeline
### tb_fat32_streamer_equiv
PASS: FAT32 fragmented FAT chain
### tb_fat32_volume_scanner
PASS: FAT32 volume scanner
### tb_frame_fifo_read_gap
PASS: frame_fifo_read burst gap min=14 cycles
### tb_frame_fifo_read_pace
PASS: refresh window holds off new read bursts (60 cycles, 0 pulses)
PASS: read burst resumed 3 cycles after refresh deasserted
PASS: controller-busy window holds off new read bursts (60 cycles, 0 pulses)
PASS: low-watermark fallback issued a burst (3 cycles) despite busy+refresh
PASS: tb_frame_fifo_read_pace all checks passed (pulses=1024 bursts=4 min_gap=14)
### tb_frame_fifo_write
PASS: frame_fifo_write registered-level burst
### tb_hdmi_pcm_audio_bridge
PASS: 48kHz PCM count=4800, amplitude/error checks clean, blip active
### tb_osd_overlay
PASS: tb_osd_overlay all checks passed
### tb_promax_audio_waveform
PASS: taller colored waveform bars and peak meter are active
### tb_sd_card_bmp_fourbank
PASS: four-bank scheduler preload/switch/next_event/long-press/auto
### tb_sd_sector_adapter
PASS: sd sector adapter
### tb_video_fade_transition
PASS: tb_video_fade_transition manual/auto/wipe arithmetic
### tb_wav_equiv_control
PASS: stop/restart, reset, SD error, silence equivalence
Compared 46240 clock edges
### tb_wav_equiv_long
PASS: wav stream multi-sector high-water/order/drain
Compared 329348 clock edges
### tb_wav_equiv_stalls
PASS: wav stream multi-sector high-water/order/drain
Compared 440356 clock edges
### tb_wav_stream_player
PASS: wav stream player little-endian/prefill/drain/end
