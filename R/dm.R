
#' filter data matrix by factor completeness
#'
#' @param betas matrix data
#' @param fc factors
#' @return a boolean vector whether there is non-NA value for each tested
#' group for each probe
#' @examples
#' se0 = sesameDataGet("MM285.10.tissues")[1:1000,]
#' se_ok = checkLevels(SummarizedExperiment::assay(se0),
#'     SummarizedExperiment::colData(se0)$tissue)
#' sum(se_ok) # number of good probes
#' se1 = se0[se_ok,]
#' @export
checkLevels = function(betas, fc) {
    apply(betas, 1, function(dt) {
        all(vapply(split(dt, fc), function(x) sum(!is.na(x))>0, logical(1)))
    })
}

#' Test differential methylation on each locus
#'
#' The function takes a beta value matrix with probes on the rows and
#' samples on the columns. It also takes a sample information data frame
#' (meta) and formula for testing. The function outputs a list of
#' coefficient tables for each factor tested.
#' @param betas beta values, matrix or SummarizedExperiment
#' @param fm formula
#' @param meta data frame for sample information, column names
#' are predictor variables (e.g., sex, age, treatment, tumor/normal etc)
#' and are referenced in formula. Rows are samples.
#' @param mc.cores number of cores for parallel processing
#' @return a list of test summaries
#' @import stats
#' @examples
#' sesameDataCache("HM450") # in case not done yet
#' data <- sesameDataGet('HM450.76.TCGA.matched')
#' smry <- summaryExtractSlope(DML(
#'     data$betas[1:1000,], ~type, meta=data$sampleInfo))
#' @export
DML <- function(betas, fm, meta=NULL, mc.cores=1) {

    if(is(betas, "SummarizedExperiment")) {
        betas0 = betas
        betas = assay(betas0)
        meta = colData(betas0)
    }
    
    mm = model.matrix(fm, meta)
    smry = mclapply(seq_len(nrow(betas)), function(i) {
        summary(lm(betas[i,]~.+0, data=as.data.frame(mm)))
    }, mc.cores=mc.cores)
    names(smry) = rownames(betas)
    class(smry) = "DMLSummary"
    smry
}

#' Extract slope information from DMLSummary
#' @param smry DMLSummary from DML command
#' @return a table of slope and p-value
#' @examples
#' sesameDataCache("HM450") # in case not done yet
#' data <- sesameDataGet('HM450.76.TCGA.matched')
#' smry <- DML(data$betas[1:1000,], ~type, meta=data$sampleInfo)
#' slopes <- summaryExtractSlope(smry)
#' @export
summaryExtractSlope = function(smry) {
    est = as.data.frame(t(do.call(cbind, lapply(smry, function(x) {
        x$coefficients[,'Estimate']; }))))
    rownames(est) <- names(smry)
    colnames(est) = paste0("Est_", colnames(est))
    pvals = as.data.frame(t(do.call(cbind, lapply(smry, function(x) {
        x$coefficients[,"Pr(>|t|)"] }))))
    rownames(pvals) = names(smry)
    colnames(pvals) = paste0("pval_", colnames(pvals))
    cbind(est, pvals)
}

#' Extract slope information from DMLSummary
#' @param smry DMLSummary from DML command
#' @return a list of coefficients for each tested factor
#' @examples
#' sesameDataCache("HM450") # in case not done yet
#' data <- sesameDataGet('HM450.76.TCGA.matched')
#' smry <- DML(data$betas[1:1000,], ~type, meta=data$sampleInfo)
#' cf_list <- summaryExtractCfList(smry)
#' @export
summaryExtractCfList = function(smry) {
    tests = unique(do.call(c, lapply(smry, function(x) {
        rownames(x$coefficients)
    })))
    cf_list = lapply(tests, function(tn) {
        cf = do.call(rbind, lapply(smry, function(x) {
            x$coefficients[tn,]
        }))
        rownames(cf) = names(smry)
        cf
    })
    names(cf_list) = tests
    cf_list
}

dmr_merge_cpgs <- function(betas, probe.coords, dist.cutoff, seg.per.locus) {

    betas.noNA <- betas[!apply(betas, 1, function(x) all(is.na(x))),]
    cpg.ids <- intersect(rownames(betas.noNA), names(probe.coords))
    probe.coords <- GenomicRanges::sort(probe.coords[cpg.ids])
    betas.coord.srt <- betas.noNA[names(probe.coords),]
    
    cpg.ids <- rownames(betas.coord.srt)
    cpg.coords <- probe.coords[cpg.ids]
    cpg.chrm <- as.vector(GenomicRanges::seqnames(cpg.coords))
    cpg.start <- GenomicRanges::start(cpg.coords)
    cpg.end <- GenomicRanges::end(cpg.coords)

    n.cpg <- length(cpg.ids)

    ## euclidean distance suffcies
    beta.dist <- vapply(seq_len(n.cpg-1), function(i) sum(
        (betas.coord.srt[i,] - betas.coord.srt[i+1,])^2, na.rm=TRUE), 1)

    chrm.changed <- (cpg.chrm[-1] != cpg.chrm[-n.cpg])

    ## empirical cutoff based on quantiles
    if (is.null(dist.cutoff)) {
        dist.cutoff <- quantile(beta.dist, 1-seg.per.locus)
    }

    change.points <- (beta.dist > dist.cutoff | chrm.changed)
    seg.ids <- cumsum(c(TRUE,change.points))
    message("Done.")

    ## add back unmapped
    all.cpg.ids <- rownames(betas)
    unmapped <- all.cpg.ids[!(all.cpg.ids %in% cpg.ids)]
    cpg.ids <- c(cpg.ids, unmapped)
    cpg.chrm <- c(cpg.chrm, rep('*', length(unmapped)))
    cpg.start <- c(cpg.start, rep(NA, length(unmapped)))
    cpg.end <- c(cpg.end, rep(NA, length(unmapped)))

    ## segment coordinates
    seg.ids <- c(seg.ids, seq.int(
        from=seg.ids[length(seg.ids)]+1, length.out=length(unmapped)))
    
    seg.chrm <- as.vector(tapply(cpg.chrm, seg.ids, function(x) x[1]))
    seg.start <- as.vector(tapply(cpg.start, seg.ids, function(x) x[1]))
    seg.end <- as.vector(tapply(cpg.end, seg.ids, function(x) x[length(x)]))

    list(id = seg.ids, chrm = seg.chrm,
        start = seg.start, end = seg.end, cpg.ids = cpg.ids)
}

dmr_combine_pval = function(cf, segs) {
    ## Stouffer's Z-score method
    seg.pval <- as.vector(tapply(
        cf[segs$cpg.ids, 'Pr(>|t|)'], segs$id,
        function(x) pnorm(sum(qnorm(x))/sqrt(length(x)))))
    seg.pval.adj <- p.adjust(seg.pval, method="BH")
    seg.ids.cf <- match(rownames(cf), segs$cpg.ids)
    cf <- as.data.frame(cf)
    cf$Seg.ID <- segs$id[seg.ids.cf]
    cf$Seg.chrm <- segs$chrm[cf$Seg.ID]
    cf$Seg.start <- segs$start[cf$Seg.ID]
    cf$Seg.end <- segs$end[cf$Seg.ID]
    cf$Seg.Pval <- seg.pval[cf$Seg.ID]
    cf$Seg.Pval.adj <- seg.pval.adj[cf$Seg.ID]
    message(sprintf(
        ' - %d significant segments.',
        sum(seg.pval<0.05, na.rm=TRUE)))
    message(sprintf(
        ' - %d significant segments (after BH).',
        sum(seg.pval.adj<0.05, na.rm=TRUE)))
    cf
}

DMGetProbeInfo <- function(platform, refversion) {
    mft = sesameDataGet(sprintf("%s.%s.manifest", platform, refversion))
    mft = mft[GenomicRanges::seqnames(mft) != "*"]
    GenomicRanges::mcols(mft) = NULL
    GenomicRanges::strand(mft) = "*"
    mft = sort(mft)
    mft
}

#' Find Differentially Methylated Region (DMR)
#'
#' This subroutine uses Euclidean distance to group CpGs and
#' then combine p-values for each segment. The function performs DML test first
#' if cf is NULL. It groups the probe testing results into differential
#' methylated regions in a coefficient table with additional columns
#' designating the segment ID and statistical significance (P-value) testing
#' the segment.
#' 
#' @param betas beta values for distance calculation
#' @param cf coefficient table from DML or DMLShrinkage
#' @param dist.cutoff distance cutoff (default to use dist.cutoff.quantile)
#' @param seg.per.locus number of segments per locus
#' higher value leads to more segments
#' @param platform EPIC, HM450, MM285, ...
#' @param refversion hg38, hg19, mm10, ...
#' @return coefficient table with segment ID and segment P-value
#' @importFrom SummarizedExperiment assay
#' @importFrom SummarizedExperiment colData
#' @examples
#'
#' sesameDataCache("HM450") # in case not done yet
#' 
#' data <- sesameDataGet('HM450.76.TCGA.matched')
#' cf_list = summaryExtractCfList(DML(data$betas, ~type, meta=data$sampleInfo))
#' cf_list = DMR(data$betas, cf_list$typeTumour)
#' @export
DMR <- function(betas, cf, platform=NULL, refversion=NULL,
    dist.cutoff=NULL, seg.per.locus=0.5) {

    if (is.null(platform)) {
        platform = inferPlatformFromProbeIDs(rownames(betas)) }
    
    if (is.null(refversion)) refversion = defaultAssembly(platform)

    if(is(betas, "SummarizedExperiment")) {
        betas = assay(betas)
    }

    ## sort by coordinates
    probe.coords = DMGetProbeInfo(platform, refversion)
    message("Merging correlated CpGs ... ", appendLF=FALSE)
    segs = dmr_merge_cpgs(betas, probe.coords, dist.cutoff, seg.per.locus)
    message(sprintf('Generated %d segments.', segs$id[length(segs$id)]))
    message("Combine p-values ... ")
    cf = dmr_combine_pval(cf, segs)
    message("Done.")
    cf
}

#' Top segments in differential methylation
#' 
#' This is a utility function to show top differential methylated segments.
#' The function takes a coefficient table as input and output the same
#' table ordered by the sigificance of the segments.
#' 
#' @param cf1 coefficient table of one factor from DMR
#' @return coefficient table ordered by adjusted p-value of segments
#' @examples
#'
#' sesameDataCache("HM450") # in case not done yet
#' 
#' data <- sesameDataGet('HM450.76.TCGA.matched')
#' cf_list = summaryExtractCfList(DML(data$betas, ~type, meta=data$sampleInfo))
#' cf_list = DMR(data$betas, cf_list$typeTumour)
#' topSegments(cf_list)
#' @export
topSegments <- function(cf1) {
    x <- unique(cf1[order(cf1[,'Seg.Pval']), c(
        'Seg.ID','Seg.chrm','Seg.start','Seg.end','Seg.Pval','Seg.Pval.adj')])
    rownames(x) <- x[['Seg.ID']]
    x
}

