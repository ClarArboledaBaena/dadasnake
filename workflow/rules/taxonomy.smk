taxConts = ["sequenceTables/all.seqTab.tsv","sequenceTables/all.seqTab.RDS"]
if config['taxonomy']['decipher']['do'] or config['taxonomy']['mothur']['do']:
    taxConts.append("sequenceTables/all.seqTab.tax.tsv")
if config['blast']['do']:
    taxConts.append("sequenceTables/blast_results.tsv")
if config['hand_off']['phyloseq'] and not config['do_postprocessing']:
    taxConts.append("sequenceTables/all.seqTab.phyloseq.RDS")

localrules: taxonomy_control

rule taxonomy_control:
    input:
        taxConts
    output:
        "taxonomy.done"
    shell:
        """
        touch {output}
        """

taxTabs = ["sequenceTables/all.seqTab.RDS"]
if config['ITSx']['do']:
    taxTabs.append("sequenceTables/ITSx.seqs.fasta")
if config['taxonomy']['decipher']['do']:
    taxTabs.append("sequenceTables/tax.decipher.RDS")
if config['taxonomy']['mothur']['do']:
    taxTabs.append("sequenceTables/tax.mothur.tsv")

rule taxonomy_to_OTUtab:
    input:
        taxTabs
    output:
        "sequenceTables/all.seqTab.tax.tsv",
        "sequenceTables/all.seqTab.tax.RDS"
    threads: 12
    resources:
        runtime="12:00:00"
    conda: ENVDIR + "dada_env.yml"
    log: "logs/taxonomy.log"
    message: "Combining taxa and OTU tables {input}."
    script:
        SCRIPTSDIR+"add_taxonomy.R"

if config['taxonomy']['decipher']['post_ITSx']:
    rule decipher_taxonomy:
        input:
            "sequenceTables/ITSx.seqs.fasta"
        output:
            "sequenceTables/tax.decipher.tsv",
            "sequenceTables/tax.decipher.RDS"
        threads: 1
        resources:
            runtime="48:00:00"
        conda: ENVDIR + "dada_env.yml"
        log: "logs/decipher_taxonomy.log"
        message: "Running decipher on {input}."
        script:
            SCRIPTSDIR+"decipher_ID.R"
else:
    rule decipher_taxonomy:
        input:
            "sequenceTables/all.seqs.fasta"
        output:
            "sequenceTables/tax.decipher.tsv", 
            "sequenceTables/tax.decipher.RDS"
        threads: 1
        resources:
            runtime="48:00:00"
        conda: ENVDIR + "dada_env.yml"
        log: "logs/decipher_taxonomy.log"
        message: "Running decipher on {input}."
        script:
            SCRIPTSDIR+"decipher_ID.R"

if config['taxonomy']['mothur']['post_ITSx']:
    rule mothur_taxonomy_postITSx:
        input:
            "sequenceTables/ITSx.seqs.fasta"
        output:
            "sequenceTables/tax.mothur.tsv"
        threads: 6
        resources:
            runtime="48:00:00"
        params:
            outBase="sequenceTables/ITSx.seqs"
        conda: ENVDIR + "dada_env.yml"
        log: "logs/mothur_taxonomy.log"
        message: "Running mothur classifier on {input}."
        shell:
            """
            mothur "#set.dir(tempdefault={config[taxonomy][mothur][db_path]});
            classify.seqs(fasta={input}, template={config[taxonomy][mothur][tax_db]}.fasta, taxonomy={config[taxonomy][mothur][tax_db]}.taxonomy, cutoff={config[taxonomy][mothur][cutoff]}, method=wang, processors={threads})"
            mv {params[outBase]}.*.wang.taxonomy {output}
            """
else:
    rule mothur_taxonomy:
        input:
            "sequenceTables/all.seqs.fasta"
        output:
            "sequenceTables/tax.mothur.tsv"
        threads: 1
        resources:
            runtime="48:00:00"
        params:
            outBase="sequenceTables/all.seqs"
        conda: ENVDIR + "dada_env.yml"
        log: "logs/mothur_taxonomy.log"
        message: "Running mothur classifier on {input}."
        shell:
            """
            mothur "#set.dir(tempdefault={config[taxonomy][mothur][db_path]});
            classify.seqs(fasta={input}, template={config[taxonomy][mothur][tax_db]}.fasta, taxonomy={config[taxonomy][mothur][tax_db]}.taxonomy, cutoff={config[taxonomy][mothur][cutoff]}, method=wang, processors={threads})"
            mv {params[outBase]}.*.wang.taxonomy {output}
            """

if config['ITSx']['do']:
    rule ITSx:
        input:
            "sequenceTables/all.seqs.fasta"
        output:
            directory("sequenceTables/ITSx_out"),
            "sequenceTables/ITSx.seqs.fasta"
        threads: 12
        resources:
            runtime="12:00:00"
        log: "logs/ITSx.log"
        conda: ENVDIR + "dada_env.yml"
        message: "Running ITSx on {input}."
        shell:
            """
            PL5=${{PERL5LIB:-}}
            export PERL5LIB=$CONDA_PREFIX/lib/site_perl/5.26.2/x86_64-linux-thread-multi:$PL5
            mkdir {output[0]}
            ITSx -i {input} --cpu {threads} --detailed_results T --save_regions {config[ITSx][region]} --graphical F \
            -o {output[0]}/ITSx -N {config[ITSx][min_regions]} -E {config[ITSx][e_val]}
            grep '|F|{config[ITSx][region]}' -A 1 --no-group-separator {output[0]}/ITSx.{config[ITSx][region]}.fasta | sed 's/|.*//' > {output[1]}
            """

if config['blast']['do']:
    if not config['blast']['all']:
        rule prepare_blastn:
            input:
                expand("sequenceTables/all.seqTab.{tax}RDS",tax="tax." if (config['taxonomy']['decipher']['do'] or config['taxonomy']['mothur']['do']) else "")
            output:
                "sequenceTables/no_anno.seqs.fasta"
            threads: 12
            resources:
                runtime="2:00:00"
            log: "logs/prep_blastn.log"
            conda: ENVDIR + "dada_env.yml"
            message: "Preparing blast: extracting un-annotated sequences."
            script:
                SCRIPTSDIR+"prepare_blastn.R"
        BLAST_IN="sequenceTables/no_anno.seqs.fasta"
    else:
        BLAST_IN="sequenceTables/all.seqs.fasta"
    if config['blast']['tax2id'] == "" or config['blast']['tax2id'] == "none":
        rule blastn:
            input:
                BLAST_IN
            output:
                "sequenceTables/blast_results.tsv"
            threads: 6
            resources:
                runtime="48:00:00"
            log: "logs/blastn.log"
            conda: ENVDIR + "blast_env.yml"
            message: "Running blastn on {input}."
            shell:
                """
                if [ -s {input} ]; then
                  if [ ! -f "{config[blast][db_path]}/{config[blast][tax_db]}.nin" ]
                    then
                    makeblastdb -dbtype nucl -in {config[blast][db_path]}/{config[blast][tax_db]} -out {config[blast][db_path]}/{config[blast][tax_db]}
                  fi
                  blastn -db {config[blast][db_path]}/{config[blast][tax_db]} \
                   -query {input} -outfmt 7 -out {output} -max_target_seqs 10
                else
                  touch {output}
                fi
                """
    else:
        rule blastn:
            input:
                BLAST_IN
            output:
                "sequenceTables/blast_results.tsv"
            threads: 2
            resources:
                runtime="48:00:00"
            log: "logs/blastn.log"
            conda: ENVDIR + "blast_env.yml"
            message: "Running blastn on {input}."
            shell:
                """
                if [ -s {input} ]; then
                  export BLASTDB={config[blast][db_path]}
                  blastn -query {input} -db {config[blast][db_path]}/{config[blast][tax_db]} \
                   -out sequenceTables/blast_output.{config[blast][tax_db]}.tsv \
                   -evalue {config[blast][e_val]} -max_target_seqs 10 \
                   -outfmt '6 qseqid sseqid pident length mismatch gapopen qstart qend evalue bitscore sgi sacc staxids ssciname scomnames stitle'
                 awk -F $"\\t" '{{if (NR==FNR) {{val[$13] = $0; next}} if($1 in val){{print val[$1]"\\t"$0}}}}' \
                  sequenceTables/blast_output.{config[blast][tax_db]}.tsv {config[blast][tax2id]} >> {output}
                else
                  touch {output}
                fi  
                """

if config['hand_off']['biom'] and (config['taxonomy']['decipher']['do'] or config['taxonomy']['mothur']['do']):
    rule biom_handoff_tax:
        input:
            "sequenceTables/all.seqTab.tax.RDS",
            "reporting/finalNumbers_perSample.tsv"
        output:
            "sequenceTables/all.seqTab.biom"
        threads: 12
        resources:
            currentStep = "taxonomy",
            runtime="12:00:00"
        conda: ENVDIR + "dada_env.yml"
        log: "logs/biom_hand-off.log"
        script:
            SCRIPTSDIR+"biom_handoff.R"

if config['hand_off']['phyloseq'] and (config['taxonomy']['decipher']['do'] or config['taxonomy']['mothur']['do']) and not config['do_postprocessing']:
    rule phyloseq_handoff_tax:
        input:
            "sequenceTables/all.seqTab.tax.RDS",
            "reporting/finalNumbers_perSample.tsv"
        output:
            "sequenceTables/all.seqTab.phyloseq.RDS"
        threads: 1
        resources:
            currentStep = "taxonomy",
            runtime="12:00:00"
        conda: ENVDIR + "dada_env.yml"
        log: "logs/phyloseq_hand-off.log"
        script:
            SCRIPTSDIR+"phyloseq_handoff.R"



