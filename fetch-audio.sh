#!/usr/bin/env bash
# 下载视频音频，供 transcribe.py 转写。
# 适用于 fetch-transcript.sh 抓不到字幕，或平台没有可下载字幕的情况。
# B 站、播客等走通用 yt-dlp 下载；YouTube 用 deno 解 n-challenge，
# 锁死视频（SABR / PO-token）再按需启动可选的 bgutil 提供器（setup.sh --with-bgutil）。
# 用法: fetch-audio.sh <url> [browser]
# 登录态规则同 fetch-transcript.sh（见 lib.sh）：先 cookie 文件或匿名，失败再自动找浏览器重试。
# 成功时把音频文件路径打印到 stdout。
set -uo pipefail
SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SD/lib.sh"

URL="${1:-}"
[ -z "$URL" ] && { echo "usage: fetch-audio.sh <url> [browser]" >&2; exit 1; }

if ! tsz_ytdlp; then
  echo "✗ 没有找到 yt-dlp。先运行: bash $SD/setup.sh" >&2
  exit 1
fi

BGUTIL_MAIN="$TSZ_HOME/bgutil/server/build/main.js"
DIR="$(mktemp -d -t tashan-audio-XXXXXX)"
YTDLP_ARGS=(-f "bestaudio/18/worst[acodec!=none]/best[acodec!=none]" -o "$DIR/audio.%(ext)s")

if is_youtube_url "$URL"; then
  if DENO="$(tsz_deno)"; then
    YTDLP_ARGS+=(--js-runtimes "deno:$DENO")
  else
    echo "! 没找到 deno，YouTube 很可能拿不到音频。重跑 bash $SD/setup.sh 会装上" >&2
  fi
  YTDLP_ARGS+=(--extractor-args "youtube:player_client=default")

  # bgutil 是可选组件：构建过才启动，用来解锁 SABR / PO-token 锁死的视频
  if [ -f "$BGUTIL_MAIN" ] && command -v node >/dev/null 2>&1 \
     && ! curl -s -m 3 http://127.0.0.1:4416/ping >/dev/null 2>&1; then
    echo "→ 启动 bgutil POT 提供器..." >&2
    nohup node "$BGUTIL_MAIN" >"${TMPDIR:-/tmp}/tashan-bgutil.log" 2>&1 &
    # 等提供器就绪（最多 ~30s）。用 curl 自带重试，避免 sleep；node 启动要几秒。
    curl -s --retry 30 --retry-delay 1 --retry-connrefused -m 3 \
      http://127.0.0.1:4416/ping >/dev/null 2>&1 \
      || echo "⚠ 提供器未在 30s 内就绪" >&2
  fi
else
  echo "→ 非 YouTube 链接，使用通用 yt-dlp 音频下载路径" >&2
fi

fetch() { "${TSZ_YTDLP[@]}" "${YTDLP_ARGS[@]}" "$@" "$URL" >&2; }
got_audio() { ls "$DIR"/audio.* >/dev/null 2>&1; }

PINNED="${2:-${TSZ_BROWSER:-}}"
if [ -n "$PINNED" ]; then
  fetch --cookies-from-browser "$PINNED"
else
  tsz_cookie_file_args; rc=$?
  [ "$rc" -eq 2 ] && exit 1
  if [ "$rc" -eq 0 ]; then first="用 cookie 文件"; fetch "${TSZ_COOKIE_ARGS[@]}"
  else first="匿名"; fetch; fi
  if ! got_audio && BROWSER="$(tsz_detect_browser)"; then
    echo "→ ${first}下载失败，改用 ${BROWSER} 的登录态重试（macOS 可能弹钥匙串授权）" >&2
    fetch --cookies-from-browser "$BROWSER"
  fi
fi

AUDIO="$(ls "$DIR"/audio.* 2>/dev/null | head -1)"
if [ -z "$AUDIO" ]; then
  echo "✗ 音频下载失败。可以按顺序排查：" >&2
  echo "  1. bash $SD/setup.sh --upgrade   视频站改版后旧 yt-dlp 会失效" >&2
  if is_youtube_url "$URL" && [ ! -f "$BGUTIL_MAIN" ]; then
    echo "  2. bash $SD/setup.sh --with-bgutil   解锁 YouTube 锁死视频（需要 Node.js）" >&2
  fi
  echo "  或者把平台自带的文字稿、字幕粘贴过来直接整理。" >&2
  exit 2
fi
echo "$AUDIO"
