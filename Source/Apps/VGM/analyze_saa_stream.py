#!/usr/bin/env python3
import argparse
from collections import Counter, defaultdict
from pathlib import Path


CMD_LEN_2 = {0x4F, 0x50, 0x30}
CMD_LEN_3 = {
    0x51,
    0x52,
    0x53,
    0x54,
    0x55,
    0x56,
    0x57,
    0x58,
    0x59,
    0x5A,
    0x5B,
    0x5C,
    0x5D,
    0x5E,
    0x5F,
    0xA0,
    0xBD,
}

WATCH_REGS = [
    0x00,
    0x01,
    0x02,
    0x03,
    0x04,
    0x05,
    0x08,
    0x09,
    0x0A,
    0x0B,
    0x0C,
    0x0D,
    0x10,
    0x11,
    0x12,
    0x14,
    0x15,
    0x16,
    0x18,
    0x19,
    0x1C,
]


def parse_vgm(path: Path):
    data = path.read_bytes()
    if data[:4] != b"Vgm ":
        raise ValueError(f"{path.name}: invalid VGM signature")
    off = int.from_bytes(data[0x34:0x38], "little")
    pos = 0x40 if off == 0 else (0x34 + off)
    if pos < 0x40:
        pos = 0x40
    t = 0
    waits = 0
    samples = 0
    opcodes = Counter()
    unknown = Counter()
    regs = defaultdict(list)
    saa_writes = []

    i = pos
    while i < len(data):
        c = data[i]
        opcodes[c] += 1
        if c == 0x66:
            break
        if c == 0x61 and i + 2 < len(data):
            n = int.from_bytes(data[i + 1 : i + 3], "little")
            t += n
            samples += n
            waits += 1
            i += 3
            continue
        if c == 0x62:
            t += 735
            samples += 735
            waits += 1
            i += 1
            continue
        if c == 0x63:
            t += 882
            samples += 882
            waits += 1
            i += 1
            continue
        if 0x70 <= c <= 0x7F:
            n = (c & 0x0F) + 1
            t += n
            samples += n
            waits += 1
            i += 1
            continue
        if c == 0x67 and i + 7 < len(data):
            size = int.from_bytes(data[i + 3 : i + 7], "little")
            i += 7 + size
            continue
        if c == 0xBD and i + 2 < len(data):
            reg = data[i + 1]
            val = data[i + 2]
            regs[reg].append(val)
            saa_writes.append((t / 44100.0, reg, val))
            i += 3
            continue
        if c in CMD_LEN_2:
            i += 2
            continue
        if c in CMD_LEN_3:
            i += 3
            continue
        unknown[c] += 1
        i += 1

    return {
        "waits": waits,
        "samples": samples,
        "opcodes": opcodes,
        "unknown": unknown,
        "regs": regs,
        "saa_writes": saa_writes,
    }


def fmt_values(vals):
    uniq = sorted(set(vals))
    nz = [v for v in uniq if v != 0]
    head = " ".join(f"{v:02X}" for v in nz[:16])
    more = "" if len(nz) <= 16 else f" ...(+{len(nz)-16})"
    return f"{len(vals):4d} writes | nonzero={head}{more}"


def main():
    ap = argparse.ArgumentParser(description="Analyze SAA1099 command stream in VGM files.")
    ap.add_argument("files", nargs="+", help="VGM files to inspect")
    ap.add_argument("--timeline", type=int, default=40, help="Number of first SAA writes to show")
    args = ap.parse_args()

    for file_arg in args.files:
        path = Path(file_arg)
        info = parse_vgm(path)
        print(f"\n=== {path.name} ===")
        print(
            f"duration={info['samples']/44100.0:.3f}s waits={info['waits']} "
            f"saa_writes={len(info['saa_writes'])}"
        )
        print("top opcodes:", ", ".join(f"{k:02X}:{v}" for k, v in info["opcodes"].most_common(8)))
        if info["unknown"]:
            print("unknown opcodes:", ", ".join(f"{k:02X}:{v}" for k, v in info["unknown"].most_common(8)))
        else:
            print("unknown opcodes: none")
        print("key register values:")
        for reg in WATCH_REGS:
            vals = info["regs"].get(reg)
            if vals:
                print(f"  reg {reg:02X}: {fmt_values(vals)}")
        print(f"first {args.timeline} SAA writes:")
        for t_sec, reg, val in info["saa_writes"][: args.timeline]:
            print(f"  t={t_sec:7.3f}s reg={reg:02X} val={val:02X}")


if __name__ == "__main__":
    main()
