#!/usr/bin/env python3
"""用 faster-whisper 把音频转成文字（无需 ffmpeg，PyAV 解码）。
用法: transcribe.py <音频文件> [模型] [语言]
  模型默认 small；质量优先用 medium 或 large-v3（更慢、模型更大）。
  语言默认自动检测；中文视频可传 zh。
转录文本输出到 stdout，进度/语言信息到 stderr。
"""
import sys
from faster_whisper import WhisperModel

audio = sys.argv[1] if len(sys.argv) > 1 else sys.exit("usage: transcribe.py <audio> [model] [lang]")
model_size = sys.argv[2] if len(sys.argv) > 2 else "small"
lang = sys.argv[3] if len(sys.argv) > 3 else None

model = WhisperModel(model_size, device="cpu", compute_type="int8")
segments, info = model.transcribe(audio, language=lang, vad_filter=True, beam_size=5)
print(f"[model={model_size} lang={info.language} dur={info.duration:.0f}s]", file=sys.stderr)
for seg in segments:
    print(seg.text.strip())
