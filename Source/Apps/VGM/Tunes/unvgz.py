#!/usr/bin/env python3
import argparse
import gzip
import sys
from pathlib import Path


def iter_input_files(inputs):
    if not inputs:
        yield from Path(".").glob("*.vgz")
        return

    for entry in inputs:
        p = Path(entry)
        if p.is_dir():
            yield from p.rglob("*.vgz")
        elif p.is_file():
            yield p
        else:
            # Basic glob support
            yield from Path(".").glob(entry)


def decompress_file(src_path: Path, keep: bool, force: bool) -> int:
    if src_path.suffix.lower() != ".vgz":
        print(f"SKIP  {src_path} (not .vgz)")
        return 0

    dst_path = src_path.with_suffix(".vgm")
    if dst_path.exists() and not force:
        print(f"SKIP  {dst_path} exists (use --force)")
        return 1

    try:
        with gzip.open(src_path, "rb") as src, open(dst_path, "wb") as dst:
            dst.write(src.read())
        if not keep:
            src_path.unlink()
        print(f"OK    {src_path} -> {dst_path}")
        return 0
    except Exception as exc:
        print(f"FAIL  {src_path}: {exc}")
        try:
            if dst_path.exists():
                dst_path.unlink()
        except OSError:
            pass
        return 1


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Decompress .vgz files into .vgm files."
    )
    parser.add_argument(
        "inputs",
        nargs="*",
        help="Files, directories, or glob patterns. Default: *.vgz in current directory.",
    )
    parser.add_argument(
        "--keep",
        action="store_true",
        help="Keep original .vgz files after decompression.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite existing .vgm files.",
    )
    args = parser.parse_args()

    files = sorted({p.resolve() for p in iter_input_files(args.inputs) if p.exists()})
    if not files:
        print("No input files found.")
        return 1

    failures = 0
    for f in files:
        failures += decompress_file(f, keep=args.keep, force=args.force)

    print(f"Done. Processed={len(files)} Failures={failures}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
