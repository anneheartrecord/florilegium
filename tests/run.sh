#!/usr/bin/env bash
# 不联网的行为测试：每个用例在独立的临时 HOME 里跑，只看退出码、输出与落盘结果。
# 用法: bash tests/run.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check() { # <描述> <命令...>
  local name="$1"; shift
  if "$@"; then pass=$((pass + 1)); echo "  ✓ $name"
  else fail=$((fail + 1)); echo "  ✗ $name"; fi
}
fresh_home() { local h; h="$(mktemp -d "$TMP/home.XXXX")"; echo "$h"; }

echo "[setup.sh]"
# 假的 3.9 解释器盖住所有候选名，模拟只有旧 Python、也没有 uv 的机器
FAKE="$TMP/fakebin"; mkdir -p "$FAKE"
for n in python3 python3.10 python3.11 python3.12 python3.13 python3.14; do
  printf '#!/bin/sh\ncase "$2" in *version_info*) exit 1 ;; *) echo 3.9.0 ;; esac\n' > "$FAKE/$n"
  chmod +x "$FAKE/$n"
done
H="$(fresh_home)"
out="$(env -i HOME="$H" PATH="$FAKE:/usr/bin:/bin" bash "$ROOT/setup.sh" --yes 2>&1)"; rc=$?
check "Python 低于 3.10 时退出码非 0" [ "$rc" -ne 0 ]
check "报错里带检测到的版本号" grep -q "python3=3.9.0" <<<"$out"
check "失败后不留下安装目录" [ ! -e "$H/.local/share/tashanzhishi" ]
out="$(env -i HOME="$H" PATH="/usr/bin:/bin" bash "$ROOT/setup.sh" --bogus 2>&1)"; rc=$?
check "未知参数直接报错" [ "$rc" -ne 0 ]

echo "[article-dir.sh]"
H="$(fresh_home)"
ad() { env -i HOME="$H" PATH="/usr/bin:/bin" ${TSZ_ARTICLE_DIR:+TSZ_ARTICLE_DIR="$TSZ_ARTICLE_DIR"} bash "$ROOT/article-dir.sh" "$@"; }
ad get >/dev/null 2>&1; rc=$?
check "未设置时 get 退出码为 3" [ "$rc" -eq 3 ]
mkdir -p "$H/Documents/Vault/.obsidian"
check "suggest 优先推荐 Obsidian 库" [ "$(ad suggest | head -1)" = "$H/Documents/Vault/他山之石" ]
ad set "~/Notes/剪藏" >/dev/null
check "set 展开 ~ 并建好目录" [ -d "$H/Notes/剪藏" ]
check "get 读回保存的目录" [ "$(ad get)" = "$H/Notes/剪藏" ]
ad set "$H/Other" >/dev/null
check "再次 set 覆盖旧值" [ "$(ad get)" = "$H/Other" ]
check "配置里只保留一条" [ "$(grep -c '^article_dir=' "$H/.config/tashanzhishi/config")" -eq 1 ]
check "环境变量优先于配置" [ "$(TSZ_ARTICLE_DIR="$TMP/env-dir" ad get)" = "$TMP/env-dir" ]

echo "[fetch 脚本]"
H="$(fresh_home)"
out="$(env -i HOME="$H" PATH="/usr/bin:/bin" bash "$ROOT/fetch-transcript.sh" "https://example.com/v" 2>&1)"; rc=$?
if ! env -i PATH="/usr/bin:/bin" sh -c 'command -v yt-dlp' >/dev/null; then
  check "没装 yt-dlp 时提示运行 setup.sh" grep -q "setup.sh" <<<"$out"
  check "没装 yt-dlp 时退出码为 1" [ "$rc" -eq 1 ]
fi
# 假 yt-dlp 什么也不下载，让脚本走到登录态检查
YT="$TMP/ytbin"; mkdir -p "$YT"; printf '#!/bin/sh\nexit 0\n' > "$YT/yt-dlp"; chmod +x "$YT/yt-dlp"
out="$(env -i HOME="$H" PATH="$YT:/usr/bin:/bin" TSZ_COOKIES="$TMP/nope.txt" bash "$ROOT/fetch-audio.sh" "https://example.com/v" 2>&1)"; rc=$?
check "TSZ_COOKIES 指向不存在的文件时报错退出" [ "$rc" -ne 0 ]
check "报错点名 TSZ_COOKIES" grep -q "TSZ_COOKIES" <<<"$out"
out="$(env -i HOME="$H" PATH="$YT:/usr/bin:/bin" bash "$ROOT/fetch-transcript.sh" "https://example.com/v" 2>&1)"; rc=$?
check "没抓到字幕时退出码为 2" [ "$rc" -eq 2 ]
out="$(env -i HOME="$H" PATH="$YT:/usr/bin:/bin" bash "$ROOT/fetch-audio.sh" "https://example.com/v" 2>&1)"; rc=$?
check "音频下载失败时退出码为 2 并给出排查建议" [ "$rc" -eq 2 ]
check "排查建议里有 --upgrade" grep -q -- "--upgrade" <<<"$out"

# 模拟用过 Chrome 的机器：两种系统的浏览器数据目录都建上
H="$(fresh_home)"
mkdir -p "$H/Library/Application Support/Google/Chrome" "$H/.config/google-chrome"
touch "$TMP/yt-cookies.txt"
out="$(env -i HOME="$H" PATH="$YT:/usr/bin:/bin" TSZ_COOKIES="$TMP/yt-cookies.txt" bash "$ROOT/fetch-transcript.sh" "https://example.com/v" 2>&1)"
check "cookie 文件没拿到字幕时回退浏览器" grep -q "用 cookie 文件没拿到字幕，改用 chrome" <<<"$out"
out="$(env -i HOME="$H" PATH="$YT:/usr/bin:/bin" bash "$ROOT/fetch-audio.sh" "https://example.com/v" 2>&1)"
check "匿名下载失败时回退浏览器" grep -q "匿名下载失败，改用 chrome" <<<"$out"
out="$(env -i HOME="$H" PATH="$YT:/usr/bin:/bin" TSZ_BROWSER=firefox bash "$ROOT/fetch-transcript.sh" "https://example.com/v" 2>&1)"
check "指定了浏览器就不再回退" [ "$(grep -c "改用" <<<"$out")" -eq 0 ]

echo "[vtt2text.py]"
printf '1\n00:00:01,000 --> 00:00:02,000\n第一句\n\n2\n00:00:02,000 --> 00:00:03,000\n第二句\n' > "$TMP/a.srt"
check "srt 去掉编号和时间轴" [ "$(python3 "$ROOT/vtt2text.py" "$TMP/a.srt")" = "$(printf '第一句\n第二句')" ]
printf 'WEBVTT\n\n00:00:01.000 --> 00:00:02.000\n<c>hello</c> &amp; hi\n' > "$TMP/a.vtt"
check "vtt 去掉标签并解码实体" [ "$(python3 "$ROOT/vtt2text.py" "$TMP/a.vtt")" = "hello & hi" ]

echo "[lib.sh]"
source "$ROOT/lib.sh"
check "B 站链接取 BV 号" [ "$(tsz_id_from_url 'https://www.bilibili.com/video/BV1GJ411x7h7/?p=1')" = BV1GJ411x7h7 ]
check "YouTube 链接取视频 ID" [ "$(tsz_id_from_url 'https://www.youtube.com/watch?v=jNQXAC9IVRw&t=3')" = jNQXAC9IVRw ]
check "youtu.be 短链取视频 ID" [ "$(tsz_id_from_url 'https://youtu.be/jNQXAC9IVRw?si=x')" = jNQXAC9IVRw ]
bad_id="$(tsz_id_from_url 'https:')"
check "取不到合法 ID 时退回 12 位哈希" [ "${#bad_id}" -eq 12 ]

echo ""
echo "通过 ${pass}，失败 ${fail}"
[ "$fail" -eq 0 ]
