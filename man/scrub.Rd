% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/background_correction.R
\name{scrub}
\alias{scrub}
\title{SCRUB background correction}
\usage{
scrub(sset)
}
\arguments{
\item{sset}{a \code{SigSet}}
}
\value{
a new \code{SigSet} with noob background correction
}
\description{
This function takes a \code{SigSet} and returns a modified \code{SigSet}
with background subtracted. scrub subtracts residual background using
background median
}
\details{
This function is meant to be used after noob.
}
\examples{
sset <- makeExampleTinyEPICDataSet()
sset.nb <- noob(sset)
sset.nb.scrub <- scrub(sset.nb)
}
