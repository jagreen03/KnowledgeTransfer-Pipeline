#!/usr/bin/env python
"""
Extract-OCR.py
Stage 4 of the KT pipeline: OCR the scene-change keyframes so the local LLM
(which cannot see images) has the on-screen slide/diagram/code text as input.

For each <INPUT_ROOT>/<session>/frames_partN/*.jpg, runs Tesseract and writes
a sibling <session>/ocr_partN.json of the form:

    { "t00m12s.jpg": "text found on that frame", ... }

This is the EXACT shape Analyze-KTPart-Local.ps1 expects.

Idempotent: skips a part whose ocr_partN.json already exists, unless --force.

Usage:
  python Extract-OCR.py --input C:\\ODIN\\TEST_RUN\\sessions
  python Extract-OCR.py                  # uses KT_INPUT_ROOT env var
  python Extract-OCR.py --force          # re-OCR everything

Requires:
  - Tesseract OCR binary:  winget install UB-Mannheim.TesseractOCR
  - pip install pytesseract pillow
"""
import argparse
import json
import os
import re
import sys
import time
from pathlib import Path

try:
    import pytesseract
    from PIL import Image
except ImportError:
    print("ERROR: pytesseract and/or pillow not installed.")
    print("Install with: pip install pytesseract pillow")
    sys.exit(1)

# Default install location for the UB-Mannheim Tesseract package on Windows.
# Used if --tesseract-exe / $TESSERACT_EXE not provided and it's not on PATH.
DEFAULT_TESSERACT = r"C:\Program Files\Tesseract-OCR\tesseract.exe"
MIN_TEXT_CHARS = 10  # ignore frames whose OCR yields almost nothing


def parse_args():
    p = argparse.ArgumentParser(description="Tesseract OCR over KT keyframes.")
    p.add_argument("--input", "-i",
        default=os.environ.get("KT_INPUT_ROOT", r"C:\ODIN\TEST_RUN\sessions"),
        help="Root containing session subfolders with frames_partN dirs")
    p.add_argument("--force", "-f", action="store_true",
        help="Re-OCR even if ocr_partN.json already exists")
    p.add_argument("--tesseract-exe",
        default=os.environ.get("TESSERACT_EXE", ""),
        help="Full path to tesseract.exe (falls back to default install path)")
    return p.parse_args()


def resolve_tesseract(explicit: str):
    """Point pytesseract at a working binary, or exit with guidance."""
    if explicit:
        pytesseract.pytesseract.tesseract_cmd = explicit
    elif Path(DEFAULT_TESSERACT).exists():
        pytesseract.pytesseract.tesseract_cmd = DEFAULT_TESSERACT
    # else: rely on PATH
    try:
        ver = pytesseract.get_tesseract_version()
        print(f"Tesseract version: {ver}")
    except Exception as e:
        print("ERROR: Tesseract binary not found.")
        print(f"  ({e})")
        print("  Install: winget install UB-Mannheim.TesseractOCR")
        print(f"  Or pass --tesseract-exe \"{DEFAULT_TESSERACT}\"")
        sys.exit(1)


def ocr_frames(frames_dir: Path) -> dict:
    """OCR every *.jpg in frames_dir (chronological). Returns {frame_name: text}."""
    result = {}
    for frame in sorted(frames_dir.glob("*.jpg")):
        try:
            with Image.open(frame) as img:
                text = pytesseract.image_to_string(img)
            text = re.sub(r"[ \t]+", " ", text)
            text = re.sub(r"\n{3,}", "\n\n", text).strip()
            if len(text) > MIN_TEXT_CHARS:
                result[frame.name] = text
        except Exception as e:
            print(f"  Error processing {frame.name}: {e}")
    return result


def main():
    args = parse_args()
    resolve_tesseract(args.tesseract_exe)

    input_root = Path(args.input)
    if not input_root.exists():
        print(f"ERROR: input root not found: {input_root}")
        sys.exit(1)

    jobs = []
    for folder in sorted(input_root.iterdir()):
        if not folder.is_dir():
            continue
        for frames_dir in sorted(folder.glob("frames_part*")):
            if not frames_dir.is_dir():
                continue
            m = re.search(r"frames_part(\d+)$", frames_dir.name)
            if not m:
                continue
            part_num = m.group(1)
            out_file = folder / f"ocr_part{part_num}.json"
            done = out_file.exists() and not args.force
            jobs.append({"folder": folder.name, "frames_dir": frames_dir,
                         "out": out_file, "part": part_num, "done": done})

    todo = [j for j in jobs if not j["done"]]
    print("=" * 70)
    print("KT Keyframe OCR (Tesseract)")
    print(f"  Source: {input_root}")
    print("=" * 70)
    print(f"  Total parts:  {len(jobs)}")
    print(f"  Already done: {len(jobs) - len(todo)}")
    print(f"  To OCR:       {len(todo)}\n")

    if not todo:
        print("Nothing to do.")
        return

    total_frames = 0
    empty_parts = []
    t_start = time.time()
    for i, job in enumerate(todo, 1):
        label = f"{job['folder']} Part{job['part']}"
        print(f"[{i}/{len(todo)}] {label}")
        t0 = time.time()
        ocr_map = ocr_frames(job["frames_dir"])
        # temp-write then atomic rename so a crash can't leave a half file
        tmp = job["out"].with_suffix(".json.tmp")
        tmp.write_text(json.dumps(ocr_map, indent=2, ensure_ascii=False), encoding="utf-8")
        tmp.replace(job["out"])
        n = len(ocr_map)
        total_frames += n
        if n == 0:
            empty_parts.append(label)
        print(f"  -> {job['out'].name} ({n} frames with text, {time.time()-t0:.1f}s)\n")

    print(f"Complete. OCR'd {total_frames} frames across {len(todo)} part(s) in {(time.time()-t_start)/60:.1f} min.")
    if empty_parts:
        print(f"\nNOTE: {len(empty_parts)} part(s) produced no OCR text (frames may be video/photos, not slides):")
        for e in empty_parts:
            print(f"  - {e}")


if __name__ == "__main__":
    main()
