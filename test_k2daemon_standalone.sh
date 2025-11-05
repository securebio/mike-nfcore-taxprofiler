#!/usr/bin/env bash
#
# Phase 1: Standalone k2 daemon testing
# Tests k2 daemon functionality outside of Nextflow to verify basic operation
#
set -euo pipefail

echo "=== Phase 1: Standalone k2 Daemon Test ==="
echo ""

# Configuration
TEST_DIR="./test_k2daemon_work"
DB_PATH="${1:-./test-datasets/kraken2_test_db}"  # First arg or default
READS_DIR="${2:-./test-datasets/reads}"          # Second arg or default

# Check if k2 is available
if ! command -v k2 &> /dev/null; then
    echo "ERROR: k2 command not found. Please ensure kraken2 with k2 script is installed."
    exit 1
fi

echo "✓ k2 command found: $(which k2)"
echo "  Version: $(k2 --version 2>&1 || echo 'Unable to determine version')"
echo ""

# Create test directory
mkdir -p "${TEST_DIR}"
cd "${TEST_DIR}"

echo "Test configuration:"
echo "  Database: ${DB_PATH}"
echo "  Reads: ${READS_DIR}"
echo "  Working directory: $(pwd)"
echo ""

# Check if database exists
if [ ! -d "../${DB_PATH}" ]; then
    echo "ERROR: Database not found at ../${DB_PATH}"
    echo "Please provide a valid kraken2 database path as the first argument."
    exit 1
fi

echo "=== Test 1: Single Sample Classification ==="
echo "Testing k2 daemon with a single sample..."

# Find test reads
SAMPLE1=$(find "../${READS_DIR}" -name "*.fastq.gz" -o -name "*.fq.gz" | head -n 1)

if [ -z "${SAMPLE1}" ]; then
    echo "ERROR: No FASTQ files found in ../${READS_DIR}"
    exit 1
fi

echo "  Using: ${SAMPLE1}"

# Run single sample with daemon
k2 classify \
    --use-daemon \
    --db "../${DB_PATH}" \
    --threads 2 \
    --report sample1.report.txt \
    --output sample1.output.txt \
    --gzip-compressed \
    "${SAMPLE1}"

if [ $? -eq 0 ] && [ -f "sample1.report.txt" ]; then
    echo "✓ Single sample classification succeeded"
    echo "  Report lines: $(wc -l < sample1.report.txt)"
else
    echo "✗ Single sample classification FAILED"
    k2 clean --stop-daemon
    exit 1
fi
echo ""

echo "=== Test 2: Multiple Sequential Classifications ==="
echo "Testing k2 daemon with multiple samples sequentially..."

# Find more test reads
SAMPLES=($(find "../${READS_DIR}" -name "*.fastq.gz" -o -name "*.fq.gz" | head -n 5))
SAMPLE_COUNT=${#SAMPLES[@]}

echo "  Found ${SAMPLE_COUNT} samples to test"

for i in "${!SAMPLES[@]}"; do
    SAMPLE="${SAMPLES[$i]}"
    PREFIX="sample_$((i+2))"
    echo "  Processing ${PREFIX}: $(basename ${SAMPLE})"

    k2 classify \
        --use-daemon \
        --db "../${DB_PATH}" \
        --threads 2 \
        --report "${PREFIX}.report.txt" \
        --output "${PREFIX}.output.txt" \
        --gzip-compressed \
        "${SAMPLE}" 2>&1 | head -n 20

    if [ $? -eq 0 ] && [ -f "${PREFIX}.report.txt" ]; then
        echo "    ✓ ${PREFIX} succeeded ($(wc -l < ${PREFIX}.report.txt) lines)"
    else
        echo "    ✗ ${PREFIX} FAILED"
        echo "    Stopping daemon and exiting..."
        k2 clean --stop-daemon
        exit 1
    fi
done

echo "✓ All sequential classifications succeeded"
echo ""

echo "=== Test 3: Stop Daemon ==="
k2 clean --stop-daemon

if [ $? -eq 0 ]; then
    echo "✓ Daemon stopped successfully"
else
    echo "✗ Failed to stop daemon"
    exit 1
fi
echo ""

echo "=== Summary ==="
echo "All standalone k2 daemon tests PASSED"
echo ""
echo "Generated files:"
ls -lh *.report.txt | awk '{print "  " $9 " (" $5 ")"}'
echo ""
echo "Next step: Run Phase 2 (module isolation test) with:"
echo "  bash test_k2daemon_module.sh"
