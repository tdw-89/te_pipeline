nextflow.enable.dsl = 2

include { REPEATMODELER_BUILDDATABASE } from 'github:nf-core/modules//modules/nf-core/repeatmodeler/builddatabase'
include { REPEATMODELER_REPEATMODELER }  from 'github:nf-core/modules//modules/nf-core/repeatmodeler/repeatmodeler'
include { REPEATMASKER_REPEATMASKER }     from 'github:nf-core/modules//modules/nf-core/repeatmasker/repeatmasker'

/*
 * Minimal TE discovery pipeline
 * 1. Build RepeatModeler blast database
 * 2. Run RepeatModeler to infer repeat library
 * 3. Run RepeatMasker using inferred library on the original genome
 */

workflow {
    checkParams()

    Channel
        .fromPath(params.genome, checkIfExists: true)
        .ifEmpty { exit 1, "Genome FASTA not found: ${params.genome}" }
        .map { fasta ->
            def sampleId = params.prefix ?: fasta.getBaseName()
            tuple([id: sampleId], fasta)
        }
        .into { genome_for_db; genome_for_mask }

    db_results     = REPEATMODELER_BUILDDATABASE(genome_for_db)
    repmod_results = REPEATMODELER_REPEATMODELER(db_results.db)

    repeatmasker_input = genome_for_mask
        .map { meta, fasta -> [meta.id, tuple(meta, fasta)] }
        .join(
            repmod_results.fasta.map { meta, lib -> [meta.id, tuple(meta, lib)] }
        )
        .map { id, genomeTuple, libTuple ->
            def (meta, fasta) = genomeTuple
            def (libMeta, lib) = libTuple
            assert meta.id == libMeta.id
            tuple(meta, fasta, lib)
        }

    repeatmasker_input.into { repeatmasker_fasta; repeatmasker_lib }

    repeatmasker_results = REPEATMASKER_REPEATMASKER(
        repeatmasker_fasta.map { meta, fasta, lib -> tuple(meta, fasta) },
        repeatmasker_lib.map { meta, fasta, lib -> lib }
    )

    emit:
        db_results.db
        repmod_results.fasta
        repeatmasker_results.masked
        repeatmasker_results.out
        repeatmasker_results.tbl
        repeatmasker_results.gff
        db_results.versions.mix(repmod_results.versions).mix(repeatmasker_results.versions)
}

def checkParams() {
    if (!params.genome) {
        exit 1, "Please provide a genome FASTA with --genome"
    }
}
