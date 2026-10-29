# MV 卡顿 fixF 发布包（基于 e65bec4）

| 项 | 值 |
| --- | --- |
| 基线提交 | `e65bec439587970ff39e8cec6f37387db6069f78` |
| 器件 / 封装 | Anlogic EG4S20 / BG256 |
| 顶层 | `top`（`prj/VinylFPGA.al`） |
| 工具链 | TD 6.2.168116 |
| 构建 seed | 7（`.al` multiseed Init=7） |
| 物理综合参数 | 9 条，见 `doc/开发方案/MV卡顿_fixF_实施记录与构建收敛_20261028.md` §3.1 |
| 构建日期 | 2026-10-28 |

## 烧写文件

```
VinylFPGA_MV_fixF_20261028.bit   680840 bytes
SHA-256 CCB027C1102F66F60672845B40D34B18D643FB0DBEB023636B96EE35C82FD07E
```

校验：

```powershell
Get-FileHash .\VinylFPGA_MV_fixF_20261028.bit -Algorithm SHA256
```

## 时序与面积

| 指标 | fixF | 基线 e65bec4 |
| --- | --- | --- |
| Setup WNS | **+0.116 ns**（TNS 0，违例 0） | +0.143 ns |
| Hold WNS | **+0.024 ns**（违例 0） | +0.037 ns |
| Slice | **9307 / 9800 = 94.97%** | 9317 / 9800 = 95.07% |
| BRAM9K | 64 / 64（100%） | 64 / 64 |
| BRAM32K | 2 / 16 | — |
| DSP | 10 / 29 | — |
| Wire length | 2 787 336 | — |
| bit 大小 / SHA | 680 840 / `CCB027C1…` | 676 184 / `A7F3E5A1…` |

## 文件清单

| 文件 | 字节 | 说明 |
| --- | --- | --- |
| `VinylFPGA_MV_fixF_20261028.bit` | 680 840 | 烧写文件 |
| `fixF_route.qor` | 1 313 | 布线后 QoR（WNS/TNS/违例/线长/Slice） |
| `fixF_place.qor` | 1 741 | 布局后 QoR |
| `fixF_phy.ts` | 62 | 时序摘要（SWNS/STNS/HWNS/HTNS） |
| `fixF_pr.timing` | 745 850 | 完整布线后时序报告（查违例只看这个） |
| `fixF_phy.area` | 47 356 | 物理综合面积 |
| `fixF_gate.area` | 28 628 | 综合面积（LUT/REG/BRAM/DSP/PLL/IO） |
| `fixF_exception.timing` | 14 568 | 仅 HDMI 5x MCP 例外，**不含** sd_card_clk 违例路径 |

## 行为变化

1. 切歌不再冻结（`timebase_48k` restart 优先级修正）。
2. MV 帧读取改为 CMD18 连续流 + 双 512 B bank，SD 总线单所有权仲裁，音频请求不再被 MV 抢占、也不被误判超时。
3. WAV 尾包不满一扇区时不再误报 underrun。
4. 诊断串口已移除，`uart_tx` 归还 `expansion_integration`（与原产品行为一致）。

## 回滚

重烧基线 bit（SHA-256 `A7F3E5A15A096CDEE30D89303A05E6684B76B95592B8653B5A6AB90FE4C7762B`，676 184 B），代码回退到 `e65bec4`。

## 验证状态

- 仿真：SD 所有权 11/11、3 帧像素等价（308 200 像素）、音频/加载器/UI 32/32。
- 实板：fixE 诊断版连续播放 299.808 s，0 SD 错误 / 0 欠载 / 0 长卡顿（episode ≥ 1000 ms 为 0）。
- **本 bit 尚未烧板验证**；实板结论来自功能等价、仅少诊断模块的 fixE 版本。

详见 `doc/开发方案/MV卡顿_fixF_实施记录与构建收敛_20261028.md`。
