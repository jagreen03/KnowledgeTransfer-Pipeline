#!/usr/bin/env python
"""
Extract-Keyframes.py
Scene-change keyframe extraction for ACMP module video chunks.

For each C:\\ODIN\\GeminiReady_ACMP_Modules\\*\\Part*.mp4, creates a sibling
frames_partN\\ directory with JPG frames named by timestamp (t02m11s.jpg).
Idempotent: skips chunks where frames_* directory exists with content.

Requires: ffmpeg in PATH.
CPU-only. Safe to run while other GPU jobs are active.
"""
import re
import subprocess
import sys
import time
from pathlib import Path

INPUT_ROOT = Path(r"C:\ODIN\GeminiReady_ACMP_Modules")
SCENE_THRESHOLD = 0.30  # 0.0-1.0; higher = fewer frames. 0.30 = slide-friendly.
JPEG_QUALITY = 5        # ffmpeg -q:v: 1-31, lower = better. 5 = good.
MAX_FRAMES_PER_CHUNK = 200  # safety cap


def extract_keyframes(video_path: Path, frames_dir: Path) -> int:
    """Run ffmpeg scene detection, rename outputs by timestamp. Returns frame count."""
    frames_dir.mkdir(exist_ok=True)

    cmd = [
        "ffmpeg", "-y", "-i", str(video_path),
        "-vf", f"select='gt(scene,{SCENE_THRESHOLD})',showinfo",
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
    if not INPUT_ROOT.exists():
        print(f"ERROR: not found: {INPUT_ROOT}")
        sys.exit(1)

    jobs = []
    for folder in sorted(INPUT_ROOT.iterdir()):
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
                "video": video,
                "frames_dir": frames_dir,
                "part": part_num,
                "folder": folder.name,
                "done": done,
            })

    todo = [j for j in jobs if not j["done"]]
    done = len(jobs) - len(todo)

    print("=" * 70)
    print("ACMP Module Keyframe Extraction (CPU / ffmpeg scene detection)")
    print(f"  Source:    {INPUT_ROOT}")
    print(f"  Threshold: {SCENE_THRESHOLD}  Quality: {JPEG_QUALITY}")
    print("=" * 70)
    print(f"  Total chunks:  {len(jobs)}")
    print(f"  Already done:  {done}")
    print(f"  To extract:    {len(todo)}\n")

    if not todo:
        print("Nothing to do.")
        return

    total_frames = 0
    t_start = time.time()
    for i, job in enumerate(todo, 1):
        label = f"{job['folder']} Part{job['part']}"
        print(f"[{i}/{len(todo)}] {label}")
        t0 = time.time()
        try:
            count = extract_keyframes(job["video"], job["frames_dir"])
            elapsed = time.time() - t0
            print(f"         -> {count} frames in {elapsed:.1f}s -> {job['frames_dir'].name}\n")
            total_frames += count
        except Exception as e:
            print(f"         FAILED: {e}\n")

    total_elapsed = time.time() - t_start
    print(f"Complete. {total_frames} frames in {total_elapsed/60:.1f} min total.")


if __name__ == "__main__":
    main()
