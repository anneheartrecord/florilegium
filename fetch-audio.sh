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
DENO="$(command -v deno 2>/dev/null || echo "$HOME/.deno/bin/deno")"  # 解 YouTube n-challenge

# 1) 确保 bgutil POT 提供器在 :4416 运行（锁死视频靠它解锁）
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

# 2) 用新版 yt-dlp + cookies + default client 下载音频（bgutil 自动提供 PO token）
DIR="$(mktemp -d -t tashan-audio-XXXXXX)"
JS_ARGS=(); [ -x "$DENO" ] && JS_ARGS=(--js-runtimes "deno:$DENO")
"$PY" -m yt_dlp -f bestaudio "${JS_ARGS[@]}" --cookies-from-browser "$BROWSER" \
  --extractor-args "youtube:player_client=default" \
  -o "$DIR/audio.%(ext)s" "$URL" >&2

AUDIO="$(ls "$DIR"/audio.* 2>/dev/null | head -1)"
if [ -z "$AUDIO" ]; then
  echo "✗ 音频下载失败：yt-dlp 可能需要更新（venv 内），或该视频不可用。" >&2
  exit 2
fi
echo "$AUDIO"
