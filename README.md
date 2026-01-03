# te_pipeline

Minimal Nextflow pipeline for de novo identification of transposable elements (TEs) using nf-core modules for RepeatModeler/RepeatMasker.

## Requirements
- [Nextflow](https://www.nextflow.io/) (DSL2)
- Container or package management of your choice (choose a profile):
  - `-profile docker` (default recommendation)
  - `-profile singularity`
  - `-profile conda`
- Internet access on first run to fetch nf-core modules/containers

## Usage
```bash
nextflow run main.nf \
  --genome /path/to/genome.fasta \
  --outdir results \
  -profile docker
```

Optional parameters:
- `--prefix`: sample/prefix name (defaults to fasta basename)
- `--repeatmodeler_args`: additional arguments passed to RepeatModeler
- `--repeatmasker_args`: additional arguments passed to RepeatMasker

## Pipeline steps
1. **BuildDatabase (RepeatModeler)** – prepare the genome as a BLAST database.
2. **RepeatModeler** – infer a de novo repeat library from the database.
3. **RepeatMasker** – mask the original genome using the inferred library.

Outputs are written to `--outdir` in subfolders for each step (`builddatabase/`, `repeatmodeler/`, `repeatmasker/`). Masked genome, `.out`, `.tbl`, and optional `.gff` files are produced by RepeatMasker.
