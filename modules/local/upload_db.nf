
process UPLOAD_MONGO {
    tag "$meta.id"
    label 'process_low'


    input:
    tuple val(meta), path(vcf), path(prs), path(ancestry), val(mongo_uri)

    output:
    tuple val(meta), path("$updated_mongodb"),   optional:true, emit: updated_mongodb

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    Rscript --vanilla /home/anabella/R/upload2mongo2.r \\
        -s ${prefix} \\
        -p ${prs}  \\
        -v ${vcf} \\
        -a ${ancestry} \\
        -u ${mongo_uri}
    """

}
