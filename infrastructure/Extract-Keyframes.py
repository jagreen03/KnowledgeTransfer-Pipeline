#!/usr/bin/env python
"""
Extract-Keyframes.py
Scene-change keyframe extraction for KT video chunks.

For each <INPUT_ROOT>\*\Part*.mp4, creates a sibling frames_partN\ directory
with JPG frames named by timestamp (t02m11s.jpg). Idempotent: skips chunks
where frames_partN\ exists with content.

Usage:
  python Extract-Keyframes.py --input C:\path\to\sessions
  python Extract-Keyframes.py                  # uses KT_INPUT_ROOT env var, else legacy default

Requires: ffmpeg in PATH.
CPU-only. Safe to run while other GPU jobs are active.
"""
import argparse
import os
import re
import subprocess
import sys
import time
from pathlib import Path

# 0.15 is tuned for KT-style slow slide content. A typical slide change is a
# big visual delta (close to 1.0) so 0.15 catches them comfortably while still
# rejecting speaker-camera micro-movements. The previous 0.30 was too aggressive
# for stream-copy splits whose first GOP can produce muted scene-detect signals.
SCENE_THRESHOLD = 0.15
JPEG_QUALITY = 5             # ffmpeg -q:v: 1-31, lower = better. 5 = good.
MAX_FRAMES_PER_CHUNK = 200   # safety cap


def parse_args():
    p = argparse.ArgumentParser(description="Scene-change keyframe extraction for KT video chunks.")
    p.add_argument(
        "--input", "-i",
        default=os.environ.get("KT_INPUT_ROOT", r"C:\ODIN\GeminiReady_ACMP_Modules"),
        help="Root containing session subfolders with Part*.mp4 (default: $KT_INPUT_ROOT or legacy path)",
    )
    p.add_argument(
        "--threshold", "-t",
        type=float, default=SCENE_THRESHOLD,
        help=f"Scene-change threshold 0.0-1.0 (default: {SCENE_THRESHOLD})",
    )
    return p.parse_args()


def extract_keyframes(video_path: Path, frames_dir: Path, threshold: float) -> int:
    """Run ffmpeg scene detection, rename outputs by timestamp. Returns frame count."""
    frames_dir.mkdir(exist_ok=True)

    cmd = [
        "ffmpeg", "-y", "-i", str(video_path),
        "-vf", f"select='gt(scene,{threshold})',showinfo",
        "-vsync", "vfr",
        "-q:v", str(JPEG_QUALITY),
        "-frames:v", str(MAX_FRAMES_PER_CHUNK),
        str(frames_dir / "frame_%04d.jpg"),
        "-loglevel", "info",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)

    # showinfo writes pts_time per output frame to stderr
    timestamps = re.findall(r"pts_time:(\d+\.?\d*)", result.stderr)

    # Rename frame_NNNN.jpg -> tMMmSSs.jpg
    frames = sorted(frames_dir.glob("frame_*.jpg"))
    for i, frame in enumerate(frames):
        if i >= len(timestamps):
            break
        t = float(timestamps[i])
        mm = int(t // 60)
        ss = int(t % 60)
        target = frames_dir / f"t{mm:02d}m{ss:02d}s.jpg"
        if target.exists() and target != frame:
            target = frames_dir / f"t{mm:02d}m{ss:02d}s_{i:03d}.jpg"
        if target != frame:
            frame.rename(target)

    return len(list(frames_dir.glob("t*.jpg")))


def main():
    args = parse_args()
    input_root = Path(args.input)
    threshold = args.threshold

    if not input_root.exists():
        print(f"ERROR: not found: {input_root}")
        sys.exit(1)

    jobs = []
    for folder in sorted(input_root.iterdir()):
        if not folder.is_dir():
            continue
        for video in sorted(folder.glob("*Part*.mp4")):
            m = re.search(r"Part(\d+)\.mp4$", video.name)
            if not m:
                continue
            part_num = m.group(1)
            frames_dir = folder / f"frames_part{part_num}"
            done = frames_dir.exists() and any(frames_dir.glob("t*.jpg"))
            jobs.append({
                "video":      video,
                "frames_dir": frames_dir,
                "part":       part_num,
                "folder":     folder.name,
                "done":       done,
            })

    todo = [j for j in jobs if not j["done"]]
    done = len(jobs) - len(todo)

    print("=" * 70)
    print("KT Keyframe Extraction (CPU / ffmpeg scene detection)")
    print(f"  Source:    {input_root}")
    print(f"  Threshold: {threshold}  Quality: {JPEG_QUALITY}")
    print("=" * 70)
    print(f"  Total chunks:  {len(jobs)}")
    print(f"  Already done:  {done}")
    print(f"  To extract:    {len(todo)}\n")

    if not todo:
        print("Nothing to do.")
        return

    total_frames = 0
    zero_frame_chunks = []
    t_start = time.time()
    for i, job in enumerate(todo, 1):
        label = f"{job['folder']} Part{job['part']}"
        print(f"[{i}/{len(todo)}] {label}")
        t0 = time.time()
        try:
            count = extract_keyframes(job["video"], job["frames_dir"], threshold)
            elapsed = time.time() - t0
            print(f"         -> {count} frames in {elapsed:.1f}s -> {job['frames_dir'].name}\n")
            total_frames += count
            if count == 0:
                zero_frame_chunks.append(label)
        except Exception as e:
            print(f"         FAILED: {e}\n")

    total_elapsed = time.time() - t_start
    print(f"Complete. {total_frames} frames in {total_elapsed/60:.1f} min total.")
    if zero_frame_chunks:
        print(f"\nWARNING: {len(zero_frame_chunks)} chunk(s) produced 0 frames:")
        for z in zero_frame_chunks:
            print(f"  - {z}")
        print(f"Consider lowering --threshold below {threshold} and re-running.")


if __name__ == "__main__":
    main()
