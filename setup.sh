#!/usr/bin/env bash
# tashanzhishi 依赖安装。全部装进 ~/.local/share/tashanzhishi，不碰系统环境，卸载删掉这个目录即可。
# 支持 macOS 与 Linux，Windows 暂不支持。
#
# 用法: setup.sh [--skip-model] [--with-bgutil] [--upgrade] [--yes]
#   --skip-model   不预下载转写模型，首次转写时再下
#   --with-bgutil  额外构建 bgutil PO-token 提供器，解锁 YouTube 锁死视频（需要 Node.js）
#   --upgrade      只升级 yt-dlp：视频站改版导致抓不到时用
#   --yes          不提问；文章输出目录留到首次剪藏时由 agent 询问
#
# 必需的只有 Python 3.10+（或 uv）。其余缺了都只降级对应能力，不中断安装。
set -euo pipefail
SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SD/lib.sh"

SKIP_MODEL=0; WITH_BGUTIL=0; UPGRADE=0; ASSUME_YES=0
for a in "$@"; do
  case "$a" in
    --skip-model)  SKIP_MODEL=1 ;;
    --with-bgutil) WITH_BGUTIL=1 ;;
    --upgrade)     UPGRADE=1 ;;
    --yes|-y)      ASSUME_YES=1 ;;
    -h|--help)     sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "✗ 未知参数: ${a}（--help 查看用法）" >&2; exit 1 ;;
  esac
done

ok()   { echo "✓ $*"; }
step() { echo "→ $*"; }
warn() { echo "! $*"; }
die()  { echo "✗ $*" >&2; exit 1; }

case "$(uname -s)" in
  Darwin|Linux) ;;
  *) die "暂不支持 $(uname -s)，目前只支持 macOS 与 Linux" ;;
esac

# ---- 网络：PyPI 连不上时改用国内镜像（用户自己设了 PIP_INDEX_URL 就不动）----
PYPI_MIRROR="https://pypi.tuna.tsinghua.edu.cn/simple"
NPM_MIRROR="https://registry.npmmirror.com"
CN_NET=0
if [ -z "${PIP_INDEX_URL:-}" ] && ! curl -s -m 3 -o /dev/null https://pypi.org/simple/pip/; then
  if curl -s -m 3 -o /dev/null "$PYPI_MIRROR/pip/"; then
    export PIP_INDEX_URL="$PYPI_MIRROR" UV_INDEX_URL="$PYPI_MIRROR"
    CN_NET=1
    step "pypi.org 连不上，改用镜像 $PYPI_MIRROR"
  else
    warn "pypi.org 和国内镜像都连不上，下面的安装可能失败"
  fi
fi

pip_install() { "$TSZ_VENV/bin/python" -m pip install -q -U "$@"; }

if [ "$UPGRADE" -eq 1 ]; then
  [ -x "$TSZ_VENV/bin/python" ] || die "还没安装过，先不带参数运行 setup.sh"
  step "升级 yt-dlp"
  pip_install "yt-dlp[default,curl-cffi]"
  ok "yt-dlp $("$TSZ_VENV/bin/python" -m yt_dlp --version)"
  exit 0
fi

# ---- 1. 解释器与独立 venv ----
py_ok()  { "$1" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' >/dev/null 2>&1; }
py_ver() { "$1" -c 'import platform; print(platform.python_version())' 2>/dev/null; }

step "检查 Python（需要 3.10+）"
if [ -x "$TSZ_VENV/bin/python" ] && py_ok "$TSZ_VENV/bin/python" \
   && "$TSZ_VENV/bin/python" -m pip --version >/dev/null 2>&1; then
  ok "复用已有独立环境：${TSZ_VENV}（Python $(py_ver "$TSZ_VENV/bin/python")）"
else
  PY=""; seen=""
  # 先看默认的 python3，再找带版本号的命令：只装了 python3 也能识别
  for p in python3 python3.13 python3.12 python3.11 python3.10 python3.14; do
    command -v "$p" >/dev/null 2>&1 || continue
    v="$(py_ver "$p")"; seen="$seen $p=$v"
    py_ok "$p" && { PY="$p"; break; }
  done

  seen="${seen# }"
  rm -rf "$TSZ_VENV"
  if [ -n "$PY" ]; then
    mkdir -p "$TSZ_HOME"
    ok "找到 ${PY}（Python $(py_ver "$PY")）"
    if ! "$PY" -m venv "$TSZ_VENV" 2>/dev/null; then
      rm -rf "$TSZ_VENV"
      if command -v uv >/dev/null 2>&1; then
        step "$PY 建不了 venv，改用 uv"
        uv venv -q --seed --python "$PY" "$TSZ_VENV"
      else
        rmdir "$TSZ_HOME" 2>/dev/null || true
        mm="$("$PY" -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")')"
        die "$PY 缺少 venv 模块。Debian/Ubuntu 上运行：sudo apt install python${mm}-venv，然后重跑 setup.sh"
      fi
    fi
  elif command -v uv >/dev/null 2>&1; then
    step "系统里没有 3.10+ 的 Python（${seen:-未找到 python3}），用 uv 下载 Python 3.12"
    mkdir -p "$TSZ_HOME"
    uv venv -q --seed --python 3.12 "$TSZ_VENV"
  else
    die "需要 Python 3.10+，当前检测到：${seen:-没有 python3}。
  安装 Python 3.10+，或安装 uv（https://docs.astral.sh/uv/ ，它会自动下载合适的 Python）后重跑"
  fi
  ok "独立环境已建好：${TSZ_VENV}（Python $(py_ver "$TSZ_VENV/bin/python")）"
fi

# ---- 2. 核心依赖 ----
step "安装核心依赖：yt-dlp、faster-whisper、deno（YouTube 解 n-challenge 用）"
pip_install pip
pip_install "yt-dlp[default,curl-cffi]" faster-whisper bgutil-ytdlp-pot-provider
ok "核心组件安装完成"
# deno 走 PyPI 装进 venv，不用 curl | sh，也能吃到上面的 PyPI 镜像
if pip_install deno 2>/dev/null && [ -x "$TSZ_VENV/bin/deno" ]; then
  ok "deno 已就绪"
elif tsz_deno >/dev/null; then
  ok "deno 已就绪（使用系统里的 $(tsz_deno)）"
else
  warn "deno 没装上：只影响 YouTube，B 站、播客与本地音频不受影响"
fi

if [ "$(uname)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ]; then
  # CTranslate2 在 macOS 只支持 CPU，Apple Silicon 的 GPU 加速只有 mlx 这条路。
  # 实测同一条 13 分钟音频：CPU 10-16 分钟，GPU 2 分 20 秒。
  step "Apple Silicon：安装 mlx-whisper（转写走 GPU）"
  if pip_install mlx-whisper; then
    ok "mlx-whisper 安装完成"
  else
    warn "mlx-whisper 没装上，转写会回退 CPU（慢约 5 倍）"
  fi
fi

# ---- 3. 可选：bgutil 提供器 ----
if [ "$WITH_BGUTIL" -eq 1 ]; then
  if ! command -v node >/dev/null 2>&1; then
    warn "没有 Node.js，跳过 bgutil。装好 Node.js 后重跑 setup.sh --with-bgutil"
  else
    [ "$CN_NET" -eq 1 ] && export npm_config_registry="$NPM_MIRROR"
    if { [ -d "$TSZ_HOME/bgutil" ] || git clone -q --depth 1 \
           https://github.com/Brainicism/bgutil-ytdlp-pot-provider.git "$TSZ_HOME/bgutil"; } \
       && ( cd "$TSZ_HOME/bgutil/server" && npm ci --silent && npx tsc ); then
      ok "bgutil 提供器已构建（fetch-audio.sh 遇到 YouTube 时按需启动）"
    else
      warn "bgutil 构建失败，只影响 YouTube 锁死视频"
    fi
  fi
elif [ -f "$TSZ_HOME/bgutil/server/build/main.js" ]; then
  ok "bgutil 提供器已存在，继续沿用"
fi

# ---- 4. 文章输出目录 ----
if d="$(tsz_article_dir)"; then
  ok "文章输出目录：$d"
elif [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; then
  echo ""
  echo "整理好的文章存到哪个目录？"
  CANDS=(); while IFS= read -r l; do CANDS+=("$l"); done < <(tsz_suggest_article_dirs)
  for i in "${!CANDS[@]}"; do echo "  $((i + 1))) ${CANDS[$i]}"; done
  printf "输入编号或完整路径，直接回车选 1："
  read -r ans || ans=""
  case "$ans" in
    "") choice="${CANDS[0]}" ;;
    *[!0-9]*) choice="$ans" ;;
    *) [ "$ans" -ge 1 ] && [ "$ans" -le "${#CANDS[@]}" ] && choice="${CANDS[$((ans - 1))]}" || choice="$ans" ;;
  esac
  ok "文章输出目录：$(tsz_set_article_dir "$choice")（以后可用 article-dir.sh set 修改）"
else
  warn "文章输出目录未设置：首次剪藏时 agent 会问你，也可以运行 bash $SD/article-dir.sh set <目录>"
fi

# ---- 5. 预热转写模型 ----
if [ "$SKIP_MODEL" -eq 1 ]; then
  warn "已跳过模型下载：首次转写时自动下载"
else
  step "预下载转写模型并自检（首次下载 Apple Silicon 约 1.5GB，其他平台约 500MB）"
  if ! "$TSZ_VENV/bin/python" "$SD/transcribe.py" --warmup; then
    warn "模型预热没成功，安装本身不受影响：首次转写时会再下载"
  fi
fi

echo ""
ok "安装完成。运行 bash $SD/doctor.sh 查看各项能力是否就绪"
