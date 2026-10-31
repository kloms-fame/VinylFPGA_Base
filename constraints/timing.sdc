
# ============================================================
# merged_top_tf_hdmi_audio.sdc
# 用于：TF 图片轮播 + HDMI(视频+音频) 整合工程
#
# 合并原则：
# 1) 保留 top.sdc 里的系统主时钟与 derive_clocks
# 2) 把 timing(2).sdc 里的 pixel/serial 时钟改成整合工程实际名字
# 3) 增加 hdmi_5x_clk 命名，音频统一使用 video_clk
# 4) 不再对内部 net 直接 create_clock，避免和 derive_clocks 重复
# ============================================================

# ------------------------------------------------------------
# 1. 板级输入主时钟
#    你的原 top.sdc 里 clk=50MHz，所以这里仍然用 20ns
# ------------------------------------------------------------
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]

# ------------------------------------------------------------
# 2. 自动推导 PLL 输出时钟
# ------------------------------------------------------------
derive_clocks

# ------------------------------------------------------------
# 3. 给关键 PLL 输出命名
#    下面这些路径是按你当前工程实例名写的：
#      sys_pll      -> sys_pll_m0
#      video_pll    -> video_pll_m0
#      第3课音频已复用 video_clk，不再创建 audio_mclk
#
#    如果综合后实例路径略有不同，就按 Timing Analyzer 里的实际 pin 路径改。
# ------------------------------------------------------------
rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {ext_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {ext_mem_clk_sft} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[2]}]
rename_clock -name {video_clk}   -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[1]}]

# 麦克风 ADC 采样时钟：由 video_clk 二分频后驱动片内 SAR ADC 硬 IP。
# 综合后分频寄存器为 u_mic_adc/adc_clk_reg.q；布局布线阶段该寄存器可能被
# 改名，此时回退到硬 ADC 的时钟引脚，两个目标指向同一根分频网络，只会
# 创建一个时钟；两者都取不到时不创建，避免 get_pins 报 USR-6001 导致
# 后续 set_clock_groups 整条失败。
set mic_adc_target [get_pins -quiet {u_mic_adc/adc_clk_reg.q}]
if {[llength $mic_adc_target] == 0} {
    set mic_adc_target [get_pins -quiet {u_mic_adc/u_adc.clk}]
}
if {[llength $mic_adc_target] > 0} {
    create_generated_clock -name {mic_adc_clk} -source [get_pins {video_pll_m0/pll_inst.clkc[0]}] -master_clock {video_clk} -divide_by 2 $mic_adc_target
}

# ------------------------------------------------------------
# 4. HDMI 像素/串行时钟关系
#
#    原文件是：
#      create_clock -name pixel_clk  ... [get_nets {S_pixel_clk}]
#      create_clock -name serial_clk ... [get_nets {S_serial_clk}]
#      set_clock_groups -exclusive ...
#
#    在整合工程里，这两个时钟已经由 video_pll 产生，并通过 derive_clocks 建出来了，
#    所以这里只保留“组关系”，不再重复 create_clock。
#
#    两者由同一个 video_pll 同时产生，并同时进入 HDMI TX core，不是
#    mutually-exclusive clocks；让 TD 分析两者间的同步路径。
# ------------------------------------------------------------

# ------------------------------------------------------------
# 5. 第3课起 pcm_media_tone / ACR / 音频数据全部运行在 video_clk，
#    不再存在 audio_mclk 跨域约束。
#
# 6. S7-02：把各 PLL 派生时钟域声明为异步时钟组。
#
#    理由：clk(50MHz 输入) 与 sys_pll/video_pll 输出的 sd_card_clk、ext_mem_clk、
#    video_clk、hdmi_5x_clk 分属不同时钟树，器件内 PLL 插入延迟不一致，跨域
#    相位关系并非固定；工程内跨域使用 2FF 同步器、gray-code 异步 FIFO 或
#    bundled-data/toggle 握手。video_clk 与 hdmi_5x_clk 同源且保留同步分析。
#
#    S7-01 基线 Hold WNS 仅 +0.003ns，本就处于临界；S7-02 在 sd_card_clk 域新增
#    media_supervisor 后，sd_card_clk 时钟树扇出/偏斜增大，使既有的
#    media_status_sd / osd_error_code / media_err_code 等 2FF 状态同步路径出现
#    -1.5ns 级别的跨域 hold 违例。这些跨域本就应按异步域处理，而不是靠 PnR 恰好
#    满足相位关系，因此在此显式分组消除伪违例。
#
#    ext_mem_clk_sft 是 SDRAM 采样移位时钟（fanout=1，仅进硬 IP），仍由第 8 节的
#    set_false_path 与 ext_mem_clk 互斥处理，不纳入异步组。
# ------------------------------------------------------------
set mic_video_group {video_clk hdmi_5x_clk}
if {[llength $mic_adc_target] > 0} { lappend mic_video_group mic_adc_clk }
set_clock_groups -asynchronous \
    -group [get_clocks {clk}] \
    -group [get_clocks {sd_card_clk}] \
    -group [get_clocks {ext_mem_clk}] \
    -group [get_clocks $mic_video_group]

# ------------------------------------------------------------
# 7. I/O timing model gaps
#    SD MISO and forwarded HDMI clock/data require card/display setup/hold and
#    board trace data before numeric input/output delays can be added. These
#    interface/board values are absent from this project snapshot; do not
#    invent zero or nominal delays. Mechanical UI inputs are asynchronous and
#    synchronized in RTL, not synchronous source-clock interfaces.
# ------------------------------------------------------------

# ------------------------------------------------------------
# 8. 第六讲：复位与同步器时序约束
# ------------------------------------------------------------
# 复位信号异步进入各时钟域，由 reset_sync 做同步释放。
set_false_path -from [get_ports {rst_n}]

# reset_sync / sync_2ff 的第一级均为异步采样寄存器。
set_false_path -to [get_regs -hier {*/s1}]

# HDMI TMDS ODDR 输出路径的数字延迟上限。
set_max_delay -from [get_clocks {hdmi_5x_clk}] \
    -to [get_ports {HDMI_CLK_P HDMI_D0_P HDMI_D1_P HDMI_D2_P}] \
    8.000 -datapath_only

# SDRAM 移位采样时钟属于硬 IP 的 I/O 窗口，不做 fabric 跨时钟分析。
set_false_path -from [get_clocks {ext_mem_clk}] -to [get_clocks {ext_mem_clk_sft}]
set_false_path -from [get_clocks {ext_mem_clk_sft}] -to [get_clocks {ext_mem_clk}]

# ------------------------------------------------------------
# 9. S1：拓展板（J2）约束说明
#
#    S1 集成层（expansion_io_hub / ui_event_bus / exp_echo_reporter）整体
#    运行在已约束的 50 MHz clk 域（见本文件第 1 节 create_clock），未新增任何
#    时钟或 PLL 输出，因此不需要新增时钟约束。
#
#    exp_key_n / exp_dip_n / exp_enc*_a/b / exp_enc*_sw_n / exp_ir_rx 均为板外
#    异步外设输入，已在 expansion_io_hub 内部逐路做两级同步（sync_bit）后才
#    使用。这里沿用 J2 标定工程的做法：不为这些输入端口设置 input delay，也
#    不用 set_false_path 掩盖真实跨时钟关系；待 S1 上板后按 TD check_timing
#    报告再决定是否需要补充量化约束。
#
#    uart_tx 为 clk 域输出，输出延迟保持空白，与既有 SD / HDMI / 数码管输出
#    的处理方式一致。
# ------------------------------------------------------------
