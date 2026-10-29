# 从零看懂 Verilog 与自己的工程

## 1. 先建立硬件思维

Verilog描述的是硬件结构与每个时钟沿如何更新状态。多个`always`块可以代表同时工作的电路。文件从上到下排列，不表示电路像C程序一样依次执行完一个模块再执行下一个模块。

在本项目中，屏幕扫描、音频消费、读卡状态机和编码器采样并行发生。所谓“暂停音乐”，通常只是改变使能、消费和状态；并不是CPU停止执行一段程序。

## 2. 最小必备概念

| 概念 | 初学者解释 | 项目中的例子 |
|---|---|---|
| 组合逻辑 | 输出由当前输入决定 | 图层区域命中、地址选择、大小比较 |
| 时序逻辑 | 时钟沿保存状态 | 播放/暂停、计数器、显示bank |
| 寄存器 | 保存一段状态的触发器集合 | 当前曲目、指针、参数 |
| 状态机 | 用状态和条件描述分步协议 | SD命令、Flash保存、会话重启 |
| 流水线 | 把复杂计算分成多个时钟阶段 | Seek加法与钳位、图像参数处理 |
| FIFO | 按先入先出顺序排队的数据缓存 | PCM与像素缓冲 |
| 握手 | 发起方和接收方明确约定接收/完成 | req/ack、valid/ready |
| 时钟域 | 同一时钟沿更新的一组逻辑 | UI50MHz、SD100MHz、像素25MHz |
| 综合 | 把RTL转换成逻辑与资源 | LUT、寄存器、BRAM、DSP |
| 布局布线 | 把逻辑放到器件并连接 | 物理拥塞、布线延迟、最终时序 |

`wire`常表示连接，`reg`表示Verilog过程赋值变量；`reg`这个语法词本身不保证最终一定是触发器。组合过程里也可使用`reg`。最终硬件取决于描述方式和综合结果。

## 3. 两个必须亲手推导的小例子

### 3.1 非阻塞赋值

```verilog
always @(posedge clk) begin
    a <= b;
    b <= a;
end
```

两条右侧都取该时钟沿前的旧值，因此会交换a和b。不能理解为先把b写给a，再把新a写给b。

练习：初始a=1、b=0，写出之后三个时钟沿的结果。答案为0/1、1/0、0/1。这个原理决定同步器各级延迟、状态机脉冲和流水线对齐。

### 3.2 脉冲、状态和完成不是同一信号

```text
start：一拍“请开始”
busy：多拍“正在处理”
done：一拍“本次处理完成”
valid：这一拍的数据有效
ready：这一拍接收方可以接收
```

接口名字只是提示，仍须读生产者和消费者：本项目某些`busy`兼具“不允许请求”的含义；某些`done`只表示扇区接收结束，不能代表像素已全部写入SDRAM。

验收练习：为什么SD最后一个字节到达时，显示bank还不能立刻切换？因为后面仍可能有拼像素、FIFO和内存写尾，必须等待真正完成条件。

## 4. 读文件时固定问六个问题

1. 这个模块解决什么问题？
2. 在哪个时钟域、怎样复位？
3. 输入是什么，输入什么时候有效？
4. 内部保存了哪些状态？
5. 输出何时可以被下游使用？
6. 遇到忙、失败、复位或新请求时怎么办？

读完后用自己的话写五行摘要。若只能抄模块头注释，就还没有真正建立输入到输出的理解。

## 5. 顶层应该怎样读

第一遍只找模块端口、参数、PLL、复位和主要实例。第二遍只追一个可观察动作。第三遍再看跨域和异常。

不要把三千余行顶层所有`wire`一次记住。用信号名回溯：它由谁驱动、谁消费、在哪个时钟边沿更新。名称含`_sd`、`_vid`、`_clk`常提示域，但不能代替核对实例端口。

可在工程根目录执行只读检索：

```powershell
rg -n 'module top|sys_pll|video_pll|reset_sync' src/top_tf_hdmi_audio.v
rg -n 'wav_sample_consumed|u_timebase_48k|lyric_time_ms' src/top_tf_hdmi_audio.v
rg -n 'u_audio_prefetch_sdram|u_audio_sdram_arbiter' src/top_tf_hdmi_audio.v
rg -n 'ui_param_csr|ui_param_persistence' src/top_tf_hdmi_audio.v
```

命中一行后，读前后几十行接口连接。不要只搜索到一个名字就认定它的具体行为。

## 6. 五条源码阅读路线

### 路线A：一声音乐从哪里来

按下列顺序读：

1. `wav_stream_player.v`头部格式约定与端口。
2. 写侧拼样本、FIFO指针、读侧`buffer_read`与`sample_consumed`。
3. 顶层怎样接入`audio_prefetch_sdram`，区别原始SD请求和预取后的客户端扇区。
4. `pcm_volume_fade`、`audio_source_mux`与`hdmi_pcm_source_bridge`。
5. `audio_arc_calculate.v`和HDMI核端口连接。

产出：画出从512字节扇区到256个16-bit样本的过程，解释单声道如何送到左右声道。

### 路线B：按暂停以后为什么歌词也停

读`ui_event_bridge`确认事件来源，再读`play_ctrl`的`paused`更新，回顶层追踪同步后的`play_running_vid`。最后看`timebase_48k`的`running`及`sample_tick`连接。

产出：写出“输入事件→paused→消费使能→实际样本脉冲→媒体时间→歌词选择”的链条，并说明HDMI节拍可以继续。

### 路线C：为什么切图不应该显示半张新图

读`sd_card_bmp`和`fat32_media_loader`的加载/完成接口，接着看共享writer、`frame_read_write`及读请求/ACK。回顶层找`frame_start`、索引提交和转场。

产出：区分“读完文件”“写完帧”“发布新bank”“下一帧读取新bank”四个时间点。

### 路线D：旋钮修改的参数最后放在哪里

读`ec2_param_controller`得到参数项与方向，再到`ui_param_csr`确认唯一写入位置、默认值和饱和范围。沿顶层看`cdc_bundle_latest`和像素帧锁存，再看实际消费者。

产出：以BRI为例写出从EC2到画面像素的完整路径，以VOL为例说明播放域音量意图也要汇聚。

### 路线E：断电后如何恢复设置

读`ui_param_persistence`的dirty、snapshot、manual_pending与save_done，再读`w25q64_param_store`的记录布局、目标槽、擦写、回读与提交标记。最后找Flash引脚约束。

产出：画出保存期间断电的三个时刻，分别说明下一次应读取旧记录还是新记录。

## 7. 怎样读状态机

以`stream_session`为最小例子：

```text
未请求/请求重启：enable=0，稳定计数清零
请求仍有效且未使能：等待storage/video不忙、reader_idle
条件持续稳定：累计settle
达到阈值：enable=1，start_toggle翻转
```

它不是整套播放器，只负责安全地结束旧会话并启动新一代数据。模块职责越清楚，越容易理解为什么不应该再造第二套重复播控状态机。

阅读较大状态机时，先列状态表：每个状态发什么命令、等哪个完成、失败去哪、何时改变所有权。再看具体`always`，避免陷入大量信号细节。

## 8. 位宽与有符号数是必修项

PCM可以为负数，像素通道通常是0—255无符号。做音量乘法、对比度中心偏移和Seek反向步进时，需要明确符号扩展、中间位宽、右移方式与饱和截断。

例如对比度先算`pixel-128`，负数不能用普通无符号逻辑解释。中间溢出后再截断与先扩位再饱和不同。Verilog表达式位宽还会受上下文影响，不能用“乘法当然自动无限扩位”或“乘法一定只有输入位宽”这类口诀替代逐项分析。

练习：8-bit无符号0减1若只保留8位会成为255；Seek目标不能这样回绕，必须扩位有符号计算后钳位到有效区间。

## 9. 怎样看波形

先提出一个明确命题，例如“短扇区不得提交音频环”。然后按时间对齐观察：请求、busy、字节索引、valid、done、error、DMA请求/ACK、写指针。

记录预期序列，查首次偏离点。不要以“波形在动”代替验证。对CDC还应注意源域和目标域的不同采样沿；对ROM要知道输出延迟几拍；对视频要让RGB、DE、坐标与同步信号对齐。

本报告引用的既有WLF/VCD可作为案例，但并不要求你比赛前重跑所有仿真。先能看懂一个真实用例，再逐步深入。

## 10. 学会到什么程度才够

| 层级 | 表现 | 当前应达到 |
|---|---|---|
| 识别 | 知道模块名字 | 全部主链路 |
| 解释 | 能讲输入、输出、机制 | 数据/控制/时间/缓存四条线 |
| 追踪 | 能从按钮追到结果 | 暂停、Seek、调参、保存 |
| 推导 | 能算大小、速率、边界 | 主要量级计算 |
| 修改验证 | 能提出小改动及验证方案 | 在独立练习中完成，不要求改比赛稳定版 |

不需要在赛前手写整个HDMI协议核。需要知道你与厂家IP之间的接口契约，能解释为什么输入数据和时序是合法的。

依据入口：[工程入口](<D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/VinylFPGA.al>)、[顶层](<D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/src/top_tf_hdmi_audio.v>)、[会话模块](<D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/src/audio/stream_session.v>)、[参数CSR](<D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/src/io/ui_param_csr.v>)。
