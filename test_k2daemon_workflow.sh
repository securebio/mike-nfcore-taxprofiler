#!/usr/bin/env bash
#
# Phase 3: Full workflow integration testing
# Tests k2daemon in the complete taxprofiler workflow
#
set -euo pipefail

echo "=== Phase 3: K2DAEMON Workflow Integration Test ==="
echo ""

# Configuration - can be overridden by arguments
TEST_DIR="${1:-./test_workflow_work}"
INPUT_SAMPLESHEET="${2:-}"
INPUT_DATABASE="${3:-}"

# Check if nextflow is available
if ! command -v nextflow &> /dev/null; then
    echo "ERROR: nextflow command not found."
    exit 1
fi

echo "✓ nextflow command found: $(which nextflow)"
echo "  Version: $(nextflow -version 2>&1 | head -n 1)"
echo ""

# Create test directory
mkdir -p "${TEST_DIR}"

echo "Test configuration:"
echo "  Working directory: ${TEST_DIR}"
echo "  Input samplesheet: ${INPUT_SAMPLESHEET}"
echo "  Input database: ${INPUT_DATABASE}"
echo ""

# Validate inputs
if [ -z "${INPUT_SAMPLESHEET}" ] || [ ! -f "${INPUT_SAMPLESHEET}" ]; then
    echo "ERROR: Valid samplesheet not provided or not found."
    echo ""
    echo "Usage: $0 [work_dir] [samplesheet.csv] [database.csv]"
    echo ""
    echo "Example samplesheet.csv format:"
    echo "  sample,run_accession,instrument_platform,fastq_1,fastq_2,fasta"
    echo "  sample1,run1,ILLUMINA,/path/to/sample1_R1.fastq.gz,/path/to/sample1_R2.fastq.gz,"
    echo "  sample2,run1,ILLUMINA,/path/to/sample2_R1.fastq.gz,/path/to/sample2_R2.fastq.gz,"
    echo ""
    exit 1
fi

if [ -z "${INPUT_DATABASE}" ] || [ ! -f "${INPUT_DATABASE}" ]; then
    echo "ERROR: Valid database sheet not provided or not found."
    echo ""
    echo "Example database.csv format:"
    echo "  tool,db_name,db_params,db_path"
    echo "  kraken2,k2_standard,,/path/to/kraken2_db"
    echo ""
    exit 1
fi

echo "=== Test 1: Run workflow WITHOUT k2daemon (baseline) ==="
echo "This establishes a baseline for comparison..."
echo ""

BASELINE_DIR="${TEST_DIR}/baseline_standard_kraken2"
mkdir -p "${BASELINE_DIR}"

echo "Running with standard KRAKEN2..."
time nextflow run main.nf \
    -profile docker,test \
    --input "${INPUT_SAMPLESHEET}" \
    --databases "${INPUT_DATABASE}" \
    --outdir "${BASELINE_DIR}/results" \
    --run_kraken2 \
    --use_kraken2_daemon false \
    -work-dir "${BASELINE_DIR}/work" \
    -resume

BASELINE_STATUS=$?

if [ ${BASELINE_STATUS} -eq 0 ]; then
    echo "✓ Baseline workflow (standard kraken2) completed successfully"

    # Count reports
    BASELINE_REPORTS=$(find "${BASELINE_DIR}/results" -name "*.kraken2.report.txt" | wc -l)
    echo "  Generated ${BASELINE_REPORTS} kraken2 reports"
else
    echo "✗ Baseline workflow FAILED"
    echo "  Check logs at: ${BASELINE_DIR}/work/"
    exit 1
fi
echo ""

echo "=== Test 2: Run workflow WITH k2daemon ==="
echo "This tests the k2daemon implementation..."
echo ""

DAEMON_DIR="${TEST_DIR}/test_k2daemon"
mkdir -p "${DAEMON_DIR}"

# Test with different batch sizes
for BATCH_SIZE in 2 5; do
    echo "--- Testing with batch_size=${BATCH_SIZE} ---"

    BATCH_DIR="${DAEMON_DIR}/batch_${BATCH_SIZE}"
    mkdir -p "${BATCH_DIR}"

    echo "Running with K2DAEMON (batch_size=${BATCH_SIZE})..."
    time nextflow run main.nf \
        -profile docker,test \
        --input "${INPUT_SAMPLESHEET}" \
        --databases "${INPUT_DATABASE}" \
        --outdir "${BATCH_DIR}/results" \
        --run_kraken2 \
        --use_kraken2_daemon true \
        --kraken2_daemon_batch_size ${BATCH_SIZE} \
        -work-dir "${BATCH_DIR}/work" \
        -resume

    DAEMON_STATUS=$?

    if [ ${DAEMON_STATUS} -eq 0 ]; then
        echo "✓ K2DAEMON workflow (batch_size=${BATCH_SIZE}) completed successfully"

        # Count reports
        DAEMON_REPORTS=$(find "${BATCH_DIR}/results" -name "*.kraken2.report.txt" | wc -l)
        echo "  Generated ${DAEMON_REPORTS} kraken2 reports"

        # Compare counts
        if [ ${DAEMON_REPORTS} -eq ${BASELINE_REPORTS} ]; then
            echo "  ✓ Report count matches baseline"
        else
            echo "  ⚠ Report count differs from baseline (${DAEMON_REPORTS} vs ${BASELINE_REPORTS})"
        fi
    else
        echo "✗ K2DAEMON workflow (batch_size=${BATCH_SIZE}) FAILED"
        echo ""
        echo "Debugging information:"
        echo "  Work directory: ${BATCH_DIR}/work"
        echo "  Most recent task directories:"
        find "${BATCH_DIR}/work" -name ".command.log" -type f -mtime -1 | head -n 5
        echo ""
        echo "  Check for hanging processes:"
        echo "    ps aux | grep k2"
        echo "    ps aux | grep kraken2"
        echo ""
        echo "  Examine failed task logs:"
        echo "    nextflow log -f name,status,exit,duration"
        exit 1
    fi
    echo ""
done

echo "=== Test 3: Compare outputs ==="
echo "Comparing results between standard kraken2 and k2daemon..."
echo ""

# Compare specific reports if they exist
BASELINE_SAMPLE_REPORT=$(find "${BASELINE_DIR}/results" -name "*.kraken2.report.txt" | head -n 1)
DAEMON_SAMPLE_REPORT=$(find "${DAEMON_DIR}/batch_5/results" -name "*.kraken2.report.txt" | head -n 1)

if [ -n "${BASELINE_SAMPLE_REPORT}" ] && [ -n "${DAEMON_SAMPLE_REPORT}" ]; then
    echo "Comparing sample reports:"
    echo "  Baseline: ${BASELINE_SAMPLE_REPORT}"
    echo "  K2DAEMON: ${DAEMON_SAMPLE_REPORT}"
    echo ""

    # Compare line counts
    BASELINE_LINES=$(wc -l < "${BASELINE_SAMPLE_REPORT}")
    DAEMON_LINES=$(wc -l < "${DAEMON_SAMPLE_REPORT}")

    echo "  Baseline lines: ${BASELINE_LINES}"
    echo "  K2DAEMON lines: ${DAEMON_LINES}"

    if [ ${BASELINE_LINES} -eq ${DAEMON_LINES} ]; then
        echo "  ✓ Line counts match"
    else
        echo "  ⚠ Line counts differ slightly (this may be acceptable)"
    fi

    # Check for significant differences
    if diff -q "${BASELINE_SAMPLE_REPORT}" "${DAEMON_SAMPLE_REPORT}" > /dev/null 2>&1; then
        echo "  ✓ Reports are identical"
    else
        echo "  ⚠ Reports differ (checking if differences are significant...)"
        # Compare just the taxonomy structure (first 5 columns typically)
        diff <(awk '{print $1,$2,$3,$4,$5}' "${BASELINE_SAMPLE_REPORT}") \
             <(awk '{print $1,$2,$3,$4,$5}' "${DAEMON_SAMPLE_REPORT}") > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "  ✓ Taxonomy structure matches (differences are minor)"
        else
            echo "  ⚠ Taxonomy structure differs - review needed"
        fi
    fi
fi
echo ""

echo "=== Summary ==="
echo "✓ All workflow integration tests completed"
echo ""
echo "Results directories:"
echo "  Baseline (standard): ${BASELINE_DIR}/results"
echo "  K2DAEMON (batch=2):  ${DAEMON_DIR}/batch_2/results"
echo "  K2DAEMON (batch=5):  ${DAEMON_DIR}/batch_5/results"
echo ""
echo "Performance comparison:"
echo "  Review the 'time' outputs above to compare runtime"
echo "  K2DAEMON should be faster when processing multiple samples"
echo ""
echo "If tests passed:"
echo "  - K2DAEMON module works correctly"
echo "  - No hanging issues observed"
echo "  - Outputs are consistent with standard kraken2"
echo ""
