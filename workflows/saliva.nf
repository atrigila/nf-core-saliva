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
def checkPathParamList = [ params.multiqc_config, params.fasta, params.input_vcf, params.rsid_file , params.uri ]
//def checkPathParamList = [ params.multiqc_config, params.fasta, params.input, params.rsid_file  ] //, params.uri ] // If input is samplesheet

for (param in checkPathParamList) { if (param) { file(param, checkIfExists: true) } }

// Check mandatory parameters
if (params.input_vcf ) { ch_input = file(params.input_vcf) } else { exit 1, 'Input vcf not specified!' } // If input is VCF
//if (params.input) { ch_input = file(params.input) } else { exit 1, 'Input samplesheet not specified!' } // If input is Samplesheet


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
include { PLINK_RECODE                     } from '../modules/local/plink_recode'
include { TILEDBVCF_STORE                  } from '../modules/local/tiledb_vcf'

//
// SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
//
include { INPUT_CHECK } from '../subworkflows/local/input_check'


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
include { TABIX_TABIX as TABIX_NORM     } from '../modules/nf-core/tabix/tabix/main'
include { BCFTOOLS_NORM                 } from '../modules/nf-core/bcftools/norm/main'
include { VCFTOOLS                      } from '../modules/nf-core/vcftools/main'
include { PLINK_VCF                     } from '../modules/nf-core/plink/vcf/main'
include { BCFTOOLS_VIEW                 } from '../modules/nf-core/bcftools/view/main'

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

    ch_vcf.dump(tag:"CH_VCF")

    //
    // MODULE: TABIX
    //

    TABIX_TABIX(
        ch_vcf
    )
    ch_vcf_tbi = ch_vcf.join(TABIX_TABIX.out.tbi)
    ch_vcf_tbi.dump(tag:"CH_VCF_TBI") // this will print the channel contents when running nextflow with `-dump-channels`

    //
    // MODULE: BCFTOOLS_NORM
    //

  //  BCFTOOLS_NORM(
  //      ch_vcf_tbi,
  //      params.fasta
  //  )

    //
    // MODULE: VCFTOOLS
    //
    VCFTOOLS(
        ch_vcf, [], []
    )
    ch_filtered_vcf = VCFTOOLS.out.vcf

    ch_filtered_vcf.dump(tag:"CH_filtered_vcf_VCFTOOLS")

    //
    // MODULE: PLINK_VCF
    //

    // Could there be a channel emiting all of them together at once?
    PLINK_VCF(
        ch_filtered_vcf
    )
    bed_ch = PLINK_VCF.out.bed
    bim_ch = PLINK_VCF.out.bim
    fam_ch = PLINK_VCF.out.fam

    ch_bed_bim_fam = bed_ch.join(bim_ch).join(fam_ch)

    ch_bed_bim_fam.dump(tag:"CH_bed_bim_bam")

    //
    // MODULE: PLINK_RECODE
    //

    PLINK_RECODE(
        ch_bed_bim_fam
    )

    ch_ped_map = PLINK_RECODE.out.ped.join(PLINK_RECODE.out.map)
    ch_ped_map.dump(tag:"CH_ped_map_PLINK_RECODE")

    //
    // MODULE: TILEDBVCF_STORE
    //


    tiledb_array_uri = Channel.of(params.uri)


    TILEDBVCF_STORE(
        ch_vcf_tbi,
        tiledb_array_uri
    )
    ch_out_store = TILEDBVCF_STORE.out.updatedb
    ch_out_store.dump(tag:"CH_updateddb_TILEDBVCF_STORE")


    CUSTOM_DUMPSOFTWAREVERSIONS (
        ch_versions.unique().collectFile(name: 'collated_versions.yml')


    )

    //
    // MODULE: MultiQC
    //
    // workflow_summary    = WorkflowSaliva.paramsSummaryMultiqc(workflow, summary_params)
    // ch_workflow_summary = Channel.value(workflow_summary)

    // methods_description    = WorkflowSaliva.methodsDescriptionText(workflow, ch_multiqc_custom_methods_description)
    // ch_methods_description = Channel.value(methods_description)

    // ch_multiqc_files = Channel.empty()
    // ch_multiqc_files = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    // ch_multiqc_files = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml'))
    // ch_multiqc_files = ch_multiqc_files.mix(CUSTOM_DUMPSOFTWAREVERSIONS.out.mqc_yml.collect())

    // MULTIQC (
    //     ch_multiqc_files.collect(),
    //     ch_multiqc_config.collect().ifEmpty([]),
    //     ch_multiqc_custom_config.collect().ifEmpty([]),
    //     ch_multiqc_logo.collect().ifEmpty([])
    // )
    // multiqc_report = MULTIQC.out.report.toList()
    // ch_versions    = ch_versions.mix(MULTIQC.out.versions)


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
