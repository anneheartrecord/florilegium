#!/usr/bin/env bash
# Fetch a video's metadata + subtitles for 他山之石 archival.
# Usage: fetch-transcript.sh <url> [browser]
# On success: prints the temp dir path on stdout.
#   <dir>/meta.txt  -> 标题 ||| 作者 ||| 上传日期 ||| 链接 ||| 时长
#   <dir>/sub.*.vtt 或 sub.*.srt -> 字幕文件（优先中文，其次英文；B 站只给 srt）
# yt-dlp diagnostics go to stderr.
#
# 登录态：指定了 browser 参数、TSZ_BROWSER 或 TSZ_COOKIES（cookie 文件）就直接用；
# 都没指定时先匿名抓，没拿到字幕再自动找一个用过的浏览器读登录态重试
# （B 站 AI 字幕、YouTube 人机验证都需要登录态）。

set -uo pipefail
SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SD/lib.sh"

URL="${1:-}"
if [[ -z "$URL" ]]; then
  echo "usage: fetch-transcript.sh <url> [browser]" >&2
  exit 1
fi

if ! tsz_ytdlp; then
  echo "✗ 没有找到 yt-dlp。先运行: bash $SD/setup.sh" >&2
  exit 1
fi

EXTRA=()
if is_youtube_url "$URL"; then
  DENO="$(tsz_deno)" && EXTRA+=(--js-runtimes "deno:$DENO")
fi

DIR="$(mktemp -d -t tashan-XXXXXX)"

# --skip-download: 只要字幕和元数据，不下视频，因此不需要 ffmpeg。
# 优先简中/繁中/通用中文，回退英文。自动字幕和人工字幕都试。
fetch() { # [cookie 参数...]
  rm -f "$DIR"/sub.* "$DIR/meta.txt"
  "${TSZ_YTDLP[@]}" --skip-download "$@" ${EXTRA[@]+"${EXTRA[@]}"} \
    --write-auto-subs --write-subs \
    --sub-langs "zh-Hans,zh-Hant,zh,zh-CN,ai-zh,en,en-orig" \
    --sub-format "vtt/srt/best" \
    --print-to-file "%(title)s ||| %(uploader)s ||| %(upload_date)s ||| %(webpage_url)s ||| %(duration_string)s" "$DIR/meta.txt" \
    -o "$DIR/sub.%(ext)s" \
    "$URL" >&2
}
has_subs() { local f; for f in "$DIR"/sub.*.vtt "$DIR"/sub.*.srt; do [ -e "$f" ] && return 0; done; return 1; }

tsz_explicit_cookie_args "${2:-}"; rc=$?
if [ "$rc" -eq 2 ]; then
  exit 1
elif [ "$rc" -eq 0 ]; then
  fetch "${TSZ_COOKIE_ARGS[@]}"
else
  fetch
  if ! has_subs && BROWSER="$(tsz_detect_browser)"; then
    echo "→ 匿名没拿到字幕，改用 $BROWSER 的登录态重试（macOS 可能弹钥匙串授权）" >&2
    fetch --cookies-from-browser "$BROWSER"
  fi
fi

if ! has_subs; then
  echo "没有抓到字幕（该视频可能没有字幕，或需要登录态）。可以改走 fetch-audio.sh 下载音频本地转写，或让用户粘贴文字稿。" >&2
  echo "$DIR"
  exit 2
fi

echo "$DIR"
