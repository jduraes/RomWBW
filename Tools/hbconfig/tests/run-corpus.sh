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

# picker source list: every Config/*.asm except cfg_*.asm must appear as
# "<plat> <conf>", sorted, with no cfg_ leakage
cd "$HBIOS"
n_list=$(../../Tools/hbconfig/hbconfig.exe -listcfgs | wc -l)
n_cfg=$(ls Config/*.asm Config/*.ASM 2>/dev/null | grep -vc '/cfg_')
../../Tools/hbconfig/hbconfig.exe -listcfgs | grep -i '^cfg_' && { echo "FAIL: cfg_ leaked into -listcfgs"; fail=1; }
[ "$n_list" = "$n_cfg" ] || { echo "FAIL: -listcfgs count $n_list != config files $n_cfg"; fail=1; }
../../Tools/hbconfig/hbconfig.exe -listcfgs | grep -q '^SCZ180 sc126_std$' || { echo "FAIL: SCZ180 sc126_std missing"; fail=1; }
echo "listcfgs $n_list entries, fail=$fail"
exit $fail
