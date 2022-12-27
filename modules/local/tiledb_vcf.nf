
process TILEDBVCF_STORE {
    tag 'store_vcf'
    label 'process_low'

   // container 'tiledb/tiledbvcf-cli:latest'
   //conda '/home/anabella/anaconda3/envs/myenv'

    input:
    tuple val(meta), path(vcf), path(tbi)
    path(tiledb_array_uri)

    output:
    tuple val(meta), path("$updated_db")    , optional:true, emit: updatedb

    script:
   // updated_db = ""
    """
    /home/anabella/anaconda3/envs/myenv/bin/tiledbvcf store --uri ${tiledb_array_uri} ${vcf}
    """

}
