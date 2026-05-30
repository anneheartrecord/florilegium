#!/usr/bin/env bash
# Fetch a video's metadata + subtitles for 他山之石 archival.
# Usage: fetch-transcript.sh <url>
# On success: prints the temp dir path on stdout.
#   <dir>/meta.txt  -> 标题 ||| 作者 ||| 上传日期 ||| 链接 ||| 时长
#   <dir>/sub.*.vtt -> 字幕文件（优先中文，其次英文）
# yt-dlp diagnostics go to stderr.

set -uo pipefail

URL="${1:-}"
if [[ -z "$URL" ]]; then
  echo "usage: fetch-transcript.sh <url> [browser]   # browser 默认 chrome" >&2
  exit 1
fi
# YouTube 现在要求登录态才能下字幕，用浏览器 cookies 解锁。需在该浏览器登录 YouTube。
BROWSER="${2:-chrome}"

# 解析 yt-dlp 调用方式：优先 PATH 上的 yt-dlp，回退到 python3 -m yt_dlp
if command -v yt-dlp >/dev/null 2>&1; then
  YTDLP=(yt-dlp)
elif python3 -m yt_dlp --version >/dev/null 2>&1; then
  YTDLP=(python3 -m yt_dlp)
else
  echo "yt-dlp 未安装。安装: python3 -m pip install --user yt-dlp  或  brew install yt-dlp" >&2
  exit 1
fi

DIR="$(mktemp -d -t tashan-XXXXXX)"

# --skip-download: 只要字幕和元数据，不下视频，因此不需要 ffmpeg。
# 优先简中/繁中/通用中文，回退英文。自动字幕和人工字幕都试。
"${YTDLP[@]}" --skip-download \
  --cookies-from-browser "$BROWSER" \
  --write-auto-subs --write-subs \
  --sub-langs "zh-Hans,zh-Hant,zh,zh-CN,en,en-orig" \
  --sub-format vtt \
  --print-to-file "%(title)s ||| %(uploader)s ||| %(upload_date)s ||| %(webpage_url)s ||| %(duration_string)s" "$DIR/meta.txt" \
  -o "$DIR/sub.%(ext)s" \
  "$URL" >&2

# 检查是否真的拿到字幕文件
if ! ls "$DIR"/sub.*.vtt >/dev/null 2>&1; then
  echo "没有抓到字幕（该视频可能没有字幕或自动字幕）。请让用户粘贴文字稿。" >&2
  echo "$DIR"
  exit 2
fi

echo "$DIR"
