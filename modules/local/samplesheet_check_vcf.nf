process SAMPLESHEET_CHECK_VCF {
    tag "$samplesheet"
    label 'process_single'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/mulled-v2-1021c2bc41756fa99bc402f461dad0d1c35358c1:b0c847e4fb89c343b04036e33b2daa19c4152cf5-0' :
        'quay.io/biocontainers/mulled-v2-1021c2bc41756fa99bc402f461dad0d1c35358c1:b0c847e4fb89c343b04036e33b2daa19c4152cf5-0' }"

    input:
    path samplesheet

    output:
    path '*.csv'       , emit: csv
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script: // This script is bundled with the pipeline, in nf-core/test/bin/
    """
    samplesheet_check.R \\
        -i $samplesheet \\
        -o samplesheet.valid.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //g')
    END_VERSIONS
    """
}
