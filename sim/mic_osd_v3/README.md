# MIC / OSD v3 自检

两个独立测试台，只覆盖本次新增的麦克风链路与参数页逻辑；不参与 `tools/run_current_regression.py` 的既有套件。

| 测试台 | 覆盖 |
| --- | --- |
| `tb_mic_signal_condition.v` | 0X 静音、5X 增益(≈5.0x)、软噪声门、7X 饱和、两级低通 20 kHz 抑制、4:1 抽取比 |
| `tb_ui_mic_params.v` | 6 个参数页轮转 0..5、MIC 页 5X→6X→7X→0X→4X 与反向回绕、上电默认 200/5X |

```powershell
# 在仓库根目录执行
iverilog -g2005 -o tb_mic.vvp sim/mic_osd_v3/tb_mic_signal_condition.v src/audio/mic_signal_condition.v
vvp tb_mic.vvp            # 期望最后一行 TB_PASS

iverilog -g2005 -o tb_ui.vvp sim/mic_osd_v3/tb_ui_mic_params.v src/io/ec2_param_controller.v src/io/ui_param_csr.v
vvp tb_ui.vvp             # 期望最后一行 TB_PASS all checks
```

`tb_mic_signal_condition.v` 用 `$sin` 直接生成激励（不要改成大数组查表，数组初始化在 iverilog 下曾给出错误激励）。
