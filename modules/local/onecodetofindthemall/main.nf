/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    OneCodeToFindThemAll - Custom Local Module
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    This module uses the OneCodeToFindThemAll Perl scripts to parse RepeatMasker 
    output and identify high-confidence transposable element (TE) sequences, 
    followed by Julia-based aggregation.
    
    The workflow:
    1. build_dictionary.pl - Build LTR dictionary from RepeatMasker output
    2. one_code_to_find_them_all.pl - Parse and identify high-confidence TEs
    3. aggregate.jl - Aggregate and format all output files
    
    Original Paper: https://link.springer.com/article/10.1186/1759-8753-5-13
    Tool Website: https://doua.prabi.fr/software/one-code-to-find-them-all
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

process ONECODETOFINDTHEMALL {
    tag "$meta.id"
    label 'process_medium'

    // Container with Perl + Julia + OneCodeToFindThemAll scripts
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'docker://tdw0student0uml/octfta:v1.0':
        'tdw0student0uml/octfta:v1.0' }"

    input:
    tuple val(meta), path(repeatmasker_out)
    path(genome_fasta)

    output:
    tuple val(meta), path("${prefix}_octrta_output")       , emit: octrta_dir
    tuple val(meta), path("${prefix}_aggregated.csv")      , emit: aggregated
    tuple val(meta), path("${prefix}_aggregated_compat.csv"), emit: aggregated_compat
    tuple val(meta), path("${prefix}_dictionary.txt")      , emit: dictionary
    path "versions.yml"                                    , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args_dict   = task.ext.args_dict    ?: ''
    def args_octrta = task.ext.args_octrta  ?: ''
    def prefix      = task.ext.prefix       ?: "${meta.id}"
    """
    # Set Julia depot path to a writable location (container's /opt is read-only)
    export JULIA_DEPOT_PATH="\${PWD}/.julia"
    mkdir -p "\${JULIA_DEPOT_PATH}"

    # Create output directory for OCTRTA results
    mkdir -p ${prefix}_octrta_output

    # OCTRTA's Wanted_Fasta subroutine only matches .fa files
    # Create a symlink with .fa extension if needed
    genome_fa="${genome_fasta}"
    if [[ ! "${genome_fasta}" =~ \\.fa\$ ]]; then
        genome_fa="genome_input.fa"
        ln -sf ${genome_fasta} \${genome_fa}
    fi

    # Step 1: Build the LTR dictionary from RepeatMasker output
    # This identifies LTR/internal element associations
    build_dictionary.pl \\
        --rm ${repeatmasker_out} ${args_dict} \\
        > ${prefix}_dictionary.txt

    # Check if dictionary is empty (no LTR elements found)
    if [ ! -s ${prefix}_dictionary.txt ]; then
        echo "# No LTR elements found - empty dictionary" > ${prefix}_dictionary.txt
    fi

    # Step 2: Run OneCodeToFindThemAll to identify high-confidence TEs
    # Uses the dictionary to properly associate LTR and internal regions
    echo "DEBUG: Running one_code_to_find_them_all.pl..."
    echo "DEBUG: genome_fa value is: \${genome_fa}"
    one_code_to_find_them_all.pl \\
        --rm ${repeatmasker_out} \\
        --ltr ${prefix}_dictionary.txt \\
        --fasta "\${genome_fa}" ${args_octrta}
    echo "DEBUG: one_code_to_find_them_all.pl completed"

    # Move all generated output files to the output directory
    # OCTRTA creates files with patterns: *.transposons.csv, *.ltr.csv, 
    # *.copynumber.csv, *.elem_sorted.csv, etc.
    find . -maxdepth 1 -name "*.csv" -exec mv {} ${prefix}_octrta_output/ \\;
    find . -maxdepth 1 -name "*.log.txt" -exec mv {} ${prefix}_octrta_output/ \\;
    find . -maxdepth 1 -name "*.length" -exec mv {} ${prefix}_octrta_output/ \\;
    find . -maxdepth 1 -name "*.fasta" ! -name "${genome_fasta}" -exec mv {} ${prefix}_octrta_output/ \\; || true

    # Step 3: Aggregate results using Julia script
    # Check if there are any output files to aggregate
    tp_count=\$(find ${prefix}_octrta_output -name "*.transposons.csv" 2>/dev/null | wc -l)
    ltr_count=\$(find ${prefix}_octrta_output -name "*.ltr.csv" 2>/dev/null | wc -l)

    if [ "\${tp_count}" -gt 0 ] || [ "\${ltr_count}" -gt 0 ]; then
        aggregate.jl \\
            --dir ${prefix}_octrta_output \\
            --output .
        mv aggregated.csv ${prefix}_aggregated.csv
        mv aggregated_compat.csv ${prefix}_aggregated_compat.csv
    else
        # No TEs found - create empty output files with headers
        echo "Score,%_Div,%_Del,%_Ins,Query,Beg.,End.,Length,Sense,Element,Family,Pos_Repeat_Beg,Pos_Repeat_End,Pos_Repeat_Left,ID,Num_Assembled,%_of_Ref" > ${prefix}_aggregated.csv
        echo "Chromosome,Start,End,Type,Family,GeneID" > ${prefix}_aggregated_compat.csv
        echo "Warning: No transposable elements identified by OneCodeToFindThemAll" >&2
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        onecodetofindthemall: "1.0.0"
        perl: \$(perl --version | grep 'version' | sed 's/.*v\\([0-9.]*\\).*/\\1/')
        julia: \$(julia --version | sed 's/julia version //')
    END_VERSIONS
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    mkdir -p ${prefix}_octrta_output
    touch ${prefix}_octrta_output/stub.transposons.csv
    touch ${prefix}_octrta_output/stub.ltr.csv
    
    echo "Chromosome,Start,End,Type,Family,GeneID" > ${prefix}_aggregated.csv
    echo "Chromosome,Start,End,Type,Family,GeneID" > ${prefix}_aggregated_compat.csv
    echo "# Stub dictionary" > ${prefix}_dictionary.txt
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        onecodetofindthemall: "1.0.0"
        perl: "stub"
        julia: "stub"
    END_VERSIONS
    """
}
