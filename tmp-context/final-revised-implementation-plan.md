# Final Revised Implementation Plan: MEGAN-LR-nuc-ONT Support

## Executive Summary

Add MEGAN-LR-nuc-ONT taxonomic profiling to nf-core/taxprofiler following the Bracken pattern. This workflow uses minimap2 for long-read alignment against taxonomic databases, with optional MEGAN post-processing for taxonomic profile extraction.

## Key Design Decisions

### Database Handling - Following Bracken Pattern

**Two-line approach in databases.csv:**
- **`minimap2`** entries: Runs minimap2 alignment, produces SAM files
- **`meganlr`** entries: Runs MEGAN post-processing (sam2rma → rma2info) on minimap2 output matched by `db_name`

This exactly mirrors how Bracken works:
- **`kraken2`** entries: Runs classification, produces reports
- **`bracken`** entries: Runs Bracken on kraken2 output matched by `db_name`

**Example databases.csv:**
```csv
tool,db_name,db_params,db_path
minimap2,nt_ont,,/path/to/nt_ont.mmi
meganlr,nt_ont,,/path/to/megan-nucl-Jan2021.db
```

### Use Cases

**Case 1: Minimap2 alignment only (no MEGAN)**
```csv
tool,db_name,db_params,db_path
minimap2,nt_ont,,/path/to/nt_ont.mmi
minimap2,refseq,,/path/to/refseq.mmi
```
→ Produces SAM alignments for both databases

**Case 2: Full MEGAN-LR pipeline**
```csv
tool,db_name,db_params,db_path
minimap2,nt_ont,,/path/to/nt_ont.mmi
meganlr,nt_ont,,/path/to/megan-nucl-Jan2021.db
```
→ Produces taxonomic profiles from nt_ont

**Case 3: Mixed - MEGAN on some, minimap2-only on others**
```csv
tool,db_name,db_params,db_path
minimap2,nt_ont,,/path/to/nt_ont.mmi
minimap2,refseq,,/path/to/refseq.mmi
meganlr,nt_ont,,/path/to/megan-nucl-Jan2021.db
```
→ Full MEGAN-LR on nt_ont, SAM alignments only from refseq

**Case 4: Multiple taxonomic levels (like Bracken)**
```csv
tool,db_name,db_params,db_path
minimap2,nt_ont,,/path/to/nt_ont.mmi
meganlr,nt_ont_species,-c2c Taxonomy,/path/to/megan-map.db
meganlr,nt_ont_genus,-c2c Taxonomy --majorRanksOnly,/path/to/megan-map.db
```
→ Produces profiles at different taxonomic levels

### Other Design Principles

1. **Reuse existing modules**: Use `modules/nf-core/minimap2/align/`
2. **New modules**: Create `modules/local/megan/sam2rma/` (follows local module pattern)
3. **Integration**: Add to existing `subworkflows/local/profiling.nf`
4. **Flexibility**: Support general reference databases, not just NCBI nt
5. **No automatic index building**: Users must provide pre-built minimap2 indices
6. **Modularity**: Presence of `meganlr` entries determines MEGAN processing (like Bracken)

## Implementation Phases

### Phase 1: Minimap2 Taxonomic Alignment

Add minimap2 as a standalone taxonomic profiler outputting SAM alignments.

#### Files to Create
None - reuse existing nf-core modules.

#### Files to Modify

**1. `assets/schema_database.json`**

Add both `minimap2` and `meganlr` to the tool enum:

```json
// Line 12-24: Update tool enum
"enum": [
    "bracken",
    "centrifuge",
    "diamond",
    "ganon",
    "kaiju",
    "kmcp",
    "kraken2",
    "krakenuniq",
    "malt",
    "meganlr",      // <- ADD THIS
    "metaphlan",
    "minimap2",     // <- ADD THIS
    "motus"
],
// Line 25: Update error message
"errorMessage": "Invalid tool name. Please see documentation for all supported profilers. Currently these classifiers are included: bracken, centrifuge, diamond, ganon, kaiju, kmcp, kraken2, krakenuniq, malt, meganlr, metaphlan, minimap2, motus.",
```

**2. `nextflow.config`**

```groovy
// Add after ganon parameters (around line 179):

// Minimap2 (taxonomic profiling)
run_minimap2                   = false
minimap2_save_alignment        = false      // Save minimap2 SAM output

// MEGAN-LR (requires minimap2)
run_meganlr                    = false      // Run MEGAN post-processing
meganlr_save_rma6              = false      // Save intermediate RMA6 files
```

**3. `conf/modules.config`**

```groovy
// Add after GANON_REPORT block (around line 675):

withName: 'PROFILING:MINIMAP2_ALIGN' {
    tag = { "${meta.db_name}|${meta.tool}|${meta.id}" }
    ext.args = { "${meta.db_params} -ax map-ont" }  // ONT-specific alignment
    ext.prefix = { "${meta.id}_${meta.db_name}" }
    publishDir = [
        path: { "${params.outdir}/minimap2/${meta.db_name}/" },
        mode: params.publish_dir_mode,
        pattern: '*.sam',
        enabled: params.minimap2_save_alignment
    ]
}
```

**4. `subworkflows/local/profiling.nf`**

Add minimap2 import:
```groovy
// Line 21: Add after GANON_REPORT
include { MINIMAP2_ALIGN                                } from '../../modules/nf-core/minimap2/align/main'
```

Add branching logic (like kraken2/bracken):
```groovy
// Line 98: Update ganon branch and add minimap2
ganon: db_meta.tool == 'ganon'
minimap2: db_meta.tool == 'minimap2' || db_meta.tool == 'meganlr'
```

Add minimap2 profiling block (after ganon block, around line 506):
```groovy
if (params.run_minimap2) {

    ch_input_for_minimap2 = ch_input_for_profiling.minimap2
        .filter { meta, reads, db_meta, db ->
            // Only process minimap2 entries here, not meganlr
            db_meta.tool == 'minimap2'
        }
        .multiMap { meta, reads, db_meta, db ->
            reads: [meta + db_meta, reads]
            db: [[id: db_meta.db_name], db]
        }

    MINIMAP2_ALIGN(
        ch_input_for_minimap2.reads,
        ch_input_for_minimap2.db,
        false,  // bam_format (false = SAM output)
        false,  // bam_index_extension
        false,  // cigar_paf_format
        false   // cigar_bam
    )

    ch_versions = ch_versions.mix(MINIMAP2_ALIGN.out.versions.first())
    ch_raw_classifications = ch_raw_classifications.mix(MINIMAP2_ALIGN.out.paf)
}
```

#### Database Configuration (Phase 1)

Users specify in `databases.csv`:

```csv
tool,db_name,db_params,db_path
minimap2,nt_ont,,/path/to/nt_ont.mmi
minimap2,refseq_ont,,/path/to/refseq_ont.mmi
```

**Note on db_params**:
- Can include additional minimap2 alignment parameters
- The `-ax map-ont` is set by default in modules.config but can be overridden
- Example: `db_params="-k 15 -w 5"` for custom k-mer/window settings

#### Testing (Phase 1)
- [ ] Pipeline accepts `minimap2` in databases.csv
- [ ] Minimap2 aligns ONT reads against taxonomic database
- [ ] SAM output generated with correct naming
- [ ] Optional SAM saving works (minimap2_save_alignment=true)
- [ ] Works with both .mmi files and directory paths
- [ ] Custom db_params override defaults correctly

---

### Phase 2: MEGAN Post-Processing (sam2rma + rma2info)

Add MEGAN tools to convert minimap2 alignments to taxonomic profiles, following the Bracken pattern.

#### Files to Create

**1. `modules/local/megan/sam2rma.nf`**

Based on pattern from `kraken2_standard_report.nf` and using same container as `megan/rma2info`:

```groovy
process MEGAN_SAM2RMA {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/megan:6.25.9--h9ee0642_0':
        'biocontainers/megan:6.25.9--h9ee0642_0' }"

    input:
    tuple val(meta), path(sam)
    path megan_db

    output:
    tuple val(meta), path("*.rma6"), emit: rma6
    path "versions.yml"            , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    sam2rma \\
        -i ${sam} \\
        -r ${megan_db} \\
        -o ${prefix}.rma6 \\
        -lg \\
        -alg longReads \\
        $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        megan: \$(echo \$(sam2rma 2>&1) | grep -o 'version.*' | sed 's/version //; s/,.*//')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.rma6

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        megan: 6.25.9
    END_VERSIONS
    """
}
```

**2. `modules/local/megan/sam2rma/environment.yml`**
```yaml
name: megan_sam2rma
channels:
  - conda-forge
  - bioconda
dependencies:
  - bioconda::megan=6.25.9
```

**3. `modules/local/megan/sam2rma/meta.yml`**
```yaml
name: megan_sam2rma
description: Convert SAM alignment files to MEGAN RMA6 format for taxonomic analysis
keywords:
  - metagenomics
  - taxonomic profiling
  - megan
  - rma6
tools:
  - megan:
      description: MEtaGenome ANalyzer for analyzing metagenomic data
      homepage: https://uni-tuebingen.de/fakultaeten/mathematisch-naturwissenschaftliche-fakultaet/fachbereiche/informatik/lehrstuehle/algorithms-in-bioinformatics/software/megan6/
      documentation: https://megan.cs.uni-tuebingen.de/
      licence: ["GPL v3"]
input:
  - meta:
      type: map
      description: Groovy Map containing sample information
  - sam:
      type: file
      description: SAM alignment file
      pattern: "*.sam"
  - megan_db:
      type: file
      description: MEGAN nucleotide mapping database
      pattern: "*.db"
output:
  - meta:
      type: map
      description: Groovy Map containing sample information
  - rma6:
      type: file
      description: MEGAN RMA6 format file
      pattern: "*.rma6"
  - versions:
      type: file
      description: File containing software versions
      pattern: "versions.yml"
authors:
  - "@<your-github-handle>"
```

#### Files to Modify

**1. `subworkflows/local/profiling.nf`**

Add imports:
```groovy
// Line 6: Add after MEGAN_RMA2INFO_TSV
include { MEGAN_RMA2INFO as MEGAN_RMA2INFO_MEGANLR     } from '../../modules/nf-core/megan/rma2info/main'
include { MEGAN_SAM2RMA                                } from '../../modules/local/megan/sam2rma'
```

Extend minimap2 block to handle MEGAN processing (following Bracken pattern):
```groovy
if (params.run_minimap2) {

    ch_input_for_minimap2 = ch_input_for_profiling.minimap2
        .filter { meta, reads, db_meta, db ->
            // Only process minimap2 entries here, not meganlr
            db_meta.tool == 'minimap2'
        }
        .multiMap { meta, reads, db_meta, db ->
            reads: [meta + db_meta, reads]
            db: [[id: db_meta.db_name], db]
        }

    MINIMAP2_ALIGN(
        ch_input_for_minimap2.reads,
        ch_input_for_minimap2.db,
        false, false, false, false
    )

    ch_versions = ch_versions.mix(MINIMAP2_ALIGN.out.versions.first())
    ch_raw_classifications = ch_raw_classifications.mix(MINIMAP2_ALIGN.out.paf)
}

if (params.run_minimap2 && params.run_meganlr) {
    // Extract meganlr databases from the database channel, keyed by db_name
    // This is analogous to how Bracken extracts bracken databases (profiling.nf:210-212)
    ch_meganlr_databases = databases
        .filter { meta, db -> meta.tool == 'meganlr' }
        .map { meta, db -> [meta.db_name, meta, db] }

    // Combine minimap2 SAM output with meganlr databases by db_name
    // This is analogous to Bracken combining kraken2 reports with bracken databases (profiling.nf:215-218)
    ch_input_for_meganlr = MINIMAP2_ALIGN.out.paf
        .map { meta, sam -> [meta.db_name, meta, sam] }
        .combine(ch_meganlr_databases, by: 0)
        .map { key, meta, sam, db_meta, db ->
            // Merge db_meta params into meta (like Bracken does)
            def db_meta_keys = db_meta.keySet()
            def db_meta_new = db_meta.subMap(db_meta_keys)
            [key, meta, sam, db_meta_new, db]
        }
        .multiMap { key, meta, sam, db_meta, db ->
            sam: [meta + db_meta, sam]
            db: db
        }

    MEGAN_SAM2RMA(ch_input_for_meganlr.sam, ch_input_for_meganlr.db)
    MEGAN_RMA2INFO_MEGANLR(MEGAN_SAM2RMA.out.rma6, false)

    ch_versions = ch_versions.mix(
        MEGAN_SAM2RMA.out.versions.first(),
        MEGAN_RMA2INFO_MEGANLR.out.versions.first()
    )
    ch_raw_classifications = ch_raw_classifications.mix(MEGAN_SAM2RMA.out.rma6)
    ch_raw_profiles = ch_raw_profiles.mix(MEGAN_RMA2INFO_MEGANLR.out.txt)
}
```

**2. `conf/modules.config`**

```groovy
// Add after MINIMAP2_ALIGN block:

withName: 'PROFILING:MEGAN_SAM2RMA' {
    tag = { "${meta.db_name}|${meta.id}" }
    ext.args = { "${meta.db_params}" }
    ext.prefix = { "${meta.id}_${meta.db_name}" }
    publishDir = [
        path: { "${params.outdir}/meganlr/${meta.db_name}/" },
        mode: params.publish_dir_mode,
        pattern: '*.rma6',
        enabled: params.meganlr_save_rma6
    ]
}

withName: 'PROFILING:MEGAN_RMA2INFO_MEGANLR' {
    tag = { "${meta.db_name}|${meta.id}" }
    ext.args = "-c2c Taxonomy"
    ext.prefix = { "${meta.id}_${meta.db_name}" }
    publishDir = [
        path: { "${params.outdir}/meganlr/${meta.db_name}/" },
        mode: params.publish_dir_mode,
        pattern: '*.txt.gz'
    ]
}
```

#### Database Configuration (Phase 2)

When using MEGAN post-processing, add corresponding `meganlr` entries:

```csv
tool,db_name,db_params,db_path
minimap2,nt_ont,,/path/to/nt_ont.mmi
meganlr,nt_ont,,/path/to/megan-nucl-Jan2021.db
```

The `db_name` must match between `minimap2` and `meganlr` entries for the pipeline to link them.

#### Testing (Phase 2)
- [ ] sam2rma converts minimap2 SAM to RMA6
- [ ] rma2info extracts taxonomic profiles from RMA6
- [ ] Output format matches MALT output (megan6 format)
- [ ] Profiles added to ch_raw_profiles channel
- [ ] RMA6 files optionally saved (meganlr_save_rma6=true)
- [ ] Correct matching by db_name (like Bracken)
- [ ] Can run minimap2 without meganlr (only minimap2 in databases.csv)
- [ ] Can run different combinations per database

---

### Phase 3: Taxpasta Standardization

Enable taxpasta to normalize MEGAN-LR output alongside other profilers.

#### Files to Modify

**1. `subworkflows/local/standardisation_profiles.nf`**

Update the tool mapping (around line 73):
```groovy
// Line 73: Update mapping to include meganlr
meta_new.tool = meta.tool == 'malt' || meta.tool == 'meganlr' ? 'megan6' : meta.tool
```

This tells taxpasta to treat meganlr output the same as MALT output (both use megan6 format).

#### Testing (Phase 3)
- [ ] taxpasta recognizes meganlr profiles as megan6 format
- [ ] Standardization produces correct output
- [ ] Multi-sample merging works
- [ ] Integration with other profilers works
- [ ] Output appears in final merged taxonomic profiles

---

## Complete Parameter Reference

Add to `nextflow.config`:

```groovy
// Minimap2 (taxonomic profiling)
run_minimap2                   = false    // Enable minimap2 taxonomic alignment
minimap2_save_alignment        = false    // Save minimap2 SAM alignment output

// MEGAN-LR (requires minimap2)
run_meganlr                    = false    // Run MEGAN post-processing (sam2rma + rma2info)
meganlr_save_rma6              = false    // Save intermediate RMA6 files
```

**Note**: Like Bracken, `meganlr` is triggered by:
1. Having `run_minimap2=true` (runs minimap2 alignment)
2. Having `run_meganlr=true` (enables MEGAN post-processing)
3. Having matching `meganlr` entries in databases.csv

## Database Setup Guide for Users

### Creating Minimap2 Index for ONT

According to the manuscript, the recommended indexing parameters for ONT are:

```bash
# Download NCBI nt database (or your reference database)
# Index with ONT-specific parameters
minimap2 -k 15 -w 10 -I 10G -d nt_ont.mmi nt.fasta.gz
```

### Setting Up MEGAN Database

1. Download MEGAN6 Community Edition
2. Obtain MEGAN nucleotide mapping file (e.g., `megan-nucl-Jan2021.db`)

### databases.csv Configuration

**Minimap2 only:**
```csv
tool,db_name,db_params,db_path
minimap2,nt_ont,,/data/databases/nt_ont.mmi
```

**Full MEGAN-LR:**
```csv
tool,db_name,db_params,db_path
minimap2,nt_ont,,/data/databases/nt_ont.mmi
meganlr,nt_ont,,/data/databases/megan-nucl-Jan2021.db
```

**Multiple databases with mixed processing:**
```csv
tool,db_name,db_params,db_path
minimap2,nt_ont,,/data/databases/nt_ont.mmi
minimap2,refseq_ont,,/data/databases/refseq_ont.mmi
meganlr,nt_ont,,/data/databases/megan-nucl-Jan2021.db
```
This runs full MEGAN-LR on nt_ont, minimap2 alignment only on refseq_ont.

### Running the Pipeline

**Minimap2 alignment only:**
```bash
nextflow run nf-core/taxprofiler \
  --input samplesheet.csv \
  --databases databases.csv \
  --outdir results \
  --run_minimap2 \
  --minimap2_save_alignment
```

**Full MEGAN-LR pipeline:**
```bash
nextflow run nf-core/taxprofiler \
  --input samplesheet.csv \
  --databases databases.csv \
  --outdir results \
  --run_minimap2 \
  --run_meganlr \
  --run_profile_standardisation
```

## Success Criteria Summary

### Phase 1: Minimap2 Alignment
- [x] Accepts `minimap2` tool in databases.csv
- [x] Applies ONT-specific alignment parameters (`-ax map-ont`)
- [x] Can save alignment output (SAM format)
- [x] Works as standalone taxonomic alignment tool
- [x] Supports custom parameters via db_params

### Phase 2: MEGAN Integration
- [x] Accepts `meganlr` tool in databases.csv
- [x] Matches minimap2 and meganlr entries by db_name (like Bracken)
- [x] sam2rma converts minimap2 SAM to RMA6
- [x] rma2info extracts taxonomic profiles
- [x] Output format compatible with taxpasta (megan6)
- [x] Can run minimap2-only OR full MEGAN-LR pipeline per database
- [x] Follows Bracken pattern for two-step profiling

### Phase 3: Standardization
- [x] taxpasta recognizes meganlr as megan6 format
- [x] Profiles merge correctly with other profilers
- [x] Multi-sample support works

### Overall Quality
- [x] All new modules in `modules/local/`
- [x] Follows existing nf-core/taxprofiler patterns (especially Bracken)
- [x] No automatic index building (users provide pre-built indices)
- [x] Works with any reference database (not nt-specific)
- [x] Integrated into `profiling.nf` (not separate subworkflow)
- [x] Clear documentation for database setup
- [x] All parameters follow naming conventions
- [x] Two-line database.csv approach enables modularity

## Key Differences from Previous Plans

### What Changed Based on Final Feedback:

1. **Two tools instead of one**: `minimap2` for alignment, `meganlr` for MEGAN processing
2. **Follows Bracken pattern**: Two separate database entries matched by `db_name`
3. **Better modularity**: Can run minimap2 without MEGAN on a per-database basis
4. **Clearer naming**: `minimap2` reflects what it does (alignment), `meganlr` reflects the full workflow
5. **Simpler parameters**: No `meganlr_run_megan` - presence of `meganlr` entries triggers it
6. **Database matching**: Uses `db_name` to link minimap2 and meganlr (like Bracken uses `db_name`)

### What Stayed the Same:

1. Three-phase implementation approach
2. Workflow: minimap2 → sam2rma → rma2info
3. Output standardization via taxpasta
4. ONT-specific default parameters
5. General reference database support
6. No automatic index building

## Implementation Order

1. **Phase 1** - Minimap2 alignment (weeks 1-2)
   - Update schema to add both `minimap2` and `meganlr`
   - Add minimap2 parameters
   - Add minimap2 block to profiling.nf
   - Configure modules.config
   - Test with pre-built indices

2. **Phase 2** - MEGAN processing (weeks 2-3)
   - Create sam2rma module
   - Add meganlr parameters
   - Integrate sam2rma and rma2info with db_name matching
   - Test full pipeline with various database combinations

3. **Phase 3** - Standardization (week 3)
   - Update standardisation_profiles.nf
   - Test taxpasta integration
   - Final integration testing

## Questions for Clarification

1. **MEGAN rma2info parameters**: Should we allow different parameters per meganlr entry (like Bracken allows different taxonomic levels)?
2. **Error handling**: If meganlr entry has no matching minimap2 entry, warn or error?
3. **Output naming**: Follow MALT pattern or create meganlr-specific naming?
4. **Testing data**: Do we have ONT test data available, or should we create it?
5. **Documentation**: Should we add a tutorial section like Bracken has?

## Next Steps

1. ✅ Review this final plan with stakeholders
2. ✅ Confirm the two-tool approach matches expectations
3. Begin Phase 1 implementation
4. Create test datasets (small reference + ONT reads)
5. Update documentation as each phase completes
6. Create pull request with comprehensive testing
