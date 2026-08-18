# -*- coding: utf-8 -*-
"""生成 iClass 静态资源（无需第三方库）：
- assets/sounds/reminder.wav  提醒提示音（双音阶铃声）
- assets/icons/tray.ico       托盘图标（淡蓝圆角方块 + 白色表盘）
- assets/icons/app_icon.ico   应用图标（同款，多尺寸）

用户提供真实资源后，把文件放到 assets/user_assets/ 即可优先使用：
- reminder.wav → 提示音（直接用用户的音频文件）
- iClass_icon.png → 图标源文件（先运行 tools/convert_icon.ps1 生成 ico，
  再复制到 assets/icons/ 与 windows/runner/resources/；本脚本不再覆盖图标）
"""
import math
import os
import shutil
import struct
import wave
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")
USER_ASSETS = os.path.join(ASSETS, "user_assets")
os.makedirs(os.path.join(ASSETS, "sounds"), exist_ok=True)
os.makedirs(os.path.join(ASSETS, "icons"), exist_ok=True)


# ---------------- PNG 写入 ----------------

def png_chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + \
           struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def write_png(path, w, h, rgba):
    raw = b"".join(b"\x00" + bytes(rgba[y * w * 4:(y + 1) * w * 4]) for y in range(h))
    data = b"\x89PNG\r\n\x1a\n"
    data += png_chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    data += png_chunk(b"IDAT", zlib.compress(raw, 9))
    data += png_chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(data)


def png_bytes(w, h, rgba):
    raw = b"".join(b"\x00" + bytes(rgba[y * w * 4:(y + 1) * w * 4]) for y in range(h))
    data = b"\x89PNG\r\n\x1a\n"
    data += png_chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    data += png_chunk(b"IDAT", zlib.compress(raw, 9))
    data += png_chunk(b"IEND", b"")
    return data


# ---------------- ICO 写入（PNG 条目，Vista+ 全尺寸可用） ----------------

def write_ico(path, images):
    """images: [(size, png_bytes)]"""
    count = len(images)
    header = struct.pack("<HHH", 0, 1, count)
    offset = 6 + 16 * count
    entries = b""
    blobs = b""
    for size, png in images:
        entries += struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32, len(png), offset)
        blobs += png
        offset += len(png)
    with open(path, "wb") as f:
        f.write(header + entries + blobs)


# ---------------- 图标绘制：淡蓝圆角方块 + 白色表盘 + 指针 ----------------

BG = (91, 155, 213, 255)      # 淡蓝
WHITE = (255, 255, 255, 255)  # 表盘
HAND = (40, 90, 140, 255)     # 深蓝指针


def seg_dist(px, py, x1, y1, x2, y2):
    vx, vy = x2 - x1, y2 - y1
    wx, wy = px - x1, py - y1
    t = max(0.0, min(1.0, (wx * vx + wy * vy) / (vx * vx + vy * vy)))
    return math.hypot(px - (x1 + t * vx), py - (y1 + t * vy))


def draw_icon(size):
    w = h = size
    px = bytearray(w * h * 4)
    cx = cy = (size - 1) / 2.0
    radius = size * 0.30
    corner = size * 0.22
    hand_w = max(0.8, size * 0.045)

    def hand_dir(deg):
        r = math.radians(deg)
        return math.sin(r), -math.cos(r)  # 0 度 = 12 点方向

    h1x, h1y = hand_dir(-55)  # 时针（10 点）
    h2x, h2y = hand_dir(150)  # 分针（5 点）
    h1l = radius * 0.50
    h2l = radius * 0.68

    for y in range(h):
        for x in range(w):
            i = (y * w + x) * 4
            # 圆角方块背景
            dx = max(corner - x, x - (w - corner), 0.0)
            dy = max(corner - y, y - (h - corner), 0.0)
            if dx * dx + dy * dy > corner * corner:
                continue
            px[i:i + 4] = bytes(BG)
            # 白色表盘
            if (x - cx) ** 2 + (y - cy) ** 2 <= radius * radius:
                px[i:i + 4] = bytes(WHITE)
            # 指针（小尺寸下略过，避免糊成一团）
            if size >= 32:
                if seg_dist(x, y, cx, cy, cx + h1x * h1l, cy + h1y * h1l) <= hand_w or \
                   seg_dist(x, y, cx, cy, cx + h2x * h2l, cy + h2y * h2l) <= hand_w:
                    px[i:i + 4] = bytes(HAND)
            # 中心点
            if (x - cx) ** 2 + (y - cy) ** 2 <= (size * 0.04) ** 2:
                px[i:i + 4] = bytes(HAND)
    return bytes(px)


# ---------------- 提示音：880Hz + 1174Hz 双音阶 ----------------

def write_wav(path):
    rate = 44100
    samples = []

    def tone(freq, start, dur, amp):
        n0 = int(start * rate)
        n1 = int((start + dur) * rate)
        for n in range(n0, n1):
            t = (n - n0) / rate
            env = min(1.0, t / 0.02) * min(1.0, (dur - t) / 0.10)
            samples.append(int(32767 * amp * env * math.sin(2 * math.pi * freq * t)))

    tone(880.0, 0.0, 0.45, 0.9)
    tone(1174.66, 0.45, 0.70, 0.9)
    total = int(rate * 1.2)
    while len(samples) < total:
        samples.append(0)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(rate)
        f.writeframes(struct.pack("<%dh" % len(samples), *samples))


# ---------------- 生成 ----------------

# 提示音：用户提供了 assets/user_assets/reminder.wav 就直接用，否则程序化生成
user_wav = os.path.join(USER_ASSETS, "reminder.wav")
if os.path.exists(user_wav):
    shutil.copy(user_wav, os.path.join(ASSETS, "sounds", "reminder.wav"))
    print("reminder.wav 已复制（使用用户提供的提示音）")
else:
    write_wav(os.path.join(ASSETS, "sounds", "reminder.wav"))
    print("reminder.wav 已生成（程序化铃声）")

# 图标：用户提供了 assets/user_assets/iClass_icon.png 时不覆盖已有 ico
#（需要先运行 tools/convert_icon.ps1 转换，再把 ico 复制到
#  assets/icons/ 与 windows/runner/resources/）
user_png = os.path.join(USER_ASSETS, "iClass_icon.png")
if os.path.exists(user_png):
    print("检测到用户图标源文件，跳过图标生成（请用 tools/convert_icon.ps1 转换）")
else:
    tray_images = [(16, png_bytes(16, 16, draw_icon(16))), (32, png_bytes(32, 32, draw_icon(32)))]
    write_ico(os.path.join(ASSETS, "icons", "tray.ico"), tray_images)
    print("tray.ico 已生成（程序化图标）")

    app_images = [
        (16, png_bytes(16, 16, draw_icon(16))),
        (32, png_bytes(32, 32, draw_icon(32))),
        (48, png_bytes(48, 48, draw_icon(48))),
        (256, png_bytes(256, 256, draw_icon(256))),
    ]
    write_ico(os.path.join(ASSETS, "icons", "app_icon.ico"), app_images)
    print("app_icon.ico 已生成（程序化图标）")
