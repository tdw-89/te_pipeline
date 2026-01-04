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
    HELP MESSAGE FUNCTION
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
    
    Example:
        nextflow run main.nf --input genome.fasta
    """.stripIndent()
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PROCESS: DUMP SOFTWARE VERSIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

process CUSTOM_DUMPSOFTWAREVERSIONS {
    label 'process_single'
    
    // Use a minimal container with basic shell utilities
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/ubuntu:22.04':
        'ubuntu:22.04' }"
    
    publishDir "${params.outdir}/pipeline_info", mode: 'copy'

    input:
    path versions

    output:
    path "software_versions.yml"    , emit: yml
    path "software_versions_mqc.yml", emit: mqc_yml

    script:
    """
    cat $versions > software_versions.yml
    
    # Create MultiQC-compatible version for reporting
    echo "id: 'software_versions'" > software_versions_mqc.yml
    echo "section_name: 'TE Pipeline Software Versions'" >> software_versions_mqc.yml
    echo "plot_type: 'html'" >> software_versions_mqc.yml
    echo "data: |" >> software_versions_mqc.yml
    echo "  <dl class='dl-horizontal'>" >> software_versions_mqc.yml
    cat $versions | sed 's/^/    /' >> software_versions_mqc.yml
    echo "  </dl>" >> software_versions_mqc.yml
    """
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow {
    //
    // VALIDATE INPUTS
    //
    if (params.help) {
        helpMessage()
        exit 0
    }

    if (!params.input) {
        log.error "ERROR: --input parameter is required. Please provide a genome FASTA file."
        helpMessage()
        exit 1
    }

    // Check if input file exists
    def input_file = file(params.input, checkIfExists: true)

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
        REPEATMODELER_REPEATMODELER.out.fasta.map { _meta, fasta -> fasta }
    )

    //
    // STEP 4: Run OneCodeToFindThemAll for high-confidence TE identification
    // Uses the RepeatMasker output to identify high-confidence TEs
    //
    ONECODETOFINDTHEMALL(
        REPEATMASKER_REPEATMASKER.out.out,
        ch_genome.map { _meta, fasta -> fasta }
    )

    //
    // Collect version information from all modules and save to disk
    //
    ch_versions = REPEATMODELER_BUILDDATABASE.out.versions
        .mix(REPEATMODELER_REPEATMODELER.out.versions)
        .mix(REPEATMASKER_REPEATMASKER.out.versions)
        .mix(ONECODETOFINDTHEMALL.out.versions)
        .collectFile(name: 'collated_versions.yml')

    CUSTOM_DUMPSOFTWAREVERSIONS(ch_versions)
}
