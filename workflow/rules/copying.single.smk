def get_fastq(wildcards):
    return RAW+"/"+samples.loc[(wildcards.library,wildcards.run), ["r1_file"]].dropna()

def get_lib_perRunAndSample(wildcards,prefix,suffix):
    return prefix+samples.loc[(samples['run']==wildcards.run) & (samples['sample']==wildcards.sample), "library"].unique()+suffix

localrules: primers_control

rule primers_control:
    input:
        expand("preprocessing/{samples.run}/{samples.sample}.fastq.gz", samples=samples.itertuples()),
        "reporting/readNumbers.tsv",
        "reporting/primerNumbers_perSample.tsv"
    output:
        "copying_raw_files.done"
    shell:
        """
        touch {output}
        """

rule combine_or_rename:
    input:
        "reporting/primerNumbers_perLibrary.tsv",
        files = lambda wildcards: get_lib_perRunAndSample(wildcards,"preprocessing/{run}/",".fastq.gz")    
    output:
        "preprocessing/{run}/{sample}.fastq.gz"
    wildcard_constraints:
        sample='|'.join(samples['sample'])
    threads: 1
    log: "logs/combine_or_rename.{run}.{sample}.log"
    resources:
        runtime="01:00:00",
        mem=config['normalMem']
    run:
        if len(input) > 1:
            shell("cat {input.files} > {output}")
        else:
            shell("mv {input.files} {output}")

rule input_numbers:
    input:
        "reporting/sample_table.tsv",
        expand("{raw_directory}/{file}", file=samples.r1_file,raw_directory=RAW)
    output:
        report("reporting/readNumbers.tsv",category="Reads")
    threads: 1
    params:
        currentStep = "raw",
        raw_directory = RAW
    resources:
        runtime="12:00:00",
        mem=config['normalMem']
    conda: ENVDIR + "dada2_env.yml"
    log: "logs/countInputReads.log"
    script:
        SCRIPTSDIR+"report_readNumbers.single.R" 


rule primer_numbers:
    input:
        "reporting/readNumbers.tsv",
        expand("preprocessing/{samples.run}/{samples.library}.fastq.gz", samples=samples.itertuples())
    output:
        report("reporting/primerNumbers_perLibrary.tsv",category="Reads"),
        report("reporting/primerNumbers_perSample.tsv",category="Reads")
    threads: 1
    params:
        currentStep = "primers"
    resources:
        runtime="12:00:00",
        mem=config['normalMem']
    log: "logs/countPrimerReads.log"
    conda: ENVDIR + "dada2_env.yml"
    script:
        SCRIPTSDIR+"report_readNumbers.single.R"

rule copy_fwd:
    input:
        get_fastq
    output:
        "preprocessing/{run}/{library}.fastq.gz",
    threads: 1
    resources:
        runtime="12:00:00",
        mem=config['normalMem']
    log: "logs/copying.{run}.{library}.log"
    message: "Running copying {input} to {output}. Keeping forward reads."
    shell:
        """
        if [[ {input[0]} = *.gz ]]
        then
          cp {input[0]} {output[0]}
        else
          gzip -c {input[0]} > {output[0]}
        fi
        """

