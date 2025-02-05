% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/utils.R
\name{getAutosomeProbes}
\alias{getAutosomeProbes}
\title{Get autosome probes}
\usage{
getAutosomeProbes(
  platform = c("EPIC", "HM450", "MM285"),
  refversion = c("hg19", "hg38", "mm10")
)
}
\arguments{
\item{platform}{'EPIC', 'HM450' etc.}

\item{refversion}{hg19, hg38, mm10}
}
\value{
a vector of autosome probes
}
\description{
Get autosome probes
}
\examples{
auto.probes <- getAutosomeProbes('EPIC')
}
