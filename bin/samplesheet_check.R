#!/usr/bin/env Rscript

library(optparse)
suppressPackageStartupMessages(library(tidyverse))

# Define external input parameters using optparse

option_list = list(
  make_option(c("-i", "--input"), type="character", default=NULL,
              help="The path of the input file.", metavar="character"),
  make_option(c("-o", "--output"), type="character", default=NULL,
              help="The path of the output file.", metavar="character")
);

opt_parser = OptionParser(option_list=option_list);
opt = parse_args(opt_parser);

# Check that both input and output are provided
if (is.null(opt$input) || is.null(opt$output)) {
  stop("Error: both input (path to csv) and output (path to csv output) parameters are required.")
}

# Check samplesheet function
check_samplesheet <- function(file_in, file_out) {
  required_columns <- c("sample", "vcf", "traits", "ancestry")

  #Load data
  df <- read.csv(file_in)

  #Check if all required columns exist in the input file
  missing_cols <- setdiff(required_columns, colnames(df))
  if (length(missing_cols) > 0) {
    stop(sprintf("Columns missing in the input file: %s", paste(missing_cols, collapse = ", ")))
  }

  #Check that the VCF, traits, and ancestry file extensions are correct

  # Check VCF column
  if (any(!grepl("\\.vcf\\.gz$", df$vcf))) {
    stop("Not all elements in the 'vcf' column end in '.vcf.gz'")
  }

  # Check traits column
  if (any(!grepl("_traits-json\\.json$", df$traits))) {
    stop("Not all elements in the 'traits' column end in '_traits-json.json'")
  }

  # Check ancestry column
  if (any(!grepl("_ancestry-json\\.json$", df$ancestry))) {
    stop(sprintf("Not all elements in the 'ancestry' column end in: _ancestry-json.json."))
  }


  # Check that the combination of sample name and VCF filename is unique
  # Check for duplicate combinations of 'sample' and 'vcf' columns
  if (any(duplicated(paste(df$sample, df$vcf)))) {
    stop("The combination of 'sample' and 'vcf' is not unique for each row.")
  }

  # Check for duplicated values in the 'sample' column
  if (any(duplicated(df$sample))) {
    stop("There are duplicate values in the 'sample' column")
  }

  #Write the validated and transformed samplesheet to the output file
  write_csv(df, file_out)
}

check_samplesheet(opt$input, opt$output)
