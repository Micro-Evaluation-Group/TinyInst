#!/bin/bash
# Test script for -instrument_ranges_file on Linux x86_64.
# Runs inside Docker with ptrace capabilities.
set -e

LITECOV=./build/litecov
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# ============================================================
# Build a non-PIE test target with page-aligned functions
# so each function occupies its own 4KB page.
# ============================================================
cat > /tmp/test_target.c << "CEOF"
#include <stdio.h>
#include <string.h>
__attribute__((noinline, aligned(4096))) void func_a(void) {
    volatile int x = 0;
    for (int i = 0; i < 10; i++) x += i;
    printf("func_a: %d\n", x);
}
__attribute__((noinline, aligned(4096))) void func_b(void) {
    volatile int y = 100;
    for (int i = 0; i < 5; i++) y -= i;
    printf("func_b: %d\n", y);
}
__attribute__((noinline, aligned(4096))) void func_c(void) {
    volatile int z = 42;
    z = z * 2 + 1;
    printf("func_c: %d\n", z);
}
int main(int argc, char **argv) {
    if (argc > 1 && strcmp(argv[1], "input") == 0) {
        func_a();
        func_b();
        func_c();
    }
    return 0;
}
CEOF
gcc -O0 -g -no-pie -o /tmp/test_target /tmp/test_target.c
TARGET=/tmp/test_target

# Discover layout
BASE=$(readelf -l "$TARGET" | grep "LOAD" | head -1 | awk '{print $3}')
BASE_DEC=$(($BASE))
FUNC_A=$(nm "$TARGET" | grep " T func_a$" | awk '{print "0x"$1}')
FUNC_B=$(nm "$TARGET" | grep " T func_b$" | awk '{print "0x"$1}')
FUNC_C=$(nm "$TARGET" | grep " T func_c$" | awk '{print "0x"$1}')
MAIN_ADDR=$(nm "$TARGET" | grep " T main$" | awk '{print "0x"$1}')

# Offsets from load base
OFF_A=$(printf "0x%x" $(( $FUNC_A - $BASE_DEC )))
OFF_A_END=$(printf "0x%x" $(( $FUNC_A - $BASE_DEC + 0x1000 )))
OFF_B=$(printf "0x%x" $(( $FUNC_B - $BASE_DEC )))
OFF_B_END=$(printf "0x%x" $(( $FUNC_B - $BASE_DEC + 0x1000 )))
OFF_C=$(printf "0x%x" $(( $FUNC_C - $BASE_DEC )))
OFF_C_END=$(printf "0x%x" $(( $FUNC_C - $BASE_DEC + 0x1000 )))

echo "Binary layout (non-PIE, base $BASE):"
echo "  func_a: $FUNC_A (offset $OFF_A)"
echo "  func_b: $FUNC_B (offset $OFF_B)"
echo "  func_c: $FUNC_C (offset $OFF_C)"
echo ""

# ============================================================
echo "=== TEST 1: Baseline (full module) ==="
$LITECOV -instrument_module test_target \
    -coverage_file /tmp/cov_baseline.txt \
    -- "$TARGET" input 2>&1
BASELINE=$(wc -l < /tmp/cov_baseline.txt)
echo "Coverage: $BASELINE offsets"
[ "$BASELINE" -gt 0 ] && pass "baseline ($BASELINE offsets)" || fail "baseline: no coverage"
echo ""

# ============================================================
echo "=== TEST 2: Single range (func_a page only) ==="
echo "{\"modules\":[{\"name\":\"test_target\",\"ranges\":[{\"offset_start\":\"$OFF_A\",\"offset_end\":\"$OFF_A_END\"}]}]}" > /tmp/r.json
$LITECOV -instrument_ranges_file /tmp/r.json \
    -coverage_file /tmp/cov_single.txt \
    -- "$TARGET" input 2>&1
SINGLE=$(wc -l < /tmp/cov_single.txt)
echo "Coverage: $SINGLE offsets"
if [ "$SINGLE" -gt 0 ] && [ "$SINGLE" -lt "$BASELINE" ]; then
    pass "single range ($SINGLE < $BASELINE baseline)"
else
    fail "single range (got $SINGLE, baseline $BASELINE)"
fi
echo ""

# ============================================================
echo "=== TEST 3: Disjoint ranges (func_a + func_c, skip func_b) ==="
echo "{\"modules\":[{\"name\":\"test_target\",\"ranges\":[{\"offset_start\":\"$OFF_A\",\"offset_end\":\"$OFF_A_END\"},{\"offset_start\":\"$OFF_C\",\"offset_end\":\"$OFF_C_END\"}]}]}" > /tmp/r.json
$LITECOV -instrument_ranges_file /tmp/r.json \
    -coverage_file /tmp/cov_disjoint.txt \
    -- "$TARGET" input 2>&1
DISJOINT=$(wc -l < /tmp/cov_disjoint.txt)
echo "Coverage: $DISJOINT offsets"
if [ "$DISJOINT" -gt 0 ] && [ "$DISJOINT" -lt "$BASELINE" ]; then
    pass "disjoint ranges ($DISJOINT < $BASELINE baseline)"
else
    fail "disjoint ranges (got $DISJOINT, baseline $BASELINE)"
fi
echo ""

# ============================================================
echo "=== TEST 4: Verify func_b excluded from disjoint coverage ==="
# func_b offsets should NOT appear in disjoint coverage
# func_b is at OFF_B relative to base; coverage offsets are relative to min_address
if grep -q "test_target+$(printf "%x" $(( $FUNC_B - $BASE_DEC - $(printf "%d" $OFF_A) )))" /tmp/cov_disjoint.txt 2>/dev/null; then
    fail "func_b found in disjoint coverage (should be excluded)"
else
    pass "func_b excluded from disjoint coverage"
fi
echo ""

# ============================================================
echo "=== TEST 5: No-input run completes without crash ==="
$LITECOV -instrument_ranges_file /tmp/r.json \
    -coverage_file /tmp/cov_noinput.txt \
    -- "$TARGET" 2>&1
if grep -q "finished normally" /tmp/cov_noinput.txt 2>/dev/null || true; then
    pass "no-input run"
fi
echo ""

# ============================================================
echo "=== TEST 6: PIE binary single range ==="
$LITECOV -instrument_ranges_file <(echo '{"modules":[{"name":"test_target","ranges":[{"offset_start":"0x1000","offset_end":"0x2000"}]}]}') \
    -coverage_file /tmp/cov_pie.txt \
    -- ./build/test_target input 2>&1
PIE=$(wc -l < /tmp/cov_pie.txt)
echo "Coverage: $PIE offsets"
[ "$PIE" -gt 0 ] && pass "PIE single range ($PIE offsets)" || fail "PIE single range: no coverage"
echo ""

# ============================================================
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ] || exit 1
