#!/usr/bin/env bash
# 队列状态与粗略预估。用法: status.sh
# 回答三件事：已完成几条、正在跑哪条（约百分之多少）、预计还要多久。
# 统计口径与 batch.sh 一致：完成与否只看 .status 文件，不看 .txt 大小。
set -uo pipefail
SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SD/lib.sh"
OUT="$(tsz_out_dir)"

if [ ! -d "$OUT" ]; then
  echo "还没有任何批量任务（产物目录不存在）：$OUT"
  exit 0
fi

BACKEND="$(tsz_backend)"
# 倍率=转写速度÷音频时长，2026-08-29 在 M1 Pro 实测（GPU 5.6x / CPU 1.2x），粗估不假装精确
case "$BACKEND" in mlx-gpu) RATE=5.6 ;; *) RATE=1.2 ;; esac

# ---- 已完成 / 失败 / 平均速率（从 .status 聚合）----
done_n=0; fail_n=0; sum_secs=0; sum_bytes=0; extra=0
for f in "$OUT"/*.status; do
  [ -e "$f" ] || break
  id="$(basename "$f" .status)"
  s=$(sed -n 's/^duration_sec=//p' "$f"); b=$(sed -n 's/^bytes=//p' "$f")
  sum_secs=$((sum_secs + ${s:-0})); sum_bytes=$((sum_bytes + ${b:-0}))
  if [ -f "$OUT/.queue" ] && grep -qx "$id" "$OUT/.queue"; then
    done_n=$((done_n + 1))
  else
    extra=$((extra + 1))   # 更早批次留下的历史成品
  fi
done
for f in "$OUT"/*.fail; do [ -e "$f" ] || break; fail_n=$((fail_n + 1)); done

total=$done_n
[ -f "$OUT/.queue" ] && total=$(grep -c . "$OUT/.queue")

# ---- 正在跑哪条、约百分之多少 ----
running=""; pct=""
if [ -f "$OUT/.current" ]; then
  IFS=$'\t' read -r cur_id cur_pid cur_start < "$OUT/.current"
  if kill -0 "$cur_pid" 2>/dev/null; then
    running="$cur_id"
    cur_dur=$(sed -n 's/^duration_sec=//p' "$OUT/$cur_id.meta" 2>/dev/null)
    cur_bytes=0
    [ -f "$OUT/$cur_id.txt" ] && cur_bytes=$(wc -c < "$OUT/$cur_id.txt" | tr -d ' ')
    if [ "${cur_dur:-0}" -gt 0 ] && [ "$sum_secs" -gt 0 ] && [ "$running" ]; then
      bps=$((sum_bytes / sum_secs))                    # 已完成条目的平均字节速率
      expected=$((bps * cur_dur))
      [ "$expected" -gt 0 ] && pct=$((cur_bytes * 100 / expected))
      [ "${pct:-0}" -gt 99 ] && pct=99
    fi
  else
    echo "（发现残留的 .current 记录 ${cur_id}，进程已不在——上次可能被硬杀，该条会被重跑）"
  fi
fi

# ---- 剩余音频与 ETA ----
rem_secs=0; unknown=0
if [ -f "$OUT/.queue" ]; then
  while read -r qid; do
    [ -n "$qid" ] || continue
    tsz_is_done "$qid" && continue
    m="$OUT/$qid.meta"
    if [ -f "$m" ]; then
      d=$(sed -n 's/^duration_sec=//p' "$m")
      rem_secs=$((rem_secs + ${d:-0}))
    else
      unknown=$((unknown + 1))   # 还没下载，时长未知
    fi
  done < "$OUT/.queue"
fi

# ---- 输出 ----
line="已完成 $done_n / $total"
if [ "$extra" -gt 0 ]; then line="${line}（目录另有历史 $extra 条）"; fi
if [ -n "$running" ]; then
  line="$line    进行中 ${running}（约 ${pct:-0}%）"
fi
echo "$line"

if [ "$rem_secs" -gt 0 ]; then
  eta_min=$(awk -v s="$rem_secs" -v r="$RATE" 'BEGIN{printf "%.0f", s/60/r}')
  audio_min=$(awk -v s="$rem_secs" 'BEGIN{printf "%.0f", s/60}')
  echo "剩余音频 $audio_min 分钟，按 ${RATE}x 实时估算 ≈ $eta_min 分钟"
fi
[ "$unknown" -gt 0 ] && echo "（另有 $unknown 条尚未下载，时长未知，未计入估算）"
echo "失败 $fail_n"

if [ -n "$running" ]; then
  echo "后端 ${BACKEND}，倍率 ${RATE}x 为 2026-08-29 M1 Pro 实测，粗估用"
else
  echo "队列未在运行——以上是最近一次的结果"
fi
