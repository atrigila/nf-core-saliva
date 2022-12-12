/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    VALIDATE INPUTS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

def summary_params = NfcoreSchema.paramsSummaryMap(workflow, params)

// Validate input parameters
WorkflowSaliva.initialise(params, log)

// TODO nf-core: Add all file path parameters for the pipeline to the list below
// Check input path parameters to see if they exist
def checkPathParamList = [ params.input, params.multiqc_config, params.fasta, params.input_vcf ]
for (param in checkPathParamList) { if (param) { file(param, checkIfExists: true) } }

// Check mandatory parameters
if (params.input) { ch_input = file(params.input_vcf) } else { exit 1, 'Input vcf not specified!' }

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    CONFIG FILES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

ch_multiqc_config          = Channel.fromPath("$projectDir/assets/multiqc_config.yml", checkIfExists: true)
ch_multiqc_custom_config   = params.multiqc_config ? Channel.fromPath( params.multiqc_config, checkIfExists: true ) : Channel.empty()
ch_multiqc_logo            = params.multiqc_logo   ? Channel.fromPath( params.multiqc_logo, checkIfExists: true ) : Channel.empty()
ch_multiqc_custom_methods_description = params.multiqc_methods_description ? file(params.multiqc_methods_description, checkIfExists: true) : file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT LOCAL MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// LOCAL MODULES:
//

include { LOCAL_BCFTOOLS_NORM           } from '../modules/local/local_bcftools_norm'

//
// SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT NF-CORE MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// MODULE: Installed directly from nf-core/modules
//

include { CUSTOM_DUMPSOFTWAREVERSIONS   } from '../modules/nf-core/custom/dumpsoftwareversions/main'
include { MULTIQC                       } from '../modules/nf-core/multiqc/main'
include { TABIX_TABIX                   } from '../modules/nf-core/tabix/tabix/main'
include { BCFTOOLS_NORM                 } from '../modules/nf-core/bcftools/norm/main' addParams( options: [args: '-m +any'] )
include { VCFTOOLS                      } from '../modules/nf-core/vcftools/main'
include { PLINK_VCF                     } from '../modules/nf-core/plink/vcf/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/



// Info required for completion email and summary
def multiqc_report = []

workflow SALIVA {

    ch_versions = Channel.empty()


    // Typically, input channels are parsed from a samplesheet, which is given as input to the pipeline
    // The "samplesheet_check" script will generate a meta map (see below) and check the input files. See other pipelines for various examples.
    // Here we just mock a meta map and take the path to the vcf file from `params`
    ch_vcf = Channel.of(
        [
            [id:"vcf"],                                        // nf-core module require a meta map with their inputs
            file(params.input_vcf, checkIfExists:true)
        ]
    )

    //
    // MODULE: TABIX
    //

    // Outputs are defined in the module with "emit" statements.
   ch_tbi = TABIX_TABIX(ch_vcf).out.tbi  // I have an error here when running the pipeline with a sample input vcf : No such variable: Exception evaluating property 'out' for nextflow.script.ChannelOut, Reason: groovy.lang.MissingPropertyException: No such property: out for class: groovyx.gpars.dataflow.DataflowBroadcast


    ch_vcf_tbi = ch_vcf.join(ch_tbi)
    // This will yield a channel of format
    // [
    //     [id:"vcf"],
    //     vcf,
    //     tbi
    // ]

    //
    // MODULE: BCFTOOLS_NORM
    //


    // Option 1: Use nf-core module
    // If I were to use the tool just as it is from nf-core, I would do the following:
    // If normally FASTA files are optional in nf-core modules, I could use the original tool
    // ch_vcf_tbi is a tuple channel (?) contaning meta, vcf, and tbi.
    // Then:
     ch_norm_vcf = BCFTOOLS_NORM(ch_vcf_tbi, ch_fasta).out.vcf // Here I would keep the emited normalized vcf.
     // However, I am not passing the additional arguments (+any, etc). I think this should be done in the modules.config


    // Option 2: local copy of BCFTOOLS
    // I will make a copy of the contents of bcftools/norm into the local modules, delete the fasta requirement, add the +any arguments and try to run it.
    // The new file is in modules/local/local_bcftools_norm.nf
    // Not sure if I should also copy the meta.yml file

    ch_norm_vcf = LOCAL_BCFTOOLS_NORM(ch_vcf_tbi).out.vcf


    //
    // MODULE: TABIX
    //

    // Indexing the previously normalized VCF
    ch_tbi = TABIX_TABIX(ch_norm_vcf).out.tbi
    ch_vcf_tbi = ch_vcf.join(ch_tbi)

    //
    // MODULE: VCFTOOLS
    //

    // Again, here I should pass an external bed file, which I am unsure how to do that
    ch_filtered_vcf = VCFTOOLS(ch_vcf_tbi).out.vcf

    // Meta map:
        ch_filter_vcf_meta = Channel.of(
        [
            [id:"vcf"],                                        // PLINK_VCF requires a meta map with their inputs
            ch_filtered_vcf
        ]
    )


    //
    // MODULE: PLINK_VCF
    //
    // I should figure out how to pass additional arguments such as: --snps-only

    // Could there be a channel emiting all of them together at once?
    bed_ch = PLINK_VCF(ch_filter_vcf_meta).out.bed
    bim_ch = PLINK_VCF(ch_filter_vcf_meta).out.bim
    fam_ch = PLINK_VCF(ch_filter_vcf_meta).out.fam



    // I should store info on TileDB. There is not a nf-core module for that. Best approach? Local module?


    CUSTOM_DUMPSOFTWAREVERSIONS (
        ch_versions.unique().collectFile(name: 'collated_versions.yml')


    )

    //
    // MODULE: MultiQC
    //
    workflow_summary    = WorkflowSaliva.paramsSummaryMultiqc(workflow, summary_params)
    ch_workflow_summary = Channel.value(workflow_summary)

    methods_description    = WorkflowSaliva.methodsDescriptionText(workflow, ch_multiqc_custom_methods_description)
    ch_methods_description = Channel.value(methods_description)

    ch_multiqc_files = Channel.empty()
    ch_multiqc_files = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_files = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml'))
    ch_multiqc_files = ch_multiqc_files.mix(CUSTOM_DUMPSOFTWAREVERSIONS.out.mqc_yml.collect())
    ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip.collect{it[1]}.ifEmpty([]))

    MULTIQC (
        ch_multiqc_files.collect(),
        ch_multiqc_config.collect().ifEmpty([]),
        ch_multiqc_custom_config.collect().ifEmpty([]),
        ch_multiqc_logo.collect().ifEmpty([])
    )
    multiqc_report = MULTIQC.out.report.toList()
    ch_versions    = ch_versions.mix(MULTIQC.out.versions)


}



/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    COMPLETION EMAIL AND SUMMARY
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow.onComplete {
    if (params.email || params.email_on_fail) {
        NfcoreTemplate.email(workflow, params, summary_params, projectDir, log, multiqc_report)
    }
    NfcoreTemplate.summary(workflow, params, log)
    if (params.hook_url) {
        NfcoreTemplate.adaptivecard(workflow, params, summary_params, projectDir, log)
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
