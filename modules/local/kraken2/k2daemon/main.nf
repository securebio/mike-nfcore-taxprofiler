process KRAKEN2_K2DAEMON {
    tag "${meta.db_name ?: 'database'}"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/kraken2:2.1.5--pl5321hdcf5f25_0':
        'biocontainers/kraken2:2.1.5--pl5321hdcf5f25_0' }"

    input:
    tuple val(meta), path(reads), val(prefixes)
    path  db
    val   save_output_fastqs
    val   save_reads_assignment

    output:
    tuple val(meta), path('*.classified{.,_}*')   , optional:true, emit: classified_reads_fastq
    tuple val(meta), path('*.unclassified{.,_}*') , optional:true, emit: unclassified_reads_fastq
    tuple val(meta), path('*classifiedreads.txt') , optional:true, emit: classified_reads_assignment
    tuple val(meta), path('*report.txt')                         , emit: report
    path "versions.yml"                                           , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def classified = meta.single_end ? "\${PREFIX}.classified.fastq" : "\${PREFIX}.classified#.fastq"
    def unclassified = meta.single_end ? "\${PREFIX}.unclassified.fastq" : "\${PREFIX}.unclassified#.fastq"
    def classified_option = save_output_fastqs ? "--classified-out \"${classified}\"" : ''
    def unclassified_option = save_output_fastqs ? "--unclassified-out \"${unclassified}\"" : ''
    def output_option = save_reads_assignment ? '--output "\${PREFIX}.kraken2.classifiedreads.txt"' : '--output /dev/null'
    def paired = meta.single_end ? '' : '--paired'
    def compress_reads_command = save_output_fastqs ? "find . -name '*.fastq' -print0 | xargs -0 -t -P ${task.cpus} -I % pigz --no-name %" : ''
    def command_inputs_file = '.inputs.txt'

    if (meta.single_end) {
        assert reads.size() == prefixes.size()
        command_inputs = [reads, prefixes].transpose().collect { read, prefix -> "${read}\t${prefix}" }

        """
        # Store the batch of samples for later command input
        cat <<-END_INPUTS > ${command_inputs_file}
        ${command_inputs.join('\n        ')}
        END_INPUTS

        # Process each sample through k2 daemon
        while IFS='\t' read -r READ PREFIX; do
            k2 classify \\
                --use-daemon \\
                --db ${db} \\
                --threads ${task.cpus} \\
                --report \${PREFIX}.kraken2.report.txt \\
                ${classified_option} \\
                ${unclassified_option} \\
                ${output_option} \\
                ${args} \\
                "\${READ}"
        done < ${command_inputs_file}

        # Stop the daemon
        k2 clean --stop-daemon

        # Compress output fastq files if they were saved
        ${compress_reads_command}

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            k2: \$(echo \$(k2 --version 2>&1) | sed 's/^.*version //; s/ .*\$//')
            pigz: \$(pigz --version 2>&1 | sed 's/pigz //g')
        END_VERSIONS
        """
    }
    else {
        assert reads.size() / 2 == prefixes.size()
        command_inputs = [reads.collate(2), prefixes].transpose().collect { pair, prefix -> "${pair[0]}\t${pair[1]}\t${prefix}" }

        """
        # Store the batch of samples for later command input
        cat <<-END_INPUTS > ${command_inputs_file}
        ${command_inputs.join('\n        ')}
        END_INPUTS

        # Process each sample through k2 daemon
        while IFS='\t' read -r READ1 READ2 PREFIX; do
            k2 classify \\
                --use-daemon \\
                --db ${db} \\
                --threads ${task.cpus} \\
                --report \${PREFIX}.kraken2.report.txt \\
                ${classified_option} \\
                ${unclassified_option} \\
                ${output_option} \\
                ${paired} \\
                ${args} \\
                "\${READ1}" "\${READ2}"
        done < ${command_inputs_file}

        # Stop the daemon
        k2 clean --stop-daemon

        # Compress output fastq files if they were saved
        ${compress_reads_command}

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            k2: \$(echo \$(k2 --version 2>&1) | sed 's/^.*version //; s/ .*\$//')
            pigz: \$(pigz --version 2>&1 | sed 's/pigz //g')
        END_VERSIONS
        """
    }

    stub:
    """
    for prefix in ${prefixes.join(' ')}; do
        touch \${prefix}.kraken2.report.txt
        [ "${save_output_fastqs}" == "true" ] && touch \${prefix}.classified.fastq.gz && touch \${prefix}.unclassified.fastq.gz
        [ "${save_reads_assignment}" == "true" ] && touch \${prefix}.kraken2.classifiedreads.txt
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        k2: 2.1.5
        pigz: 2.8
    END_VERSIONS
    """
}
