% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/rank.r
\name{pathwayDiggitIntersect}
\alias{pathwayDiggitIntersect}
\title{Combine DIGGIT inferences with pathway knowledge}
\usage{
pathwayDiggitIntersect(diggit.int, pathway, pos.nes.only = TRUE, cores = 1)
}
\arguments{
\item{diggit.int}{List of interactions between MRs - Genomic events, inferred
by DIGGIT}

\item{pathway}{- a list indexed by TF/MR entrez ID, contains the named vector
of p-values for interactions}

\item{pos.nes.only}{Only use positive associations between MR activity and 
presence of events (default = True)}

\item{cores}{Number of cores to use if parallel is selected}
}
\value{
numeric vector, zscores for each TF/MR
}
\description{
Combine DIGGIT inferences with pathway knowledge
}
\keyword{internal}
