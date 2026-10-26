#!/usr/bin/env bash
# 环境诊断：各项依赖是否就绪、当前机器能用哪几层能力、缺什么怎么补。
# 用法: doctor.sh
# 只看本机状态，不联网、不加载模型，几秒内出结果。venv 不存在时退出码 1。
set -uo pipefail
SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SD/lib.sh"

ok()   { printf '  ✓ %s：%s\n' "$1" "$2"; }
warn() { printf '  ! %s：%s\n' "$1" "$2"; }
bad()  { printf '  ✗ %s：%s\n' "$1" "$2"; }
off()  { printf '  · %s：%s\n' "$1" "$2"; }
FIX=()

echo "==== Florilegium 环境诊断 ===="
echo "[运行环境]"
case "$(uname -s)" in
  Darwin|Linux) ok "系统" "$(uname -s) $(uname -m)" ;;
  *) bad "系统" "$(uname -s) 暂不支持，只支持 macOS 与 Linux"; exit 1 ;;
esac

VPY="$TSZ_VENV/bin/python"
if [ ! -x "$VPY" ]; then
  bad "独立环境" "未安装（$TSZ_VENV 不存在）"
  echo ""
  echo "  粘贴文字稿整理不需要安装，现在就能用。"
  echo "  要抓字幕或转写音频，先运行：bash $SD/setup.sh"
  exit 1
fi

# 一次 python 调用收齐版本信息，避免逐项起解释器
INFO="$("$VPY" - <<'PYEOF'
import datetime, importlib.metadata as md, platform
print("py=" + platform.python_version())
try:
    v = md.version("yt-dlp")
    y, m, d = (int(x) for x in v.split(".")[:3])
    print("ytdlp=" + v)
    print("ytdlp_age=%d" % (datetime.date.today() - datetime.date(y, m, d)).days)
except Exception:
    print("ytdlp=")
PYEOF
)"
get() { printf '%s\n' "$INFO" | sed -n "s/^$1=//p"; }
ok "独立环境" "${TSZ_VENV}（Python $(get py)）"

YTDLP_OK=0
if [ -n "$(get ytdlp)" ]; then
  YTDLP_OK=1
  age="$(get ytdlp_age)"
  if [ "${age:-0}" -gt 60 ]; then
    warn "yt-dlp" "$(get ytdlp)（$age 天前发布，视频站改版后旧版会失效）"
    FIX+=("升级 yt-dlp：bash $SD/setup.sh --upgrade")
  else
    ok "yt-dlp" "$(get ytdlp)"
  fi
else
  bad "yt-dlp" "未安装"
  FIX+=("重跑 bash $SD/setup.sh")
fi

DENO_OK=0
if d="$(tsz_deno)"; then DENO_OK=1; ok "deno" "$d"
else warn "deno" "未找到，影响 YouTube"; FIX+=("重跑 bash $SD/setup.sh 安装 deno"); fi

BGUTIL_OK=0
if [ -f "$TSZ_HOME/bgutil/server/build/main.js" ] && command -v node >/dev/null 2>&1; then
  BGUTIL_OK=1; ok "bgutil（可选）" "已构建"
else
  off "bgutil（可选）" "未启用，只用于 YouTube 锁死视频：bash $SD/setup.sh --with-bgutil（需要 Node.js）"
fi

echo "[转写]"
CHECK="$("$VPY" "$SD/transcribe.py" --check 2>/dev/null)"
cget() { printf '%s\n' "$CHECK" | sed -n "s/^$1=//p"; }
BACKEND="$(cget backend)"; MODEL="$(cget model)"
ASR_OK=0
case "$BACKEND" in
  mlx-gpu) ASR_OK=1; ok "后端" "mlx-gpu（Apple Silicon GPU，实测约 5.6 倍速）" ;;
  faster-cpu)
    if [ "$(cget faster_whisper)" = 1 ]; then
      ASR_OK=1; ok "后端" "faster-whisper CPU（small 模型；M1 Pro 的 CPU 实测约 1.2 倍速，其他机器未实测）"
    else
      bad "后端" "faster-whisper 未安装"; FIX+=("重跑 bash $SD/setup.sh")
    fi ;;
  *) bad "后端" "transcribe.py --check 运行失败"; FIX+=("重跑 bash $SD/setup.sh") ;;
esac
if [ "$(cget cached)" = 1 ]; then
  ok "模型" "$MODEL 已缓存"
elif [ -n "$MODEL" ]; then
  warn "模型" "$MODEL 未缓存，首次转写时下载（huggingface.co 不通会自动走 hf-mirror.com）"
fi

echo "[登录态]"
if [ -n "${TSZ_COOKIES:-}" ]; then
  if [ -f "$TSZ_COOKIES" ]; then ok "cookie 文件" "$TSZ_COOKIES"
  else bad "cookie 文件" "TSZ_COOKIES 指向的 $TSZ_COOKIES 不存在"; fi
elif [ -n "${TSZ_BROWSER:-}" ]; then
  ok "浏览器" "${TSZ_BROWSER}（TSZ_BROWSER 指定）"
elif b="$(tsz_detect_browser)"; then
  ok "浏览器" "${b}（先匿名抓取，需要登录时才读它的 cookie）"
else
  off "浏览器" "没找到可读 cookie 的浏览器：需要登录的视频（B 站 AI 字幕等）可能抓不到"
fi

echo "[文章输出目录]"
if d="$(tsz_article_dir)"; then ok "目录" "$d"
else warn "目录" "未设置，首次剪藏时 agent 会问你（或 bash $SD/article-dir.sh set <目录>）"; fi

echo "[能力层级]"
ok "粘贴文字稿整理" "可用，不需要任何依赖"
if [ "$YTDLP_OK" -eq 1 ]; then ok "抓字幕" "可用（B 站、YouTube 等有字幕的视频）"
else bad "抓字幕" "不可用，缺 yt-dlp"; fi
if [ "$YTDLP_OK" -eq 1 ] && [ "$ASR_OK" -eq 1 ]; then ok "无字幕音频转写" "可用（本地转写）"
else bad "无字幕音频转写" "不可用"; fi
if [ "$YTDLP_OK" -eq 1 ] && [ "$DENO_OK" -eq 1 ]; then ok "YouTube" "可用"
else warn "YouTube" "受限，缺 deno"; fi
if [ "$BGUTIL_OK" -eq 1 ]; then ok "YouTube 锁死视频" "可用"
else off "YouTube 锁死视频" "未启用（可选）"; fi

echo "=============================="
if [ "$YTDLP_OK" -eq 1 ] && [ "$ASR_OK" -eq 1 ]; then
  echo "结论：本地核心能力完整可用"
elif [ "$YTDLP_OK" -eq 1 ]; then
  echo "结论：能抓字幕，无字幕视频暂时转写不了"
else
  echo "结论：目前只能整理粘贴的文字稿"
fi
if [ "${#FIX[@]}" -gt 0 ]; then
  echo "建议："
  printf '%s\n' "${FIX[@]}" | awk '!seen[$0]++' | sed 's/^/  - /'
fi
exit 0
