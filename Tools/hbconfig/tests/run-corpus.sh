#!/usr/bin/env bash
# hbconfig M1 corpus test: run -show over every in-tree HBIOS config.
# Every config must parse cleanly (exit 0). Output goes to tests/out/.
set -u
cd "$(dirname "$0")/.."
HBIOS=../../Source/HBIOS
mkdir -p tests/out
fail=0
count=0
for cfg in "$HBIOS"/Config/*.asm "$HBIOS"/Config/*.ASM; do
    [ -e "$cfg" ] || continue
    count=$((count+1))
    base=$(basename "$cfg" .asm); base=$(basename "$base" .ASM)
    if ! ./hbconfig.exe -show "$cfg" > "tests/out/$base.txt" 2>"tests/out/$base.err"; then
        echo "FAIL: $cfg"
        cat "tests/out/$base.err"
        fail=1
    fi
done
echo "parsed $count configs, fail=$fail"
exit $fail
