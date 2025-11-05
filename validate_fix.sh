#!/usr/bin/env bash
#
# Quick validation script to verify the K2DAEMON fix is applied
#
set -euo pipefail

echo "=== K2DAEMON Fix Validation ==="
echo ""

# Check if we're on the correct branch
CURRENT_BRANCH=$(git branch --show-current)
EXPECTED_BRANCH="claude/review-k2daemon-branch-011CUpnBmYYmqj9B1uYMBoj4"

if [ "${CURRENT_BRANCH}" != "${EXPECTED_BRANCH}" ]; then
    echo "⚠ Warning: You're on branch '${CURRENT_BRANCH}'"
    echo "  Expected branch: '${EXPECTED_BRANCH}'"
    echo ""
fi

# Check if module file exists
MODULE_FILE="modules/local/kraken2/k2daemon/main.nf"
if [ ! -f "${MODULE_FILE}" ]; then
    echo "✗ ERROR: K2DAEMON module not found at ${MODULE_FILE}"
    exit 1
fi

echo "✓ K2DAEMON module found"
echo ""

# Check for --gzip-compressed flag
echo "Checking for --gzip-compressed flag..."
GZIP_LINES=$(grep -n "gzip-compressed" "${MODULE_FILE}" || true)

if [ -z "${GZIP_LINES}" ]; then
    echo "✗ ERROR: --gzip-compressed flag NOT found!"
    echo "  The fix has not been applied."
    exit 1
fi

# Count occurrences (should be 2: single-end and paired-end)
GZIP_COUNT=$(echo "${GZIP_LINES}" | wc -l)

echo "✓ Found --gzip-compressed flag (${GZIP_COUNT} occurrences)"
echo ""
echo "Locations:"
echo "${GZIP_LINES}" | sed 's/^/  /'
echo ""

if [ ${GZIP_COUNT} -eq 2 ]; then
    echo "✓ Correct: Flag present for both single-end and paired-end processing"
else
    echo "⚠ Warning: Expected 2 occurrences, found ${GZIP_COUNT}"
fi
echo ""

# Check test scripts exist
echo "Checking test scripts..."
TEST_SCRIPTS=(
    "test_k2daemon_standalone.sh"
    "test_k2daemon_module.sh"
    "test_k2daemon_workflow.sh"
)

ALL_SCRIPTS_FOUND=true
for script in "${TEST_SCRIPTS[@]}"; do
    if [ -f "${script}" ] && [ -x "${script}" ]; then
        echo "  ✓ ${script}"
    elif [ -f "${script}" ]; then
        echo "  ⚠ ${script} (not executable - run: chmod +x ${script})"
    else
        echo "  ✗ ${script} (missing)"
        ALL_SCRIPTS_FOUND=false
    fi
done
echo ""

# Check documentation
echo "Checking documentation..."
if [ -f "K2DAEMON_TESTING_GUIDE.md" ]; then
    echo "  ✓ K2DAEMON_TESTING_GUIDE.md"
fi
if [ -f "QUICK_START_TESTING.md" ]; then
    echo "  ✓ QUICK_START_TESTING.md"
fi
echo ""

# Summary
echo "=== Summary ==="
if [ ${GZIP_COUNT} -eq 2 ] && [ "${ALL_SCRIPTS_FOUND}" = "true" ]; then
    echo "✅ All validation checks PASSED"
    echo ""
    echo "The fix has been applied correctly. You can now run tests:"
    echo "  ./test_k2daemon_module.sh       # Recommended: Quick module test"
    echo "  ./test_k2daemon_workflow.sh ... # Full workflow test"
    echo ""
    echo "See QUICK_START_TESTING.md for detailed instructions."
else
    echo "⚠ Some validation checks failed"
    echo ""
    echo "Please ensure you have:"
    echo "  1. Checked out the correct branch"
    echo "  2. Pulled the latest changes"
    echo "  3. Made test scripts executable: chmod +x test_k2daemon_*.sh"
fi
