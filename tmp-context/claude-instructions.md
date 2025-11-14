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
