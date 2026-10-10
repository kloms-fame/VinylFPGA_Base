# D7 ROT 轮播周期参数范围

## 需求与取舍

ROT 接入唯一参数 CSR，并控制已有图片自动轮播周期。保留用户此前明确指定的 3 秒默认值；同时提供 OFF、2 秒、3 秒、5 秒、10 秒、20 秒六档。六档仍由 3-bit 索引表示，5 秒档按原方案保留。

## 行为合同

- 旋钮 SELECT/ADJUST 流程沿用 D4–D6；ROT 在 VOL、BRI、CON 之后开放。
- 改变 ROT 后，100 MHz 轮播域经独立 `cdc_bundle_latest` 收到稳定参数。周期计数和忙时 pending 一起清零，不立刻兑现旧周期。
- 周期由 100 MHz 本地秒使能和 5-bit 已用秒计数构成；DIP2 仍是总使能。OFF 关闭自动触发。
- 自动切图只请求 `cover_navigation`；手动前/后操作优先并重置周期；媒体未就绪、单图、缩略图或播放状态保持原有门控。
- 该提交只开放 ROT。WSL 仍不在 EC2 选择列表中，待 D8 灯光执行器接入后再开放。

## 综合结果边界

SynthPilot `opt_gate` 完成且 `legalize_phy_inst` 完成。Gate 时序检查有 setup 违例，最差路径在既有 `frame_read_write_m0` 写计数到读状态逻辑，不经过 ROT 调度器。此结果仅代表逻辑综合候选；未进行布局布线、bitgen 或板级验收，不能登记为 D7 完整放行。
