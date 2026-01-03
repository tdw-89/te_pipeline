# TE Pipeline

A Nextflow pipeline for de novo transposable element (TE) identification in genome sequences.

## Overview

This pipeline uses the following tools to identify transposable elements:

1. **RepeatModeler2** (`REPEATMODELER_BUILDDATABASE` + `REPEATMODELER_REPEATMODELER`)
   - Builds a BLAST database from the input genome
   - Performs de novo repeat family identification and modeling

2. **RepeatMasker** (`REPEATMASKER_REPEATMASKER`)
   - Screens the genome for repeats using the de novo repeat library from RepeatModeler
   - Produces masked sequences and annotation files

3. **OneCodeToFindThemAll** (`ONECODETOFINDTHEMALL`) - *Stub Module*
   - Parses RepeatMasker output to identify high-confidence TE sequences
   - Uses heuristics to filter and classify TEs
   - **Note**: This module requires custom implementation with the OneCodeToFindThemAll Perl scripts

## Requirements

- [Nextflow](https://www.nextflow.io/) >= 23.04.0
- Container runtime: [Apptainer](https://apptainer.org/) (recommended for HPC), [Singularity](https://sylabs.io/singularity/), or [Docker](https://www.docker.com/)

## Installation

Clone this repository:

```bash
git clone https://github.com/tdw-89/te_pipeline.git
cd te_pipeline
```

## Usage

### Basic Usage

```bash
nextflow run main.nf --input <genome.fasta> -profile <profile>
```

### Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--input` | Path to input genome FASTA file (required) | - |
| `--outdir` | Output directory | `results` |
| `--help` | Show help message | - |

### Profiles

| Profile | Description |
|---------|-------------|
| `apptainer` | Use Apptainer containers |
| `singularity` | Use Singularity containers |
| `docker` | Use Docker containers |
| `unity` | UMass Unity cluster (Apptainer + SLURM) |
| `test` | Test with minimal resources |

### Examples

**Run with Apptainer (recommended for HPC):**
```bash
nextflow run main.nf --input genome.fasta -profile apptainer
```

**Run on UMass Unity cluster:**
```bash
nextflow run main.nf --input genome.fasta -profile unity
```

**Run with Docker:**
```bash
nextflow run main.nf --input genome.fasta -profile docker
```

## Pipeline Steps

```
Input Genome (FASTA)
        │
        ▼
┌───────────────────────────┐
│ REPEATMODELER_BUILDDATABASE│
│ Build BLAST database      │
└───────────────────────────┘
        │
        ▼
┌───────────────────────────┐
│ REPEATMODELER_REPEATMODELER│
│ De novo repeat modeling   │
└───────────────────────────┘
        │
        ▼ (repeat library)
┌───────────────────────────┐
│ REPEATMASKER_REPEATMASKER │ ◄── Input genome
│ Identify repeat locations │
└───────────────────────────┘
        │
        ▼
┌───────────────────────────┐
│ ONECODETOFINDTHEMALL      │
│ High-confidence TE ID     │
└───────────────────────────┘
        │
        ▼
    Output Files
```

## Output

The pipeline produces the following outputs in the `results` directory:

```
results/
├── repeatmodeler/
│   ├── database/           # RepeatModeler database files
│   └── families/           # Identified repeat families (.fa, .stk, .log)
├── repeatmasker/           # RepeatMasker output (.masked, .out, .tbl, .gff)
├── onecodetofindthemall/   # High-confidence TE identification results
└── pipeline_info/          # Execution reports and trace files
```

## Custom Module: OneCodeToFindThemAll

The `ONECODETOFINDTHEMALL` module is currently a stub that needs to be implemented with the actual OneCodeToFindThemAll Perl scripts.

### Resources
- Original paper: [One code to find them all](https://link.springer.com/article/10.1186/1759-8753-5-13)
- Tool website: [https://doua.prabi.fr/software/one-code-to-find-them-all](https://doua.prabi.fr/software/one-code-to-find-them-all)

### Implementation Notes
1. Download the OneCodeToFindThemAll Perl scripts from the website
2. Create a custom container or conda environment with the scripts
3. Update the `modules/local/onecodetofindthemall/main.nf` file with the actual commands

## nf-core Modules

This pipeline uses the following nf-core modules:
- `repeatmodeler/builddatabase` - [nf-core page](https://nf-co.re/modules/repeatmodeler_builddatabase/)
- `repeatmodeler/repeatmodeler` - [nf-core page](https://nf-co.re/modules/repeatmodeler_repeatmodeler/)
- `repeatmasker/repeatmasker` - [nf-core page](https://nf-co.re/modules/repeatmasker_repeatmasker/)

## License

This pipeline is open source. Individual tools have their own licenses:
- RepeatModeler: Open Software License v2.1
- RepeatMasker: Open Software License v2.1
- OneCodeToFindThemAll: See tool website

## Citations

If you use this pipeline, please cite the following tools:

- **RepeatModeler2**: Flynn, J.M., Hubley, R., Goubert, C. et al. RepeatModeler2 for automated genomic discovery of transposable element families. PNAS 117, 9451-9457 (2020).
- **RepeatMasker**: Smit, AFA, Hubley, R & Green, P. RepeatMasker Open-4.0. http://www.repeatmasker.org
- **OneCodeToFindThemAll**: Bailly-Bechet, M., Haudry, A. & Lerat, E. "One code to find them all": a perl tool to conveniently parse RepeatMasker output files. Mobile DNA 5, 13 (2014).
