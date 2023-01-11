process TILEDBVCF_LIST {
    tag "$uri"
    label 'process_medium'

    conda "tiledb::tiledbvcf-py=0.21.0"
    container "${ 'tiledb/tiledbvcf-cli:0.21.0' }"
    containerOptions '--entrypoint ""'

    input:
    val(uri)

    output:
    stdout
    path  "versions.yml"          , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    """
    tiledbvcf \\
        list \\
        --uri $uri \\
        $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        tiledbvcf: \$(tiledbvcf --version 2>&1 | head -n 1 | sed 's/^TileDB-VCF version //')
    END_VERSIONS
    """
}
