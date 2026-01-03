#!/usr/bin/env nextflow
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Transposable Element (TE) Identification Pipeline
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    A Nextflow pipeline for de novo transposable element identification using:
    - RepeatModeler2 for building TE consensus sequences
    - RepeatMasker for identifying TE locations in the genome
    - OneCodeToFindThemAll for high-confidence TE identification (stub module)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

nextflow.enable.dsl = 2

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { REPEATMODELER_BUILDDATABASE } from './modules/nf-core/repeatmodeler/builddatabase/main'
include { REPEATMODELER_REPEATMODELER } from './modules/nf-core/repeatmodeler/repeatmodeler/main'
include { REPEATMASKER_REPEATMASKER   } from './modules/nf-core/repeatmasker/repeatmasker/main'
include { ONECODETOFINDTHEMALL        } from './modules/local/onecodetofindthemall/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PRINT HELP MESSAGE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

def helpMessage() {
    log.info """
    =========================================
    TE PIPELINE v${workflow.manifest.version}
    =========================================
    
    Usage:
        nextflow run main.nf --input <genome.fasta> [options]
    
    Mandatory arguments:
        --input         Path to input genome FASTA file
    
    Optional arguments:
        --outdir        Output directory (default: 'results')
        --help          Show this help message
    
    Profiles:
        -profile singularity    Use Singularity containers
        -profile apptainer      Use Apptainer containers
        -profile docker         Use Docker containers
        -profile unity          UMass Unity cluster with Apptainer and SLURM
        -profile test           Test with minimal resources
    
    Example:
        nextflow run main.nf --input genome.fasta -profile apptainer
        nextflow run main.nf --input genome.fasta -profile unity
    """.stripIndent()
}

if (params.help) {
    helpMessage()
    exit 0
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    VALIDATE INPUTS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

if (!params.input) {
    log.error "ERROR: --input parameter is required. Please provide a genome FASTA file."
    helpMessage()
    exit 1
}

// Check if input file exists
input_file = file(params.input, checkIfExists: true)

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow {
    // Create input channel with metadata
    // Format: [ [id: sample_name], path_to_fasta ]
    ch_genome = channel.of(
        [ [id: input_file.getBaseName()], input_file ]
    )

    //
    // STEP 1: Build RepeatModeler database from input genome
    //
    REPEATMODELER_BUILDDATABASE(ch_genome)

    //
    // STEP 2: Run RepeatModeler to identify de novo repeat families
    //
    REPEATMODELER_REPEATMODELER(REPEATMODELER_BUILDDATABASE.out.db)

    //
    // STEP 3: Run RepeatMasker using the de novo repeat library
    // Uses the genome FASTA and the repeat families identified by RepeatModeler
    //
    REPEATMASKER_REPEATMASKER(
        ch_genome,
        REPEATMODELER_REPEATMODELER.out.fasta.map { meta, fasta -> fasta }
    )

    //
    // STEP 4: Run OneCodeToFindThemAll for high-confidence TE identification
    // Uses the RepeatMasker output to identify high-confidence TEs
    //
    ONECODETOFINDTHEMALL(
        REPEATMASKER_REPEATMASKER.out.out,
        ch_genome.map { meta, fasta -> fasta }
    )

    //
    // Collect version information from all modules
    //
    ch_versions = REPEATMODELER_BUILDDATABASE.out.versions
        .mix(REPEATMODELER_REPEATMODELER.out.versions)
        .mix(REPEATMASKER_REPEATMASKER.out.versions)
        .mix(ONECODETOFINDTHEMALL.out.versions)
        .collect()
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    COMPLETION MESSAGES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow.onComplete {
    log.info ""
    log.info "Pipeline completed at: ${workflow.complete}"
    log.info "Execution status: ${workflow.success ? 'SUCCESS' : 'FAILED'}"
    log.info "Execution duration: ${workflow.duration}"
    log.info "Output directory: ${params.outdir}"
    log.info ""
}

workflow.onError {
    log.error "Pipeline execution stopped with error: ${workflow.errorMessage}"
}
