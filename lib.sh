#!/usr/bin/env bash
# tashanzhishi 脚本共用函数。被其他脚本 source，不要直接执行。

TSZ_HOME="$HOME/.local/share/tashanzhishi"
TSZ_VENV="$TSZ_HOME/venv"
TSZ_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/tashanzhishi/config"

# 批量转写的中间产物目录，可用环境变量 TSZ_OUT 覆盖
tsz_out_dir() { echo "${TSZ_OUT:-$TSZ_HOME/out}"; }

# venv python（setup.sh 装的；没有就退回 python3）
tsz_py() {
  local p="$TSZ_VENV/bin/python"
  [ -x "$p" ] && echo "$p" || echo python3
}

# yt-dlp 调用方式写进数组 TSZ_YTDLP。优先 venv：PATH 上的 yt-dlp 常是过期的系统版本，
# 视频站一改版就抓不到。都没有时返回 1。
tsz_ytdlp() {
  if [ -x "$TSZ_VENV/bin/python" ] && "$TSZ_VENV/bin/python" -c "import yt_dlp" >/dev/null 2>&1; then
    TSZ_YTDLP=("$TSZ_VENV/bin/python" -m yt_dlp)
  elif command -v yt-dlp >/dev/null 2>&1; then
    TSZ_YTDLP=(yt-dlp)
  else
    return 1
  fi
}

# YouTube 解 n-challenge 用的 deno：setup.sh 装进 venv 的优先，其次系统里已有的
tsz_deno() {
  local d
  for d in "$TSZ_VENV/bin/deno" "$(command -v deno 2>/dev/null)" "$HOME/.deno/bin/deno"; do
    [ -n "$d" ] && [ -x "$d" ] && { echo "$d"; return 0; }
  done
  return 1
}

is_youtube_url() {
  case "$1" in *youtube.com*|*youtu.be*) return 0 ;; *) return 1 ;; esac
}

# 找一个用过的浏览器，供「匿名抓取失败后用登录态重试」。看的是浏览器的用户数据目录，
# 装了没用过的浏览器没有 cookie，不算。Safari 读 cookie 需要「完全磁盘访问」授权，不自动选。
tsz_detect_browser() {
  local base
  if [ "$(uname)" = "Darwin" ]; then
    base="$HOME/Library/Application Support"
    [ -d "$base/Google/Chrome" ] && { echo chrome; return 0; }
    [ -d "$base/Firefox/Profiles" ] && { echo firefox; return 0; }
    [ -d "$base/BraveSoftware/Brave-Browser" ] && { echo brave; return 0; }
    [ -d "$base/Microsoft Edge" ] && { echo edge; return 0; }
    [ -d "$base/Chromium" ] && { echo chromium; return 0; }
  else
    [ -d "$HOME/.config/google-chrome" ] && { echo chrome; return 0; }
    { [ -d "$HOME/.mozilla/firefox" ] || [ -d "$HOME/snap/firefox" ]; } && { echo firefox; return 0; }
    [ -d "$HOME/.config/BraveSoftware/Brave-Browser" ] && { echo brave; return 0; }
    [ -d "$HOME/.config/microsoft-edge" ] && { echo edge; return 0; }
    [ -d "$HOME/.config/chromium" ] && { echo chromium; return 0; }
  fi
  return 1
}

# 用户显式指定的登录态写进数组 TSZ_COOKIE_ARGS：cookie 文件（TSZ_COOKIES）优先，
# 其次浏览器（参数或 TSZ_BROWSER）。没指定返回 1，调用方先匿名抓，失败再自动找浏览器。
tsz_explicit_cookie_args() { # [browser]
  local browser="${1:-${TSZ_BROWSER:-}}"
  if [ -n "${TSZ_COOKIES:-}" ]; then
    [ -f "$TSZ_COOKIES" ] || { echo "✗ TSZ_COOKIES 指向的文件不存在：$TSZ_COOKIES" >&2; return 2; }
    TSZ_COOKIE_ARGS=(--cookies "$TSZ_COOKIES")
  elif [ -n "$browser" ]; then
    TSZ_COOKIE_ARGS=(--cookies-from-browser "$browser")
  else
    return 1
  fi
}

# 文章输出目录：环境变量 TSZ_ARTICLE_DIR 优先，其次配置文件。都没有返回 1。
tsz_article_dir() {
  if [ -n "${TSZ_ARTICLE_DIR:-}" ]; then
    echo "$TSZ_ARTICLE_DIR"; return 0
  fi
  [ -f "$TSZ_CONFIG" ] || return 1
  local d; d="$(sed -n 's/^article_dir=//p' "$TSZ_CONFIG" | tail -1)"
  [ -n "$d" ] || return 1
  echo "$d"
}

# 保存文章输出目录：展开 ~、转绝对路径、建目录，再写配置。成功时打印绝对路径。
tsz_set_article_dir() { # <dir>
  local d="$1"
  case "$d" in "~") d="$HOME" ;; "~/"*) d="$HOME/${d#\~/}" ;; esac
  mkdir -p "$d" || { echo "✗ 无法创建目录：$d" >&2; return 1; }
  d="$(cd "$d" && pwd)"
  mkdir -p "$(dirname "$TSZ_CONFIG")"
  if [ -f "$TSZ_CONFIG" ]; then
    grep -v '^article_dir=' "$TSZ_CONFIG" > "$TSZ_CONFIG.tmp" || true
    mv "$TSZ_CONFIG.tmp" "$TSZ_CONFIG"
  fi
  printf 'article_dir=%s\n' "$d" >> "$TSZ_CONFIG"
  echo "$d"
}

# 候选输出目录，每行一个：本机找到的 Obsidian 库各给一个「<库>/他山之石」，最后是通用默认。
tsz_suggest_article_dirs() {
  local v roots=("$HOME/Documents" "$HOME" "$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents")
  for v in "${roots[@]}"; do
    [ -d "$v" ] || continue
    find "$v" -maxdepth 3 -type d -name .obsidian -not -path '*/.Trash/*' 2>/dev/null
  done | while read -r o; do echo "$(dirname "$o")/他山之石"; done | awk '!seen[$0]++'
  echo "$HOME/Documents/他山之石"
}

# URL → 规范 ID。B 站取 BV 号，YouTube 取视频 ID，其余取路径末段；
# 提取结果必须通过字符集校验，否则退回 URL 哈希——
# 这道闸门是给「https:.txt」那类垃圾文件名上一把锁（2026-08-29 事故）。
tsz_id_from_url() {
  local url="$1" id=""
  case "$url" in
    *bilibili.com*|*b23.tv*)
      id="$(printf '%s' "$url" | grep -oE 'BV[0-9A-Za-z]{10}' | head -1)" ;;
    *youtu.be/*)
      id="${url#*youtu.be/}"; id="${id%%\?*}"; id="${id%%#*}"; id="${id%%/*}" ;;
    *youtube.com*)
      case "$url" in
        # & 是 shell 元字符，case 模式里必须转义
        *[?\&]v=*)  id="${url#*[?\&]v=}"; id="${id%%&*}"; id="${id%%#*}" ;;
        */shorts/*|*/live/*|*/embed/*)
          id="${url#*/shorts/}"; id="${id#*/live/}"; id="${id#*/embed/}"
          id="${id%%\?*}"; id="${id%%#*}"; id="${id%%/*}" ;;
      esac ;;
    *)
      id="$(basename "${url%%\?*}")"; id="${id%.*}" ;;
  esac
  if ! printf '%s' "$id" | grep -qE '^[A-Za-z0-9_-]{6,24}$'; then
    id="$(printf '%s' "$url" | shasum -a 256 | cut -c1-12)"
  fi
  printf '%s\n' "$id"
}

# 是否已完成：只看 .status，绝不用「文本文件非空」判断——
# 被中断的转写会留下一个语法完整但内容截断的 .txt，从大小看不出来。
tsz_is_done() { [ -f "$(tsz_out_dir)/$1.status" ]; }

# 是否失败过（batch 会在重跑前清掉）
tsz_is_failed() { [ -f "$(tsz_out_dir)/$1.fail" ]; }

# 写完成标记（仅在转写退出码为 0 后调用）：时长、字节数、后端与模型、完成时间
tsz_mark_done() { # <id> <dur_sec> <backend> <model>
  local id="$1" secs="$2" backend="$3" model="$4" out; out="$(tsz_out_dir)"
  printf 'finished=%s\nduration_sec=%s\nbytes=%s\nbackend=%s\nmodel=%s\n' \
    "$(date -Iseconds)" "$secs" "$(wc -c < "$out/$id.txt" | tr -d ' ')" \
    "$backend" "$model" > "$out/$id.status"
}

tsz_mark_fail() { # <id> <原因>
  printf 'failed=%s\nreason=%s\n' "$(date -Iseconds)" "$2" \
    > "$(tsz_out_dir)/$1.fail"
}

# 记录「正在跑哪条」：<id> <pid> <start_epoch>。status.sh 靠 pid 存活判断真在跑。
tsz_set_current() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" > "$(tsz_out_dir)/.current"; }
tsz_clear_current() { rm -f "$(tsz_out_dir)/.current"; }

# 探测当前默认转写后端（与 transcribe.py 的选择逻辑一致）
tsz_backend() {
  if [ "$(uname)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ] \
     && "$(tsz_py)" -c "import mlx_whisper" >/dev/null 2>&1; then
    echo mlx-gpu
  else
    echo faster-cpu
  fi
}

# 音频文件时长（秒）；探测失败回 0，不阻塞流程。PyAV 由 faster-whisper 依赖带入。
tsz_audio_secs() {
  "$(tsz_py)" - "$1" <<'PYEOF' 2>/dev/null
import sys
try:
    import av
    with av.open(sys.argv[1]) as c:
        print(int((c.duration or 0) / av.time_base))
except Exception:
    print(0)
PYEOF
}
