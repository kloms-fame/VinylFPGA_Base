# 当前工程工具

所有命令在仓库根目录执行。脚本只依赖当前目录结构和所列工具，不读取同级历史备份。

| 工具 | 用途 |
| --- | --- |
| `verify_submission.py` | 校验已验收设计输入、61 个工程条目与文档链接 |
| `run_current_regression.py` | 统一运行精选测试，支持 `--quick` |
| `package_submission.py` | 生成不含 Git/媒体/Runs 的源码 ZIP 和哈希 |
| `build_closeout.ps1`、`run_closeout_project.tcl` | TD 完整构建及阶段/时序/产物停线判定 |
| `verify_gui_runs.py`、`audit_final_timing.tcl` | 核对实际 Runs，或导入数据库独立复算 |
| `configure_optimized_project.tcl` | 保留原生种子语义的配置维护工具，常规提交无需运行 |
| `test_*.py` | 构建、配置和 GUI 产物校验工具的 27 项单元测试 |
| `run_audio_cache_regression.py` | 音频缓存、FAT32、索引和受影响通路的 32 项回归 |
| `verify_finish_rtl.py` | 顶层与 MV/显示的 10 项收尾回归 |
| `verify_mv_owner.py` | 真实 SD 控制器配合字节级 SPI 卡模型，8 项所有权与 3 项恢复 |
| `verify_seek_integration.py` | 时间/MV 目标及 PCM 实际重定位的 2 项集成 |
| `verify_lyric_focus.py` | 歌词专注、按键桥接及页面的 8 项回归 |
| `verify_system_sound.py` | 顶层提示音、调度与 Flash 保存的 6 项回归 |
| `verify_brightness_contrast_steps.py` | 亮度/对比度算术和像素对齐，16,385 组检查 |
| `verify_finish_modelsim.py` | 可选 ModelSim 独立检查及波形保存 |
| `vinyl_packer.py` | FAT32 镜像 pack / info / verify；verify 为只读检查 |
| `mv_pack.py` | 将编号 BMP 帧转换为 MV 数据，需 Pillow |
| `pack_backgrounds.py` | 背景图片预处理与媒体包生成，需 Pillow |

各工具参数使用 `--help` 查看。`pack` 或图片资源转换会写输出文件，应使用新的镜像/目录；本轮验收不会调用它们改写用户已验收媒体。离线素材准备不等于板端运行时引入额外处理器。

过往下载脚本、固定历史种子的候选发布脚本、旧资源优化实验和原媒体制作现场保留在用户备份目录，不作为当前工具入口。工具环境与 TD 路径说明见 [复建文档](../doc/build.md)。
