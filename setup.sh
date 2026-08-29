#!/usr/bin/env bash
# tashanzhishi 依赖一次性安装：新版 yt-dlp + faster-whisper + bgutil PO-token 提供器。
# 全部装进独立位置，不污染系统环境。需要 Python 3.10+ 和 Node.js。
set -euo pipefail

HOME_DIR="$HOME/.local/share/tashanzhishi"
mkdir -p "$HOME_DIR"

# 找一个 3.10+ 的 python（最新 yt-dlp 需要 >=3.10）
PY310=""
for p in python3.13 python3.12 python3.11 python3.10; do
  command -v "$p" >/dev/null 2>&1 && { PY310="$p"; break; }
done
[ -z "$PY310" ] && { echo "✗ 需要 Python 3.10+（最新 yt-dlp 依赖），请先安装"; exit 1; }
echo "→ 用 $PY310 创建 venv: $HOME_DIR/venv"
"$PY310" -m venv "$HOME_DIR/venv"
"$HOME_DIR/venv/bin/pip" install -q -U pip
echo "→ 安装 yt-dlp / faster-whisper / bgutil 插件 / yt-dlp-ejs（解 n-challenge）"
"$HOME_DIR/venv/bin/pip" install -q -U yt-dlp faster-whisper bgutil-ytdlp-pot-provider yt-dlp-ejs

# deno：yt-dlp 解 YouTube n-challenge 的默认 JS 运行时（node 26 的权限模型会拦截 EJS）
if ! command -v deno >/dev/null 2>&1 && [ ! -x "$HOME/.deno/bin/deno" ]; then
  echo "→ 安装 deno"
  curl -fsSL https://deno.land/install.sh | sh
fi

# Apple Silicon：转写走 mlx（GPU）。CTranslate2 在 macOS 只支持 CPU，GPU 加速只有这条路；
# 实测同一条 13 分钟音频 CPU 10-16 分钟、GPU 2 分 20 秒。其他平台跳过，自动回退 CPU。
if [ "$(uname)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ]; then
  echo "→ Apple Silicon：安装 mlx-whisper（转写走 GPU）"
  "$HOME_DIR/venv/bin/pip" install -q -U mlx-whisper
  # 预热：把默认模型拉进 HF 缓存（约 1.5GB，一次性），并用 1 秒静音做端到端自检
  echo "→ 预热 whisper-large-v3-turbo 模型缓存（首次约 1.5GB 下载，之后走缓存）"
  "$HOME_DIR/venv/bin/python" - <<'PYEOF'
import numpy as np, os, tempfile, wave
import mlx_whisper
p = os.path.join(tempfile.gettempdir(), "tashan-warmup.wav")
w = wave.open(p, "w"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
w.writeframes(np.zeros(16000, dtype=np.int16).tobytes())
w.close()
mlx_whisper.transcribe(p, path_or_hf_repo="mlx-community/whisper-large-v3-turbo")
os.remove(p)
print("✓ mlx GPU 后端自检通过")
PYEOF
fi

# 构建 bgutil POT 提供器（解锁被 SABR / PO-token 锁死的视频；不需要 Chromium）
command -v node >/dev/null 2>&1 || { echo "✗ 需要 Node.js 来运行 bgutil 提供器"; exit 1; }
if [ ! -d "$HOME_DIR/bgutil" ]; then
  echo "→ 克隆 bgutil 提供器"
  git clone --depth 1 https://github.com/Brainicism/bgutil-ytdlp-pot-provider.git "$HOME_DIR/bgutil"
fi
echo "→ 构建 bgutil 提供器"
( cd "$HOME_DIR/bgutil/server" && npm ci && npx tsc )

echo ""
echo "✓ 安装完成。"
echo "  venv:       $HOME_DIR/venv"
echo "  转写后端:   Apple Silicon 上 mlx-gpu（whisper-large-v3-turbo 已预热）；其他平台 faster-whisper CPU"
echo "  provider:   node $HOME_DIR/bgutil/server/build/main.js  (fetch-audio.sh 会按需自动启动)"
