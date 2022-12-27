
process UPLOAD_MONGO {
    tag "$meta.id"
    label 'process_low'

    input:
    tuple val(meta), path(vcf)
    path(url_mongo)
    path(prs)
    path(ancestry)

    output:
    tuple val(meta), path("$updated_mongodb"),   optional:true, emit: updated_mongodb

    script:
    """
    Rscript --vanilla /home/anabella/R/upload2mongo2.R \\
        -s ${vcf} \\
        -u ${url_mongo} \\
        -p ${prs}  \\
        -v ${vcf} \\
        -a ${ancestry} \\
    """

}
