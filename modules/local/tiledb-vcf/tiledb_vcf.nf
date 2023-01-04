
process TILEDBVCF_STORE {
    tag "$meta.id"
    label 'process_high'

    container "tiledb/tiledbvcf-cli:latest" // Call to a system-wide image

    input:
    tuple val(meta), path(vcf), path(tbi), path(tiledb_array_uri)


    output:
    tuple val(meta), path("$updated_db")    , optional:true, emit: updatedb

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''

    uri_command = "--uri ${tiledb_array_uri}"
    samples_command = "--samples-file ${vcf} ${tbi}"


    """
    tiledbvcf store $uri_command $samples_command $args
    """

    updated_db = "${tiledb_array_uri}"

}
