[中文](./README.md)

# Florilegium · 他山之石

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Shell](https://img.shields.io/badge/shell-bash-green.svg)
![Python](https://img.shields.io/badge/python-3.10%2B-blue.svg)
![Agent Workflow](https://img.shields.io/badge/agent-workflow-8A63D2.svg)

A general local agent workflow / skill: give it a YouTube, Bilibili, podcast, or other video link (or a transcript), and it will fetch captions or transcribe audio, turn the content into a **readable article**, then file it into the "他山之石" (other people's insights) folder of your Obsidian vault. Free, runs entirely on your machine.

The name comes from a Chinese proverb: "stones from other hills can polish your jade" — collect others' insights and put them to use. *Florilegium* is the medieval scholars' term for a curated anthology of excerpts gathered from other people's works — the same idea. The skill's internal name remains `tashanzhishi`.

It was first written in the shape of a Claude Code skill, but the repository is not Claude-specific. Codex, Claude, Cursor, OpenCode, or any coding agent that can read `SKILL.md` and run shell scripts can use the workflow.

## What it solves

You see a good video and want to keep the author's points, but taking notes by hand is tedious. This workflow turns it into one sentence:

> Use tashanzhishi to clip this link: `<video url>`

It then: pulls captions → cleans them → writes a neutral, directly-readable article → saves it into your Obsidian "他山之石" folder.

## Features

- **A readable article, not a bullet dump** — reads like a short magazine piece, not `1. The author thinks…`.
- **Faithful + bias-flagged** — facts and speculation kept separate; the author's promotions/agenda are called out.
- **Three-tier retrieval**:
  1. Downloadable captions → grabbed directly with yt-dlp (fastest).
  2. No captions but audio available → local transcription with `faster-whisper`. Bilibili videos without captions use this path.
  3. YouTube anti-bot locked (SABR / PO-token) → a bundled `bgutil` PO-token provider unlocks the audio, then transcribes.
- **Platform-aware audio fallback** — YouTube starts `bgutil` and passes YouTube-specific extractor args; Bilibili and other platforms use the generic `yt-dlp` audio path.
- **Free & fully local** — nothing leaves your machine except fetching from the source platform; no paid APIs.
- **Obsidian-native** — the output folder is your vault folder.

## Install

### Generic repository install

```bash
git clone https://github.com/anneheartrecord/florilegium.git ~/.local/share/florilegium
bash ~/.local/share/florilegium/setup.sh
```

Then point your agent at `~/.local/share/florilegium/SKILL.md` and let it call the scripts described there.

### Install for Claude Code

```bash
git clone https://github.com/anneheartrecord/florilegium.git ~/.claude/skills/tashanzhishi
bash ~/.claude/skills/tashanzhishi/setup.sh
```

### Install for Codex

If you have a Codex skills directory, clone or symlink the repository into it:

```bash
mkdir -p ~/.codex/skills
git clone https://github.com/anneheartrecord/florilegium.git ~/.codex/skills/tashanzhishi
bash ~/.codex/skills/tashanzhishi/setup.sh
```

You can also keep the repository anywhere and point Codex to this repo's `SKILL.md`.

Requirements: Python 3.10+, Node.js (to build the bgutil provider), deno (the JS runtime yt-dlp uses to solve YouTube's n-challenge; `setup.sh` installs it automatically). `setup.sh` creates an isolated venv. Caption and audio download can use your browser session, so it helps to be logged into YouTube / Bilibili in Chrome.

## Usage

In your agent, just say:

```
Use tashanzhishi to clip this link: https://www.bilibili.com/video/BVxxxx
```

Or paste a transcript and let it organize that. Output lands in `your-vault/20-knowledge/他山之石/` (configurable).

You can also run the scripts manually:

```bash
# 1) Try captions first
bash ./fetch-transcript.sh "<video url>" chrome

# 2) If there are no captions, download audio
AUDIO=$(bash ./fetch-audio.sh "<video url>" chrome)

# 3) Transcribe locally
~/.local/share/tashanzhishi/venv/bin/python ./transcribe.py "$AUDIO" small zh > /tmp/transcript.txt
```

## Layout

| File | Purpose |
|------|---------|
| `SKILL.md` | Main skill file: flow + document template |
| `fetch-transcript.sh` | Pull captions + metadata via yt-dlp |
| `vtt2text.py` | Clean a .vtt subtitle into plain text |
| `fetch-audio.sh` | Platform-aware audio download: generic yt-dlp for Bilibili and others, bgutil for locked YouTube videos |
| `transcribe.py` | Transcribe audio with faster-whisper |
| `setup.sh` | One-shot dependency install |

## Credits

- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [faster-whisper](https://github.com/SYSTRAN/faster-whisper)
- [bgutil-ytdlp-pot-provider](https://github.com/Brainicism/bgutil-ytdlp-pot-provider)

## License

MIT
