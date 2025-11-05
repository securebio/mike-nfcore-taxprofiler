# Quick-Start Testing Guide for K2DAEMON

## You Need to Run These Tests

Since the testing tools (`k2`, `kraken2`, `nf-test`, `nextflow`) are not available in this environment, **you'll need to run these tests in your environment** where you have taxprofiler set up.

## Prerequisites

Ensure you have:
- [ ] Nextflow installed
- [ ] nf-test installed (for Phase 2)
- [ ] Docker or Singularity/Apptainer (for containers)
- [ ] kraken2 with k2 script installed

## Recommended Testing Order

### Phase 2 First (Easiest): Module Tests

This is the **easiest and fastest** test to run since it uses small test datasets that download automatically:

```bash
# Ensure you're on the correct branch
git checkout claude/review-k2daemon-branch-011CUpnBmYYmqj9B1uYMBoj4

# Run the module tests
./test_k2daemon_module.sh
```

**Expected time**: 5-10 minutes
**What it tests**: K2DAEMON module with small test datasets
**If it passes**: The module works correctly in isolation with the --gzip-compressed flag

### Phase 3 (Most Important): Full Workflow Test

This tests with your actual data and reproduces the original issue:

```bash
# Prepare your test data
# 1. Create a samplesheet with 10 samples (your original failing case)
# 2. Create a database sheet with your kraken2 database

# Run the workflow test
./test_k2daemon_workflow.sh ./test_work ./samplesheet.csv ./database.csv
```

**Expected time**: Varies by dataset size
**What it tests**:
- Standard KRAKEN2 (baseline)
- K2DAEMON with batch_size=2
- K2DAEMON with batch_size=5 (your original failing configuration)

**If it passes**: The hanging issue is resolved!

### Phase 1 (Optional): Standalone k2 Test

Only needed if Phase 2 or 3 fail - helps isolate whether k2 daemon itself works:

```bash
./test_k2daemon_standalone.sh /path/to/kraken2_db /path/to/test_reads
```

## Minimal Test (If Short on Time)

If you want to quickly verify the fix:

```bash
# Just run the nf-test module tests
cd /path/to/mike-nfcore-taxprofiler
git checkout claude/review-k2daemon-branch-011CUpnBmYYmqj9B1uYMBoj4
nf-test test modules/local/kraken2/k2daemon/tests/main.nf.test
```

This will test with 2 samples and verify the --gzip-compressed flag works.

## What to Look For

### ✅ Success Indicators
- All tests complete without hanging
- All samples produce .kraken2.report.txt files
- No stuck k2 or kraken2 processes
- K2DAEMON completes in reasonable time (faster than standard KRAKEN2)

### ❌ Failure Indicators
- Process hangs after 1-2 samples (original issue)
- Missing output files
- Error messages about input format
- k2 daemon processes remain after test

## Reporting Back

Please let me know:
1. **Which phase(s) you ran**
2. **Whether tests passed or failed**
3. **If failed**:
   - At what point did it fail/hang?
   - Any error messages in logs?
   - Output of `ps aux | grep k2`
4. **If passed**:
   - Performance improvement observed?
   - All expected outputs generated?

## Quick Validation of Fix

To quickly check if the fix is present:

```bash
# Verify --gzip-compressed flag is in the module
grep -n "gzip-compressed" modules/local/kraken2/k2daemon/main.nf

# Should show two lines:
#  54:                --gzip-compressed \
#  92:                --gzip-compressed \
```

## Next Steps After Testing

### If Tests Pass ✅
The fix works! You can:
1. Test with your full production dataset
2. Merge to the k2daemon branch
3. Compare performance vs standard KRAKEN2

### If Tests Still Fail ❌
We'll need to debug further:
1. Share the error logs
2. Check k2 daemon behavior
3. May need additional fixes beyond --gzip-compressed

---

**Most Important**: Run **Phase 2** first (module tests) - it's quick and will confirm the basic fix works.
