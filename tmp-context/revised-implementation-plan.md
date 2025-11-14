# Revised Implementation Plan: MEGAN-LR-nuc-ONT Support for nf-core/taxprofiler

## Overview

Add support for MEGAN-LR-nuc-ONT taxonomic profiling, a workflow specifically designed for long-read metagenomic sequencing that:
1. Aligns reads to a reference taxonomic database (e.g., NCBI nt) using **minimap2** with ONT-optimized parameters
2. Converts alignments to MEGAN's RMA6 format using **sam2rma**
3. Extracts taxonomic profiles using **rma2info** (already supported for MALT)

This implementation will be modular, allowing users to:
- Run only minimap2 alignment (for general-purpose taxonomic alignment)
- Run the full MEGAN-LR pipeline (minimap2 + sam2rma + rma2info)
- Optionally normalize outputs with taxpasta

## Key Design Principles (Based on Feedback)

1. **Reuse existing infrastructure**: Leverage existing `minimap2/index` and `minimap2/align` modules from `modules/nf-core/`
2. **Follow established patterns**: Use `longread_hostremoval.nf` as a template for index handling
3. **Support flexibility**:
   - Accept pre-built index OR reference fasta (build on-the-fly if needed)
   - Option to save built index for reuse
   - Support any reference database (not just NCBI nt)
4. **Modular execution**:
   - Can run just minimap2 alignment
   - Can optionally add MEGAN post-processing
   - Can optionally add taxpasta normalization
5. **New custom modules**: Place in `modules/local/` (not `modules/nf-core/`)
6. **Integration location**: Add to existing `profiling.nf` subworkflow (not a separate subworkflow)

## Phased Implementation Strategy

### Phase 1: Minimap2 Alignment for Taxonomic Profiling

Add support for using minimap2 as a standalone taxonomic classifier (outputting SAM/BAM alignments).

**Files to Create:**
- None (use existing nf-core modules)

**Files to Modify:**

1. **`assets/schema_database.json`**
   - Add `"meganlr"` to the tool enum (line 12-24)
   - Update error message to include meganlr

2. **`nextflow.config`**
   - Add parameters:
     ```groovy
     // MEGAN-LR
     run_meganlr                    = false
     meganlr_alignment_format       = 'sam'      // 'sam' or 'bam'
     meganlr_save_alignment         = false      // Save minimap2 SAM/BAM output
     meganlr_run_megan              = false      // Run MEGAN post-processing (Phase 2)
     meganlr_save_index             = false      // Save minimap2 index if built
     ```

3. **`conf/modules.config`**
   - Add configuration for minimap2 when used for MEGAN-LR:
     ```groovy
     withName: 'PROFILING:MINIMAP2_INDEX_MEGANLR' {
         ext.args = '-k 15 -w 10'  // ONT-specific indexing parameters
         publishDir = [
             path: { "${params.outdir}/meganlr/index" },
             mode: params.publish_dir_mode,
             pattern: '*.mmi',
             enabled: params.meganlr_save_index
         ]
     }

     withName: 'PROFILING:MINIMAP2_ALIGN_MEGANLR' {
         ext.args = '-ax map-ont'  // ONT-specific alignment parameters
         ext.prefix = { "${meta.id}" }
         publishDir = [
             path: { "${params.outdir}/meganlr/alignment" },
             mode: params.publish_dir_mode,
             pattern: '*.{sam,bam}',
             enabled: params.meganlr_save_alignment
         ]
     }
     ```

4. **`subworkflows/local/profiling.nf`**
   - Add `meganlr` branch to the input channel branching logic (around line 88-100)
   - Add minimap2 alignment block for MEGAN-LR (after ganon block, around line 506)
   - Handle index building logic (following longread_hostremoval.nf pattern)

**Testing:**
- Test with pre-built minimap2 index (.mmi file)
- Test with reference fasta (should build index)
- Test with save_index enabled
- Verify ONT-specific parameters are applied
- Verify output SAM/BAM files are generated

---

### Phase 2: MEGAN Post-Processing (sam2rma + rma2info)

Add MEGAN tools to convert alignments to taxonomic profiles.

**Files to Create:**

1. **`modules/local/megan_sam2rma.nf`** - New module for sam2rma conversion
   - Follow pattern from `modules/local/kraken2_standard_report.nf`
   - Use same conda/container as `modules/nf-core/megan/rma2info/main.nf`
   - Input: SAM/BAM file + MEGAN mapping database
   - Output: RMA6 file
   - Key arguments: `-lg -alg longReads` for long-read mode

2. **`modules/local/megan_sam2rma/environment.yml`**
   - Same as megan/rma2info (megan=6.25.9)

**Files to Modify:**

1. **`subworkflows/local/profiling.nf`**
   - Add import for MEGAN_SAM2RMA
   - Chain: MINIMAP2_ALIGN  MEGAN_SAM2RMA  MEGAN_RMA2INFO
   - Conditional execution based on `meganlr_run_megan` parameter

2. **`conf/modules.config`**
   - Add configuration for MEGAN_SAM2RMA
   - Add configuration for MEGAN_RMA2INFO when used with meganlr

3. **`nextflow.config`**
   - Add parameter: `meganlr_save_rma6`

**Testing:**
- Test full pipeline with MEGAN processing enabled
- Verify sam2rma converts SAM to RMA6
- Verify rma2info generates taxonomic profiles
- Test with different MEGAN mapping databases

---

### Phase 3: Taxpasta Standardization

Enable taxpasta to normalize MEGAN-LR output alongside other profilers.

**Files to Modify:**

1. **`subworkflows/local/standardisation_profiles.nf`**
   - Update taxpasta preparation to map meganlr  megan6 (same format as MALT)
   - This leverages the fact that rma2info output is identical regardless of source

**Testing:**
- Test taxpasta standardization with meganlr profiles
- Verify merged profiles include meganlr results
- Test with multiple samples/databases

---

## Database Configuration

### Phase 1 (Minimap2-only):

**With pre-built index:**
```csv
tool,db_name,db_params,db_path
meganlr,nt_ont,,/path/to/nt_ont.mmi
```

**With reference fasta (will build index):**
```csv
tool,db_name,db_params,db_path
meganlr,nt_ont,,/path/to/nt.fasta
```

### Phase 2 (Full MEGAN-LR):

The database path should point to a directory containing:
- The minimap2 index (.mmi) OR reference fasta
- The MEGAN nucleotide mapping file (e.g., megan-nucl-Jan2021.db)

```csv
tool,db_name,db_params,db_path
meganlr,nt_ont,,/path/to/meganlr_db/
```

Expected directory structure:
```
/path/to/meganlr_db/
nt_ont.mmi                    # minimap2 index (or nt.fasta)
megan-nucl-Jan2021.db         # MEGAN mapping file
```

**Implementation note**: The pipeline will need logic to:
1. Detect if db_path is a file (index/fasta) or directory
2. If directory, find the index/fasta and MEGAN db separately
3. Build index from fasta if needed

---

## Parameter Summary

| Parameter | Default | Description | Phase |
|-----------|---------|-------------|-------|
| `run_meganlr` | `false` | Enable MEGAN-LR profiling | 1 |
| `meganlr_alignment_format` | `'sam'` | Output format: 'sam' or 'bam' | 1 |
| `meganlr_save_alignment` | `false` | Save minimap2 SAM/BAM output | 1 |
| `meganlr_save_index` | `false` | Save minimap2 index if built | 1 |
| `meganlr_run_megan` | `false` | Run MEGAN post-processing | 2 |
| `meganlr_save_rma6` | `false` | Save intermediate RMA6 files | 2 |

---

## Key Technical Details

### ONT-Specific Parameters
From the manuscript:
- **Indexing**: `minimap2 -k 15 -w 10 -I 10G -d mm_nt_db_ONT.mmi nt.gz`
- **Alignment**: `minimap2 -ax map-ont`

These will be set as defaults in `conf/modules.config` but can be overridden via `db_params`.

### MEGAN Integration
- **sam2rma**: Requires MEGAN nucleotide mapping file (megan-nucl-Jan2021.db or similar)
- **rma2info**: Already supported in the pipeline for MALT output
- **Output format**: Identical to MALT, so taxpasta can handle it as 'megan6'

### Database Handling Strategy

**Problem**: MEGAN-LR needs two separate files (minimap2 index + MEGAN mapping db)

**Solution**:
1. **Phase 1**: db_path points directly to index or fasta file
2. **Phase 2**: db_path points to directory containing both files
   - Use file globbing to find `.mmi` or `.fasta` files for minimap2
   - Use globbing to find `.db` file for MEGAN mapping
   - Build index from fasta if no .mmi found

**Alternative considered**: Use db_params to specify second file path
- Rejected: Less intuitive for users; breaks the single-path paradigm

### Memory and Performance
- **minimap2 index**: Can require 10G+ memory for large databases like nt
- **sam2rma**: Memory-intensive, needs process_medium or process_high label
- **Indexing once**: Index building should be done once and cached/saved

---

## Implementation Order

1. **Phase 1: Minimap2 alignment**
   - Start: Update database schema and parameters
   - Core: Implement profiling.nf changes for minimap2
   - Test: Verify alignment works with both index and fasta

2. **Phase 2: MEGAN processing**
   - Create: megan_sam2rma module
   - Integrate: Chain sam2rma and rma2info
   - Test: Full pipeline produces taxonomic profiles

3. **Phase 3: Standardization**
   - Update: standardisation_profiles.nf
   - Test: Integration with taxpasta and other tools

---

## Success Criteria

### Phase 1
- [ ] Minimap2 aligns ONT reads against taxonomic database
- [ ] Accepts pre-built .mmi index
- [ ] Accepts reference fasta and builds index with ONT parameters
- [ ] Can save built index for reuse
- [ ] Can save alignment output (SAM or BAM)
- [ ] Follows longread_hostremoval.nf patterns

### Phase 2
- [ ] sam2rma converts minimap2 SAM to RMA6
- [ ] rma2info extracts taxonomic profiles from RMA6
- [ ] Output format matches MALT output
- [ ] Profiles are added to ch_raw_profiles channel
- [ ] RMA6 files optionally saved

### Phase 3
- [ ] taxpasta recognizes meganlr profiles as megan6 format
- [ ] Standardization produces correct output
- [ ] Multi-sample merging works
- [ ] Integration with other profilers works

### Overall
- [ ] All code follows existing nf-core/taxprofiler patterns
- [ ] Works with any reference database (not nt-specific)
- [ ] New modules in modules/local/ (not modules/nf-core/)
- [ ] Integration in profiling.nf (not separate subworkflow)
- [ ] Documentation complete
- [ ] All tests pass

---

## Differences from Initial Draft Plan

### What Changed (Based on Feedback):

1. **Module location**: New modules go in `modules/local/`, not `modules/nf-core/`
2. **Minimap2 modules**: Reuse existing nf-core modules instead of creating new ones
3. **Index handling**: Follow `longread_hostremoval.nf` pattern for index building
4. **Subworkflow**: Integrate into `profiling.nf`, don't create separate subworkflow
5. **Database support**: Generalized to any reference, not nt-specific
6. **MEGAN integration**: Leverage existing `rma2info` support and patterns
7. **Phased approach**: Explicit phases for minimap2  MEGAN  taxpasta
8. **Modularity**: Can run just minimap2, or full pipeline with MEGAN

### What Stayed the Same:

1. Overall workflow: minimap2  sam2rma  rma2info
2. Need for new sam2rma module
3. ONT-specific parameters
4. Output standardization via taxpasta
5. Database schema and parameter additions

---

## Next Steps

1. Review this plan with stakeholders
2. Clarify any ambiguities (especially database directory structure handling)
3. Begin Phase 1 implementation
4. Test thoroughly at each phase before proceeding
5. Update documentation as features are added

---

## Questions for Clarification

1. **Database directory structure**: Should we enforce a specific structure, or auto-detect files?
2. **MEGAN mapping file**: Should we support multiple mapping files (nucl, prot) or just nucleotide?
3. **Default alignment format**: Should default be SAM or BAM?
4. **Integration with existing MALT**: Any concerns about having two tools producing MEGAN output?
5. **Testing data**: Do we have ONT test data available, or should we create it?

# Feedback on revised plan and the question of database specification

I initially asked for support for providing either an index or a reference fasta file for the minimap step similar to the host removal, which is handled via pipeline parameters (e.g. setting either `hostremoval_reference`  or `longread_hostremoval_index`). However, for taxonomic profilers the standard pattern in this repo seems to be to use a pre-built database that is passed through `databases.csv`. By trying to mix these patterns I caused design confusion.

I would like to discard my earlier request to have minimap2 optionally automatically build the reference database for this new tax profiling feature. Instead, let's treat this new minimap2 tax profiling functionality similar to other tax profiling steps, not like the host removal step. The user must supply a prebuilt minimap2 tax-profiling database and a path to the megan mapping databse through `databases.csv`.
