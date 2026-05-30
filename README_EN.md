[中文](./README.md)

# tashanzhishi

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Shell](https://img.shields.io/badge/shell-bash-green.svg)
![Python](https://img.shields.io/badge/python-3.10%2B-blue.svg)
![Claude Code](https://img.shields.io/badge/Claude%20Code-skill-8A63D2.svg)

A Claude Code skill: give it a YouTube / video link (or a transcript) and it automatically **transcribes and rewrites the content into a readable article**, then files it into the "他山之石" (other people's insights) folder of your Obsidian vault. Free, runs entirely on your machine.

The name comes from a Chinese proverb: "stones from other hills can polish your jade" — collect others' insights and put them to use.

## What it solves

You see a good video and want to keep the author's points, but taking notes by hand is tedious. This skill turns it into one sentence:

> Use tashanzhishi to clip this link: `<youtube url>`

It then: pulls captions → cleans them → writes a neutral, directly-readable article → saves it into your Obsidian "他山之石" folder.

## Features

- **A readable article, not a bullet dump** — reads like a short magazine piece, not `1. The author thinks…`.
- **Faithful + bias-flagged** — facts and speculation kept separate; the author's promotions/agenda are called out.
- **Three-tier retrieval**:
  1. Downloadable captions → grabbed directly with yt-dlp (fastest).
  2. No captions but audio available → local transcription with `faster-whisper`.
  3. YouTube anti-bot locked (SABR / PO-token) → a bundled `bgutil` PO-token provider unlocks the audio, then transcribes.
- **Free & fully local** — nothing leaves your machine except fetching from YouTube; no paid APIs.
- **Obsidian-native** — the output folder is your vault folder.

## Install

```bash
# 1) Drop it into Claude Code's skills directory
git clone <repo-url> ~/.claude/skills/tashanzhishi

# 2) Install dependencies (recent yt-dlp + faster-whisper + bgutil provider)
bash ~/.claude/skills/tashanzhishi/setup.sh
```

Requirements: Python 3.10+, Node.js (to build the bgutil provider). `setup.sh` creates an isolated venv. Caption download uses your browser session, so be logged into YouTube in Chrome.

## Usage

In Claude Code, just say:

```
Use tashanzhishi to clip this link: https://www.youtube.com/watch?v=XXXX
```

Or paste a transcript and let it organize that. Output lands in `your-vault/20-knowledge/他山之石/` (configurable).

## Layout

| File | Purpose |
|------|---------|
| `SKILL.md` | Main skill file: flow + document template |
| `fetch-transcript.sh` | Pull captions + metadata via yt-dlp |
| `vtt2text.py` | Clean a .vtt subtitle into plain text |
| `fetch-audio.sh` | Audio download for locked videos (via bgutil) |
| `transcribe.py` | Transcribe audio with faster-whisper |
| `setup.sh` | One-shot dependency install |

## Credits

- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [faster-whisper](https://github.com/SYSTRAN/faster-whisper)
- [bgutil-ytdlp-pot-provider](https://github.com/Brainicism/bgutil-ytdlp-pot-provider)

## License

MIT
