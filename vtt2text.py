#!/usr/bin/env python3
"""把 yt-dlp 下载的 .vtt 字幕清洗成纯文本。
用法: python3 vtt2text.py <file.vtt>
处理：去掉 WEBVTT 头、时间轴、cue 编号、内联 <c>/<时间戳> 标签；
合并 YouTube 自动字幕常见的滚动重复（逐行去重 + 去掉被下一行包含的前缀行）。
"""
import sys
import re
import html

if len(sys.argv) < 2:
    sys.exit("usage: vtt2text.py <file.vtt>")

raw_lines = []
with open(sys.argv[1], encoding="utf-8") as fh:
    for raw in fh:
        line = raw.rstrip("\n")
        if line.startswith(("WEBVTT", "Kind:", "Language:", "NOTE")):
            continue
        if "-->" in line:
            continue
        if re.match(r"^\d+$", line.strip()):  # cue 编号
            continue
        line = re.sub(r"<[^>]+>", "", line)    # 内联标签
        line = html.unescape(line)             # &gt; &amp; 等实体
        line = line.strip()
        if line:
            raw_lines.append(line)

# 逐行去重 + 去掉与下一行重复或被其包含的滚动残留
cleaned = []
for i, line in enumerate(raw_lines):
    nxt = raw_lines[i + 1] if i + 1 < len(raw_lines) else ""
    if cleaned and line == cleaned[-1]:
        continue
    if line and nxt and (line == nxt or nxt.startswith(line)):
        continue
    cleaned.append(line)

print("\n".join(cleaned))
