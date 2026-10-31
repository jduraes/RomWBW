#!/usr/bin/env bash
# hbconfig M3 writer tests (run from Tools/hbconfig)
set -u
cd "$(dirname "$0")/.."
fail=0
say() { echo "== $* =="; }
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fresh() { rm -rf "$WORK/fx"; cp -r tests/fixtures "$WORK/fx"; }

say "no-edit write is a no-op"
fresh
out=$(./hbconfig.exe -write "$WORK/fx/fx_ok.asm"); rc=$?
echo "$out"
{ [ $rc -eq 0 ] && echo "$out" | grep -q "no changes"; } || { echo FAIL; fail=1; }
cmp -s "$WORK/fx/fx_ok.asm" tests/fixtures/fx_ok.asm || { echo "FAIL: file touched"; fail=1; }

say "replace existing value with identical value = no change"
fresh
out=$(./hbconfig.exe -write "$WORK/fx/fx_ok.asm" FOOENABLE=TRUE); rc=$?
echo "$out"
echo "$out" | grep -q "no changes" || { echo "FAIL: expected no changes"; fail=1; }
cmp -s "$WORK/fx/fx_ok.asm" tests/fixtures/fx_ok.asm || { echo "FAIL: file changed"; fail=1; }

say "replace existing value (fx_std INTMODE 2->3), comment + layout preserved"
fresh
out=$(./hbconfig.exe -write "$WORK/fx/fx_std.asm" INTMODE=3); rc=$?
echo "$out"; [ $rc -eq 0 ] || { echo FAIL; fail=1; }
line=$(grep 'INTMODE' "$WORK/fx/fx_std.asm" | tail -1)
echo "now: [$line]"
# original line had no comment: spacing before/after value must be preserved
[ "$line" = "INTMODE     .SET    3" ] || { echo "FAIL: layout damaged"; fail=1; }

say "set back to inherited value removes own .SET line"
fresh
# fx_ok sets FOOENABLE TRUE; inherited (master) is FALSE
out=$(./hbconfig.exe -write "$WORK/fx/fx_ok.asm" FOOENABLE=FALSE); rc=$?
echo "$out"; [ $rc -eq 0 ] || { echo FAIL; fail=1; }
grep -q '^FOOENABLE' "$WORK/fx/fx_ok.asm" && { echo "FAIL: FOOENABLE not removed"; fail=1; }

say "append new setting (FOOMODE=MD_GAMMA) with master comment, house layout"
fresh
out=$(./hbconfig.exe -write "$WORK/fx/fx_ok.asm" FOOMODE=MD_GAMMA); rc=$?
echo "$out"; [ $rc -eq 0 ] || { echo FAIL; fail=1; }
line=$(grep 'FOOMODE' "$WORK/fx/fx_ok.asm" | tail -1)
echo "appended: [$line]"
echo "$line" | grep -q 'FOOMODE' || { echo FAIL; fail=1; }
printf '%s' "$line" | grep -qP '^FOOMODE\t+\.SET\t+MD_GAMMA' \
  || { echo "FAIL: house layout (tab columns) not used"; fail=1; }
# (fixture master is not cfg_MASTER.asm, so no comment here; the real-master
#  append test below covers the comment)

say "removal swallows indented continuation comments"
fresh
printf 'FOOADDR\t.SET\t$C0\t\t; local override\n\t\t; continuation note\n; full comment stays\n' >> "$WORK/fx/fx_ok.asm"
./hbconfig.exe -write "$WORK/fx/fx_ok.asm" 'FOOADDR=$80' >/dev/null
grep -q 'local override' "$WORK/fx/fx_ok.asm" && { echo "FAIL: .SET line not removed"; fail=1; }
grep -q 'continuation note' "$WORK/fx/fx_ok.asm" && { echo "FAIL: continuation not removed"; fail=1; }
grep -q 'full comment stays' "$WORK/fx/fx_ok.asm" || { echo "FAIL: column-0 comment removed"; fail=1; }

say "CRLF file keeps CRLF"
fresh
python - "$WORK/fx/fx_ok.asm" <<'PYEOF'
import sys
p = sys.argv[1]
d = open(p, 'rb').read().replace(b'\n', b'\r\n')
open(p, 'wb').write(d)
PYEOF
./hbconfig.exe -write "$WORK/fx/fx_ok.asm" BARENABLE=FALSE >/dev/null
python - "$WORK/fx/fx_ok.asm" <<'PYEOF'
import sys
d = open(sys.argv[1], 'rb').read()
n_lf = d.count(b'\n'); n_crlf = d.count(b'\r\n')
print("CRLF" if n_lf == n_crlf and n_lf > 0 else "MIXED/LF")
sys.exit(0 if n_lf == n_crlf and n_lf > 0 else 1)
PYEOF
[ $? -eq 0 ] || { echo "FAIL: CRLF lost"; fail=1; }

say "unknown setting rejected"
fresh
./hbconfig.exe -write "$WORK/fx/fx_ok.asm" NOSUCHTHING=1 >/dev/null 2>&1 \
  && { echo "FAIL: should have failed"; fail=1; } || echo "rejected OK"

say "in-tree round-trip: self-assignment leaves every config byte-identical"
HBIOS=../../Source/HBIOS
changed=0
for cfg in "$HBIOS"/Config/*.asm; do
    [ -e "$cfg" ] || continue
    line=$(./hbconfig.exe -show "$cfg" | awk -v C="$cfg" '$1 !~ /^;/ && index($NF, C) {print $1"="$2; exit}')
    [ -z "$line" ] && continue
    before=$(md5sum "$cfg" | cut -d' ' -f1)
    ./hbconfig.exe -write "$cfg" "$line" >/dev/null
    after=$(md5sum "$cfg" | cut -d' ' -f1)
    if [ "$before" != "$after" ]; then
        echo "FAIL: $cfg changed by self-assignment ($line)"
        changed=1; fail=1
    fi
done
[ $changed -eq 0 ] && echo "all configs byte-identical after self-assignment"

say "append against real master carries the master comment"
REAL=../../Source/HBIOS/Config/SCZ180_sc126_std.asm
before=$(md5sum "$REAL" | cut -d' ' -f1)
out=$(./hbconfig.exe -write "$REAL" CTCENABLE=TRUE); rc=$?
echo "$out"
line=$(grep 'CTCENABLE' "$REAL" | tail -1)
echo "appended: [$line]"
cd ../.. && git checkout -- Source/HBIOS/Config/SCZ180_sc126_std.asm && cd Tools/hbconfig
[ $rc -eq 0 ] || { echo FAIL; fail=1; }
printf '%s' "$line" | grep -q 'ENABLE ZILOG CTC SUPPORT' || { echo "FAIL: master comment missing"; fail=1; }

say "git tree stays clean"
cd ../..
if [ -n "$(git status --porcelain -- Source/HBIOS/Config)" ]; then
    git status --porcelain -- Source/HBIOS/Config | head -5
    echo "FAIL: config tree dirty"; fail=1
else
    echo "clean"
fi
cd Tools/hbconfig

echo "fail=$fail"
exit $fail
