# Supporting Mixed Public and Private S3 Paths

## Problem

Some public S3 buckets (like `human-pangenomics`) have bucket policies that:
- Allow anonymous LIST operations
- Allow anonymous GET operations (downloads)
- **Explicitly deny** authenticated GET requests

This means these buckets can only be accessed with `--no-sign-request` flag in AWS CLI, even if you have valid AWS credentials. This creates a challenge when you need to use both public and private S3 paths in the same workflow.

## Solution

This pipeline now supports marking specific S3 paths as "public" so they will be downloaded explicitly with `--no-sign-request`, while other S3 paths use your authenticated AWS credentials.

## Usage

### New Parameters

Two new boolean parameters have been added:

- `hostremoval_reference_is_public`: Set to `true` if the host removal reference is a public S3 path that requires anonymous access
- `longread_hostremoval_index_is_public`: Set to `true` if the longread host removal index is a public S3 path that requires anonymous access

### Example Configuration

```yaml
# params.yaml
input: "./samplesheet.csv"
databases: "./databases.csv"
outdir: "./results/"

# Public S3 reference (requires --no-sign-request)
hostremoval_reference: "s3://human-pangenomics/T2T/CHM13/assemblies/analysis_set/chm13v2.0.fa.gz"
hostremoval_reference_is_public: true

# Private S3 index (uses your AWS credentials)
longread_hostremoval_index: "s3://your-private-bucket/path/to/index.mmi"
longread_hostremoval_index_is_public: false

perform_longread_hostremoval: true
```

### Command Line Usage

```bash
nextflow run nf-core/taxprofiler \
  -params-file params.yaml \
  -profile docker
```

Or with command line parameters:

```bash
nextflow run nf-core/taxprofiler \
  --input samplesheet.csv \
  --databases databases.csv \
  --hostremoval_reference "s3://human-pangenomics/T2T/CHM13/assemblies/analysis_set/chm13v2.0.fa.gz" \
  --hostremoval_reference_is_public true \
  --longread_hostremoval_index "s3://your-private-bucket/path/to/index.mmi" \
  --longread_hostremoval_index_is_public false \
  --perform_longread_hostremoval \
  -profile docker
```

## How It Works

1. When `*_is_public` is set to `true` for an S3 path:
   - The pipeline uses a dedicated `DOWNLOAD_PUBLIC_S3` process
   - This process runs `aws s3 cp --no-sign-request` to download the file
   - The downloaded file is then used in the workflow

2. When `*_is_public` is `false` or not set:
   - The file is accessed directly using Nextflow's built-in S3 support
   - This uses your configured AWS credentials

## Requirements

- The AWS CLI must be available in the execution environment
- For private S3 paths, AWS credentials must be properly configured
- For public S3 paths, no credentials are needed

## Testing

You can verify the bucket access policy with:

```bash
# Public bucket - this should work with --no-sign-request
aws s3 cp --no-sign-request s3://human-pangenomics/T2T/CHM13/assemblies/analysis_set/chm13v2.0.fa.gz test.fa.gz

# Public bucket - this might fail with authenticated access
aws s3 cp s3://human-pangenomics/T2T/CHM13/assemblies/analysis_set/chm13v2.0.fa.gz test.fa.gz
```

If the second command fails with "403 Forbidden" but the first succeeds, you need to use `hostremoval_reference_is_public: true`.

## Implementation Details

- New module: `modules/local/download_public_s3.nf`
- Modified workflow: `workflows/taxprofiler.nf`
- New parameters in: `nextflow.config`
- The download happens once at the start of the workflow and the file is reused throughout
