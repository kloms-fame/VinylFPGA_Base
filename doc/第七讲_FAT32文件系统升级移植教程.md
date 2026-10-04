# 第七讲 第6课：FAT32 文件系统升级 —— VinylFPGA 工程移植教程

> 参照教程：`FPGA创新设计赛道安路赛项（完赛系列）/第七讲：FAT32文件系统升级/第6课_FAT32文件系统升级.md`
> 参照代码：`第七讲：FAT32文件系统升级/第6课_FAT32文件系统/`
> 移植对象：`D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA`
> 移植前基线：`7d1d3f7 第六讲：Flash固化与上电自启（复位同步/PLL锁定/SDRAM就绪/约束）`
> 本讲最终位流：`prj/VinylFPGA_lecture7_fat32_keyfix_v4.bit`

---

## 一、目标与边界

### 1.1 本讲目标

第七讲把原先基于固定扇区扫描的 BMP 加载方式升级为 FAT32 文件系统读取。升级后不再依赖“BMP 必须从某个固定 LBA 开始连续存放”，而是通过 FAT32 目录项取得文件名、首簇和文件长度，再沿 FAT 链读取文件内容。

本讲最终实现以下能力：

1. 识别直接 FAT32 引导扇区，也支持带 MBR 的单分区 FAT32；
2. 解析 BPB 中的每簇扇区数、保留扇区、FAT 起始和根目录起始；
3. 扫描根目录第一个簇，匹配 `PIC1.BMP` ~ `PIC4.BMP` 的 8.3 大写短文件名；
4. 根据目录项记录文件首簇和文件大小；
5. 通过 FAT 链读取文件，支持文件数据在 TF 卡上不连续存放；
6. 解析 24 位无压缩 BMP 头，把 BGR 像素转成现有 SDRAM 写通路需要的 RGB 数据；
7. 保持 KEY1/KEY2、自动轮播、切图音效、双缓冲和数码管功能不变。

### 1.2 教程与本工程的适配方式

教程给出的完整媒体流水线包含 `media_ingest_frontend`、`media_ingest_pipeline`、`media_frame_loader` 等多个模块。本工程没有整体替换视频/SDRAM 架构，而是采用“保留上层状态机，只替换底层 BMP 读取器”的最小改动方案：

| 教程层次 | 本工程落点 |
|---|---|
| FAT32 卷扫描 | 新增 `src/SD/fat32_volume_scanner.v` |
| FAT 链文件流 | 新增 `src/SD/fat32_file_streamer.v` |
| 扇区接口重放/适配 | 新增 `src/SD/sd_sector_adapter.v` |
| FAT32 与旧 `bmp_read` 接口兼容 | 新增 `src/SD/fat32_media_loader.v` |
| BMP 到 SDRAM 写数据 | 由 `fat32_media_loader.v` 内部完成 |
| 按键、轮播、双缓冲、提交 | 保留 `src/SD/sd_card_bmp.v` 原有状态机 |

这样做的原因是当前工程的 `sd_card_bmp.v` 已经包含第三讲、第五讲和第六讲验证过的按键、轮播、错误恢复、SDRAM 就绪和双缓冲提交逻辑。直接替换整套上层流水线会扩大改动面，并可能重新引入黑屏、按键失效和显示撕裂问题。

### 1.3 不可修改清单

以下内容属于比赛工程的高危或已验收链路，本讲没有改动：

- `src/hdmi1.4b_transmitter_core/` 下的 HDMI 1.4b 加密发射核；
- `src/include/*.enc.v` 下的 SDRAM 加密核和初始化核；
- HDMI PHY、TMDS、DDC 和 EDID 链路；
- SDRAM 控制器、视频时序和双缓冲显示链路；
- `src/top_tf_hdmi_audio.v` 的顶层端口、时钟和管脚约束；
- KEY1 短按下一张、KEY2 短按自动轮播、KEY2 长按上一张；
- 3 秒自动轮播计时、数码管图号、切图音效和 HDMI 音频。

### 1.4 TF 卡文件要求

本讲参考实现有明确的教学边界：

1. TF 卡必须是 FAT32；
2. 四张图片必须位于根目录；
3. 文件名必须是 8.3 大写短文件名：
   - `PIC1.BMP`
   - `PIC2.BMP`
   - `PIC3.BMP`
   - `PIC4.BMP`
4. 文件必须是 640x480、24 位、无压缩 BMP；
5. 扫描器只扫描根目录的第一个簇。四张图片应放在根目录前端，避免目录项落在后续簇；
6. 文件名不要使用中文、空格、长文件名或小写扩展名。

推荐使用 SD Card Formatter 把卡格式化为 FAT32，再直接复制四个文件。不要只做快速删除式格式化后沿用旧目录项。

---

## 二、新增源码

### 2.1 `src/SD/fat32_volume_scanner.v`

本模块是教程 5.1 的卷扫描器移植。它读取 LBA0：

- 如果首字节是 `0xEB` 或 `0xE9`，按直接 FAT32 引导扇区解析；
- 如果分区类型是 `0x0B` 或 `0x0C`，读取 MBR 中的分区起始 LBA，再读取 FAT32 引导扇区；
- 检查 `0x55AA` 引导签名、512 字节扇区、每簇扇区数、FAT 数量、FAT 大小和根簇号；
- 扫描根目录第一个簇中的 8.3 目录项；
- 输出四张图片的首簇、文件大小和 `resource_valid`。

错误码定义：

| 错误码 | 含义 |
|---|---|
| `0x00` | 无错误 |
| `0x10` | SD 扇区读错误 |
| `0x20` | 引导扇区签名错误 |
| `0x21` | 不支持的 BPB 布局 |
| `0x22` | 根目录中缺少 PIC1~PIC4 |

完整文件位于：

`src/SD/fat32_volume_scanner.v`

核心匹配条件如下：

```verilog
if ((sector_byte == 8'h20) &&
    (dir_name0 == "P") && (dir_name1 == "I") &&
    (dir_name2 == "C") && (dir_name3 >= "1") &&
    (dir_name3 <= "4") && (dir_name4 == " ") &&
    (dir_name5 == " ") && (dir_name6 == " ") &&
    (dir_name7 == " ") && (dir_name8 == "B") &&
    (dir_name9 == "M") && (dir_name10 == "P")) begin
    dir_entry_match <= 1'b1;
    dir_resource_index <= dir_name3 - "1";
end
```

### 2.2 `src/SD/fat32_file_streamer.v`

本模块是教程 5.2 的文件流读取器移植。输入是目录项中的首簇、文件大小、FAT 起始 LBA 和数据区起始 LBA；输出是按字节顺序排列的原始文件流。

它包含以下保护：

1. 首簇 `< 2` 或大于卷内最大簇时上报范围错误；
2. FAT 表项达到 `0x0FFFFFF8` 以上按 EOF 处理；
3. 下一簇小于 2、大于最大簇时上报错误；
4. 自身指向自身、环链和访问簇数超过 8192 时上报错误；
5. 文件长度未用完就遇到 EOF 时上报提前结束错误；
6. 文件长度刚好结束时，最后一次读取仍校验当前簇的 FAT 表项是 EOC。

完整文件位于：

`src/SD/fat32_file_streamer.v`

### 2.3 `src/SD/sd_sector_adapter.v`

现有 `sd_card_top` 的接口是电平请求：

```verilog
sd_sec_read
sd_sec_read_addr
sd_sec_read_data_valid
sd_sec_read_data
sd_sec_read_end
```

FAT32 模块使用通用扇区接口：

```verilog
sector_req
sector_lba
sector_busy
sector_valid
sector_byte
sector_byte_index
sector_done
sector_error
```

`sd_sector_adapter.v` 在两者之间做协议转换。它只改变接口形式，不改变 SD 控制器、CMD17 命令和 SPI 链路。

完整文件位于：

`src/SD/sd_sector_adapter.v`

### 2.4 `src/SD/fat32_media_loader.v`

本模块是第七讲的最小兼容层。它对外保持原有 `bmp_read` 的使用语义，避免改动 `sd_card_bmp.v` 的按键、轮播和双缓冲状态机。

模块内部顺序非常重要：

```text
扫描完成
  -> 按 load_index 找到 PICn.BMP 的首簇和大小
  -> 先申请 SDRAM 写缓冲区
  -> 收到 write_req_ack 后启动 FAT32 文件流
  -> 解析 BMP 前 54 字节
  -> 跳过 data_offset
  -> 每 3 字节 BGR 转成 RGB
  -> 写入现有 frame_read_write 接口
```

先申请写区、后启动文件流，是为了避免等待 SDRAM 写区时过早消费文件字节。

本模块严格校验：

```verilog
wire header_valid = (header0 == "B") && (header1 == "M") &&
                    (dib_size >= 32'd40) &&
                    (width[15:0] == bmp_width) &&
                    (height[15:0] == bmp_height) &&
                    (planes == 16'd1) &&
                    (bit_count == 16'd24) &&
                    (compression == 32'd0) &&
                    (data_offset >= 32'd54) &&
                    (data_offset < file_len) &&
                    (file_len >= (data_offset + required_pixel_bytes));
```

完整文件位于：

`src/SD/fat32_media_loader.v`

---

## 三、修改 `src/SD/sd_card_bmp.v`

### 3.1 替换底层加载器

原来：

```verilog
bmp_read #(
    .CLK_FREQ_HZ        (CLK_FREQ_HZ),
    .SD_READ_TIMEOUT_MS (SD_READ_TIMEOUT_MS)
) bmp_read_m0 (
    ...
);
```

现在：

```verilog
fat32_media_loader fat32_media_loader_m0 (
    .clk                    (clk),
    .rst                    (rst),
    .ready                  (bmp_ready),
    .scan_start             (scan_start_pulse),
    .scan_done              (scan_done),
    .scan_found_valid       (scan_found_valid),
    .scan_found_index       (scan_found_index),
    .scan_found_total       (scan_found_total),
    .load_start             (load_start_pulse),
    .load_index             (load_index),
    .sd_init_done           (sd_init_done),
    .state_code             (bmp_internal_state),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .bmp_error              (bmp_error),
    .load_error             (load_error),
    .write_req              (write_req),
    .write_req_ack          (write_req_ack),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .bmp_data_wr_en         (bmp_data_wr_en),
    .bmp_data               (bmp_data)
);
```

### 3.2 扫描结果从扇区号改成资源索引

原来的 `img_sector0` ~ `img_sector3` 表示“图片数据起始扇区”。FAT32 版本改为 `img_index0` ~ `img_index3`，保存扫描器发出的资源索引 `0~3`。

```verilog
reg [1:0] img_index0;
reg [1:0] img_index1;
reg [1:0] img_index2;
reg [1:0] img_index3;
```

扫描结果按出现顺序写入：

```verilog
if (scan_found_valid) begin
    case (img_found_count)
        3'd0: img_index0 <= scan_found_index;
        3'd1: img_index1 <= scan_found_index;
        3'd2: img_index2 <= scan_found_index;
        3'd3: img_index3 <= scan_found_index;
        default: ;
    endcase
    if (img_found_count < 3'd4)
        img_found_count <= img_found_count + 3'd1;
end
```

第七讲扫描器要求四张图片全部存在，并且按 `PIC1~PIC4` 顺序报告。因此显示序号与资源索引一致，最终直接把图片序号送给加载器：

```verilog
load_index <= boot_idx;             // 上电首图
load_index <= next_from_current;    // KEY1 / 自动轮播下一张
load_index <= prev_from_current;    // KEY2 长按上一张
load_index <= boot_index_next;      // 首图失败后的下一张候选
```

这一步同时去掉了旧工程里“图片序号 -> 32 位扇区号”的组合查表，降低了 100 MHz 下的长组合路径。

### 3.3 未改动的功能

以下逻辑保持第三讲/第五讲/第六讲原样：

- 20 ms 按键消抖；
- KEY1 短按下一张；
- KEY2 短按切换自动轮播，长按上一张；
- 3 秒自动轮播；
- 双缓冲写区和显示区原子提交；
- 写完成 toggle 跨时钟同步；
- 首图失败重试和坏图跳过；
- 数码管和音频图号。

---

## 四、工程文件修改

`prj/VinylFPGA.al` 中新增四个源文件，并使用 TD 的工程文件管理接口注册：

```text
src/SD/fat32_volume_scanner.v
src/SD/fat32_file_streamer.v
src/SD/sd_sector_adapter.v
src/SD/fat32_media_loader.v
```

原有 `src/SD/bmp_read.v` 不再被 `sd_card_bmp.v` 实例化。TD 会把它标记为 `AutoExcluded`，这是正常现象，不需要删除文件。

---

## 五、本次移植中修复的额外问题

### 5.1 扫描完成时重复启动扫描

初版兼容层在 `scanner_done` 出现时，可能因为扫描请求 pending 尚未撤销，把已经结束的请求再次送进扫描器。扫描器第二次启动后，`scanner_busy` 长期为高，`ready` 不释放，上层永远无法进入加载。

修复方式：

```verilog
// scanner 在 ST_IDLE 看到 scan_start 后下一拍拉起 scanner_busy。
// 以 busy 上升沿确认请求已接收，避免扫描完成时再次启动一轮扫描。
if (scan_launch_pending && !use_streamer && scanner_busy)
    scan_launch_pending <= 1'b0;
```

### 5.2 `scan_done` 必须是保持电平，不能是单周期脉冲

上板回归时出现“首图能显示，但 KEY1/KEY2 无法切图、自动轮播不启动、没有切图音效”。根因不在按键或轮播状态机，而在 FAT32 兼容层的完成握手：初版 `fat32_media_loader.v` 只在扫描结果全部发出的那一拍把 `scan_done` 置 1，下一拍又清 0。

上层 `sd_card_bmp.v` 把 `scan_done_eff` 当作已经稳定完成的条件使用：

```verilog
assign scan_done_eff = scan_done | scan_abort;
```

KEY1 切图、KEY2 上一张、自动轮播和首图提交都依赖 `scan_done_eff`。首图提交后脉冲已经消失，这些分支就永久不成立，因此表现为“首图显示正常、HDMI 音频正常，但所有切图动作失效”。

修复方式是在 `fat32_media_loader.v` 中让 `scan_done` 保持为高，只有下一次 `scan_start` 到来时清除：

```verilog
if (scan_start) begin
    scan_done <= 1'b0;
end else if (scanner_done) begin
    ...
end else if (scan_emitting) begin
    ...
    if (scan_emit_idx == 2'd3) begin
        scan_emitting <= 1'b0;
        scan_done <= 1'b1;
    end
end
```

`sim/tb_fat32_media_loader.v` 增加了两项回归断言：

1. 首图提交后 `scan_done` 仍为 1；
2. 首图完成后还能再次发起加载。

第二项用于确认兼容层没有在第一次加载后锁死。

### 5.3 `file_stream_start` 多驱动

Icarus 未报出、TD elaborate 报出的真实问题：

```text
[HDL-8007] net 'file_stream_start' is constantly driven from multiple places
```

修复后 `file_stream_start` 只保留一个组合来源：

```verilog
wire file_stream_start = (load_state == LD_WAIT_WRITE) && write_req_ack;
```

SDRAM 写区握手完成的那一拍，流读取器采样到启动脉冲；下一拍 `load_state` 离开 `LD_WAIT_WRITE`，脉冲自动撤销。

### 5.4 FAT 链地址计算时序收敛

初版直接使用：

```verilog
sector_lba <= data_start_lba +
              (cluster_value - 2) * sectors_per_cluster;
```

在 100 MHz 的 `sd_card_clk` 下，32 位减法、8 位乘法、32 位加法和 FAT 校验串在同一拍，最差建立裕量为 `-1.792ns`，Fmax 只有约 `84.8MHz`。

修复采用两步：

1. 利用每簇扇区数必为 2 的幂，把乘法改为移位；
2. 增加 `ST_FAT_COMMIT` 一级，把 FAT 值锁存后再计算数据 LBA。

```verilog
ST_FAT_PARSE: begin
    next_cluster <= {4'd0, fat_value};
    ...
    state <= ST_FAT_COMMIT;
end

ST_FAT_COMMIT: begin
    advance_to_next_cluster(next_cluster);
end
```

地址计算改为：

```verilog
sector_lba <= data_start_lba +
              ((cluster_value - 2) << spc_shift);
```

### 5.5 旧图片索引查表的长组合路径

旧按键逻辑使用 `index_lut` 做“图片序号 -> 图片资源索引”的组合查表。第七讲扫描器要求四张图片全部存在，固件顺序与资源顺序一致，因此改成直接使用图片序号，去掉这段长组合路径。

---

## 六、仿真验证

### 6.1 新增仿真

本讲新增：

```text
sim/tb_fat32_volume_scanner.v
sim/tb_fat32_file_streamer.v
sim/tb_sd_sector_adapter.v
sim/tb_fat32_media_loader.v
```

其中 `tb_fat32_media_loader.v` 覆盖完整链路：

```text
FAT32 引导扇区
  -> 根目录第一条目录项
  -> PIC1 文件流
  -> BMP 头校验
  -> BGR -> RGB
  -> 四个像素输出
```

### 6.2 已通过结果

```text
PASS: sd sector adapter
PASS: FAT32 volume scanner
PASS: FAT32 fragmented FAT chain
PASS: FAT32 media loader scan/load/pixel pipeline
PASS: 48kHz PCM count=4800, amplitude/error checks clean, blip active
```

`tb_fat32_media_loader.v` 中的 `scan_done` 保持回归和二次加载回归均包含在上述 PASS 内。PASS 表示首图提交后，KEY1/KEY2 和自动轮播所需的扫描完成条件仍然有效。

音频回归说明第七讲没有破坏第四讲音频桥。

### 6.3 编译检查

SD/FAT32 相关文件通过 Icarus Verilog 编译：

```powershell
D:\iverilog\bin\iverilog.exe -g2005 -t null -o NUL `
  src\SD\fat32_volume_scanner.v `
  src\SD\fat32_file_streamer.v `
  src\SD\sd_sector_adapter.v `
  src\SD\fat32_media_loader.v `
  src\SD\sd_card_bmp.v `
  src\SD\sd_card_top.v `
  src\SD\sd_card_sec_read_write.v `
  src\SD\sd_card_cmd.v `
  src\SD\spi_master.v
```

全工程包含安路加密 IP，不能用 Icarus 替代 TD 做最终综合；最终门禁是安路 TD。

---

## 七、安路 TD 结果

工程：

```text
prj/VinylFPGA.al
```

器件：

```text
EG4S20BG256
```

顶层：

```text
top
```

约束：

```text
constraints/timing.sdc
constraints/pin.adc
```

最终位流：

```text
prj/VinylFPGA_lecture7_fat32_keyfix_v4.bit
SHA256: 17F5E716EA298E2AA617171CBF677B4F0853E542445D2E6C9387AFFA2F8C853E
```

最终布线后时序：

```text
Slow corner: SWNS +0.111ns, STNS 0.000ns
Fast corner: HWNS +0.003ns, HTNS 0.000ns
sd_card_clk: setup SWNS +0.111ns, hold HWNS +0.146ns
```

不存在负裕量端点。`sd_card_clk` 最终 Fmax 约 `101.122MHz`，满足当前 100 MHz 工作时钟。

资源占用：

```text
mslice: 1917 / 4900   39.12%
lslice: 1919 / 4900   39.16%
lut:    5884 / 19600  30.02%
reg:    4671 / 19600  23.83%
bram:   20 / 64       31.25%
dsp:    2 / 29         6.90%
pll:    2 / 4          50.00%
```

TD 的 PLL 反馈网络警告与本讲 FAT32 逻辑无关，属于第六讲已有的全局时钟约束现象；本讲没有改动 PLL 和时钟树。

---

## 八、上板与 Flash 验收

### 8.1 TF 卡准备

1. 把 TF 卡格式化为 FAT32；
2. 将图片命名成 `PIC1.BMP` ~ `PIC4.BMP`；
3. 复制到根目录；
4. 确认文件是 640x480、24 位、无压缩 BMP；
5. 安全弹出后再插到开发板。

### 8.2 验证顺序

1. 用 TD Download 下载 `VinylFPGA_lecture7_fat32_keyfix_v4.bit`；
2. 上电等待 PLL 锁定和 SDRAM 初始化；
3. 数码管应先显示初始化状态，首图提交后显示 `1`；
4. HDMI 显示 `PIC1.BMP`；
5. KEY1 短按应切到下一张，并产生切图音效；
6. KEY2 短按应打开/关闭 3 秒自动轮播；
7. KEY2 长按应回到上一张；
8. 播放过程中不应黑屏、不应卡死；
9. 按复位键后应能重新扫描并回到第一张；
10. 断电重启后，Flash 固化版本应能自启动。

### 8.3 建议加测

- 把四个 BMP 故意做成碎片化文件，验证 FAT 链读取；
- 使用不同容量和不同品牌的 FAT32 TF 卡；
- 在根目录前 16 个目录项内放四张图片；
- 测试大文件和多张图片连续切换；
- 用示波器或逻辑分析仪确认 SD 时钟和复位释放。

---

## 九、回退方法

本讲保留第六讲提交 `7d1d3f7`，回退时不需要修改 HDL：

1. 下载第六讲位流 `prj/VinylFPGA_lecture6_flash_v2.bit`；
2. 或从 Git 检出 `7d1d3f7` 对应的源码重新生成位流；
3. 不要把第七讲的新增文件直接删除后继续使用旧 `.al`，应先让 TD 重新打开工程并刷新文件列表。

---

## 十、常见问题

### 10.1 上电黑屏，数码管停在 1

优先检查：

1. 四张文件是否都在根目录；
2. 文件名是否严格是 `PIC1.BMP` ~ `PIC4.BMP`；
3. 是否用了长文件名或小写扩展名；
4. 是否都是 640x480、24 位、无压缩 BMP；
5. 目录项是否落在根目录第一个簇内。

### 10.2 KEY1 没反应

FAT32 加载期间上层会保持 `load_busy`。先确认加载完成后再按键。如果一直不完成，说明扫描或 BMP 校验没有通过，应按第 10.1 节检查 TF 卡。

### 10.3 自动轮播不工作

自动轮播要求：

- 扫描完成；
- 至少两张图片有效；
- 当前图已经提交；
- 没有正在进行中的加载。

如果目录项缺失导致扫描失败，自动轮播不会启动。

### 10.4 烧录后仍然显示旧图或黑屏

确认烧录的是第七讲位流，并彻底断电重启一次。Flash 固化时不要只下载 SRAM，要按第六讲的 Flash 烧写流程执行。

---

## 十一、结论

本讲完成了从固定扇区 BMP 加载到 FAT32 文件系统加载的移植，同时保留了第三讲到第六讲已经验证过的按键、轮播、双缓冲、音频、复位同步和 Flash 固化结构。新增代码集中在 `src/SD/`，没有触碰 HDMI、SDRAM 加密核和高危时钟链路。

最终位流已经通过安路 TD bitgen，并且布线后所有建立/保持检查为正裕量。上板验收应重点确认：四张图片能在根目录被识别、碎片化文件能通过 FAT 链读取、KEY1/KEY2/自动轮播和切图音效均正常、复位与断电重启能够重新加载。
