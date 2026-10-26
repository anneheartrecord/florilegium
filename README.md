[English](./README_EN.md)

# Florilegium · 他山之石

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Shell](https://img.shields.io/badge/shell-bash-green.svg)
![Python](https://img.shields.io/badge/python-3.10%2B-blue.svg)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg)
![Agent Workflow](https://img.shields.io/badge/agent-workflow-8A63D2.svg)

一个运行时无关的本地 agent workflow：给它一个 YouTube、B 站、播客或其他视频链接，也可以直接给文字稿，它会抓字幕或在本机转写音频，再把内容整理成一篇**可直接阅读的中文文章**，存进你指定的目录（比如 Obsidian 知识库），专门用来沉淀他人观点。

「他山之石，可以攻玉」——收别人的见解，为我所用。Florilegium 是中世纪学者对「采撷众家精华、汇成一编」的称呼，正好对应这个意思。workflow 的内部名仍是 `tashanzhishi`。

它不是 Claude Code、Codex 或任何单一 agent 的专属扩展。适配条件只有两个：agent 能读取一份 Markdown 指令文件，并且能调用本仓库的 shell / Python 脚本。

## 三种用法，按需安装

| 层级 | 你给它什么 | 需要安装什么 |
|------|-----------|-------------|
| 1. 整理文字稿 | 粘贴文字稿、字幕或文章 | 什么都不用装，clone 下来让 agent 读 `SKILL.md` 就行 |
| 2. 抓字幕 | 有字幕的视频链接（B 站、YouTube 等） | 跑一次 `setup.sh` |
| 3. 本地转写 | 没有字幕的视频、播客 | 同上；首次转写会下载语音模型 |

**最快上手：** 不装任何东西，直接对 agent 说：

```
用 tashanzhishi 把下面这段文字稿整理成他山之石文章：<粘贴文字稿>
```

第一次写文件时，agent 会问你文章存到哪个目录，选一次就记住。

## 安装

```bash
git clone https://github.com/anneheartrecord/florilegium.git ~/.local/share/florilegium
bash ~/.local/share/florilegium/setup.sh
bash ~/.local/share/florilegium/doctor.sh   # 查看哪些能力已就绪
```

然后让你的 agent 读取 `~/.local/share/florilegium/SKILL.md`。也可以直接 clone 到 agent 的 skills 目录，例如 `~/.claude/skills/tashanzhishi` 或 `~/.codex/skills/tashanzhishi`。

**唯一必需的依赖是 Python 3.10+。** 没有的话装一个 [uv](https://docs.astral.sh/uv/)，setup.sh 会用它自动下载合适的 Python。其余依赖全部装进 `~/.local/share/tashanzhishi` 下的独立 venv，不碰系统环境，卸载删掉这个目录即可。

setup.sh 会做这些事，任何一步失败都只降级对应能力，不会中断安装：

- 找一个 3.10+ 的 Python 建独立 venv；
- 安装 yt-dlp、faster-whisper，以及 YouTube 需要的 deno（走 PyPI 安装）；Apple Silicon 再装 mlx-whisper，转写走 GPU；
- 连不上 pypi.org 时自动改用清华镜像；
- 问你文章存到哪个目录，会优先推荐本机找到的 Obsidian 库；
- 预下载转写模型并自检：Apple Silicon 约 1.5GB，其他平台约 500MB。huggingface.co 连不上时自动改走 hf-mirror.com。

可选参数：

| 参数 | 作用 |
|------|------|
| `--skip-model` | 不预下载模型，第一次转写时再下 |
| `--with-bgutil` | 构建 bgutil PO-token 提供器，解锁少数被锁死的 YouTube 视频（需要 Node.js） |
| `--upgrade` | 只升级 yt-dlp，视频站改版导致抓不到时用 |
| `--yes` | 不提问，输出目录留到第一次剪藏时再定 |

支持 macOS 与 Linux，Windows 暂不支持。

## 转写速度

| 机器 | 后端 | 默认模型 | 速度 |
|------|------|---------|------|
| Apple Silicon | mlx-whisper（GPU） | large-v3-turbo | 约 5.6 倍实时：13 分钟音频约 2 分 20 秒 |
| 其他机器 | faster-whisper（CPU） | small | M1 Pro 的 CPU 实测约 1.2 倍实时；x86 机器没有实测，通常更慢 |

速度数据是 2026-08-29 在 M1 Pro 上的实测值，只做粗估。CPU 默认用 small 模型，专有名词错误率会明显高于 GPU 的大模型。

## 登录态

抓取时先匿名请求，拿不到再自动找本机用过的浏览器（Chrome、Firefox、Brave、Edge、Chromium），读它的 cookie 重试：

- **B 站字幕必须登录才给**，所以最好在浏览器里登录过 B 站；
- macOS 上读 Chrome 的 cookie 会弹钥匙串授权，点允许即可；
- 想固定用某个浏览器，设 `TSZ_BROWSER=firefox`；想用导出的 cookie 文件，设 `TSZ_COOKIES=/path/to/cookies.txt`。

## 特点

- **可读文章，不是观点汇总**：产出像一篇杂志短文，不是 `1. 作者认为…` 的清单。
- **忠实并标注立场**：事实和推测分开写，作者的带货或立场会被点出来。
- **作者前置命名**：确定是具体个人时，文件名用 `作者名——主题标题.md`。
- **转写在本机完成**：语音转文字不调用任何云端接口，也不需要付费 API。写文章这一步由你所用的 agent 完成，文字稿会发给它背后的模型，这一点取决于你用的 agent。
- **可选的主题合流**：环境里装有 `topic-hub` skill 时，文章落盘后会自动合流进对应的主题知识卡；没有装就跳过。
- **只输出中文**：无论来源是什么语言，文章都用中文写。

## 常见问题

| 现象 | 处理 |
|------|------|
| 提示找不到 yt-dlp 或 venv | 运行 `setup.sh` |
| 以前能抓、突然抓不到 | 视频站改版了，运行 `setup.sh --upgrade` |
| B 站提示字幕需要登录 | 在浏览器里登录 B 站后重试 |
| YouTube 要求登录或确认不是机器人 | 用登录过 YouTube 的浏览器，或设 `TSZ_COOKIES` |
| YouTube 个别视频音频始终下不来 | `setup.sh --with-bgutil`（需要 Node.js） |
| 想换文章存放目录 | `bash article-dir.sh set <目录>` |
| 不确定哪里出了问题 | 运行 `doctor.sh`，它会指出没就绪的项和修复命令 |

## 手动跑脚本

```bash
# 1) 优先抓字幕；退出码 2 表示没有字幕
DIR=$(bash ./fetch-transcript.sh "<视频链接>")
python3 ./vtt2text.py "$DIR"/sub.<语言>.vtt > /tmp/transcript.txt

# 2) 没字幕时下载音频，再本地转写（模型留空按后端自动选，中文传 zh）
AUDIO=$(bash ./fetch-audio.sh "<视频链接>")
~/.local/share/tashanzhishi/venv/bin/python ./transcribe.py "$AUDIO" "" zh > /tmp/transcript.txt

# 3) 一批链接用队列，可中断、可续跑
bash ./batch.sh "<链接1>" "<链接2>"
bash ./status.sh
```

## 目录结构

| 文件 | 作用 |
|------|------|
| `SKILL.md` | agent 指令主文件，定义流程和文档模板 |
| `setup.sh` | 一次性安装依赖 |
| `doctor.sh` | 环境诊断：依赖、能力层级、修复建议 |
| `article-dir.sh` | 读写文章输出目录 |
| `fetch-transcript.sh` | 抓字幕与元数据 |
| `vtt2text.py` | 把 vtt / srt 字幕清洗成纯文本 |
| `fetch-audio.sh` | 下载音频，YouTube 锁死视频可选走 bgutil |
| `transcribe.py` | 本地转写，自动选 GPU 或 CPU 后端 |
| `batch.sh` / `status.sh` | 批量转写队列与进度查看 |
| `lib.sh` | 脚本共用函数 |

## 致谢

- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [faster-whisper](https://github.com/SYSTRAN/faster-whisper)
- [mlx-whisper](https://github.com/ml-explore/mlx-examples/tree/main/whisper)
- [bgutil-ytdlp-pot-provider](https://github.com/Brainicism/bgutil-ytdlp-pot-provider)

## License

MIT
