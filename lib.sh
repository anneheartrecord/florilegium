#!/usr/bin/env bash
# tashanzhishi 批量脚本共用函数。被 batch.sh / status.sh source，不要直接执行。

# 产物目录，可用环境变量 TSZ_OUT 覆盖
tsz_out_dir() { echo "${TSZ_OUT:-$HOME/.local/share/tashanzhishi/out}"; }

# venv python（setup.sh 装的；没有就退回 python3）
tsz_py() {
  local p="$HOME/.local/share/tashanzhishi/venv/bin/python"
  [ -x "$p" ] && echo "$p" || echo python3
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
