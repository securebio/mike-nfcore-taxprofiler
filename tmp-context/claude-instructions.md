# Background

Our goal is to add support to this pipeline for the MEGAN-LR-nuc-ONT from the manuscript

@article{portik2022eval,
  title = {Evaluation of taxonomic classification and profiling methods for long-read shotgun metagenomic sequencing datasets},
  author = {Portik, Daniel M. and Brown, C. Titus and Pierce-Ward, N. Tessa},
  date = {2022-12-13},
  journaltitle = {BMC Bioinformatics},
  shortjournal = {BMC Bioinformatics},
  volume = {23},
  number = {1},
  pages = {541},
  issn = {1471-2105},
  doi = {10.1186/s12859-022-05103-0}
}

The manuscript describes the pipeline as follows

> ### MEGAN‐LR‐nuc
>
> A streamlined workflow for MEGAN-LR-nuc is available (Taxonomic-Profiling-MinimapMegan) at: https://github.com/PacificBiosciences/pb-metagenomics-tools. The pipeline is  provided as a configurable snakemake workflow. To use the workflow, we first downloaded  the NCBI nt database and indexed it with minimap2 using the following command:
>
> ```sh
> minimap2 -k 19 -w 10 -I 10G -d mm_nt_db.mmi nt.gz
> ```
>
> We downloaded MEGAN6 community edition to obtain the executable tools required  for these workflows (sam2rma, rma2info), as well as the required MEGAN nucleotide mapping file (megan-nucl-Jan201.db). We then ran the Taxonomic-Profiling-Minimap-Megan  pipeline. The locations of the minimap2 nt index, sam2rma, rma2info, and the mapping  file were specified in the main configuration file for the analysis (config.yaml), and we also  changed the maximum number of secondary alignments from 20 to 5. The information for  the sample fasta files was added to the sample configuration file (Sample-Config.yaml), and  the snakemake (Snakefile-taxnuc) was executed. Details for the usage of each program are  provided in the online documentation.
>
> The above instructions are for the MEGAN-LR-nuc-HiFi analysis. Running the MEGAN-LR-nuc-ONT analysis required some changes. Specifically, we indexed the database with  minimap2 using the following command:
>
> ```sh
> minimap2 -k 15 -w 10 -I 10G -d mm_nt_db_ONT.mmi nt.gz
> ```
>
> We then edited the minimap2 command in the snakemake file to include the ONT recommended settings:
>
> ```sh
> minimap2 -ax map-ont
> ```

The online version of the pipeline is at https://github.com/PacificBiosciences/pb-metagenomics-tools/tree/master/Taxonomic-Profiling-Minimap-Megan

# Implementation plannign

## Iniitial draft implementation plan by Claude

Based on the feature request and exploration of the taxprofiler codebase, here's a comprehensive plan to add MEGAN-LR-nuc-ONT profiler support:

### Overview

MEGAN-LR-nuc-ONT is a taxonomic profiling workflow that uses:

1.  **minimap2** for ONT read alignment against NCBI nt database
2.  **sam2rma** (MEGAN tool) to convert SAM alignments to RMA6 format
3.  **rma2info** (existing MEGAN tool) to extract taxonomic profiles

### Implementation Steps

#### 1. **Module Development** (Steps 1-4)

- **Check/Create MINIMAP2_ALIGN module**: Align reads to nt database with ONT-specific parameters (`-ax map-ont`)
- **Create MEGAN_SAM2RMA module**: Convert SAM output to MEGAN's RMA6 format, requires MEGAN mapping database
- **Adapt MEGAN_RMA2INFO**: Reuse existing module that converts RMA6 to taxonomic profile text format

#### 2. **Configuration Updates** (Steps 5-7)

- **Database schema** (`assets/schema_database.json`): Add "meganlr" to valid tool enums
- **Pipeline parameters** (`nextflow.config`): Add `run_meganlr`, `meganlr_save_alignment`, etc.
- **Module config** (`conf/modules.config`): Configure resource requirements and output paths

#### 3. **Workflow Integration** (Steps 8-10)

- **Create MEGANLR subworkflow**: Chain the three processes (minimap2 → sam2rma → rma2info)
- **Integrate into profiling.nf**: Add meganlr branching logic and execution block
- **Update standardisation**: Handle MEGAN-LR output format in downstream standardisation

#### 4. **Testing** (Step 11)

- Test with sample ONT data
- Verify output format compatibility
- Check resource usage and performance

### Key Technical Details

**Database Requirements:**

- minimap2 index of NCBI nt (`.mmi` format, indexed with ONT parameters: `-k 15 -w 10`)
- MEGAN nucleotide mapping file (e.g., `megan-nucl-Jan2021.db`)

**Process Chain:**

``` bg-bg-200
ONT reads → minimap2 (map-ont) → SAM → sam2rma → RMA6 → rma2info → taxonomic profile
```

**Configuration Pattern:**

- Users specify database path and mapping file in database sheet
- Tool-specific parameters passed via `db_params` column
- Module handles ONT-specific minimap2 settings automatically

### Challenges & Considerations

1.  **minimap2 module availability**: Need to check if nf-core has existing minimap2 module or create custom one
2.  **Database indexing**: Users need properly indexed database (documentation needed)
3.  **MEGAN dependencies**: Requires MEGAN6 CE installation for sam2rma tool
4.  **Output format**: Ensure rma2info output is compatible with downstream standardisation

### Files to Create/Modify

**New files:**

- `modules/nf-core/minimap2/align/` (if doesn't exist)
- `modules/nf-core/megan/sam2rma/`
- `subworkflows/local/meganlr.nf` (optional, for clean organization)

**Modified files:**

- `assets/schema_database.json`
- `nextflow.config`
- `conf/modules.config`
- `subworkflows/local/profiling.nf`
- `subworkflows/local/standardisation_profiles.nf`

Would you like me to proceed with implementing this plan?

## Feedback on the draft implementation plan

- modules/nf-core/minimap2/index/ and modules/nf-core/minimap2/align/ are already present in the pipeline; you should aim to use these
- any new modules you create should go in modules/local; modules/nf-core is just for modules from the separate nf-core project
- Look at the longread_hostremoval.nf subworkflow for patterns for the minimap portion. Like for hostremoval, we should allow for the user to supply a pre-built index or a reference fasta file (in which case the index will be built), and also have an option for saving the index if it needs to be built
- I want to support the use of a general reference database, not just nt - nothing in the implementation should be specific to use of nt
- it looks like there is already support for using megan's rma2info; see line 6 of the profiling.nf subworkflow. Leverage this fact when creating your module for megan sam2rma, by using similar format for the module and seeing if the same conda and docker requirements can be used
- the new taxonomic profiling workflow should go in profiling.nf rather than a new subworkflow
- there should be an option to save the minimap output for use separately from megan; it should also be configurable whether the megan steps after minimap2 are performed, or if just up to minimap2 alignment is performed.
- new modules should follow similar format to the most relevant nf-core module in the pipeline.
- we should first add and test support for using minimap to align against a taxonomic database, then add in the Megan postprocessing, then add in the ability to normalize the megan output with taxpasta
