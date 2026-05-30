[English](./README_EN.md)

# Florilegium · 他山之石

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Shell](https://img.shields.io/badge/shell-bash-green.svg)
![Python](https://img.shields.io/badge/python-3.10%2B-blue.svg)
![Claude Code](https://img.shields.io/badge/Claude%20Code-skill-8A63D2.svg)

一个 Claude Code skill：给它一个 YouTube / 视频链接（或一段文字稿），它自动把内容**转写、整理成一篇可读文章**，写进你的 Obsidian 知识库的「他山之石」目录，专门用来沉淀他人观点。全程免费、本地运行。

「他山之石，可以攻玉」——收别人的见解，为我所用。Florilegium 是中世纪学者对「采撷众家精华、汇成一编」的称呼，正好对应这个意思。skill 的内部名仍是 `tashanzhishi`。

## 它解决什么

刷到一个好视频，想存下作者的观点，手动记又麻烦。这个 skill 让流程变成一句话：

> 用 tashanzhishi 把这个链接剪藏了：`<youtube 链接>`

然后它就：抓字幕 → 清洗 → 写成一篇中立、可直接阅读的文章 → 落到你 Obsidian 库的「他山之石」目录。

## 特点

- **可读文章，不是观点汇总**：产出像一篇杂志短文，不是 `1. 作者认为…` 的清单。
- **忠实 + 标注立场**：事实和推测分开，作者的带货 / 立场会被点出来。
- **三级取文**：
  1. 有可下载字幕 → yt-dlp 直接抓（最快）。
  2. 没字幕但音频可取 → 本地 `faster-whisper` 转写。
  3. YouTube 反爬锁死（SABR / PO-token）→ 自带 `bgutil` PO-token 提供器解锁音频，再转写。
- **全免费、纯本地**：除了从 YouTube 取数据，没有任何内容离开你的机器，无需任何付费 API。
- **和 Obsidian 打通**：输出目录就是你的 vault 文件夹。

## 安装

```bash
# 1) 放到 Claude Code 的 skills 目录
git clone https://github.com/anneheartrecord/florilegium.git ~/.claude/skills/tashanzhishi

# 2) 装依赖（新版 yt-dlp + faster-whisper + bgutil 提供器）
bash ~/.claude/skills/tashanzhishi/setup.sh
```

依赖：Python 3.10+、Node.js（构建 bgutil 提供器）、deno（yt-dlp 解 YouTube n-challenge 的 JS 运行时，setup.sh 会自动装）。setup.sh 会建一个独立 venv，不污染系统环境。字幕下载用浏览器登录态，需在 Chrome 登录过 YouTube。

## 用法

在 Claude Code 里直接说：

```
用 tashanzhishi 把这个链接剪藏了：https://www.youtube.com/watch?v=XXXX
```

或者把一段文字稿粘进来让它整理。输出落到 `你的vault/20-knowledge/他山之石/`（目录可改）。

## 目录结构

| 文件 | 作用 |
|------|------|
| `SKILL.md` | skill 主文件，定义流程和文档模板 |
| `fetch-transcript.sh` | 用 yt-dlp 抓字幕 + 元数据 |
| `vtt2text.py` | 把 .vtt 字幕清洗成纯文本 |
| `fetch-audio.sh` | 锁死视频的音频下载（走 bgutil 解锁） |
| `transcribe.py` | 用 faster-whisper 把音频转文字 |
| `setup.sh` | 一次性安装全部依赖 |

## 致谢

- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [faster-whisper](https://github.com/SYSTRAN/faster-whisper)
- [bgutil-ytdlp-pot-provider](https://github.com/Brainicism/bgutil-ytdlp-pot-provider)

## License

MIT
