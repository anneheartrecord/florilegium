#!/usr/bin/env bash
# 批量抓取+转写队列。用法: batch.sh <url1> <url2> ...
#   - 已完成（存在 <id>.status）的自动跳过；重跑同一条命令即续跑。
#   - 单条失败记录 ✗ 并继续下一条，不中断整个队列。
#   - 串行执行：GPU 推理本身串行，并发只加显存压力不提速；
#     CPU 后端要并发见 SKILL.md「后端与并发」。
#   - 产物目录: TSZ_OUT（默认 ~/.local/share/tashanzhishi/out/）
#   - 浏览器登录态: TSZ_BROWSER（默认 chrome，透传给 fetch-audio.sh）
#   - 强制语言: TSZ_LANG（默认 zh）
set -uo pipefail
SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SD/lib.sh"

[ $# -gt 0 ] || { echo "usage: batch.sh <url1> <url2> ..." >&2; exit 1; }

PY="$(tsz_py)"
OUT="$(tsz_out_dir)"; mkdir -p "$OUT"
BROWSER="${TSZ_BROWSER:-chrome}"
LANG_ARG="${TSZ_LANG:-zh}"
BACKEND="$(tsz_backend)"
# 倍率=转写速度÷音频时长，2026-08-29 在 M1 Pro 实测（GPU 5.6x / CPU 1.2x），粗估用
case "$BACKEND" in mlx-gpu) RATE=5.6 ;; *) RATE=1.2 ;; esac

total=$#; i=0; ok=0; fail=0; skip=0
CHILD_PID=""; AUDIO_DIR=""

# 队列登记：status.sh 靠它回答「一共几条、还剩几条」
for url in "$@"; do tsz_id_from_url "$url"; done > "$OUT/.queue"

ts() { date +%H:%M; }

on_interrupt() {
  [ -n "$CHILD_PID" ] && kill "$CHILD_PID" 2>/dev/null
  [ -n "$AUDIO_DIR" ] && rm -rf "$AUDIO_DIR"
  tsz_clear_current
  echo ""
  echo "[$(ts)] 中断：$ok 成功 / $fail 失败 / $skip 跳过，还剩 $((total-ok-fail-skip)) 条。重跑同一条命令会跳过已完成的继续。"
  exit 130
}
trap on_interrupt INT TERM

echo "[$(ts)] 队列 $total 条，后端 $BACKEND"
for url in "$@"; do
  i=$((i+1)); id="$(tsz_id_from_url "$url")"
  if tsz_is_done "$id"; then
    echo "[$(ts)] ($i/$total) 跳过 ${id}（已完成）"
    skip=$((skip+1)); continue
  fi
  rm -f "$OUT/$id.fail"
  echo "[$(ts)] ($i/$total) $id 下载音频"
  AUDIO="$(bash "$SD/fetch-audio.sh" "$url" "$BROWSER")"
  if [ -z "$AUDIO" ] || [ ! -f "$AUDIO" ]; then
    echo "[$(ts)] ($i/$total) ✗ $id 音频下载失败，继续下一条"
    tsz_mark_fail "$id" "音频下载失败"
    fail=$((fail+1)); continue
  fi
  AUDIO_DIR="$(dirname "$AUDIO")"

  # .meta：下载后立刻记时长，status.sh 靠它算「还剩多少音频」
  secs="$(tsz_audio_secs "$AUDIO")"
  printf 'url=%s\nduration_sec=%s\n' "$url" "$secs" > "$OUT/$id.meta"

  echo "[$(ts)] ($i/$total) $id 转写中"
  est_min="$(awk -v s="$secs" -v r="$RATE" 'BEGIN{printf "%d", s/60/r}')"
  [ "${secs:-0}" -gt 0 ] && echo "        （音频 ${secs}s，按 ${RATE}x 实时粗估 ≈ ${est_min} 分钟）"
  tsz_set_current "$id" "$$" "$(date +%s)"
  "$PY" "$SD/transcribe.py" "$AUDIO" "" "$LANG_ARG" \
    > "$OUT/$id.txt" 2> >(tee "$OUT/$id.err" >&2) &
  CHILD_PID=$!
  wait "$CHILD_PID"; rc=$?
  CHILD_PID=""
  tsz_clear_current

  bytes=$(wc -c < "$OUT/$id.txt" | tr -d ' ')
  if [ "$rc" -eq 0 ] && [ "$bytes" -gt 0 ]; then
    used_backend="$(grep -om1 'backend=[^ ]*' "$OUT/$id.err" | cut -d= -f2)"
    used_model="$(grep -om1 'model=[^ ]*' "$OUT/$id.err" | cut -d= -f2)"
    tsz_mark_done "$id" "$secs" "${used_backend:-$BACKEND}" "${used_model:-?}"
    rm -f "$OUT/$id.err"
    echo "[$(ts)] ($i/$total) ✓ $id 完成 ${bytes}B"
    ok=$((ok+1))
  else
    tsz_mark_fail "$id" "转写退出码 $rc"
    echo "[$(ts)] ($i/$total) ✗ $id 转写失败（退出码 ${rc}），继续下一条"
    fail=$((fail+1))
  fi
  rm -rf "$AUDIO_DIR"; AUDIO_DIR=""
done
echo "[$(ts)] 全部完成：$ok 成功 $fail 失败 $skip 跳过（共 $total 条）"
