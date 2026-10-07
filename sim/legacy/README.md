# 历史测试库

UART、旧母板双键菜单、短长按和三行 OSD 已退出生产。这里保存原模块与原测试；`prj/VinylFPGA.al` 不引用本目录，生产回归不扫描本目录。

- `lrc_font_rom_o0.v`、`lrc_osd_o0.v`：533f605 的冻结参考，仅供新字库/像素等价测试。
- `tb_expansion_s1.v`、`tb_health_monitor.v`：原接口历史证据；依赖原版本集成，需在 533f605 检出中运行。
- `tb_echo_telemetry.v`、`tb_param_menu_controller.v`、`tb_osd_overlay.v`：可在 `-y sim/legacy -y src/io -Isrc/include` 下单独运行。
- `verify_counter_opt.py menu/keys`、`verify_s703_arithmetic.py` 的串口部分是历史优化实验，不作为当前产品验收。
- `verify_s703_controls.py --legacy-uart` 可显式选择历史 UART。

当前产品统一入口：`python tools/verify_s7_acceptance.py`；已覆盖替代的串口静默、故障恢复、J2、共享消抖和同步歌词字库。
