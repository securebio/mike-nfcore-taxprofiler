# K2DAEMON Testing and Debugging Guide

## Overview

This guide provides a comprehensive testing strategy for the K2DAEMON module implementation in nf-core/taxprofiler. It addresses the reported hanging issue and provides incremental validation steps.

## Problem Description

When testing the k2daemon branch with 10 samples split into two batches (5 samples each), the K2DAEMON process appeared to hang:
- One batch hung after processing 1 sample
- Another batch hung after processing 2 samples
- Kraken2 results for these samples were present in the work directory

## Root Cause Analysis

### Primary Issue: Missing `--gzip-compressed` Flag

The K2DAEMON module was **missing the `--gzip-compressed` flag** that's present in the standard KRAKEN2 module. This flag is essential because:

1. **Taxprofiler uses gzipped FASTQ files** as input
2. **Without this flag**, kraken2/k2 attempts to read files as uncompressed
3. **This causes**:
   - Hanging while waiting for uncompressed input
   - Incorrect file parsing
   - Incomplete processing of samples

### Comparison with Standard KRAKEN2

**Standard KRAKEN2 module** (`modules/nf-core/kraken2/kraken2/main.nf:42`):
```groovy
kraken2 \\
    --db $db \\
    --threads $task.cpus \\
    --report ${prefix}.kraken2.report.txt \\
    --gzip-compressed \\     # ← Present
    ...
```

**K2DAEMON module** (original):
```groovy
k2 classify \\
    --use-daemon \\
    --db ${db} \\
    --threads ${task.cpus} \\
    --report \${PREFIX}.kraken2.report.txt \\
    # ← Missing --gzip-compressed
    ...
```

## Fix Applied

Added `--gzip-compressed` flag to both single-end and paired-end k2 classify commands in `modules/local/kraken2/k2daemon/main.nf`:

**Lines 54 and 92**: Added `--gzip-compressed \\` before the classified/unclassified options.

## Incremental Testing Strategy (Option C)

### Phase 1: Standalone k2 Daemon Testing

**Purpose**: Verify k2 daemon works outside Nextflow environment

**Script**: `test_k2daemon_standalone.sh`

**Usage**:
```bash
# Make executable
chmod +x test_k2daemon_standalone.sh

# Run with default paths (modify script if needed)
./test_k2daemon_standalone.sh [database_path] [reads_directory]

# Example
./test_k2daemon_standalone.sh ./kraken2_db ./test_reads
```

**What it tests**:
1. Single sample classification with daemon
2. Multiple sequential classifications (up to 5 samples)
3. Daemon stop functionality
4. Output file generation

**Expected outcome**: All samples process successfully without hanging

**If it fails**:
- k2 installation may be incorrect
- Database may be corrupted
- System may lack required resources
- Check k2 version compatibility

### Phase 2: Module Isolation Testing

**Purpose**: Test the KRAKEN2_K2DAEMON Nextflow module independently

**Script**: `test_k2daemon_module.sh`

**Prerequisites**:
- nf-test installed (`https://code.askimed.com/nf-test/`)
- Test data available (specified in `modules/local/kraken2/k2daemon/tests/main.nf.test`)

**Usage**:
```bash
# Make executable
chmod +x test_k2daemon_module.sh

# Run module tests
./test_k2daemon_module.sh
```

**What it tests**:
1. Single-end batch processing
2. Paired-end batch processing
3. Output file generation (reports, classified/unclassified reads)
4. Stub execution

**Expected outcome**: All nf-test assertions pass

**If it fails**:
- Check test data paths in `modules/local/kraken2/k2daemon/tests/main.nf.test`
- Review `.nf-test/tests/` directory for detailed logs
- Verify module syntax is correct
- Run individual tests: `nf-test test modules/local/kraken2/k2daemon/tests/main.nf.test --tag single-end`

### Phase 3: Full Workflow Integration Testing

**Purpose**: Test k2daemon in complete taxprofiler workflow

**Script**: `test_k2daemon_workflow.sh`

**Prerequisites**:
- Nextflow installed
- Valid samplesheet.csv
- Valid database.csv
- Sufficient computational resources

**Usage**:
```bash
# Make executable
chmod +x test_k2daemon_workflow.sh

# Run workflow tests
./test_k2daemon_workflow.sh [work_dir] [samplesheet.csv] [database.csv]

# Example
./test_k2daemon_workflow.sh ./test_work ./samples.csv ./databases.csv
```

**What it tests**:
1. Baseline run with standard KRAKEN2 (for comparison)
2. K2DAEMON with batch_size=2
3. K2DAEMON with batch_size=5
4. Output comparison between standard and daemon modes
5. Performance comparison

**Expected outcome**:
- All runs complete successfully
- Output counts match between standard and daemon modes
- K2DAEMON shows performance improvement
- No hanging observed

**If it fails**:
Check for:
1. **Hanging issues**:
   ```bash
   # Check for stuck processes
   ps aux | grep k2
   ps aux | grep kraken2

   # Examine task logs
   tail -f <work_dir>/work/*/.command.log
   ```

2. **Output differences**:
   - Compare report files
   - Check sample counts
   - Verify batch processing

3. **Resource issues**:
   - Memory limitations
   - CPU availability
   - Disk space

## Testing Checklist

- [ ] **Phase 1**: Standalone k2 daemon test passes
- [ ] **Phase 2**: Module isolation tests pass
- [ ] **Phase 3**: Workflow integration tests pass
- [ ] **Verification**: Outputs match between standard and daemon modes
- [ ] **Performance**: K2DAEMON shows speedup over standard mode
- [ ] **Scale test**: Test with original 10-sample dataset (2 batches of 5)

## Additional Testing Considerations

### Small-Scale Testing

Start with minimal datasets:
- 2 samples (1 batch)
- 5 samples (1 batch)
- 6 samples (2 batches of 3)
- 10 samples (2 batches of 5) ← Original failing case

### Monitoring During Tests

Watch for:
1. **Process counts**:
   ```bash
   watch 'ps aux | grep -E "(k2|kraken2)" | grep -v grep'
   ```

2. **File generation**:
   ```bash
   watch 'ls -lh <work_dir>/*.report.txt'
   ```

3. **Memory usage**:
   ```bash
   top -p $(pgrep k2)
   ```

### Debugging Tips

If hanging still occurs after applying fix:

1. **Add verbose logging** to module:
   ```bash
   echo "Processing sample: \${PREFIX}" >&2
   k2 classify ... 2>&1 | tee -a k2daemon.log
   echo "Completed sample: \${PREFIX}" >&2
   ```

2. **Check daemon status**:
   ```bash
   # The k2 daemon runs as a background process
   # Check if it's responding or stuck
   ```

3. **Test timeout handling**:
   Add timeouts to k2 commands:
   ```bash
   timeout 300 k2 classify ...
   ```

4. **Review stderr output**:
   The k2 script logs to stderr by default - check `.command.err` files

## Performance Expectations

### Standard KRAKEN2
- Database loaded once per sample
- Linear scaling: 10 samples ≈ 10× single sample time

### K2DAEMON
- Database loaded once per batch
- Sub-linear scaling: 10 samples (2 batches) ≈ 2× single sample time + processing
- Expected speedup: 2-5× depending on database size and sample count

## Next Steps After Testing

1. **If all tests pass**:
   - Merge changes to main branch
   - Update documentation
   - Consider making k2daemon the default for large sample sets

2. **If tests fail**:
   - Document specific failure mode
   - Check k2 version compatibility
   - Review k2 daemon documentation
   - Consider alternative batching strategies

3. **If performance doesn't improve**:
   - Database may be small enough that loading time is negligible
   - Processing time may dominate over loading time
   - Consider profiling to identify bottlenecks

## References

- k2 Manual: https://github.com/DerrickWood/kraken2/wiki/Manual#introducing-k2
- nf-core/taxprofiler: https://github.com/nf-core/taxprofiler
- Kraken2 Documentation: https://github.com/DerrickWood/kraken2/wiki

## Support

If issues persist after following this guide:
1. Check k2 version: `k2 --version`
2. Verify kraken2 database integrity
3. Test with minimal kraken2 database
4. Review system resources (memory, CPU, disk)
5. Check Nextflow version compatibility
