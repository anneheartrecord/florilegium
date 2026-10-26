#!/usr/bin/env bash
# 文章输出目录的读写。agent 写文件前先 get；没设置时问用户，再 set。
# 用法:
#   article-dir.sh get          打印已设置的目录；没设置退出码 3
#   article-dir.sh set <目录>   建目录并保存，打印绝对路径
#   article-dir.sh suggest      每行一个候选目录（本机 Obsidian 库优先），供提问时给用户选
# 环境变量 TSZ_ARTICLE_DIR 优先于配置文件（~/.config/tashanzhishi/config）。
set -uo pipefail
SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SD/lib.sh"

case "${1:-}" in
  get)
    d="$(tsz_article_dir)" || { echo "未设置文章输出目录。请问用户存到哪里，再运行 article-dir.sh set <目录>" >&2; exit 3; }
    mkdir -p "$d" || { echo "✗ 输出目录不可写：$d" >&2; exit 4; }
    echo "$d" ;;
  set)
    [ -n "${2:-}" ] || { echo "usage: article-dir.sh set <目录>" >&2; exit 1; }
    tsz_set_article_dir "$2" ;;
  suggest)
    tsz_suggest_article_dirs ;;
  *)
    echo "usage: article-dir.sh get | set <目录> | suggest" >&2; exit 1 ;;
esac
