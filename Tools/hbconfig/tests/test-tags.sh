#!/usr/bin/env bash
# hbconfig M2 tag-engine tests (run from Tools/hbconfig)
set -u
cd "$(dirname "$0")/.."
FX=tests/fixtures
fail=0

echo "== fx_ok (expect pass, exit 0) =="
./hbconfig.exe -check "$FX/fx_ok.asm"; rc=$?
[ $rc -eq 0 ] || { echo "FAIL: expected 0, got $rc"; fail=1; }

echo "== fx_broken (expect 1 BROKEN, exit 1) =="
out=$(./hbconfig.exe -check "$FX/fx_broken.asm"); rc=$?
echo "$out"
[ $rc -eq 1 ] || { echo "FAIL: expected 1, got $rc"; fail=1; }
n=$(echo "$out" | grep -c '^BROKEN')
[ "$n" -eq 1 ] || { echo "FAIL: expected 1 BROKEN, got $n"; fail=1; }

echo "== fx_badtag (expect 1 BAD TAG, exit 1) =="
out=$(./hbconfig.exe -check "$FX/fx_badtag.asm"); rc=$?
echo "$out"
[ $rc -eq 1 ] || { echo "FAIL: expected 1, got $rc"; fail=1; }
n=$(echo "$out" | grep -c '^BAD TAG')
[ "$n" -eq 1 ] || { echo "FAIL: expected 1 BAD TAG, got $n"; fail=1; }

echo "== in-tree configs still parse (corpus) =="
bash tests/run-corpus.sh | tail -1

echo "fail=$fail"
exit $fail
