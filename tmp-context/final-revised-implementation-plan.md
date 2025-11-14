# Final Revised Implementation Plan: MEGAN-LR-nuc-ONT Support

## Executive Summary

Add MEGAN-LR-nuc-ONT taxonomic profiling to nf-core/taxprofiler following established patterns. This workflow uses minimap2 for long-read alignment against taxonomic databases, with optional MEGAN post-processing for taxonomic profile extraction.

## Key Design Decisions (Based on All Feedback)

### Database Handling (CRITICAL CHANGE)
- **Pattern**: Follow standard taxonomic profiler pattern, NOT host removal pattern
- **Requirement**: Users must provide **pre-built databases** via `databases.csv`
- **No automatic index building**: Unlike host removal, we will not build minimap2 indices on-the-fly
- **Database structure**: db_path points to a directory containing:
  - Pre-built minimap2 index (.mmi file)
  - MEGAN nucleotide mapping database (.db file) - only needed if using MEGAN post-processing

### Other Design Principles
1. **Reuse existing modules**: Use `modules/nf-core/minimap2/align/`
2. **New modules**: Create `modules/local/megan/sam2rma/` (follows local module pattern)
3. **Integration**: Add to existing `subworkflows/local/profiling.nf`
4. **Flexibility**: Support general reference databases, not just NCBI nt
5. **Modularity**:
   - Can run minimap2 only (saves SAM/BAM alignments)
   - Can run full MEGAN-LR pipeline (minimap2 → sam2rma → rma2info)
   - Can optionally use taxpasta for standardization

## Implementation Phases

### Phase 1: Minimap2 Taxonomic Alignment

Add minimap2 as a standalone taxonomic profiler outputting SAM alignments.

#### Files to Create
None - reuse existing nf-core modules.

#### Files to Modify

**1. `assets/schema_database.json`**
```json
// Line 12-24: Add to tool enum
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
    "motus"
],
// Line 25: Update error message
"errorMessage": "Invalid tool name. Please see documentation for all supported profilers. Currently these classifiers are included: bracken, centrifuge, diamond, ganon, kaiju, kmcp, kraken2, krakenuniq, malt, meganlr, metaphlan, motus.",
```

**2. `nextflow.config`**
```groovy
// Add after ganon parameters (around line 179):

// MEGAN-LR
run_meganlr                    = false
meganlr_save_alignment         = false      // Save minimap2 SAM output
meganlr_run_megan              = false      // Run MEGAN post-processing (Phase 2)
```

**3. `conf/modules.config`**
```groovy
// Add after GANON_REPORT block (around line 675):

withName: 'PROFILING:MINIMAP2_ALIGN' {
    tag = { "${meta.db_name}|${meta.tool}|${meta.id}" }
    ext.args = { "${meta.db_params} -ax map-ont" }  // ONT-specific alignment
    ext.prefix = { "${meta.id}_${meta.db_name}" }
    publishDir = [
        path: { "${params.outdir}/meganlr/${meta.db_name}/" },
        mode: params.publish_dir_mode,
        pattern: '*.sam',
        enabled: params.meganlr_save_alignment
    ]
}
```

**4. `subworkflows/local/profiling.nf`**

Add minimap2 import:
```groovy
// Line 21: Add after GANON_REPORT
include { MINIMAP2_ALIGN                                } from '../../modules/nf-core/minimap2/align/main'
```

Add branching logic:
```groovy
// Line 98: Add after ganon branch
meganlr: db_meta.tool == 'meganlr'
```

Add minimap2 profiling block:
```groovy
// Add after ganon block (around line 506):

if (params.run_meganlr) {

    ch_input_for_minimap2 = ch_input_for_profiling.meganlr
        .multiMap { meta, reads, db_meta, db ->
            reads: [meta + db_meta, reads]
            db: [[id: db_meta.db_name], db]
        }

    // Find the minimap2 index file in the database directory
    ch_minimap2_db = ch_input_for_minimap2.db
        .map { meta, db_path ->
            // If db_path is a directory, find .mmi file; if it's a file, use it directly
            def index_file = db_path.isDirectory() ?
                file("${db_path}/*.mmi").first() : db_path
            [meta, index_file]
        }

    MINIMAP2_ALIGN(
        ch_input_for_minimap2.reads,
        ch_minimap2_db,
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

**Option 1: Database directory with index:**
```csv
tool,db_name,db_params,db_path
meganlr,nt_ont,-k 15,/path/to/meganlr_db/
```

Expected directory structure:
```
/path/to/meganlr_db/
├── nt_ont.mmi              # Pre-built minimap2 index
└── megan-map-Jan2021.db    # MEGAN mapping (for Phase 2)
```

**Option 2: Direct path to index file:**
```csv
tool,db_name,db_params,db_path
meganlr,nt_ont,-k 15,/path/to/nt_ont.mmi
```

**Note on db_params**:
- For Phase 1, db_params can include additional minimap2 alignment parameters
- The `-ax map-ont` is set by default in modules.config but can be overridden
- Example: `db_params="-k 15 -w 5"` for custom k-mer/window settings

#### Testing (Phase 1)
- [ ] Pipeline accepts meganlr in databases.csv
- [ ] Minimap2 aligns ONT reads against taxonomic database
- [ ] SAM output generated with correct naming
- [ ] Optional SAM saving works (meganlr_save_alignment=true)
- [ ] Works with both directory and file paths
- [ ] Custom db_params override defaults correctly

---

### Phase 2: MEGAN Post-Processing (sam2rma + rma2info)

Add MEGAN tools to convert alignments to taxonomic profiles.

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

**1. `nextflow.config`**
```groovy
// Add to MEGAN-LR section (after meganlr_run_megan):
meganlr_save_rma6              = false      // Save intermediate RMA6 files
```

**2. `conf/modules.config`**
```groovy
// Add after MINIMAP2_ALIGN block:

withName: 'PROFILING:MEGAN_SAM2RMA' {
    tag = { "${meta.db_name}|${meta.id}" }
    ext.args = ""  // Additional sam2rma args if needed
    ext.prefix = { "${meta.id}_${meta.db_name}" }
    publishDir = [
        path: { "${params.outdir}/meganlr/${meta.db_name}/" },
        mode: params.publish_dir_mode,
        pattern: '*.rma6',
        enabled: params.meganlr_save_rma6
    ]
}

withName: 'PROFILING:MEGAN_RMA2INFO' {
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

**3. `subworkflows/local/profiling.nf`**

Add import:
```groovy
// Line 6: Add after MEGAN_RMA2INFO_TSV
include { MEGAN_RMA2INFO as MEGAN_RMA2INFO_MEGANLR     } from '../../modules/nf-core/megan/rma2info/main'
include { MEGAN_SAM2RMA                                } from '../../modules/local/megan/sam2rma'
```

Modify minimap2 block (replace Phase 1 implementation):
```groovy
if (params.run_meganlr) {

    ch_input_for_minimap2 = ch_input_for_profiling.meganlr
        .multiMap { meta, reads, db_meta, db ->
            reads: [meta + db_meta, reads]
            db: [db_meta, db]
        }

    // Find the minimap2 index file in the database directory
    ch_minimap2_db = ch_input_for_minimap2.db
        .map { meta, db_path ->
            def index_file = db_path.isDirectory() ?
                file("${db_path}/*.mmi").first() : db_path
            [[id: meta.db_name], index_file]
        }

    MINIMAP2_ALIGN(
        ch_input_for_minimap2.reads,
        ch_minimap2_db,
        false,  // bam_format (false = SAM output)
        false,  // bam_index_extension
        false,  // cigar_paf_format
        false   // cigar_bam
    )

    ch_versions = ch_versions.mix(MINIMAP2_ALIGN.out.versions.first())

    // If MEGAN processing is enabled, run sam2rma and rma2info
    if (params.meganlr_run_megan) {

        // Find MEGAN mapping database
        ch_megan_db = ch_input_for_minimap2.db
            .map { meta, db_path ->
                def megan_db = db_path.isDirectory() ?
                    file("${db_path}/*.db").first() : null
                if (megan_db == null) {
                    error("MEGAN database (.db file) not found in ${db_path}. Required when meganlr_run_megan=true")
                }
                megan_db
            }
            .first()

        MEGAN_SAM2RMA(MINIMAP2_ALIGN.out.paf, ch_megan_db)
        MEGAN_RMA2INFO_MEGANLR(MEGAN_SAM2RMA.out.rma6, false)

        ch_versions = ch_versions.mix(
            MEGAN_SAM2RMA.out.versions.first(),
            MEGAN_RMA2INFO_MEGANLR.out.versions.first()
        )
        ch_raw_classifications = ch_raw_classifications.mix(MEGAN_SAM2RMA.out.rma6)
        ch_raw_profiles = ch_raw_profiles.mix(MEGAN_RMA2INFO_MEGANLR.out.txt)
    } else {
        // Only minimap2 alignment, output SAM as classification
        ch_raw_classifications = ch_raw_classifications.mix(MINIMAP2_ALIGN.out.paf)
    }
}
```

#### Database Configuration (Phase 2)

When using MEGAN post-processing (`meganlr_run_megan=true`), database directory must contain both files:

```csv
tool,db_name,db_params,db_path
meganlr,nt_ont,,/path/to/meganlr_db/
```

Expected directory structure:
```
/path/to/meganlr_db/
├── nt_ont.mmi              # Pre-built minimap2 index (required)
└── megan-map-Jan2021.db    # MEGAN nucleotide mapping (required for Phase 2)
```

#### Testing (Phase 2)
- [ ] sam2rma converts minimap2 SAM to RMA6
- [ ] rma2info extracts taxonomic profiles from RMA6
- [ ] Output format matches MALT output (megan6 format)
- [ ] Profiles added to ch_raw_profiles channel
- [ ] RMA6 files optionally saved (meganlr_save_rma6=true)
- [ ] Error handling when .db file missing but meganlr_run_megan=true
- [ ] Can run with meganlr_run_megan=false (minimap2 only)

---

### Phase 3: Taxpasta Standardization

Enable taxpasta to normalize MEGAN-LR output alongside other profilers.

#### Files to Modify

**1. `subworkflows/local/standardisation_profiles.nf`**

Update the tool mapping (around line 73):
```groovy
// Line 73: Update mapping
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
// MEGAN-LR
run_meganlr                    = false    // Enable MEGAN-LR profiling
meganlr_save_alignment         = false    // Save minimap2 SAM alignment output
meganlr_run_megan              = false    // Run MEGAN post-processing (sam2rma + rma2info)
meganlr_save_rma6              = false    // Save intermediate RMA6 files
```

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
3. Place both files in the same directory

### Final Database Directory Structure

```
/data/databases/meganlr_nt/
├── nt_ont.mmi                      # Minimap2 index (~50-100GB for nt)
└── megan-nucl-Jan2021.db          # MEGAN mapping (~20GB)
```

### databases.csv Entry

```csv
tool,db_name,db_params,db_path
meganlr,nt_ont,,/data/databases/meganlr_nt/
```

### Running the Pipeline

**Minimap2 alignment only:**
```bash
nextflow run nf-core/taxprofiler \
  --input samplesheet.csv \
  --databases databases.csv \
  --outdir results \
  --run_meganlr \
  --meganlr_save_alignment
```

**Full MEGAN-LR pipeline:**
```bash
nextflow run nf-core/taxprofiler \
  --input samplesheet.csv \
  --databases databases.csv \
  --outdir results \
  --run_meganlr \
  --meganlr_run_megan \
  --run_profile_standardisation
```

## Success Criteria Summary

### Phase 1: Minimap2 Alignment
- [x] Accepts pre-built .mmi index via databases.csv
- [x] Supports directory or file path for database
- [x] Applies ONT-specific alignment parameters (`-ax map-ont`)
- [x] Can save alignment output (SAM format)
- [x] Works as standalone taxonomic alignment tool

### Phase 2: MEGAN Integration
- [x] sam2rma converts minimap2 SAM to RMA6
- [x] rma2info extracts taxonomic profiles
- [x] Output format compatible with taxpasta (megan6)
- [x] Can run minimap2-only OR full MEGAN-LR pipeline
- [x] Proper error handling for missing MEGAN database

### Phase 3: Standardization
- [x] taxpasta recognizes meganlr as megan6 format
- [x] Profiles merge correctly with other profilers
- [x] Multi-sample support works

### Overall Quality
- [x] All new modules in `modules/local/`
- [x] Follows existing nf-core/taxprofiler patterns
- [x] No automatic index building (users provide pre-built indices)
- [x] Works with any reference database (not nt-specific)
- [x] Integrated into `profiling.nf` (not separate subworkflow)
- [x] Clear documentation for database setup
- [x] All parameters follow naming conventions

## Key Differences from Previous Plans

### What Changed Based on Final Feedback:
1. **Database handling**: NO automatic index building - users must provide pre-built minimap2 index
2. **Database pattern**: Follow standard taxonomic profiler pattern (via databases.csv), not host removal pattern
3. **Simplification**: Removed all index building logic and related parameters
4. **User responsibility**: Users create and maintain their own minimap2 indices with appropriate parameters

### What Stayed the Same:
1. Three-phase implementation approach
2. Workflow: minimap2 → sam2rma → rma2info
3. Modularity: can run just minimap2 or full pipeline
4. Output standardization via taxpasta
5. ONT-specific default parameters
6. General reference database support

## Implementation Order

1. **Phase 1** - Minimap2 alignment (weeks 1-2)
   - Update schema and parameters
   - Add minimap2 block to profiling.nf
   - Configure modules.config
   - Test with pre-built indices

2. **Phase 2** - MEGAN processing (weeks 2-3)
   - Create sam2rma module
   - Integrate sam2rma and rma2info
   - Add conditional MEGAN execution
   - Test full pipeline

3. **Phase 3** - Standardization (week 3)
   - Update standardisation_profiles.nf
   - Test taxpasta integration
   - Final integration testing

## Questions Resolved

1. **Database directory structure**: Users organize as they wish; pipeline finds .mmi and .db files automatically
2. **Index building**: NOT supported - users must provide pre-built indices
3. **Alignment format**: SAM (default), easier for MEGAN processing
4. **MEGAN mapping file**: Support nucleotide mapping only (as per manuscript)
5. **Testing data**: Will need sample ONT metagenomic data and small reference database for CI/CD

## Next Steps

1. ✅ Review this final plan with stakeholders
2. Begin Phase 1 implementation
3. Create test datasets (small reference + ONT reads)
4. Update documentation as each phase completes
5. Create pull request with comprehensive testing
