#!/usr/bin/env bash
# 下载视频音频，供 transcribe.py 转写。
# 适用于 fetch-transcript.sh 抓不到字幕，或平台没有可下载字幕的情况。
# YouTube 会按需启动 bgutil 提供器绕过 SABR / PO-token；B 站等其他平台走通用 yt-dlp 下载。
# 依赖：setup.sh 装好的 venv（新版 yt-dlp）+ faster-whisper；YouTube 锁死视频额外依赖 bgutil 提供器。
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
DENO="$(command -v deno 2>/dev/null || echo "$HOME/.deno/bin/deno")"  # 解 YouTube n-challenge

is_youtube_url() {
  case "$URL" in
    *youtube.com*|*youtu.be*) return 0 ;;
    *) return 1 ;;
  esac
}

DIR="$(mktemp -d -t tashan-audio-XXXXXX)"
YTDLP_ARGS=(-f bestaudio --cookies-from-browser "$BROWSER" -o "$DIR/audio.%(ext)s")

if is_youtube_url; then
  # 锁死的 YouTube 视频靠 bgutil 解锁；B 站等平台不要走这套 YouTube 专用参数。
  if ! curl -s -m 3 http://127.0.0.1:4416/ping >/dev/null 2>&1; then
    if [ -f "$BGUTIL_MAIN" ]; then
      echo "→ 启动 bgutil POT 提供器..." >&2
      nohup node "$BGUTIL_MAIN" >/tmp/tashan-bgutil.log 2>&1 &
      # 等提供器就绪（最多 ~30s）。用 curl 自带重试，避免 sleep；node 启动要几秒。
      curl -s --retry 30 --retry-delay 1 --retry-connrefused -m 3 \
        http://127.0.0.1:4416/ping >/dev/null 2>&1 \
        || echo "⚠ 提供器未在 30s 内就绪" >&2
    else
      echo "✗ 未找到 bgutil 提供器，请先运行 setup.sh" >&2
    fi
  fi

  [ -x "$DENO" ] && YTDLP_ARGS+=(--js-runtimes "deno:$DENO")
  YTDLP_ARGS+=(--extractor-args "youtube:player_client=default")
else
  echo "→ 非 YouTube 链接，使用通用 yt-dlp 音频下载路径" >&2
fi

"$PY" -m yt_dlp "${YTDLP_ARGS[@]}" "$URL" >&2

AUDIO="$(ls "$DIR"/audio.* 2>/dev/null | head -1)"
if [ -z "$AUDIO" ]; then
  echo "✗ 音频下载失败：yt-dlp 可能需要更新（venv 内），或该视频不可用。" >&2
  exit 2
fi
echo "$AUDIO"
