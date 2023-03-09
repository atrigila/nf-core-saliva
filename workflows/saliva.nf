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
include { UPLOAD_MONGO                        } from '../modules/local/upload_db'
include { GENCOVE_DOWNLOAD                    } from '../modules/local/gencove'
include { TILEDBVCF_STORE                     } from '../modules/local/tiledb_store'

//
// SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
//
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
include { PLINK_RECODE                  } from '../modules/nf-core/plink/recode/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/



// Info required for completion email and summary
def multiqc_report = []

workflow SALIVA {

    ch_versions = Channel.empty()

    // Branch to test download data from gencove

    //
    //  MODULE: GENCOVE
    //
    ch_projectID = Channel.value(params.projectid)
    ch_apikey = Channel.value(params.apikey)

    GENCOVE_DOWNLOAD (
    ch_projectID,
    ch_apikey
    )

    ch_gencove_ancestry = GENCOVE_DOWNLOAD.out.ancestryjson
    ch_gencove_ancestry.dump(tag:"CH_ANCESTRYJSON_OUT")
    ch_gencove_vcf = GENCOVE_DOWNLOAD.out.vcf
    ch_gencove_vcf.dump(tag:"CH_VCF")
    ch_gencove_traits = GENCOVE_DOWNLOAD.out.traitsjson
    ch_gencove_tbi = GENCOVE_DOWNLOAD.out.tbi

    // Assign an ID to each file: JSON Ancestry
    ch_individual_ancestry = ch_gencove_ancestry.flatten()
    ch_individual_ancestry.dump(tag:"CH_ANCESTRYJSON_FLATTEN")
    ch_individual_ancestry = ch_individual_ancestry.map { file ->
                return [[id: (file.simpleName.replaceAll('_ancestry-json',''))], file]
                }
    ch_individual_ancestry.dump(tag:"CH_individual_ancestry")

    // Assign an ID to each file: JSON Traits
    ch_individual_traits = ch_gencove_traits.flatten()
    ch_individual_traits = ch_individual_traits.map { file ->
                return [[id: (file.simpleName.replaceAll('_traits-json',''))], file]
                }
    ch_individual_traits.dump(tag:"CH_individual_traits")

    // Assign an ID to each file: VCF
    ch_individual_gencove_vcf_flatten = ch_gencove_vcf.flatten()
    ch_individual_gencove_vcf_flatten.dump(tag:"CH_gencove_vcf_flatten")

    ch_individual_gencove_vcf = ch_individual_gencove_vcf_flatten.map { file ->
                return [[id: (file.simpleName.replaceAll("_impute-vcf",''))], file]
                }
    ch_individual_gencove_vcf.dump(tag:"CH_individual_vcf")

    // Assign an ID to each file: TBI
    ch_individual_gencove_tbi = ch_gencove_tbi.flatten()
    ch_individual_gencove_tbi = ch_individual_gencove_tbi.map { file ->
                return [[id: (file.simpleName.replaceAll('_impute-tbi',''))], file]
                }
    ch_individual_gencove_tbi.dump(tag:"CH_individual_tbi")

    ch_joined = ch_individual_ancestry.join(ch_individual_traits).join(ch_individual_gencove_vcf).join(ch_individual_gencove_tbi)
    ch_joined.dump(tag:"CH_joined_traits")

    //
    // MODULE: VCFTOOLS
    //
    VCFTOOLS(
        ch_individual_gencove_vcf, [], []
    )
    ch_filtered_vcf = VCFTOOLS.out.vcf
    ch_filtered_vcf.dump(tag:"CH_filtered_vcf_VCFTOOLS")

    //
    // MODULE: PLINK_VCF
    //

    PLINK_VCF(
        ch_filtered_vcf
    )
    bed_ch = PLINK_VCF.out.bed
    bim_ch = PLINK_VCF.out.bim
    fam_ch = PLINK_VCF.out.fam

    ch_bed_bim_fam = bed_ch.join(bim_ch).join(fam_ch)
    ch_bed_bim_fam.dump(tag:"CH_bed_bim_bam")


    //
    // MODULE: UPLOAD_MONGO
    //

    ch_mongo_uri = Channel.value(params.url_mongo)

    ch_to_mongo = ch_filtered_vcf.join(ch_individual_traits).join(ch_individual_ancestry)
    ch_to_mongo.dump(tag:"CH_data_to_MONGO")

    UPLOAD_MONGO(     ch_to_mongo, ch_mongo_uri    )

    ch_out_updatedmongodb = UPLOAD_MONGO.out.updated_mongodb
    ch_out_updatedmongodb.dump(tag:"CH_updateddb_MONGO")



    //
    // MODULE: TABIX
    //

    TABIX_TABIX(ch_individual_gencove_vcf)
    ch_tbi = TABIX_TABIX.out.tbi
    ch_vcf_tbi = ch_individual_gencove_vcf.join(ch_tbi)
    ch_vcf_tbi.dump(tag:"CH_VCF_tbi")

    //
    // MODULE: TILEDBVCF_STORE
    //

    ch_tiledbvcf_uri = Channel.value(params.tiledbvcf_uri)

    TILEDBVCF_STORE(ch_vcf_tbi, ch_tiledbvcf_uri)

    ch_out_updatedtiledb = TILEDBVCF_STORE.out.updateddb
    ch_out_updatedtiledb.dump(tag:"CH_updateddb_TILEDB")




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
