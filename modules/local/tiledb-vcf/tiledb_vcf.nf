
process TILEDBVCF_STORE {
    tag "$meta.id"
    label 'process_low'

    //container 'tiledb/tiledb:2.13.0'
    container 'tiledb/tiledbvcf-cli:latest'

    input:
    tuple val(meta), path(vcf), path(tbi)
    path(tiledb_array_uri)

    output:
    tuple val(meta), path("$updated_db")    , optional:true, emit: updatedb

    script:
    """
    tiledbvcf store --uri ${tiledb_array_uri} ${vcf}
    """

    //tiledbvcf store --uri ${tiledb_array_uri} ${vcf}
    // /home/anabella/anaconda3/envs/myenv/bin/tiledbvcf store --uri ${tiledb_array_uri} ${vcf}

}
