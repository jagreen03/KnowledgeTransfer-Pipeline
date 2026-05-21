#!/usr/bin/env python
"""
transcribe-whisper.py
Local transcription for ACMP module video chunks using faster-whisper.

Walks INPUT_ROOT for *Part<N>.mp4 files and writes transcripts_part<N>.txt
next to each video. Idempotent: skips chunks that already have a transcript.

Device selection is automatic:
  1. Try CUDA at int8_float16 (best quality/speed on a 6GB GPU with large-v3).
  2. If CUDA load fails, try CUDA at int8 (lighter VRAM).
  3. If both fail, fall back to CPU at int8 (slow but reliable).

You can override via env vars if you ever need to:
  WHISPER_DEVICE=cuda|cpu
  WHISPER_COMPUTE=int8|int8_float16|float16
"""

# =============================================================================
# CONFIGURATION
# =============================================================================

MODEL_SIZE = "large-v3"
LANGUAGE = "en"           # None to auto-detect
BEAM_SIZE = 5             # 5 = quality default; lower = faster
TIMESTAMP_INTERVAL_SEC = 60
INPUT_ROOT_DEFAULT = r"C:\ODIN\GeminiReady_ACMP_Modules"

# =============================================================================

import os
import re
import sys
import time
from pathlib import Path

# ---- Windows: register NVIDIA DLL directories from pip-installed packages ----
# (cublas / cudnn / cuda-nvrtc ship in site-packages/nvidia/*/bin; Windows
# doesn't search there by default. We add them BOTH via os.add_dll_directory
# for Python import-time loads AND prepend to PATH for ctranslate2's runtime
# LoadLibrary calls.)
if sys.platform == "win32":
    site_packages = Path(sys.executable).resolve().parent.parent / "Lib" / "site-packages"
    nvidia_root = site_packages / "nvidia"
    if nvidia_root.exists():
        nvidia_bins = []
        for sub in sorted(nvidia_root.iterdir()):
            bin_dir = sub / "bin"
            if bin_dir.is_dir():
                nvidia_bins.append(str(bin_dir))
                try:
                    os.add_dll_directory(str(bin_dir))
                except OSError:
                    pass
        if nvidia_bins:
            os.environ["PATH"] = os.pathsep.join(nvidia_bins) + os.pathsep + os.environ.get("PATH", "")
            print(f"Registered {len(nvidia_bins)} NVIDIA DLL directories.")

try:
    from faster_whisper import WhisperModel
except ImportError:
    print("ERROR: faster-whisper not installed.")
    print("Install with: pip install faster-whisper")
    sys.exit(1)


# =============================================================================
# DEVICE DETECTION
# =============================================================================

def load_model_with_fallback(model_size: str):
    """
    Try CUDA first (best -> safest compute type), then CPU.
    Returns (model, device, compute_type).
    Honors WHISPER_DEVICE / WHISPER_COMPUTE env vars if set.
    """
    forced_device  = os.environ.get("WHISPER_DEVICE")
    forced_compute = os.environ.get("WHISPER_COMPUTE")

    if forced_device and forced_compute:
        attempts = [(forced_device, forced_compute)]
        print(f"Overrides: WHISPER_DEVICE={forced_device}, WHISPER_COMPUTE={forced_compute}")
    elif forced_device == "cpu":
        attempts = [("cpu", forced_compute or "int8")]
    elif forced_device == "cuda":
        attempts = [
            ("cuda", forced_compute or "int8_float16"),
            ("cuda", "int8"),
        ]
    else:
        # Auto: prefer CUDA, degrade compute type, then fall back to CPU
        attempts = [
            ("cuda", "int8_float16"),  # ~4-5GB VRAM for large-v3, good fit for 6GB
            ("cuda", "int8"),          # lighter VRAM if the first fails
            ("cpu",  "int8"),          # always works, ~10x slower
        ]

    last_err = None
    for device, compute in attempts:
        try:
            print(f"Trying {device} / {compute} ...")
            t0 = time.time()
            model = WhisperModel(model_size, device=device, compute_type=compute)
            print(f"  Loaded in {time.time() - t0:.1f}s on {device} ({compute}).")
            return model, device, compute
        except Exception as e:
            print(f"  Failed: {e}")
            last_err = e
            continue

    raise RuntimeError(f"Could not load Whisper on any device. Last error: {last_err}")


# =============================================================================
# TRANSCRIPTION
# =============================================================================

def transcribe_file(model: WhisperModel, video_path: Path) -> tuple[str, float]:
    """Transcribe one video. Returns (text, audio_duration_seconds)."""
    segments, info = model.transcribe(
        str(video_path),
        language=LANGUAGE,
        beam_size=BEAM_SIZE,
        vad_filter=True,
        vad_parameters=dict(min_silence_duration_ms=500),
    )

    lines = []
    last_marker = -TIMESTAMP_INTERVAL_SEC

    for segment in segments:
        if segment.start - last_marker >= TIMESTAMP_INTERVAL_SEC:
            mm = int(segment.start // 60)
            ss = int(segment.start % 60)
            lines.append(f"\n[{mm:02d}:{ss:02d}]\n")
            last_marker = segment.start
        lines.append(segment.text.strip())

    text = " ".join(lines).strip()
    return text, info.duration


def main():
    input_root = Path(os.environ.get("KT_INPUT_ROOT", INPUT_ROOT_DEFAULT))
    if not input_root.exists():
        print(f"ERROR: input root not found: {input_root}")
        sys.exit(1)

    # Collect work
    jobs = []
    for folder in sorted(input_root.iterdir()):
        if not folder.is_dir():
            continue
        for video in sorted(folder.glob("*Part*.mp4")):
            m = re.search(r"Part(\d+)\.mp4$", video.name)
            if not m:
                continue
            part_num = m.group(1)
            out_file = folder / f"transcripts_part{part_num}.txt"
            jobs.append({
                "folder":  folder.name,
                "video":   video,
                "out":     out_file,
                "part":    part_num,
                "exists":  out_file.exists(),
                "size_mb": video.stat().st_size / (1024 * 1024),
            })

    todo = [j for j in jobs if not j["exists"]]
    done = len(jobs) - len(todo)

    print("=" * 78)
    print("ACMP Module Chunks - Local Whisper Transcription")
    print(f"  Source: {input_root}")
    print(f"  Model:  {MODEL_SIZE}")
    print("=" * 78)
    print(f"  Total chunks:  {len(jobs)}")
    print(f"  Already done:  {done}")
    print(f"  To transcribe: {len(todo)}")
    print()

    if not todo:
        print("Nothing to do. All chunks have transcripts.")
        return

    # Load model with automatic device selection
    try:
        model, device, compute = load_model_with_fallback(MODEL_SIZE)
    except RuntimeError as e:
        print(f"\nFATAL: {e}")
        print("\nManual override if needed (PowerShell):")
        print('  $env:WHISPER_DEVICE = "cpu"; $env:WHISPER_COMPUTE = "int8"')
        sys.exit(1)
    print()

    # Process
    success = 0
    fail = 0
    total_audio_sec = 0
    t_run_start = time.time()

    for i, job in enumerate(todo, 1):
        label = f"{job['folder']} Part{job['part']}"
        print(f"[{i}/{len(todo)}] {label} ({job['size_mb']:.1f}MB)")

        t_start = time.time()
        try:
            text, audio_sec = transcribe_file(model, job["video"])
            job["out"].write_text(text, encoding="utf-8")
            elapsed = time.time() - t_start
            total_audio_sec += audio_sec
            rtf = elapsed / audio_sec if audio_sec else 0
            print(f"         -> {job['out'].name} "
                  f"({len(text):,} chars, "
                  f"{audio_sec/60:.1f}min audio, "
                  f"{elapsed:.1f}s wall, "
                  f"{rtf:.2f}x realtime)\n")
            success += 1
        except Exception as e:
            print(f"         FAILED: {e}\n")
            fail += 1

    # Summary
    total_wall = time.time() - t_run_start
    print("=" * 78)
    print(f"Device used:     {device} ({compute})")
    print(f"Complete:        {success} transcribed, {fail} failed")
    if total_audio_sec > 0:
        print(f"Audio processed: {total_audio_sec/3600:.2f} hours")
        print(f"Wall time:       {total_wall/60:.1f} minutes")
        print(f"Avg speed:       {total_audio_sec/total_wall:.1f}x realtime")
    print()


if __name__ == "__main__":
    main()
