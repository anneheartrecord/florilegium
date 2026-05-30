#!/usr/bin/env bash
# 下载「锁死视频」的音频，绕过 YouTube 的 SABR / PO-token 封锁，供 transcribe.py 转写。
# 适用于 fetch-transcript.sh 抓不到字幕、且直接下音频被 403 的视频。
# 依赖：setup.sh 装好的 venv（新版 yt-dlp）+ bgutil 提供器。
# 用法: fetch-audio.sh <url> [browser]   # browser 默认 chrome
# 成功时把音频文件路径打印到 stdout。
set -uo pipefail

URL="${1:-}"
[ -z "$URL" ] && { echo "usage: fetch-audio.sh <url> [browser]" >&2; exit 1; }
BROWSER="${2:-chrome}"

HOME_DIR="$HOME/.local/share/tashanzhishi"
VENV_PY="$HOME_DIR/venv/bin/python"
PY="$([ -x "$VENV_PY" ] && echo "$VENV_PY" || echo python3)"
BGUTIL_MAIN="$HOME_DIR/bgutil/server/build/main.js"

# 1) 确保 bgutil POT 提供器在 :4416 运行（锁死视频靠它解锁）
if ! curl -s -m 3 http://127.0.0.1:4416/ping >/dev/null 2>&1; then
  if [ -f "$BGUTIL_MAIN" ]; then
    echo "→ 启动 bgutil POT 提供器..." >&2
    nohup node "$BGUTIL_MAIN" >/tmp/tashan-bgutil.log 2>&1 &
    for _ in $(seq 1 20); do
      curl -s -m 1 http://127.0.0.1:4416/ping >/dev/null 2>&1 && break
    done
  else
    echo "✗ 未找到 bgutil 提供器，请先运行 setup.sh" >&2
  fi
fi

# 2) 用新版 yt-dlp + cookies + default client 下载音频（bgutil 自动提供 PO token）
DIR="$(mktemp -d -t tashan-audio-XXXXXX)"
"$PY" -m yt_dlp -f bestaudio --cookies-from-browser "$BROWSER" \
  --extractor-args "youtube:player_client=default" \
  -o "$DIR/audio.%(ext)s" "$URL" >&2

AUDIO="$(ls "$DIR"/audio.* 2>/dev/null | head -1)"
if [ -z "$AUDIO" ]; then
  echo "✗ 音频下载失败：yt-dlp 可能需要更新（venv 内），或该视频不可用。" >&2
  exit 2
fi
echo "$AUDIO"
