#!/usr/bin/env Rscript

suppressPackageStartupMessages(require(optparse))
suppressPackageStartupMessages(require(data.table))
suppressPackageStartupMessages(require(limma))
suppressMessages( library( ExpressionAtlasInternal ) )

option_list = list(
  make_option(
    c("-d", "--datasets_file"),
    action = "store",
    default = NA,
    type = 'character',
    help = "Experiments."
  ),
  make_option(
    c("-i", "--inputdir"),
    action = "store",
    default = NA,
    type = 'character',
    help = "Input directory with R objects"
  ),
  make_option(
    c("-o", "--outdir"),
    help = "Output directory"
  )
)


opt <- parse_args(OptionParser(option_list = option_list))

fread(input=opt$datasets_file)->datasets

microarrays<-readRDS(paste0(opt$inputdir,"/microarray.rds"))

results<-list()

for( accession in microarrays ) {
  
  experimentConfig <- parseAtlasConfig( paste0( opt$inputdir,"/",accession,"-configuration.xml" ))
  analytics <- experimentConfig$allAnalytics[[1]]
  expContrasts <- atlas_contrasts( analytics )
  expAssayGroups <- assay_groups( analytics )

  readRDS(paste0(opt$inputdir,"/",accession,".annot.rds"))->annot
  readRDS(paste0(opt$inputdir,"/",accession,".probes.rds"))->highestMeanProbePerGene

  for( contrast in unlist(strsplit(x=datasets$contrast[datasets$accession==accession], split = ",")) ) {
    
    cat("Processing ",accession," ",contrast)
    
    for( expContrast in expContrasts ) {
      # Get the sample sizes for the contrast at hand.
      if( expContrast@contrast_id == contrast ) {
        refAssayGroupID <- reference_assay_group_id( expContrast )
        testAssayGroupID <- test_assay_group_id( expContrast )
        
        refAssayGroup <- expAssayGroups[[ refAssayGroupID ]]
        testAssayGroup <- expAssayGroups[[ testAssayGroupID ]]
        
        referenceSamplesSize<-length(refAssayGroup@biological_replicates)
        testSamplesSize<-length(testAssayGroup@biological_replicates)
      }
    }
    
    readRDS(paste0(opt$inputdir,"/",accession,"_",contrast,"_fit.rds"))->fit
    
    setkey(annot,DesignElementAccession)
    cols<-colnames(topTable(fit))
    if( !("logFC" %in% cols) ) {
    #if( nchar(datasets$coef[datasets$accession==accession])==0 ) {
    #  if( !("logFC" %in% cols)) {
    #    cat(accession,":",contrast," has the following coefficients:\n")
    #    cat(cols[-1])
    #    cat("add an appropiate one to the coefficient column of datasets and re-run")
    #  }
      as.data.table(topTable(fit, confint=TRUE, number=Inf, coef="groupstest"))->expTTable
    } else {
      #as.data.table(topTable(fit, confint=TRUE, number=Inf, coef = datasets$coef[datasets$accession==accession]))->expTTable
      as.data.table(topTable(fit, confint=TRUE, number=Inf))->expTTable
    }
    setkey(expTTable,designElements)
    # keep only the highestMeanProbesPerGene
    expTTable[designElements %in% highestMeanProbePerGene, ]->expTTable
    expTTable[,variance:=((CI.R-CI.L)/3.92)^2,]
    expTTable$Accession<-accession
    expTTable$Contrast<-contrast
    expTTable$refSampleSize<-referenceSamplesSize
    expTTable$testSampleSize<-testSamplesSize
    expTTable$technology<-"microarray"
    setnames(expTTable, "adj.P.Val", "padj")
    
    columns<-c('Accession', 'Contrast', 'Gene ID', 'Gene Name', 'logFC', 'variance', 'padj', 'refSampleSize', 'testSampleSize', 'technology', 'CI.L', 'CI.R')
    results[[paste0(accession,"_",contrast)]]<-annot[expTTable, on=c(DesignElementAccession="designElements")][, columns, with=FALSE]
    summary(results[[paste0(accession,"_",contrast)]])
  }
}
print("Done microarrays\n")

readRDS(paste0(opt$inputdir,"/rna_seq_diff.rds"))->rna_seq_diff

for( accession in rna_seq_diff) {
  
  experimentConfig <- parseAtlasConfig( paste0( opt$inputdir,"/",accession,"-configuration.xml" ))
  analytics <- experimentConfig$allAnalytics[[1]]
  expContrasts <- atlas_contrasts( analytics )
  expAssayGroups <- assay_groups( analytics )
  
  readRDS(paste0(opt$inputdir,"/",accession,".annot.rds"))->annot
  setkey(annot, `Gene ID`)
  
  for( contrast in unlist(strsplit(x=datasets$contrast[datasets$accession==accession], split = ",")) ) {
    
    for( expContrast in expContrasts ) {
    # Get the sample sizes for the contrast at hand.
      if( expContrast@contrast_id == contrast ) {
        refAssayGroupID <- reference_assay_group_id( expContrast )
        testAssayGroupID <- test_assay_group_id( expContrast )
        
        refAssayGroup <- expAssayGroups[[ refAssayGroupID ]]
        testAssayGroup <- expAssayGroups[[ testAssayGroupID ]]
        
        referenceSamplesSize<-length(refAssayGroup@biological_replicates)
        testSamplesSize<-length(testAssayGroup@biological_replicates)
      }
    }
    
    readRDS(paste0(opt$inputdir,"/",accession,"_",contrast,"_deseq.rds"))->deseq2Res
    data.table(Accession=accession, Contrast=contrast, `Gene ID`=deseq2Res@rownames, 
               logFC=deseq2Res@listData$log2FoldChange, 
               variance=((deseq2Res@listData$lfcSE)^2*(referenceSamplesSize+testSamplesSize)),
               refSampleSize=referenceSamplesSize,
               testSampleSize=testSamplesSize,
               padj=deseq2Res@listData$padj,
               CI.L=deseq2Res@listData$log2FoldChange-(1.96*deseq2Res@listData$lfcSE),
               CI.R=deseq2Res@listData$log2FoldChange+(1.96*deseq2Res@listData$lfcSE)
               )->expTTable
    setkey(expTTable,`Gene ID`)
    expTTable$technology<-"rna-seq"
    columns<-c('Accession', 'Contrast', 'Gene ID', 'Gene Name', 'logFC', 'variance', 'padj', 'refSampleSize', 'testSampleSize', 'technology', 'CI.L', 'CI.R')
    results[[paste0(accession,"_",contrast)]]<-expTTable[annot, on=c(`Gene ID`="Gene ID")][!is.na(padj), columns, with=FALSE]
    summary(results[[paste0(accession,"_",contrast)]])
  }
  
}

summary(results)

saveRDS(results, file = paste0(opt$outdir,"/","expression_tables.rds"))

results<-rbindlist(results)

fwrite(file=paste0(opt$outdir,"/","merged_logfc_variance.tsv"), 
       # merge the tables and produce desired output.
       results,sep='\t')
