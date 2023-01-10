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
def checkPathParamList = [ params.multiqc_config, params.fasta, params.input_vcf, params.rsid_file , params.input_vcf_samplesheet ]
//def checkPathParamList = [ params.multiqc_config, params.fasta, params.input, params.rsid_file  ] //, params.uri ] // If input is samplesheet

for (param in checkPathParamList) { if (param) { file(param, checkIfExists: true) } }

// Check mandatory parameters
if (params.input_vcf ) { ch_input = file(params.input_vcf) } else { exit 1, 'Input vcf not specified!' } // If input is VCF
if (params.input_vcf_samplesheet) { ch_input_vcf_samplesheet = file(params.input_vcf_samplesheet) } else { exit 1, 'Input VCF samplesheet not specified!' }
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
include { TILEDBVCF_CREATE                      } from '../modules/local/tiledb-vcf/tiledbvcf_create'

//
// SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
//
include { INPUT_CHECK                      } from '../subworkflows/local/input_check'
include { INPUT_CHECK_VCF                  } from '../subworkflows/local/input_check_vcf'


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

    //
    // SUBWORKFLOW: Read in VCF samplesheet, validate and stage input files
    //

    INPUT_CHECK_VCF (
        ch_input_vcf_samplesheet
    )
    ch_versions = ch_versions.mix(INPUT_CHECK_VCF.out.versions)

    ch_vcf_json= INPUT_CHECK_VCF.out.vcf_json
    ch_vcf_json.dump(tag:"CH_VCF_JSON")

    INPUT_CHECK_VCF.out.vcf_json.multiMap { meta, vcf, ancestry, traits ->
        ch_vcf: [meta, vcf]
        ch_ancestry: [meta, ancestry]
        ch_traits: [meta, traits]
    }
    .set { ch_vcf_json_multimap}

    ch_vcf = ch_vcf_json_multimap.ch_vcf
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
    // MODULE: TILEDB_CREATE
    //

    ch_uri = Channel.value(params.uri)
    TILEDBVCF_CREATE(
        ch_uri
    )

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
