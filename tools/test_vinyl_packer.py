#!/usr/bin/env python3
"""S4 PC 侧自测：构造真实 FAT32 镜像 -> 打包 INDEX.BIN -> 回读校验 + 负例。

直接运行：  python tools/test_vinyl_packer.py
全部通过输出 PASS，任一失败输出 FAIL 并返回非零。

同时会把一份小镜像导出成 iverilog 可用的一行一字节 hex
（sim/s4_fixture/card_mem.hex），供 sim/tb_fat32_index_loader.v 复用同一份
"同一块卡"的扇区内容，保证 PC 侧与 FPGA 侧用的是同一份索引。
"""

from __future__ import annotations

import hashlib
import json
import math
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import vinyl_packer as vp  # noqa: E402

FIXTURE_DIR = ROOT / "sim" / "s4_fixture"
BPS = 512
EOC = 0x0FFFFFFF


def make_bmp(width: int, height: int, seed: int) -> bytes:
    """生成 RTL 约束下合法的 24bit 未压缩 BMP（行宽 4 字节对齐 = 无填充）。"""
    pixel_bytes = width * height * 3
    assert (width * 3) % 4 == 0, "测试宽度需 4 字节行对齐，避免 BMP 行填充复杂度"
    hdr = bytearray(54)
    hdr[0:2] = b"BM"
    struct.pack_into("<I", hdr, 2, 54 + pixel_bytes)
    struct.pack_into("<I", hdr, 10, 54)
    struct.pack_into("<I", hdr, 14, 40)
    struct.pack_into("<i", hdr, 18, width)
    struct.pack_into("<i", hdr, 22, height)
    struct.pack_into("<H", hdr, 26, 1)
    struct.pack_into("<H", hdr, 28, 24)
    struct.pack_into("<I", hdr, 30, 0)
    struct.pack_into("<I", hdr, 34, pixel_bytes)
    body = bytearray(pixel_bytes)
    state = seed
    for i in range(pixel_bytes):
        state = (state * 1103515245 + 12345) & 0xFFFFFFFF
        body[i] = (state >> 16) & 0xFF
    return bytes(hdr) + bytes(body)


class Fat32Builder:
    """够用的最小 FAT32 磁盘构造器（只服务本测试）。"""

    def __init__(self, data_sectors: int, spc: int = 1, num_fats: int = 2,
                 reserved: int = 32):
        self.spc = spc
        self.num_fats = num_fats
        self.reserved = reserved
        self.fat_size = math.ceil((data_sectors + 2) * 4 / BPS)
        self.data_sectors = data_sectors
        self.total_sectors = reserved + num_fats * self.fat_size + data_sectors
        self.max_cluster = (data_sectors >> (spc.bit_length() - 1)) + 1
        self.mem = bytearray(self.total_sectors * BPS)
        self.fat = [0] * (self.max_cluster + 2)
        self.root_slot = 0
        self.fat_start = reserved
        self.data_start = reserved + num_fats * self.fat_size
        self._write_bpb()

    def cluster_lba(self, cluster: int) -> int:
        return self.data_start + ((cluster - 2) << (self.spc.bit_length() - 1))

    def _write_bpb(self) -> None:
        b = bytearray(BPS)
        b[0] = 0xEB
        b[3:11] = b"MSDOS5.0"
        struct.pack_into("<H", b, 11, BPS)
        b[13] = self.spc
        struct.pack_into("<H", b, 14, self.reserved)
        b[16] = self.num_fats
        struct.pack_into("<H", b, 17, 0)
        struct.pack_into("<H", b, 19, 0)
        b[21] = 0xF8
        struct.pack_into("<H", b, 24, 63)
        struct.pack_into("<H", b, 26, 255)
        struct.pack_into("<I", b, 28, self.reserved + self.num_fats * self.fat_size)
        struct.pack_into("<I", b, 32, self.total_sectors)
        struct.pack_into("<I", b, 36, self.fat_size)
        struct.pack_into("<H", b, 40, 0)
        struct.pack_into("<H", b, 42, 0)
        struct.pack_into("<I", b, 44, 2)
        struct.pack_into("<H", b, 48, 1)
        struct.pack_into("<H", b, 50, 6)
        struct.pack_into("<I", b, 52, 0)
        b[64] = 0x80
        b[65] = 0x00
        b[66] = 0x29
        struct.pack_into("<I", b, 67, 0x12345678)
        b[71:82] = b"VINYL S4   "
        b[82:90] = b"FAT32   "
        b[510:512] = b"\x55\xaa"
        self.mem[0:BPS] = b
        self.fat[2] = EOC

    def alloc(self, count: int) -> list:
        got = []
        c = 3
        while len(got) < count and c < self.max_cluster:
            if self.fat[c] == 0:
                got.append(c)
            c += 1
        if len(got) != count:
            raise RuntimeError("测试镜像簇不足")
        got = list(got)
        for cl in got:
            self.fat[cl] = EOC           # 先占位，避免重复分配
        return got

    def chain(self, clusters: list) -> None:
        for a, b in zip(clusters, clusters[1:]):
            self.fat[a] = b
        self.fat[clusters[-1]] = EOC

    def put_file(self, name83: bytes, data: bytes, clusters: list) -> None:
        assert len(clusters) * self.spc * BPS >= len(data), "簇不够装文件"
        for i, cl in enumerate(clusters):
            lba = self.cluster_lba(cl)
            chunk = data[i * self.spc * BPS:(i + 1) * self.spc * BPS]
            self.mem[lba * BPS:lba * BPS + len(chunk)] = chunk
        self.chain(clusters)
        self.add_dir_entry(name83, clusters[0], len(data))

    def add_dir_entry(self, name83: bytes, first_cluster: int, size: int) -> None:
        if self.root_slot >= 16:
            raise RuntimeError("测试镜像根目录首扇区已满")
        if len(name83) != 11:
            raise RuntimeError(f"8.3 短名必须是 11 字节，得到 {len(name83)}: {name83!r}")
        off = self.root_slot * 32
        base = self.cluster_lba(2) * BPS
        e = bytearray(32)
        e[0:11] = name83
        e[11] = 0x20
        struct.pack_into("<H", e, 20, (first_cluster >> 16) & 0xFFFF)
        struct.pack_into("<H", e, 26, first_cluster & 0xFFFF)
        struct.pack_into("<I", e, 28, size)
        self.mem[base + off:base + off + 32] = e
        self.root_slot += 1

    def flush(self, path: Path) -> None:
        for copy in range(self.num_fats):
            base = (self.fat_start + copy * self.fat_size) * BPS
            for i, value in enumerate(self.fat):
                if i < 2:
                    continue
                struct.pack_into("<I", self.mem, base + i * 4, value)
        path.write_bytes(bytes(self.mem))


def build_fixture(path: Path, frag_cover: bool = False, frag_audio: bool = False,
                  song_count: int = 4, width: int = 64, height: int = 4,
                  cover_prefix: str = "PIC", audio_len: int = 2048) -> dict:
    bmp = make_bmp(width, height, 0x2468)
    audio = bytes((i * 37 + 11) & 0xFF for i in range(audio_len))
    bmp_sectors = math.ceil(len(bmp) / BPS)
    audio_sectors = math.ceil(len(audio) / BPS)
    need = song_count * bmp_sectors + audio_sectors + 12
    img = Fat32Builder(data_sectors=max(need, 24))

    covers = []
    for i in range(song_count):
        if frag_cover and i == 0 and bmp_sectors >= 2:
            head = img.alloc(1)         # 首簇
            img.alloc(1)                # 故意隔开一个簇，制造物理断点
            tail = img.alloc(bmp_sectors - 1)
            covers.append(head + tail)  # 链长度仍 = bmp_sectors，尾簇为 EOC
        else:
            covers.append(img.alloc(bmp_sectors))
    for i, cl in enumerate(covers):
        img.put_file((f"{cover_prefix}{i + 1}".ljust(8) + "BMP").encode(), bmp, cl)

    if frag_audio and audio_sectors >= 2:
        head = img.alloc(1)
        img.alloc(1)
        tail = img.alloc(audio_sectors - 1)
        acl = head + tail
    else:
        acl = img.alloc(audio_sectors)
    img.put_file(b"AUDIO   PCM", audio, acl)

    img.flush(path)
    return {"bmp": bmp, "audio": audio, "covers": covers, "audio_clusters": acl,
            "width": width, "height": height, "cover_prefix": cover_prefix}


results = []


def check(cond: bool, name: str) -> None:
    results.append((bool(cond), name))
    print(("PASS " if cond else "FAIL ") + name)


def case_roundtrip() -> None:
    FIXTURE_DIR.mkdir(parents=True, exist_ok=True)
    img = FIXTURE_DIR / "card.img"
    info = build_fixture(img, frag_cover=True)
    rc = vp.main(["pack", "--image", str(img), "--demo",
                  "--width", str(info["width"]), "--height", str(info["height"])])
    check(rc == 0, "pack 返回 0")

    with vp.Fat32Image(img) as fs:
        e = fs.find_root_file("INDEX.BIN")
        data = fs.read_file(e.first_cluster, 512)
    parsed = vp.parse_index(data)
    check(parsed["count"] == 4, "索引曲目数 = 4")
    check(e.first_cluster >= 2, "INDEX.BIN 有合法起始簇")
    check(e.raw_index < 16, "INDEX.BIN 目录项在根目录首扇区（FPGA 可见）")

    report = json.loads((img.with_name("INDEX.json")).read_text(encoding="utf-8"))
    with vp.Fat32Image(img) as fs:
        for s in report["songs"]:
            cov = fs.read_file(s["cover"]["first_cluster"], s["cover"]["bytes"])
            check(hashlib.sha256(cov).hexdigest() == s["cover"]["sha256"],
                  f"{s['cover']['name']} SHA256 可追溯")
            check(len(s["cover"]["lba_runs"]) >= 1,
                  f"{s['cover']['name']} 物理 LBA 运行段已记录")
    check(len(report["songs"][0]["cover"]["lba_runs"]) >= 2,
          "碎片封面被拆成多段 LBA（FAT 链仍正确）")
    check(len(report["songs"][0]["audio"]["lba_runs"]) == 1,
          "连续 PCM 布局保持单段 LBA（Seek 逐扇区 +1 前提）")

    rc = vp.main(["verify", "--image", str(img),
                  "--width", str(info["width"]), "--height", str(info["height"])])
    check(rc == 0, "verify 回读校验通过")

    raw = img.read_bytes()
    (FIXTURE_DIR / "card_mem.hex").write_text(
        "\n".join(f"{b:02x}" for b in raw) + "\n", encoding="ascii")
    (FIXTURE_DIR / "index_only.hex").write_text(
        "\n".join(f"{b:02x}" for b in data) + "\n", encoding="ascii")
    (FIXTURE_DIR / "card_meta.json").write_text(json.dumps({
        "bytes": len(raw), "width": info["width"], "height": info["height"],
        "song_count": 4, "index_cluster": e.first_cluster,
        "fat_start_lba": 32, "data_start_lba": 34,
    }, indent=2), encoding="utf-8")


def case_crc_detect() -> None:
    img = FIXTURE_DIR / "card.img"
    bad = bytearray(img.read_bytes())
    with vp.Fat32Image(img) as fs:
        e = fs.find_root_file("INDEX.BIN")
        base = fs.cluster_lba(e.first_cluster) * BPS
    bad[base + vp.HEADER_SIZE + 5] ^= 0x5A
    broken = FIXTURE_DIR / "card_badcrc.img"
    broken.write_bytes(bytes(bad))
    try:
        with vp.Fat32Image(broken) as fs:
            e = fs.find_root_file("INDEX.BIN")
            vp.parse_index(fs.read_file(e.first_cluster, 512))
        check(False, "CRC 错误应被拒绝")
    except vp.PackError as exc:
        check("crc" in str(exc).lower(), f"CRC 错误被拒绝: {exc}")


def case_count_overflow() -> None:
    songs = [vp.IndexSong(title=f"t{i}", flags=vp.FLAG_COVER, cover_cluster=3,
                          cover_bytes=100) for i in range(5)]
    try:
        vp.build_index(songs)
        check(False, "曲目数 > 4 应被拒绝")
    except vp.PackError as exc:
        check("1.." in str(exc) or "上限" in str(exc), f"曲目超限被拒绝: {exc}")

    blob = bytearray(vp.build_index([
        vp.IndexSong(title="a", flags=vp.FLAG_COVER, cover_cluster=3,
                     cover_bytes=100)]))
    struct.pack_into("<H", blob, 12, 5)
    try:
        vp.parse_index(bytes(blob))
        check(False, "头部 song_count=5 应被拒绝")
    except vp.PackError as exc:
        check("超出" in str(exc), f"头部计数越界被拒绝: {exc}")


def case_cluster_range() -> None:
    songs = [vp.IndexSong(title="a", flags=vp.FLAG_COVER, cover_cluster=1,
                          cover_bytes=100)]
    parsed = vp.parse_index(vp.build_index(songs))
    check(parsed["songs"][0]["cover_cluster"] == 1,
          "越界簇被原样解析（由 RTL 用 max_cluster 拒绝）")


def case_fragmented_audio() -> None:
    img = FIXTURE_DIR / "card_fragaudio.img"
    rep = FIXTURE_DIR / "card_fragaudio.json"
    info = build_fixture(img, frag_audio=True)
    rc = vp.main(["pack", "--image", str(img), "--demo", "--report", str(rep),
                  "--width", str(info["width"]), "--height", str(info["height"])])
    check(rc == 2, "音频碎片且未加开关时必须拒绝")
    rc = vp.main(["pack", "--image", str(img), "--demo", "--allow-fragmented-audio",
                  "--report", str(rep),
                  "--width", str(info["width"]), "--height", str(info["height"])])
    check(rc == 0, "显式允许后可出索引（风险已记录）")
    before = hashlib.sha256(img.read_bytes()).hexdigest()
    rc = vp.main(["verify", "--image", str(img),
                  "--width", str(info["width"]), "--height", str(info["height"])])
    check(rc == 2, "正式 verify 必须拒绝碎片音频，即使打包显式允许")
    check(hashlib.sha256(img.read_bytes()).hexdigest() == before,
          "拒绝碎片音频时只读校验不得改写镜像")


def case_odd_audio() -> None:
    img = FIXTURE_DIR / "card_odd_audio.img"
    info = build_fixture(img, audio_len=2047)
    rc = vp.main(["pack", "--image", str(img), "--demo",
                  "--width", str(info["width"]), "--height", str(info["height"])])
    check(rc == 2, "奇数音频字节长度必须被拒绝")


def case_song_named_fixture() -> None:
    """封面不叫 PIC1~4.BMP 的夹具：用来证明"封面来自索引"而不是旧 PIC 路径。"""
    img = FIXTURE_DIR / "card_song.img"
    info = build_fixture(img, cover_prefix="SONG")
    man = FIXTURE_DIR / "songs_songnamed.json"
    man.write_text(json.dumps({"songs": [
        {"title": f"Track {i + 1}", "cover": f"SONG{i + 1}.BMP",
         "audio": "AUDIO.PCM" if i == 0 else None}
        for i in range(4)]}, indent=2), encoding="utf-8")
    rep = FIXTURE_DIR / "card_song.json"
    rc = vp.main(["pack", "--image", str(img), "--manifest", str(man),
                  "--report", str(rep),
                  "--width", str(info["width"]), "--height", str(info["height"])])
    check(rc == 0, "SONG 命名夹具打包成功")
    report = json.loads(rep.read_text(encoding="utf-8"))
    check(report["song_count"] == 4, "SONG 夹具索引含 4 首")
    raw = img.read_bytes()
    (FIXTURE_DIR / "card_song_mem.hex").write_text(
        "\n".join(f"{b:02x}" for b in raw) + "\n", encoding="ascii")
    (FIXTURE_DIR / "card_song_meta.json").write_text(json.dumps({
        "bytes": len(raw), "index_cluster": report["index_cluster"],
        "index_lba": report["index_lba"], "song_count": 4,
    }, indent=2), encoding="utf-8")


def main() -> int:
    case_roundtrip()
    case_crc_detect()
    case_count_overflow()
    case_cluster_range()
    case_fragmented_audio()
    case_odd_audio()
    case_song_named_fixture()
    bad = [n for ok, n in results if not ok]
    print(f"\n{'PASS' if not bad else 'FAIL'}: vinyl_packer 自测 "
          f"{len(results) - len(bad)}/{len(results)} 项通过")
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
