[中文](./README.md)

# Florilegium · 他山之石

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Shell](https://img.shields.io/badge/shell-bash-green.svg)
![Python](https://img.shields.io/badge/python-3.10%2B-blue.svg)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg)
![Agent Workflow](https://img.shields.io/badge/agent-workflow-8A63D2.svg)

A runtime-agnostic local agent workflow: give it a YouTube, Bilibili, podcast, or other video link (or paste a transcript), and it will fetch captions or transcribe the audio on your machine, turn the content into a **readable article in Chinese**, and save it into a folder you choose (for example an Obsidian vault). It is built for collecting other people's insights.

The name comes from a Chinese proverb: "stones from other hills can polish your jade" — collect others' insights and put them to use. *Florilegium* is the medieval scholars' term for a curated anthology of excerpts from other people's works — the same idea. The workflow's internal name remains `tashanzhishi`.

It is not tied to Claude Code, Codex, or any single runtime. The only requirements: your agent can read a Markdown instruction file and run this repository's shell / Python scripts.

> **Output language:** articles are always written in Chinese, whatever the source language. Other output languages are not supported yet.

## Three ways to use it

| Tier | What you give it | What you need to install |
|------|------------------|--------------------------|
| 1. Tidy a transcript | Pasted transcript, captions, or article | Nothing — clone the repo and let your agent read `SKILL.md` |
| 2. Fetch captions | A video link that has captions (Bilibili, YouTube, …) | Run `setup.sh` once |
| 3. Local transcription | Videos or podcasts without captions | Same; the speech model downloads on first use |

**Fastest start:** install nothing and tell your agent:

```
Use tashanzhishi to turn this transcript into a 他山之石 article: <paste transcript>
```

The first time it saves a file, the agent asks which folder to use and remembers your choice.

## Install

```bash
git clone https://github.com/anneheartrecord/florilegium.git ~/.local/share/florilegium
bash ~/.local/share/florilegium/setup.sh
bash ~/.local/share/florilegium/doctor.sh   # see which capabilities are ready
```

Then point your agent at `~/.local/share/florilegium/SKILL.md`, or clone straight into its skills folder, e.g. `~/.claude/skills/tashanzhishi` or `~/.codex/skills/tashanzhishi`.

**The only hard requirement is Python 3.10+.** If you don't have it, install [uv](https://docs.astral.sh/uv/) and setup.sh will use it to fetch a suitable Python. Everything else goes into an isolated venv under `~/.local/share/tashanzhishi`; nothing touches your system. To uninstall, delete that folder.

What setup.sh does — any step that fails only disables the matching capability, it never aborts the install:

- finds a Python 3.10+ and creates an isolated venv;
- installs yt-dlp, faster-whisper, and deno for YouTube (via PyPI); on Apple Silicon also mlx-whisper so transcription runs on the GPU;
- switches to a PyPI mirror in China when pypi.org is unreachable;
- asks where to save articles, suggesting any Obsidian vaults it finds;
- pre-downloads the speech model and runs a self-test: ~1.5GB on Apple Silicon, ~500MB elsewhere. When huggingface.co is unreachable it falls back to hf-mirror.com.

Options:

| Flag | Effect |
|------|--------|
| `--skip-model` | Don't pre-download the model; fetch it on first transcription |
| `--with-bgutil` | Build the bgutil PO-token provider to unlock the few YouTube videos locked by SABR / PO-token (needs Node.js) |
| `--upgrade` | Only upgrade yt-dlp — use it when a site change breaks fetching |
| `--yes` | Don't ask questions; the output folder is chosen on first use |

Supports macOS and Linux. Windows is not supported yet.

## Transcription speed

| Machine | Backend | Default model | Speed |
|---------|---------|---------------|-------|
| Apple Silicon | mlx-whisper (GPU) | large-v3-turbo | ~5.6× real time: 13 min of audio in ~2 min 20 s |
| Everything else | faster-whisper (CPU) | small | ~1.2× real time on an M1 Pro CPU; not measured on x86, usually slower |

Numbers were measured on an M1 Pro on 2026-08-29 and are rough estimates. The CPU default is the small model, so expect more mistakes in proper nouns than with the GPU's large model.

## Logins and cookies

Requests go out anonymously first. If that fails, the scripts find a browser you've used (Chrome, Firefox, Brave, Edge, Chromium) and retry with its cookies:

- **Bilibili only serves captions to logged-in users**, so log in to Bilibili in your browser;
- on macOS, reading Chrome's cookies triggers a Keychain prompt — click Allow;
- to use an exported cookie file, set `TSZ_COOKIES=/path/to/cookies.txt`: the first request uses it and still falls back to your browser, so a YouTube-only cookie file doesn't break Bilibili;
- to pin a browser, set `TSZ_BROWSER=firefox`; then there is no fallback.

## Features

- **A readable article, not a bullet dump** — reads like a short magazine piece, not `1. The author thinks…`.
- **Faithful and bias-flagged** — facts and speculation are kept apart; the author's promotions or agenda are called out.
- **Author-first filenames** — when a concrete author is known, files are named `Author——Topic.md`.
- **Transcription stays on your machine** — speech-to-text never calls a cloud API and needs no paid key. Writing the article is done by your agent, so the transcript goes to whatever model that agent uses.
- **Optional topic merge** — if a `topic-hub` skill is installed, each saved article is merged into the matching topic card; otherwise this step is skipped.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| yt-dlp or the venv can't be found | Run `setup.sh` |
| It used to work and suddenly can't fetch | The site changed; run `setup.sh --upgrade` |
| Bilibili says captions need a login | Log in to Bilibili in your browser and retry |
| YouTube asks you to sign in or prove you're not a bot | Use a browser logged in to YouTube, or set `TSZ_COOKIES` |
| A particular YouTube video's audio never downloads | `setup.sh --with-bgutil` (needs Node.js) |
| You want a different output folder | `bash article-dir.sh set <folder>` |
| Not sure what's wrong | Run `doctor.sh`; it lists what isn't ready and the command to fix it |

## Running the scripts by hand

```bash
# 1) Try captions first; exit code 2 means there are none
DIR=$(bash ./fetch-transcript.sh "<video url>")
python3 ./vtt2text.py "$DIR"/sub.<lang>.vtt > /tmp/transcript.txt

# 2) No captions: download audio and transcribe locally (empty model = auto; pass zh for Chinese)
AUDIO=$(bash ./fetch-audio.sh "<video url>")
~/.local/share/tashanzhishi/venv/bin/python ./transcribe.py "$AUDIO" "" zh > /tmp/transcript.txt

# 3) Many links: a resumable queue
bash ./batch.sh "<url 1>" "<url 2>"
bash ./status.sh
```

## Layout

| File | Purpose |
|------|---------|
| `SKILL.md` | Main agent instructions: workflow and article template |
| `setup.sh` | One-time dependency install |
| `doctor.sh` | Environment check: dependencies, capability tiers, fixes |
| `article-dir.sh` | Read or set the article output folder |
| `fetch-transcript.sh` | Fetch captions and metadata |
| `vtt2text.py` | Clean vtt / srt captions into plain text |
| `fetch-audio.sh` | Download audio; optional bgutil for locked YouTube videos |
| `transcribe.py` | Local transcription, picks the GPU or CPU backend |
| `batch.sh` / `status.sh` | Batch transcription queue and progress |
| `lib.sh` | Shared shell functions |

## Credits

- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [faster-whisper](https://github.com/SYSTRAN/faster-whisper)
- [mlx-whisper](https://github.com/ml-explore/mlx-examples/tree/main/whisper)
- [bgutil-ytdlp-pot-provider](https://github.com/Brainicism/bgutil-ytdlp-pot-provider)

## License

MIT
