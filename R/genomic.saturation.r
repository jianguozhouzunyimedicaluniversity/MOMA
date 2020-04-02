#' Get coverage of interactions
#' 
#' @param momaObj A numeric vector with cluster membership, names are samples
#' @param viper.samples Calculate the genomic coverage only for these sample
#' @param cMR.ranking A vector entrez IDs, in order
#' @param topN Compute coverage for only the top -N- Master Regulators
#' @param mutation.filter Retain only mutation events in this (positive) list
#' @return A list of lists, indexed by sample name, with coverage statistics/data for each sample
get.coverage <- function(momaObj, cMR.ranking, viper.samples, topN = 100, mutation.filter = NULL) {
    
    if (!is(momaObj, "momaRunner")) {
        stop("Error: must have instantiated momaRunner class object passed!")
    }
    
    # select considered cMRs
    print(paste("Top : ", topN, " regulators"))
    selected.tfs <- cMR.ranking[seq_len(topN)]
    if (length(selected.tfs) == 0) {
        print("Error: no TFs selected!")
        q()
    }
    
    # confirm they are in Entrez ID format
    
    is.entrezIDs <- function(vec) {
        all(sapply(seq_along(vec), function(i) as.numeric(vec)[i]==vec[i]))
    }
    if (isFALSE(is.entrezIDs(selected.tfs))) {
        stop("Error: tfs not in entrez ID format!")
    }
    
    # For each event type, gets names of cMRs that have those events
    interaction.map <- valid.diggit.interactions(momaObj$interactions, momaObj$gene.loc.mapping, selected.tfs)
    
    # another assert statment: make sure we have non-zero interactions for each
    sapply(names(interaction.map), function(key) {
        if (sum(sapply(interaction.map[[key]], function(x) length(x))) < 1) {
            print(paste("Warning: didn't find any positive DIGGIT associations for data type ", key))
            print(paste("(in subtype)"))
        }
    })
    
    oc <- sample.overlap(momaObj, viper.samples, selected.tfs, interaction.map, mutation.filter = mutation.filter)
    # count mutations/amps/dels covered at this point. Aggregate stats
    
    oc
}


#' Return a set of events 'covered' by specified cMR-event interactions 
#' @param interactions List indexed by amp/mut/del/fus - from cMRs to interacting events
#' @param gene.loc.mapping Data.frame mapping entrezIDs to cytoband locations
#' @param selected.tfs For each event type list, search within only these cMRS
#' @return a list of events 'covered' by the supplied interactions of type mut/amp/del/fus
valid.diggit.interactions <- function(interactions, gene.loc.mapping, selected.tfs) {
    
    if (length(selected.tfs) == 0) {
        stop("No TFs input to diggit function")
    }
    selected.tfs <- as.character(selected.tfs)
    
    mut.tfs <- selected.tfs[which(selected.tfs %in% names(interactions[["mut"]]))]
    amp.tfs <- selected.tfs[which(selected.tfs %in% names(interactions[["amp"]]))]
    del.tfs <- selected.tfs[which(selected.tfs %in% names(interactions[["del"]]))]
    fus.tfs <- selected.tfs[which(selected.tfs %in% names(interactions[["fus"]]))]
    
    if (length(mut.tfs) == 0 || length(amp.tfs) == 0 || length(del.tfs) == 0) {
        stop("No valid TFs in the interactions supplied!")
    } else if (length(fus.tfs) == 0) {
        warning("No valid fusion interactions...")
    }
    
    mut.I <- subset.list.interactions(interactions[["mut"]], mut.tfs)
    del.I <- subset.list.interactions(interactions[["del"]], del.tfs)
    amp.I <- subset.list.interactions(interactions[["amp"]], amp.tfs)
    
    # only subset if fusions exist fusions IDs are unique , nothing else necessary
    if (length(fus.tfs) >= 1) {
        fus.I <- subset.list.interactions(interactions[["fus"]], fus.tfs)
        covered.fusions <- fus.I
    }
    
    
    # Add cnv events to mutation coverage, as either copy number variation is valid evidence for explaining a patient's mutation
    covered.mutations <- merge.lists(mut.I, del.I)
    covered.mutations <- merge.lists(covered.mutations, amp.I)
    
    # Add mut events to cnv coverage, as it is a valid type of evidence for explaining a patient's CNV change
    covered.amps <- merge.lists(amp.I, mut.I)
    covered.dels <- merge.lists(del.I, mut.I)
    
    
    
    # create a new mapping from TF in Entrez -> event location
    covered.amps.LOC <- lapply(names(covered.amps), function(x, I) {
        geneNames <- I[[as.character(x)]]
        band.names <- unique(as.character(gene.loc.mapping[which(gene.loc.mapping$Entrez.IDs %in% geneNames), "Cytoband"]))
        if (length(band.names) == 0 & length(geneNames) == 0) {
            #print(paste("No amplification events associated with", as.character(x)))
            band.names <- NA 
        } else if (length(band.names) == 0) {
            warning(paste("Warning: could not map entrez IDs to Cytoband for IDS, skipping...", geneNames))
            band.names <- NA
        }
        band.names
    }, I = covered.amps)
    names(covered.amps.LOC) <- names(covered.amps)
    covered.amps.LOC <- covered.amps.LOC[!is.na(covered.amps.LOC)]
    
    if (sum(sapply(covered.amps.LOC, function(x) length(x))) == 0) {
        print("Error: something went wrong when mapping amplification Entrez.IDs to Cytoband IDs. Quitting...")
        quit(status = 1)
    }
    
    # create a new mapping from TF in Entrez -> event location
    covered.dels.LOC <- lapply(names(covered.dels), function(x, I) {
        geneNames <- I[[as.character(x)]]
        band.names <- unique(as.character(gene.loc.mapping[which(gene.loc.mapping$Entrez.IDs %in% geneNames), "Cytoband"]))
        if (length(band.names) == 0 & length(geneNames) == 0) {
            #print(paste("No deletion events associated with", as.character(x)))
            band.names <- NA 
        } else if (length(band.names) == 0) {
            warning(paste("Warning: could not map entrez IDs to Cytoband for IDS, skipping...", geneNames))
            band.names <- NA
        }
        band.names
    }, I = covered.dels)
    names(covered.dels.LOC) <- names(covered.dels)
    covered.dels.LOC <- covered.dels.LOC[!is.na(covered.dels.LOC)]
    
    if (sum(sapply(covered.dels.LOC, function(x) length(x))) == 0) {
        print("Error: something went wrong when mapping deletion Entrez.IDs to Cytoband IDs. Quitting...")
        quit(status = 1)
    }
    
    # don't incorporate fusions into final list object unless they exist
    if (length(fus.tfs) >= 1) {
        return(list(mut = covered.mutations, amp = covered.amps.LOC, del = covered.dels.LOC, fus = covered.fusions))
    } else {
        return(list(mut = covered.mutations, amp = covered.amps.LOC, del = covered.dels.LOC))
    }
}


#' The core function to compute which sample-specific alterations overlap with genomic events that are explained 
#' via DIGGIT. 
#' @importFrom utils head
#' @param momaObj Object reference of momaRunner class
#' @param viper.samples Sample vector to restrict sample-specific analysis to
#' @param selected.tfs Transcription factors being analyzed
#' @param interaction.map List object of events 'covered' by the supplied interactions of type mut/amp/del/fus
#' @param cnv.threshold Numeric absolute value to threshold SNP6 and/or GISTIC 
#' or other CNV scores at. Above that absolute value is considered a positive event. 
#' @param mutation.filter A vector of whitelisted mutation events, in entrez gene IDs
#' @param idx.range Number of tfs to check for genomic saturation calculation, default is 1253
#' @param verbose Output status during the run (default=FALSE)
#' @return A list of lists, indexed by sample name, with coverage statistics/data for each sample
sample.overlap <- function(momaObj, viper.samples, selected.tfs, interaction.map,
                           cnv.threshold = 0.5, mutation.filter = NULL, 
                           idx.range = NULL, verbose = FALSE) {
    
    if (is.null(momaObj$hypotheses)) {
        stop("Error: no hypothesis set for momaRunner class object!!")
    }
    
    map <- momaObj$gene.loc.mapping
    
    mut.HYP.filter <- momaObj$hypotheses[["mut"]]
    amp.HYP.filter <- na.omit(unique(sapply(as.character(momaObj$hypotheses[["amp"]]), function(x) {
        res <- NA
        x <- as.character(x)
        if (x %in% map$Entrez.IDs) {
            # get cytoband location for this gene if it's in the map
            res <- unique(map[which(map$Entrez.IDs == x), "Cytoband"])
        }
        as.character(res)
    })))
    del.HYP.filter <- na.omit(unique(sapply(as.character(momaObj$hypotheses[["del"]]), function(x) {
        res <- NA
        x <- as.character(x)
        if (x %in% map$Entrez.IDs) {
            # get cytoband location for this gene if it's in the map
            res <- unique(map[which(map$Entrez.IDs == x), "Cytoband"])
        }
        as.character(res)
    })))
    fus.HYP.filter <- momaObj$hypotheses[["fus"]]
    
    if (length(mut.HYP.filter) == 0) {
        stop("Error: null hypotheses for mut!")
    } else if (length(amp.HYP.filter) == 0) {
        stop("Error: null hypotheses for amp!")
    } else if (length(del.HYP.filter) == 0) {
        stop("Error: null hypotheses for del!")
    } else if (length(fus.HYP.filter) == 0) {
        warning("Zero fusion hypotheses")
    }
    # consider only samples triple intersection of samples with CNV, mutation and RNA (i.e. VIPER inferences) data
    all.samples.genomics <- intersect(colnames(momaObj$mut), colnames(momaObj$cnv))
    all.sample.names <- intersect(all.samples.genomics, viper.samples)
    coverage <- lapply(all.sample.names, function(sample) {
        
        print(paste0("Computing coverage for sample ", sample))
        
        # find active and inactive proteins in this sample
        viper.pvals <- (1 - pnorm(abs(momaObj$viper[, sample])))
        active.proteins <- rownames(momaObj$viper)[intersect(which(viper.pvals < 0.05), which(momaObj$viper[, sample] > 0))]
        if (length(active.proteins) == 0) {
            warning(paste0("No active proteins found for sample: ", sample))
        }
        
        # Collect mutation events in this sample's row:
        mut.events <- as.character(names(which(momaObj$mut[, sample] > 0)))
        mut.events <- intersect(mut.events, momaObj$hypotheses[["mut"]])
        
        # entrez ids to cytoband get genes
        del.events <- as.character(names(which(momaObj$cnv[, sample] < -cnv.threshold)))
        del.events.entrez <- intersect(del.events, momaObj$hypotheses[["del"]])
        # map to genomic locations
        del.events.cytoband <- unique(map[which(map$Entrez.IDs %in% del.events.entrez), "Cytoband"])
        
        # get genes
        amp.events <- as.character(names(which(momaObj$cnv[, sample] > cnv.threshold)))
        amp.events.entrez <- intersect(amp.events, momaObj$hypotheses[["amp"]])
        # map to genomic locations
        amp.events.cytoband <- unique(map[which(map$Entrez.IDs %in% amp.events.entrez), "Cytoband"])
        
        # not all samples will have fusions: include if possible
        fus.events <- NULL
        if (!is.null(fus.HYP.filter)) {
            if (sample %in% colnames(momaObj$fusions)) {
                fus.events <- names(which(momaObj$fusions[, sample] > 0))
                if(length(fus.events) == 0) {
                    #print(paste("No fusion events in", sample))
                    fus.events <- NULL
                } else {
                    #print(paste(fus.events, "found in", sample))
                }
            } else {
                #print(paste0("Sample not recorded in fusions matrix:", sample))
            }
        }
        fus.events <- fus.events[which(fus.events %in% momaObj$hypotheses[["fus"]])]
        
        validated.del.locations <- del.events.cytoband
        validated.amp.locations <- amp.events.cytoband
        validated.fusion.events <- fus.events
        validated.mut.events <- mut.events
        
        if (!is.null(mutation.filter)) {
            print("Using mutation filter:")
            prev.count <- length(validated.mut.events)
            validated.mut.events <- intersect(mutation.filter, validated.mut.events)
            removed = prev.count - length(validated.mut.events)
            print(paste("Filtered out: ", removed, " mutations using filter..."))
        }
        
        
        if (verbose) {
            print(paste("FUS:", length(validated.fusion.events),":"))
            paste(head(validated.fusion.events))
            print(paste("DELS:", length(validated.del.locations), ":"))
            paste(head(validated.del.locations))
            print(paste("AMPS:", length(validated.amp.locations), ":"))
            print(head(validated.amp.locations))
            print(paste("MUTS:", length(validated.mut.events), ":"))
            print(head(validated.mut.events))
        }
        
        
        
        # for each K in 1:N, compute the coverage of the top K events and return the stats
        sample.cover <- lapply(seq_along(selected.tfs), function(x) c())
        # do a semi-complete range for speed and if supplied already with a range, then use that
        if (is.null(idx.range)) {
            if (length(selected.tfs) > 100) {
                idx.range <- seq_len(50)
                idx.range <- c(idx.range, 26:50 * 2)
                idx.range <- c(idx.range, 11:30 * 10)
                idx.range <- c(idx.range, 13:25 * 25)
                idx.range <- c(idx.range, 7:12 * 100)
                idx.range <- c(idx.range, 1253)
            } else {
                idx.range = seq_along(selected.tfs)
            }
        }
        
        # store the set of active MRs, if it's identical to the last iteration, update and skip re-computation
        active.mrs.length.LAST <- 0
        last.idx <- 1
        for (i in idx.range) {
            # use these for coverage
            top.N.tfs <- selected.tfs[seq_len(i)]
            active.mrs <- intersect(active.proteins, top.N.tfs)
            
            # if no extra active mrs this round, copy previous stats and continue
            if ((length(active.mrs) == active.mrs.length.LAST) & (i > 1)) {
                sample.cover[[i]] <- sample.cover[[last.idx]]
                next
            } else {
                active.mrs.length.LAST <- length(active.mrs)
                last.idx <- i
            }
            
            # print ('Active MRs:') print (active.mrs)
            covered.mut <- unique(unlist(lapply(active.mrs, function(mr) {
                covered <- intersect(interaction.map$mut[[mr]], validated.mut.events)
                covered
            })))
            covered.del <- unique(unlist(lapply(active.mrs, function(mr) {
                covered <- intersect(interaction.map$del[[mr]], validated.del.locations)
                covered
            })))
            covered.amp <- unique(unlist(lapply(active.mrs, function(mr) {
                covered <- intersect(interaction.map$amp[[mr]], validated.amp.locations)
                covered
            })))
            covered.fus <- unique(unlist(lapply(active.mrs, function(mr) {
                covered <- intersect(interaction.map$fus[[mr]], validated.fusion.events)
                covered
            })))
            amp.frac <- ifelse(length(validated.amp.locations) == 0, NA, length(covered.amp)/length(validated.amp.locations))
            del.frac <- ifelse(length(validated.del.locations) == 0, NA, length(covered.del)/length(validated.del.locations))
            mut.frac <- ifelse(length(validated.mut.events) == 0, NA, length(covered.mut)/length(validated.mut.events))
            fus.frac <- ifelse(length(validated.fusion.events) == 0, NA, length(covered.fus)/length(validated.fusion.events))
            
            # compute total frac
            total.frac <- NA
            total.num.events <- length(c(validated.mut.events, validated.amp.locations, validated.del.locations, validated.fusion.events))
            
            total.frac <- ifelse(length(total.num.events) == 0, NA, (length(covered.amp) + length(covered.del) + length(covered.mut) + length(covered.fus))/total.num.events)
            sample.cover[[i]] <- list(amp = covered.amp, del = covered.del, mut = covered.mut, fus = covered.fus, amp.frac = amp.frac, del.frac = del.frac, 
                mut.frac = mut.frac, fus.frac = fus.frac, total.frac = total.frac)
        }
        sample.cover
    })
    names(coverage) <- all.sample.names
    coverage
}


#' @title Helper function: subset a list to the set of keys supplied return the 
#' names of interactions with positive values, in a list structure
#' @param int.l List of interactions, at each index this is a numeric named vector
#' @param keys Keys used to reduce interactions
#' @return Returns a filtered list of interactions in the same format as the input
subset.list.interactions <- function(int.l, keys) {
    
    filtered.I <- lapply(keys, function(key, interactions) {
        I <- interactions[[as.character(key)]]
        # named vector
        event.names <- names(I[which(I > 0)])
        event.names
    }, interactions = int.l)
    names(filtered.I) <- keys
    
    filtered.I
}

merge.lists <- function(l1, l2) {
    
    merged <- list()
    inter <- intersect(names(l1), names(l2))
    # combine joint entries
    for (key in inter) {
        merged[[key]] <- union(l1[[key]], l2[[key]])
    }
    # add entries unique to l1
    for (key in setdiff(names(l1), names(l2))) {
        merged[[key]] <- l1[[key]]
    }
    # add entries unique to l2
    for (key in setdiff(names(l2), names(l1))) {
        merged[[key]] <- l2[[key]]
    }
    return(merged)
}


#' @title merge.genomicSaturation Create data frame from coverage data, including number of total events 'covered' and unique events
#' @param coverage.range List indexed by sample, then sub-indexed by # of master regulators, then by event type (mut/amp/del/fus). Holds all events by sample
#' @param topN Maximum number of master regulators to compute coverage
#' @return A data frame with summary statistics for genomic saturation at each 'k'
merge.genomicSaturation <- function(coverage.range, topN) {
    
    data <- c()
    for (i in seq_len(topN)) {
        # count for each sample $mut/amp/del all point to either a NA or a vector of names of the event. If NA the length will be zero so simply count the
        # number of each type of event
        count <- unlist(lapply(coverage.range, function(x) {
            num.events <- length(x[[i]]$mut) + length(x[[i]]$amp) + length(x[[i]]$del)
        }))
        count <- na.omit(count)
        
        # apply over each sample, get the coverage for each
        fraction <- unlist(lapply(coverage.range, function(x) {
            # critically: must omit the NAs so they don't interfere with count
            event.fractions <- x[[i]]$total.frac
            event.fractions
        }))
        fraction <- na.omit(fraction)
        
        all.events <- unlist(lapply(coverage.range, function(x) {
            c(x[[i]]$mut, x[[i]]$amp, x[[i]]$del)
        }))
        all.events <- na.omit(all.events)
        
        data <- rbind(data, c(i, mean(count), mean(fraction), length(unique(all.events))))
    }
    df <- data.frame(mean = data[, 2], k = data[, 1], fraction = data[, 3], unique.events = data[, 4])
    df
}


#' @title Fit based on fractional overall coverage of genomic events
#' @param sweep Numeric vector of genomic coverage values, named by -k- threshold 
#' @param frac Fraction of coverage to use as a threshold (default .85 = 85 percent)
#' @return The -k- integer where coverage is acheived
fit.curve.percent <- function(sweep, frac = 0.85) {
    fractional <- as.numeric(as.character(sweep))/max(sweep)
    best.k <- names(sweep[which(fractional >= frac)])[1]
    return(as.numeric(best.k))
}



