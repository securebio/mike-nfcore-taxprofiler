process DOWNLOAD_PUBLIC_S3 {
    tag "${s3_uri}"
    label 'process_single'

    conda "conda-forge::awscli=2.13.0"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/awscli:2.13.0--h0a1ffe4_0' :
        'biocontainers/awscli:2.13.0--h0a1ffe4_0' }"

    input:
    val s3_uri

    output:
    tuple val(s3_uri), path("downloaded_file"), emit: file
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    """
    aws s3 cp \\
        --no-sign-request \\
        ${args} \\
        ${s3_uri} \\
        downloaded_file

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        awscli: \$(aws --version 2>&1 | sed 's/aws-cli\\///; s/ Python.*//')
    END_VERSIONS
    """

    stub:
    """
    touch downloaded_file
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        awscli: \$(aws --version 2>&1 | sed 's/aws-cli\\///; s/ Python.*//')
    END_VERSIONS
    """
}
