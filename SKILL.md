---
name: tashanzhishi
description: Use when 用户给出 YouTube/B站/播客链接，或一段视频文字稿、字幕、他人文章，要整理并剪藏成知识库 20-knowledge/他山之石 下的「他人观点」笔记。触发词：用他山之石、剪藏到他山之石、整理成他山之石文档、把这个视频/链接存档、归档他人观点。
version: 0.5.0
---

# 剪藏他人观点到「他山之石」(tashanzhishi)

## Overview

把一个视频、播客或文章的内容，整理成一篇**可以直接阅读的文章**，存进「他山之石」输出目录。

当前本机默认目录：

```text
/Users/abc/Documents/knowledge-base/20-knowledge/他山之石
```

通用安装时，把输出目录理解为：

```text
<your-vault>/20-knowledge/他山之石
```

如果用户给了明确目录，以用户目录为准；如果没有，本机使用上面的默认目录。

核心原则：产出的是给读者看的**文章**，不是观点汇总，也不是逐条「作者认为……」的清单。忠实于来源、把事实和推测分清、标注作者立场，但用流畅的文章呈现。这不是写用户自己署名的内容，所以**不套用户文风、也不跑 de-ai-flavor**。输出永远中文。

这个仓库是运行时无关的本地 agent workflow，不绑定 Claude Code、Codex 或任何单一 agent。只要当前 agent 能读取这份 Markdown 指令，并调用同目录下的 shell / Python 脚本，就可以使用这套流程；Claude Code、Codex 等目录只是安装位置示例。

## 何时用 / 不用

用：用户给链接或粘贴文字稿，说要「剪藏到他山之石」「整理成他山之石文档」「归档这个观点」。
不用：用户要写自己署名的推文/文章（那是写作任务，走文风流程）。

## 输入两种来源

1. **链接**（YouTube/B站/播客等）→ 用 yt-dlp 抓元数据 + 字幕；没有字幕时下载音频本地转写。
2. **粘贴的文字/字幕/文章** → 直接用，跳过抓取。

## 流程

### 1. 拿到原文

链接来源，运行本目录的脚本：

```bash
SKILL_DIR="<包含 SKILL.md 的 florilegium/tashanzhishi 目录>"
bash "$SKILL_DIR/fetch-transcript.sh" "<链接>"          # 默认读 Chrome 登录态
bash "$SKILL_DIR/fetch-transcript.sh" "<链接>" safari   # 换浏览器：safari/brave/edge/firefox
```

它会打印一个临时目录路径，里面有 `meta.txt`（标题 ||| 作者 ||| 上传日期 ||| 链接 ||| 时长）和一个 `.vtt` 字幕文件。YouTube / B站等平台经常需要登录态，脚本默认读 Chrome cookies，所以最好在 Chrome 里登录过对应平台。

把字幕清洗成纯文本再读：

```bash
python3 "$SKILL_DIR/vtt2text.py" "<那个目录>"/sub.*.vtt > /tmp/transcript.txt
```

`vtt2text.py` 会去掉时间轴、内联标签、HTML 实体，并合并自动字幕的滚动重复。然后用 Read 读 `meta.txt` 和 `/tmp/transcript.txt`。注意：视频结尾常有重复的「精彩片段」集锦，蒸馏时忽略那段。

### 2. 写成一篇可读文章

- 清洗自动字幕的识别错误、逐字空格、错的专有名词（公司名、人名、术语、英文缩写），但不改作者语气和立场。
- 用流畅的中文写成一篇文章，**把读者当杂志读者**：正常标点（用冒号、写完整句子），不要「短语。完整句。」这种断裂节奏，也不要「1. 作者认为 X」的清单堆叠。
- 按内容自然分几个 `##` 小标题导航；attribution 自然融进句子（他算了笔账、她的观察是、他给了个尺子）。
- 事实与推测分清：可核实的当事实写，推测和判断点明是作者观点。结尾用一段「可信与存疑」的编辑提醒收尾。
- 可以摘 1 到 5 句原话金句融进正文，但别让全文变成摘抄。

### 3. 写文件

写到「他山之石」输出目录。本机默认：

```text
/Users/abc/Documents/knowledge-base/20-knowledge/他山之石/<作者名——简洁中文标题>.md
```

通用安装时写到：

```text
<your-vault>/20-knowledge/他山之石/<作者名——简洁中文标题>.md
```

文件名规则：

- 如果已经确定来源是具体个人（作者、主讲人、频道主），文件名必须把作者名放在前面：`作者名——简洁中文标题.md`。例如：`阿里阿巴达——如何开始第一门生意.md`。
- 如果作者不明确，才使用 `简洁中文标题.md`；如果只确定机构或频道，可用 `机构或频道名——简洁中文标题.md`。
- 文件名不含斜杠。`captured` 用 `date +%F` 的当天日期。结构见下。

## 文档结构（可读文章，不是观点汇总）

```markdown
---
tags: [他山之石, <领域标签>]
source: <平台> · <作者/频道>
author: <作者，未知写"未注明">
url: <原始链接>
captured: <YYYY-MM-DD>
type: 他人观点
---

# <文章式标题>

> 来源与立场：一句话说清作者是谁、有没有带货/特定立场，哪里要打折看。

<开头一两句，把读者带进来。>

## <小标题>
<流畅文章正文，自然融入 attribution，事实与推测分清。>

## <小标题>
...

---
**可信与存疑**：哪些是可核实事实（回到原始来源核对），哪些是作者的推测/判断。
```

## 写完后

简单报告：写到哪个文件、抓取还是粘贴、有没有抓到字幕。**不要**同步到 X 或个人网站。

## 常见错误

| 错误 | 纠正 |
|------|------|
| 写成 bullet 观点汇总 / 「1. 作者认为…」 | 写成可直接阅读的文章 |
| 短语加句号的断裂标点 | 正常完整句子、该用冒号用冒号 |
| 用用户的犀利文风重写 | 保持中立可读，不套文风、不去 AI 味 |
| 把推测当事实写 | 事实归事实，推测点明是作者观点 |
| 漏掉作者的带货/立场 | 写进开头的「来源与立场」 |
| 字幕抓不到就编内容 | 让用户粘贴或换方案，绝不臆造 |
| 一篇塞多个来源 | 一个来源一篇 |

## 参考样例

「他山之石」输出目录下的成品（SpaceX-IPO、跨境券商被查、AI时代普通人如何入局 等）就是目标形态，照它们的可读文章风格来。

## 抓不到字幕的视频怎么办（音频兜底）

`fetch-transcript.sh` 抓不到字幕时，走音频兜底（需先跑过 `setup.sh`）。B 站视频常见情况是没有字幕、只有弹幕，这时直接下载音频转写；YouTube 锁死视频会按需启动 bgutil 解锁 SABR / PO-token：

```bash
# 1) 下载音频（YouTube 会自动启动 bgutil；B 站等平台走通用 yt-dlp）
SKILL_DIR="<包含 SKILL.md 的 florilegium/tashanzhishi 目录>"
AUDIO=$(bash "$SKILL_DIR/fetch-audio.sh" "<链接>" chrome)
# 2) 本地转写（模型留空=按后端自动选；中文传 zh）
~/.local/share/tashanzhishi/venv/bin/python \
  "$SKILL_DIR/transcribe.py" "$AUDIO" "" zh > /tmp/transcript.txt
```

转写逐行实时写进输出文件，随时 `wc -c /tmp/transcript.txt` 看进度、区分「在跑」和「卡死」。然后读 `/tmp/transcript.txt`，按正常流程写成文章。

音频也下不动时，让用户把平台自带的转写、字幕、评论区课代表笔记，或手动整理的文字稿粘贴过来。

**NotebookLM MCP 不行**：它的 `add_source` 不支持 YouTube（只能抓网页或粘贴文本），用不了。

## 后端与并发

`transcribe.py` 每次运行自动选后端，stderr 首行标明（`[backend=… model=… lang=… dur=…s]`）：

- **mlx-gpu**：Apple Silicon 且装了 mlx-whisper（`setup.sh` 在 arm64 macOS 上自动装并预热模型）。默认 `large-v3-turbo`，实测 13 分钟音频约 2 分钟转完（2026-08-29，M1 Pro）。
- **faster-cpu**：其他机器，或 mlx 缺失时静默回退。默认 `small`——CPU 上大模型太慢，这是有意的权衡；CPU 产出的转写专有名词错误率会明显高于 GPU，蒸馏时留意公司名、人名、术语。

显式传模型时按指定的跑，不被自动选择覆盖：GPU 分支的短名映射到 mlx-community（如 `small` → `mlx-community/whisper-small-fp16`；该社区命名不统一，映射表在 `transcribe.py` 里），完整 HF 仓库名原样用。

**并发：GPU 后端串行即可**——GPU 推理本身串行，多路并发只增加显存压力，不提速。CPU 后端要并发时，路数按「物理核数 ÷ 每进程线程数」估；实测教训（2026-08-29，M1 Pro）：每进程线程数给太低时，加路数总吞吐不升反降——先确认每个进程吃满分配到的线程，再往上加。

## 批量用法

一批链接（整季播客、会员合集等）用 `batch.sh`，不要手写一次性队列脚本：

```bash
SKILL_DIR="<包含 SKILL.md 的 florilegium/tashanzhishi 目录>"
bash "$SKILL_DIR/batch.sh" "https://youtube.com/watch?v=AAA" "https://bilibili.com/video/BVxxx/"
```

输出形如：

```text
[18:02] 队列 2 条，后端 mlx-gpu
[18:02] (1/2) AAA 下载音频
[18:03] (1/2) AAA 转写中
[18:14] (1/2) ✓ AAA 完成 56031B
[18:26] 全部完成：2 成功 0 失败 0 跳过（共 2 条）
```

- **可中断可续跑**：Ctrl-C 或杀进程都没关系，重跑同一条命令，已完成的自动跳过。是否完成只看 `<id>.status` 文件，**绝不看文本文件是否非空**——被中断的转写会留下语法完整但内容截断的 `.txt`，从大小看不出来。
- **单条失败不中断队列**：失败记录进 `<id>.fail`，跑完汇总，坏链接重跑同一命令时会自动重试。
- 串行执行：GPU 后端并发不提速（见「后端与并发」）。
- 语言默认按中文（zh）转写；英文或其他语言内容设 `TSZ_LANG=en`（或留空自动检测）再跑。
- 产物目录 `~/.local/share/tashanzhishi/out/`（环境变量 `TSZ_OUT` 可覆盖）：`<id>.txt` 转写文本、`<id>.meta` 来源与音频时长、`<id>.status` 完成标记。

队列进行中随时查进度与剩余时间：

```bash
bash "$SKILL_DIR/status.sh"
# 已完成 11 / 19    进行中 9IBvlu8-umM（约 62%）
# 剩余音频 323 分钟，按 5.6x 实时估算 ≈ 58 分钟
# 失败 0
```

倍率（GPU 5.6x / CPU 1.2x 实时）是 2026-08-29 在 M1 Pro 的实测值，只做粗估。
