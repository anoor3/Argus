#!/usr/bin/env bash
# ============================================================================
# scripts/regression.sh -- one-command full regression for ARGUS.
#
# Runs the RTL self-checking testbenches (via the Makefile) and the Python host
# unit tests, and reports a single pass/fail verdict. Intended for a clean
# checkout: it makes no assumptions beyond iverilog + python3 on PATH.
# ============================================================================
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0

echo "=================================================="
echo " ARGUS REGRESSION"
echo "=================================================="

echo
echo "--- RTL testbenches (iverilog) ---"
if command -v iverilog >/dev/null 2>&1; then
    # Run each testbench; count failures.
    for tb in tb/*_tb.sv; do
        name="$(basename "$tb" _tb.sv)"
        if make --no-print-directory "$name" >/tmp/argus_$name.log 2>&1; then
            echo "  PASS  $name"
        else
            echo "  FAIL  $name (see /tmp/argus_$name.log)"
            fail=1
        fi
    done
else
    echo "  SKIP: iverilog not found on PATH"
    fail=1
fi

echo
echo "--- Host unit tests (python3) ---"
if command -v python3 >/dev/null 2>&1; then
    if ( cd host && python3 -m unittest discover -s tests >/tmp/argus_host.log 2>&1 ); then
        echo "  PASS  host unittests"
    else
        echo "  FAIL  host unittests (see /tmp/argus_host.log)"
        fail=1
    fi
else
    echo "  SKIP: python3 not found on PATH"
    fail=1
fi

echo
echo "=================================================="
if [ "$fail" -eq 0 ]; then
    echo " REGRESSION RESULT: PASS"
else
    echo " REGRESSION RESULT: FAIL"
fi
echo "=================================================="
exit $fail
