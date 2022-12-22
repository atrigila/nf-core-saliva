
process TILEDBVCF_STORE {
    tag 'store_vcf'
    label 'process_low'

    container 'tiledb/tiledbvcf-cli:latest'

    input:
    tuple val(meta), path(vcf)
    path(tiledb_array_uri)

    output:
    tuple val(meta), path("$updated_db")    , optional:true, emit: updatedb
    path 'versions.yml', emit: versions

    script:
   // updated_db = ""
    """
    tiledbvcf store --uri ${tiledb_array_uri} ${vcf}
    """

}
