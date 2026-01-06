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
        --repeat_lib    Path to pre-built repeat library FASTA file.
                        If provided, skips RepeatModeler and starts from RepeatMasker.
        --outdir        Output directory (default: 'results')
        --help          Show this help message
    
    Examples:
        # Full pipeline (de novo repeat identification)
        nextflow run main.nf --input genome.fasta
        
        # Start from RepeatMasker with existing repeat library
        nextflow run main.nf --input genome.fasta --repeat_lib repeats.fa
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
    // Determine repeat library source:
    // Either use provided library or run RepeatModeler de novo
    //
    if (params.repeat_lib) {
        // Use pre-built repeat library (skip RepeatModeler)
        log.info "Using provided repeat library: ${params.repeat_lib}"
        def lib_file = file(params.repeat_lib, checkIfExists: true)
        ch_repeat_lib = channel.of(lib_file)
        ch_versions_repeatmodeler = channel.empty()
    } else {
        // Run RepeatModeler de novo
        log.info "No repeat library provided, running RepeatModeler de novo..."
        
        //
        // STEP 1: Build RepeatModeler database from input genome
        //
        REPEATMODELER_BUILDDATABASE(ch_genome)

        //
        // STEP 2: Run RepeatModeler to identify de novo repeat families
        //
        REPEATMODELER_REPEATMODELER(REPEATMODELER_BUILDDATABASE.out.db)
        
        ch_repeat_lib = REPEATMODELER_REPEATMODELER.out.fasta.map { _meta, fasta -> fasta }
        ch_versions_repeatmodeler = REPEATMODELER_BUILDDATABASE.out.versions
            .mix(REPEATMODELER_REPEATMODELER.out.versions)
    }

    //
    // STEP 3: Run RepeatMasker using the repeat library
    // Uses the genome FASTA and the repeat library (provided or from RepeatModeler)
    //
    REPEATMASKER_REPEATMASKER(
        ch_genome,
        ch_repeat_lib
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
    ch_versions = ch_versions_repeatmodeler
        .mix(REPEATMASKER_REPEATMASKER.out.versions)
        .mix(ONECODETOFINDTHEMALL.out.versions)
        .collectFile(name: 'collated_versions.yml')

    CUSTOM_DUMPSOFTWAREVERSIONS(ch_versions)
}
