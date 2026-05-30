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
echo "→ 安装 yt-dlp / faster-whisper / bgutil 插件"
"$HOME_DIR/venv/bin/pip" install -q -U yt-dlp faster-whisper bgutil-ytdlp-pot-provider

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
echo "  provider:   node $HOME_DIR/bgutil/server/build/main.js  (fetch-audio.sh 会按需自动启动)"
