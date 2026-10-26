#!/usr/bin/env python3
"""音频转文字：自动选择本机最快可用的后端，逐行实时输出。

用法: transcribe.py <音频文件> [模型] [语言]
      transcribe.py --warmup   下载默认模型并用 1 秒静音跑通一次（setup.sh 调用）
      transcribe.py --check    打印 backend/model/cached，不联网、不加载模型（doctor.sh 调用）
  模型省略或传空串 → 按后端自动选：mlx (GPU) 用 large-v3-turbo，faster-whisper (CPU) 用 small。
  显式传入模型则按指定的跑；GPU 分支会把它映射成 mlx-community/whisper-<名>。
  语言默认自动检测；中文视频传 zh，此时模型位置传空串：transcribe.py audio.m4a "" zh

后端选择：macOS + arm64 且能 import mlx_whisper → mlx-gpu（Apple Silicon GPU）；
否则回退 faster-whisper CPU（CTranslate2 在 macOS 上只支持 CPU，GPU 会全程闲置）。
Apple Silicon 上没装 mlx 时回退并在 stderr 提示一行装法，任务继续不中断。

输出：转录文本逐行打印到 stdout，每行 flush——重定向到文件时字节数随进度增长，
用 wc -c 就能区分「正在跑」和「卡死」。两个分支的 stdout 格式完全一致（逐行纯文本）。
stderr 首行统一为：[backend=… model=… lang=… dur=…s]

模型下载：模型未缓存时先探测 huggingface.co，连不上就自动改用 hf-mirror.com。
用户自己设了 HF_ENDPOINT 时不探测，按用户的来。
"""
import importlib.util
import os
import platform
import re
import sys
import urllib.error
import urllib.request

MLX_MODEL_DEFAULT = "mlx-community/whisper-large-v3-turbo"
CPU_MODEL_DEFAULT = "small"
SAMPLE_RATE = 16000
HF_OFFICIAL = "https://huggingface.co"
HF_MIRROR = "https://hf-mirror.com"
# faster-whisper 短名对应的 HF 仓库（faster_whisper.utils 里的映射，常用的几个）
_CPU_REPOS = {
    name: f"Systran/faster-whisper-{name}"
    for name in ("tiny", "base", "small", "medium", "large-v1", "large-v2", "large-v3")
}

# mlx verbose 行示例：[00:00.000 --> 01:23.456] 或 [01:00:00.000 --> 01:01:00.000] 转出的文字
_MLX_LINE_RE = re.compile(r"^\[[\d:.]+ --> [\d:.]+\] ?(.*)$")
# mlx 语言自动检测时打印的提示行：不进转写文本，转去 stderr
_MLX_INFO_LINES = ("Detected language:", "Detecting language")


def die(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)


def decode_audio_16k(path):
    """PyAV 解码为 16kHz 单声道 float32 ndarray（不依赖系统 ffmpeg）。"""
    import numpy as np
    import av

    resampler = av.AudioResampler(format="flt", layout="mono", rate=SAMPLE_RATE)
    chunks = []
    try:
        with av.open(path) as container:
            for frame in container.decode(audio=0):
                for rf in resampler.resample(frame):
                    chunks.append(rf.to_ndarray().reshape(-1))
    except av.error.FFmpegError as e:
        die(f"✗ 无法解码音频流（{e}）")
    if not chunks:
        die("✗ 文件里没有音频流")
    return np.concatenate(chunks).astype(np.float32)


class _MlxStdoutFilter:
    """接管 sys.stdout：把 mlx verbose 行剥掉时间戳前缀，逐行实时写真正的 stdout。

    mlx 在 verbose=True 时按 30 秒窗口增量 print「[ts --> ts] 文本」；
    语言检测提示行转去 stderr；其余不认识的行按文本续行处理，保证不丢字。
    """

    def __init__(self):
        self._real = sys.stdout
        self._buf = ""

    def write(self, s):
        self._buf += s
        while "\n" in self._buf:
            line, self._buf = self._buf.split("\n", 1)
            self._emit(line)
        return len(s)

    def _emit(self, line):
        m = _MLX_LINE_RE.match(line)
        if m:
            out = m.group(1)
        elif line.startswith(_MLX_INFO_LINES):
            print(line, file=sys.stderr)
            return
        else:
            out = line
        self._real.write(out + "\n")
        self._real.flush()

    def flush(self):
        if self._buf:
            line, self._buf = self._buf, ""
            self._emit(line)
        self._real.flush()


def _hf_cache_root():
    if os.environ.get("HF_HUB_CACHE"):
        return os.environ["HF_HUB_CACHE"]
    home = os.environ.get("HF_HOME") or os.path.join(os.path.expanduser("~"), ".cache", "huggingface")
    return os.path.join(home, "hub")


def hf_cached(repo):
    """模型是否已在 HF 本地缓存里（看 snapshots 目录，不 import huggingface_hub）。"""
    if not repo:
        return False
    snaps = os.path.join(_hf_cache_root(), "models--" + repo.replace("/", "--"), "snapshots")
    return os.path.isdir(snaps) and any(os.scandir(snaps))


def _reachable(url):
    try:
        urllib.request.urlopen(urllib.request.Request(url, method="HEAD"), timeout=3)
        return True
    except urllib.error.HTTPError:
        return True  # 有 HTTP 响应就说明连得上
    except Exception:
        return False


def ensure_hf_endpoint(repo):
    """模型没缓存时选下载源：官方连不上就切镜像，两边都不通就提前报错。

    必须在 import mlx_whisper / faster_whisper 之前调用：huggingface_hub 在 import 时
    读取 HF_ENDPOINT，之后再设不生效。repo 为 None 表示本地模型目录，不需要下载。
    """
    if repo is None or os.environ.get("HF_ENDPOINT") or os.environ.get("HF_HUB_OFFLINE") == "1":
        return
    if hf_cached(repo) or _reachable(HF_OFFICIAL):
        return
    if _reachable(HF_MIRROR):
        os.environ["HF_ENDPOINT"] = HF_MIRROR
        print(
            f"→ huggingface.co 连不上，模型 {repo} 改从镜像 {HF_MIRROR} 下载"
            "（设 HF_ENDPOINT 可指定其他下载源）",
            file=sys.stderr,
            flush=True,
        )
        return
    die(
        f"✗ 模型 {repo} 还没下载，而 huggingface.co 和 {HF_MIRROR} 都连不上。\n"
        "  联网后重试；也可以先把文字稿粘贴给 agent 直接整理。"
    )


def cpu_repo(model):
    """CPU 分支模型名 → HF 仓库；本地目录返回 None。未知短名原样返回（仅用于判断缓存）。"""
    if os.path.isdir(model):
        return None
    return _CPU_REPOS.get(model, model)


def mlx_available():
    """Apple Silicon 且装了 mlx_whisper。只查包在不在，不 import，避免提前带入 huggingface_hub。"""
    return (
        sys.platform == "darwin"
        and platform.machine() == "arm64"
        and importlib.util.find_spec("mlx_whisper") is not None
    )


def detect_backend():
    """返回 (use_mlx, hint)。Apple Silicon 且 mlx_whisper 可 import 才走 GPU。"""
    if sys.platform == "darwin" and platform.machine() == "arm64":
        try:
            import mlx_whisper  # noqa: F401
            return True, None
        except Exception as e:
            return False, str(e)
    return False, None


def run_mlx(audio, model, lang):
    import mlx_whisper

    arr = decode_audio_16k(audio)
    dur = int(round(len(arr) / SAMPLE_RATE))
    print(
        f"[backend=mlx-gpu model={model} lang={lang or 'auto'} dur={dur}s]",
        file=sys.stderr,
        flush=True,
    )
    sys.stdout = _MlxStdoutFilter()
    try:
        # verbose=True 让 mlx 按 30 秒窗口增量打印段落，过滤器负责剥前缀并逐行 flush
        mlx_whisper.transcribe(arr, path_or_hf_repo=model, verbose=True, language=lang)
    finally:
        sys.stdout = sys.__stdout__


def run_cpu(audio, model, lang):
    from faster_whisper import WhisperModel

    fm = WhisperModel(model, device="cpu", compute_type="int8")
    segments, info = fm.transcribe(audio, language=lang, vad_filter=True, beam_size=5)
    print(
        f"[backend=faster-cpu model={model} lang={info.language} dur={info.duration:.0f}s]",
        file=sys.stderr,
        flush=True,
    )
    for seg in segments:
        print(seg.text.strip(), flush=True)


# GPU 分支的模型名映射。mlx-community 的仓库命名不统一（2026-08-29 实测）：
# whisper-tiny / whisper-base-fp16 / whisper-small-fp16 / whisper-medium 存在，
# 而 whisper-small、whisper-base、whisper-large-v3 反而不存在。
_MLX_REPO_ALIASES = {
    "tiny": "mlx-community/whisper-tiny",
    "base": "mlx-community/whisper-base-fp16",
    "small": "mlx-community/whisper-small-fp16",
    "medium": "mlx-community/whisper-medium",
    # GPU 上要大模型就给 turbo：turbo 是 large-v3 的蒸馏版，速度差不多、准得多
    "large-v3": MLX_MODEL_DEFAULT,
    "large-v3-turbo": MLX_MODEL_DEFAULT,
}


def mlx_repo(model):
    """GPU 分支模型名 → HF repo。完整 repo 名（含 /）原样用；短名查实测过的别名表。"""
    if "/" in model:
        return model
    if model in _MLX_REPO_ALIASES:
        return _MLX_REPO_ALIASES[model]
    die(
        f"✗ GPU 后端没有「{model}」的映射。可用短名：{', '.join(sorted(_MLX_REPO_ALIASES))}；"
        "或传完整 HF 仓库名（含 /）。"
    )


def default_repo():
    """(backend, 默认模型仓库)：与 main() 的自动选择一致。"""
    if mlx_available():
        return "mlx-gpu", MLX_MODEL_DEFAULT
    return "faster-cpu", cpu_repo(CPU_MODEL_DEFAULT)


def check():
    backend, repo = default_repo()
    print(f"backend={backend}")
    print(f"model={repo}")
    print(f"cached={1 if hf_cached(repo) else 0}")
    print(f"faster_whisper={1 if importlib.util.find_spec('faster_whisper') else 0}")


def warmup():
    """下载默认模型并用 1 秒静音端到端跑一次，确认后端可用。"""
    import numpy as np

    backend, repo = default_repo()
    ensure_hf_endpoint(repo)
    silence = np.zeros(SAMPLE_RATE, dtype=np.float32)
    if backend == "mlx-gpu":
        import mlx_whisper

        mlx_whisper.transcribe(silence, path_or_hf_repo=repo)
    else:
        from faster_whisper import WhisperModel

        segments, _ = WhisperModel(CPU_MODEL_DEFAULT, device="cpu", compute_type="int8").transcribe(silence)
        list(segments)
    print(f"✓ {backend} 后端自检通过（模型 {repo}）")


def main():
    args = sys.argv[1:]
    if not args:
        die("usage: transcribe.py <audio> [model] [lang] | --warmup | --check")
    if args[0] == "--check":
        return check()
    if args[0] == "--warmup":
        return warmup()
    audio = args[0]
    if not os.path.isfile(audio):
        die(f"✗ 音频文件不存在: {audio}")
    explicit_model = args[1] if len(args) > 1 else ""
    lang = args[2] if len(args) > 2 else None
    if not lang:
        lang = None

    if mlx_available():
        ensure_hf_endpoint(mlx_repo(explicit_model or MLX_MODEL_DEFAULT))
    else:
        ensure_hf_endpoint(cpu_repo(explicit_model or CPU_MODEL_DEFAULT))
    use_mlx, hint = detect_backend()
    if use_mlx:
        run_mlx(audio, mlx_repo(explicit_model or MLX_MODEL_DEFAULT), lang)
    else:
        if hint is not None:
            print(
                f"⚠ Apple Silicon 未检测到 mlx-whisper（{hint}），回退 CPU 后端（慢约 5 倍）。\n"
                "  安装：~/.local/share/tashanzhishi/venv/bin/pip install mlx-whisper",
                file=sys.stderr,
                flush=True,
            )
            ensure_hf_endpoint(cpu_repo(explicit_model or CPU_MODEL_DEFAULT))
        run_cpu(audio, explicit_model or CPU_MODEL_DEFAULT, lang)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n✗ 转写被中断", file=sys.stderr)
        sys.exit(130)
