#!/usr/bin/env bash
#
# Phase 2: Module isolation testing
# Tests the KRAKEN2_K2DAEMON Nextflow module in isolation
#
set -euo pipefail

echo "=== Phase 2: K2DAEMON Module Isolation Test ==="
echo ""

# Check if nf-test is available
if ! command -v nf-test &> /dev/null; then
    echo "ERROR: nf-test command not found."
    echo "Please install nf-test: https://code.askimed.com/nf-test/"
    exit 1
fi

echo "✓ nf-test command found: $(which nf-test)"
echo "  Version: $(nf-test version 2>&1 || echo 'Unable to determine version')"
echo ""

# Check if module exists
MODULE_PATH="modules/local/kraken2/k2daemon"
if [ ! -d "${MODULE_PATH}" ]; then
    echo "ERROR: Module directory not found at ${MODULE_PATH}"
    exit 1
fi

echo "✓ K2DAEMON module found at ${MODULE_PATH}"
echo ""

# Check if test file exists
TEST_FILE="${MODULE_PATH}/tests/main.nf.test"
if [ ! -f "${TEST_FILE}" ]; then
    echo "ERROR: Test file not found at ${TEST_FILE}"
    exit 1
fi

echo "✓ Test file found at ${TEST_FILE}"
echo ""

echo "=== Test 1: Run nf-test for K2DAEMON module ==="
echo "This will test the module with the test dataset..."
echo ""

# Run nf-test
nf-test test "${TEST_FILE}" --verbose

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Module tests PASSED"
else
    echo ""
    echo "✗ Module tests FAILED"
    echo ""
    echo "Debugging tips:"
    echo "  1. Check .nf-test/tests/ directory for test outputs"
    echo "  2. Review test logs for error messages"
    echo "  3. Verify test data is available at the specified paths"
    echo "  4. Try running a single test:"
    echo "     nf-test test ${TEST_FILE} --tag 'single-end'"
    exit 1
fi

echo ""
echo "=== Test 2: Inspect Module Test Outputs ==="
TEST_OUTPUT_DIR=".nf-test/tests"
if [ -d "${TEST_OUTPUT_DIR}" ]; then
    echo "Test output directory: ${TEST_OUTPUT_DIR}"
    echo ""
    echo "Recent test work directories:"
    find "${TEST_OUTPUT_DIR}" -name "work" -type d -mtime -1 | head -n 5
    echo ""

    echo "Looking for kraken2 reports generated during tests..."
    REPORTS=$(find "${TEST_OUTPUT_DIR}" -name "*.kraken2.report.txt" -mtime -1 2>/dev/null | head -n 5)
    if [ -n "${REPORTS}" ]; then
        echo "Found test reports:"
        echo "${REPORTS}" | while read report; do
            echo "  - ${report} ($(wc -l < "${report}") lines)"
        done
    else
        echo "  (No recent reports found - this may be normal if outputs are cleaned)"
    fi
fi
echo ""

echo "=== Summary ==="
echo "✓ K2DAEMON module tests PASSED"
echo ""
echo "The module successfully processes batches of samples using k2 daemon mode."
echo ""
echo "Next step: Run Phase 3 (workflow integration test) with:"
echo "  bash test_k2daemon_workflow.sh <path_to_test_data>"
