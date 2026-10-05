# 板级验收

- 日期：2026-10-05。
- 固件：VinylFPGA_optimized.bit，629624字节。
- SHA256：8d6a4d3dd22e7b50c31ef1d97ee70e202794c9d2f5a9435af31a2e2288380f7c。
- 下载：EG4S20BG256，JTAG SRAM；未写Flash。
- 用户反馈原文：“已验证，以上功能正常”。
- 验收清单：四张图片、缩略图bank映射、单击/长按/组合键菜单、自动轮播、亮度/对比度、WAV声音及淡入淡出，观察彩点/撕裂/爆音。
- 自动验证另见regression_results.md、equivalence_results.md；布线结果另见final.area、final.qor、route.status。
- 既有PLL反馈及板级IO约束告警保留在final.constraints中，未通过修改约束隐藏。
