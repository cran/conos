% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/access_wrappers.R
\name{getCountMatrix}
\alias{getCountMatrix}
\alias{getCountMatrix,Pagoda2-method}
\alias{getCountMatrix,seurat-method}
\alias{getCountMatrix,Seurat-method}
\title{Access count matrix from sample}
\usage{
getCountMatrix(sample, transposed = FALSE)

\S4method{getCountMatrix}{Pagoda2}(sample, transposed = FALSE)

\S4method{getCountMatrix}{seurat}(sample, transposed = FALSE)

\S4method{getCountMatrix}{Seurat}(sample, transposed = FALSE)
}
\arguments{
\item{sample}{sample from which to get the count matrix}

\item{transposed}{boolean Whether the count matrix should be transposed (default=FALSE)}
}
\description{
Access count matrix from sample
}
