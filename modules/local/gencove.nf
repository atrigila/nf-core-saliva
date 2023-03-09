
process GENCOVE_DOWNLOAD {
    tag "$projectid"
    label 'process_medium'

    conda "bioconda::gencove=2.4.5"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/gencove:2.4.5--pyhdfd78af_0':
        'quay.io/biocontainers/gencove:2.4.5--pyhdfd78af_0' }"

    input:
    val(projectid)
    val(api_key)

    output:
    path('*.vcf.gz')       ,        optional:true       , emit: vcf
    path('*_traits-json.json'),     optional:true       , emit: traitsjson
    path('*_ancestry-json.json'),   optional:true       , emit: ancestryjson
    path('*.tbi'),                  optional:true       , emit: tbi
    path "versions.yml"                                 , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''

    """
    gencove \\
        download . \\
        $args \\
        --project-id $projectid \\
        --api-key $api_key

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        gencove: \$(echo \$(gencove --version 2>&1) | sed 's/.*version //' )
    END_VERSIONS
    """
}
