source("sequence_io.R")
source("suffix_array.R")
source("fm_index.R")
source("search.R")
source("sam_writer.R")

words <- function(...) paste(...,collapse=" ")
value <- function(s,name) s$params[[name]][1L]
reference_text <- function(references) {
  offsets <- integer()
  offset <- 0L
  text <- character()
  for (i in seq_along(references)) {
    reference <- references[[i]]
    offsets <- c(offsets,offset)
    offset <- offset+length(reference$bases)+1L
    if (i > 1L) text <- c(text,"#")
    text <- c(text,reference$bases)
  }
  list(references=references,offsets=offsets,text=c(text,"$"),reverse=c(rev(text),"$"))
}
text_position <- function(text,p) {
  r <- findInterval(p,text$offsets)
  offset <- p-text$offsets[r]
  if (offset < length(text$references[[r]]$bases)) c(r,offset) else NULL
}
position_label <- function(text,p) {
  located <- text_position(text,p)
  if (is.null(located)) "*" else paste0(text$references[[located[1L]]]$name,":",located[2L]+1L)
}
operation_runs <- function(operations) {
  encoded <- rle(operations)
  lapply(seq_along(encoded$values),function(i) list(op=encoded$values[i],count=encoded$lengths[i]))
}
describe <- function(reference,position,strand,operations,core,trimmed,references) {
  oriented <- if (strand == "+") core else reverse_complement(core)
  sequence <- references[[reference]]$bases
  cigar <- md <- character()
  pairs <- list()
  i <- matches <- nm <- 0L
  j <- position
  for (run in operation_runs(operations)) {
    op <- run$op
    n <- run$count
    cigar <- c(cigar,paste0(n,op))
    if (op == "I") {
      i <- i+n
      nm <- nm+n
    } else if (op == "D") {
      md <- c(md,paste0(matches,"^",paste(sequence[seq.int(j+1L,j+n)],collapse="")))
      matches <- 0L
      j <- j+n
      nm <- nm+n
    } else for (unused in seq_len(n)) {
      pairs[[length(pairs)+1L]] <- c(i,j)
      if (oriented[i+1L] == sequence[j+1L]) matches <- matches+1L else {
        md <- c(md,paste0(matches,sequence[j+1L]))
        matches <- 0L
        nm <- nm+1L
      }
      i <- i+1L
      j <- j+1L
    }
  }
  md <- c(md,as.character(matches))
  if (trimmed > 0L) cigar <- if (strand == "+") c(cigar,paste0(trimmed,"S")) else c(paste0(trimmed,"S"),cigar)
  list(
      reference=reference,
      position=position,
      strand=strand,
      operations=operations,
      oriented=oriented,
      pairs=pairs,
      cigar=paste(cigar,collapse=""),
      nm=nm,
      md=paste(md,collapse="")
  )
}
banded_alignment <- function(oriented,sequence,center,width,scores) {
  match <- scores[1L]
  mismatch <- scores[2L]
  gap_open <- scores[3L]
  gap_extend <- scores[4L]
  l <- length(oriented)
  m <- length(sequence)
  lo <- max(0L,center-width)
  hi <- min(m,l+center+width)
  if (lo > hi) return(NULL)
  unreachable <- -1000000L
  h <- e <- f <- matrix(unreachable,l+1L,hi-lo+1L)
  cell <- function(matrix,i,j) if (i >= 0L && i <= l && j >= lo && j <= hi) matrix[
      i+1L,
      j-lo+1L
  ] else unreachable
  subtract <- function(v,p) if (v == unreachable) unreachable else v-p
  first <- max(0L,center-width)
  last <- min(m,center+width)
  if (first <= last) for (j in seq.int(first,last)) h[1L,j-lo+1L] <- 0L
  for (i in seq_len(l)) {
    first <- max(0L,i+center-width)
    last <- min(m,i+center+width)
    if (first > last) next
    for (j in seq.int(first,last)) {
      column <- j-lo+1L
      f[i+1L,column] <- max(subtract(cell(h,i-1L,j),gap_open+gap_extend),subtract(cell(f,i-1L,j),gap_extend))
      diagonal <- unreachable
      if (j >= 1L) {
        e[i+1L,column] <- max(
            subtract(cell(h,i,j-1L),gap_open+gap_extend),
            subtract(cell(e,i,j-1L),gap_extend)
        )
        previous <- cell(h,i-1L,j-1L)
        if (previous != unreachable) diagonal <- previous+(if (oriented[i] == sequence[j]) match else -mismatch)
      }
      h[i+1L,column] <- max(diagonal,e[i+1L,column],f[i+1L,column])
    }
  }
  endpoints <- seq.int(lo,hi)
  endpoints <- endpoints[h[l+1L,] != unreachable]
  if (!length(endpoints)) return(NULL)
  j <- endpoints[which.max(vapply(endpoints,function(j) cell(h,l,j),integer(1)))]
  score <- cell(h,l,j)
  i <- l
  state <- "H"
  backward <- character()
  repeat {
    if (state == "H") {
      if (i == 0L) break
      previous <- if (j >= 1L) cell(h,i-1L,j-1L) else unreachable
      if (previous != unreachable && cell(
          h,
          i,
          j
      ) == previous+(if (oriented[i] == sequence[j]) match else -mismatch)) {
        backward <- c(backward,"M")
        i <- i-1L
        j <- j-1L
        next
      }
      state <- if (cell(f,i,j) != unreachable && cell(h,i,j) == cell(f,i,j)) "I" else "D"
    } else if (state == "I") {
      backward <- c(backward,"I")
      previous <- cell(f,i-1L,j)
      state <- if (previous != unreachable && cell(f,i,j) == previous-gap_extend) "I" else "H"
      i <- i-1L
    } else {
      backward <- c(backward,"D")
      previous <- cell(e,i,j-1L)
      state <- if (previous != unreachable && cell(e,i,j) == previous-gap_extend) "D" else "H"
      j <- j-1L
    }
  }
  list(score=score,position=j,operations=rev(backward))
}
make_candidates <- function(s,oriented) {
  candidates <- list()
  keys <- character()
  seed_length <- value(s,"SEED_LENGTH")
  for (strand in seq_along(oriented)) {
    sequence <- oriented[[strand]]
    for (offset in seq.int(0L,length(sequence)-seed_length,value(s,"SEED_STEP"))) {
      s$seed_counts[2L] <- s$seed_counts[2L]+1L
      seed <- sequence[seq.int(offset+1L,offset+seed_length)]
      if ("N" %in% seed) {
        s$seed_counts[3L] <- s$seed_counts[3L]+1L
        next
      }
      interval <- backward_search(s$forward,seed)
      lower <- interval[1L]
      upper <- interval[2L]
      if (upper-lower > value(
          s,
          "MAX_SEED_HITS"
      )) s$seed_counts[4L] <- s$seed_counts[4L]+1L else if (lower >= upper) s$seed_counts[5L] <- s$seed_counts[5L]+1L else for (row in seq.int(
          lower,
          upper-1L
      )) {
        position <- locate(s$forward,row)[1L]
        located <- text_position(s$text,position)
        candidate <- c(strand,located[1L],located[2L]-offset)
        key <- paste(candidate,collapse=",")
        if (!(key %in% keys)) {
          keys <- c(keys,key)
          candidates[[length(candidates)+1L]] <- candidate
        }
      }
    }
  }
  s$seed_counts[6L] <- s$seed_counts[6L]+length(candidates)
  if (length(candidates)) candidates <- candidates[order(
      vapply(candidates,function(c) c[1L],integer(1)),
      vapply(candidates,function(c) c[2L],integer(1)),
      vapply(candidates,function(c) c[3L],integer(1))
  )]
  candidates
}
seed_and_extend <- function(s,result,oriented) {
  result$reason <- "NOHIT"
  if (result$length < value(s,"SEED_LENGTH")) return(invisible(NULL))
  s$seed_counts[1L] <- s$seed_counts[1L]+1L
  accepted <- list()
  scores <- s$params$SCORES
  threshold <- value(s,"MIN_SCORE_PERCENT")*scores[1L]*result$length
  for (candidate in make_candidates(s,oriented)) {
    strand <- candidate[1L]
    r <- candidate[2L]
    alignment <- banded_alignment(
        oriented[[strand]],
        s$references[[r]]$bases,
        candidate[3L],
        value(s,"BAND_WIDTH"),
        scores
    )
    if (is.null(alignment) || 100L*alignment$score < threshold) next
    key <- paste(r,alignment$position,strand,sep=",")
    if (is.null(accepted[[key]]) || alignment$score > accepted[[key]]$score) accepted[[key]] <- c(
        alignment,
        list(reference=r,strand=strand)
    )
  }
  s$seed_counts[7L] <- s$seed_counts[7L]+length(accepted)
  if (!length(accepted)) return(invisible(NULL))
  ordered <- accepted[order(
      -vapply(accepted,function(a) a$score,integer(1)),
      vapply(accepted,function(a) a$reference,integer(1)),
      vapply(accepted,function(a) a$position,integer(1)),
      vapply(accepted,function(a) a$strand,integer(1))
  )]
  best <- ordered[[1L]]$score
  best_count <- sum(vapply(ordered,function(a) a$score == best,logical(1)))
  lower <- vapply(Filter(function(a) a$score < best,ordered),function(a) a$score,integer(1))
  second <- if (length(lower)) max(lower) else 0L
  alignments <- lapply(
      ordered,
      function(a) describe(
          a$reference,
          a$position,
          if (a$strand == 1L) "+" else "-",
          a$operations,
          result$core,
          result$trimmed,
          s$references
      )
  )
  result$mapped <- TRUE
  result$primary <- alignments[[1L]]
  result$others <- alignments[-1L]
  result$method <- "SEED"
  result$score <- best
  result$mapq <- if (best_count >= 2L) 0L else (60L*(best-second)) %/% best
  result$x0 <- best_count
  result$x1 <- length(ordered)-best_count
  result$targets <- sort(unique(vapply(
      Filter(function(a) a$score == best,ordered),
      function(a) a$reference,
      integer(1)
  )))
}
map_read <- function(s,read) {
  qualities <- utf8ToInt(paste(read$quality,collapse=""))-33L
  n <- length(read$bases)
  while (n > 0L && qualities[n] < value(s,"TRIM_QUALITY")) n <- n-1L
  result <- list2env(
      list(
          read=read,
          core=read$bases[seq_len(n)],
          qualities=qualities,
          length=n,
          trimmed=length(read$bases)-n,
          mapped=FALSE,
          reason="SHORT"
      ),
      parent=emptyenv()
  )
  if (n < value(s,"MIN_READ_LENGTH")) return(result)
  oriented <- list(result$core,reverse_complement(result$core))
  exact <- lapply(oriented,function(sequence) backward_search(s$forward,sequence))
  maximum_mismatches <- if (any(vapply(
      exact,
      function(interval) interval[1L] < interval[2L],
      logical(1)
  ))) 1L else value(s,"MAX_MISMATCHES")
  hits <- list()
  for (strand in seq_along(oriented)) {
    search <- backtrack(oriented[[strand]],maximum_mismatches,s$forward,s$reverse)
    s$search_counts <- s$search_counts+c(1L,search$nodes,length(search$leaves),search$positions)
    for (leaf in search$leaves) for (row in seq.int(leaf[1L],leaf[2L]-1L)) {
      position <- locate(s$forward,row)[1L]
      located <- text_position(s$text,position)
      hits[[length(hits)+1L]] <- c(leaf[3L],located,strand)
    }
  }
  if (!length(hits)) {
    seed_and_extend(s,result,oriented)
    return(result)
  }
  hits <- hits[order(
      vapply(hits,function(h) h[1L],integer(1)),
      vapply(hits,function(h) h[2L],integer(1)),
      vapply(hits,function(h) h[3L],integer(1)),
      vapply(hits,function(h) h[4L],integer(1))
  )]
  best <- hits[[1L]][1L]
  n1 <- sum(vapply(hits,function(h) h[1L] == best,logical(1)))
  n2 <- sum(vapply(hits,function(h) h[1L] == best+1L,logical(1)))
  alignments <- lapply(
      Filter(function(h) h[1L] <= best+1L,hits),
      function(h) describe(
          h[2L],
          h[3L],
          if (h[4L] == 1L) "+" else "-",
          rep("M",n),
          result$core,
          result$trimmed,
          s$references
      )
  )
  result$mapped <- TRUE
  result$primary <- alignments[[1L]]
  result$others <- alignments[-1L]
  result$method <- if (best == 0L) "EXACT" else "MISMATCH"
  result$score <- (n-best)*s$params$SCORES[1L]-best*s$params$SCORES[2L]
  result$mapq <- if (n1 >= 2L) 0L else if (n2 == 0L) 60L-12L*best else max(30L-12L*best-3L*n2,1L)
  result$x0 <- n1
  result$x1 <- n2
  result$targets <- sort(unique(vapply(Filter(function(h) h[1L] == best,hits),function(h) h[2L],integer(1))))
  result
}
index_statistics <- function(
    text,
    suffixes,
    classes,
    forward,
    reverse_suffixes,
    reverse_classes,
    reverse_index,
    params
) {
  references <- text$references
  n <- length(text$text)
  lines <- words("text length",n,"sequences",length(references))
  for (i in seq_along(references)) {
    r <- references[[i]]
    lines <- c(
        lines,
        words(
            "sequence",
            r$name,
            "length",
            length(r$bases),
            "offset",
            text$offsets[i],
            "gc",
            ratio(sum(r$bases %in% c("G","C")),length(r$bases)),
            "masked",
            r$masked
        )
    )
  }
  lines <- c(
      lines,
      paste(
          "symbols",
          paste(
              vapply(SYMBOLS,function(symbol) words(symbol,sum(text$text == symbol)),character(1)),
              collapse=" "
          )
      ),
      "",
      "forward_index",
      words("suffix_array rounds",length(classes)-1L)
  )
  for (i in seq_along(classes)) lines <- c(
      lines,
      words("round",i-1L,"prefix_length",bitwShiftL(1L,i-1L),"classes",classes[i])
  )
  check <- adjacent_check(text$text,suffixes)
  lines <- c(
      lines,
      words(
          "sa_check pairs",
          n-1L,
          "ordered",
          check$ordered,
          "lcp_sum",
          check$lcp_sum,
          "mean_lcp",
          ratio(check$lcp_sum,n-1L),
          "max_lcp",
          check$longest
      ),
      words(
          "longest_repeat",
          check$longest,
          position_label(text,suffixes[check$row]),
          position_label(text,suffixes[check$row+1L])
      )
  )
  seed_length <- params$SEED_LENGTH[1L]
  kmers <- new.env(hash=TRUE,parent=emptyenv())
  for (r in references) if (length(r$bases) >= seed_length) for (p in seq.int(
      0L,
      length(r$bases)-seed_length
  )) {
    key <- paste(r$bases[seq.int(p+1L,p+seed_length)],collapse="")
    assign(key,if (exists(key,kmers,inherits=FALSE)) get(key,kmers,inherits=FALSE)+1L else 1L,kmers)
  }
  kmer_counts <- unlist(as.list(kmers),use.names=FALSE)
  occurrences <- sum(kmer_counts)
  unique_count <- sum(kmer_counts == 1L)
  lines <- c(
      lines,
      words(
          "kmers length",
          seed_length,
          "occurrences",
          occurrences,
          "distinct",
          length(kmer_counts),
          "unique",
          unique_count,
          "max_occurrence",
          max(kmer_counts),
          "unique_fraction",
          ratio(unique_count,occurrences)
      ),
      words("bwt runs",length(operation_runs(forward$bwt)),"head",paste(head(forward$bwt,60L),collapse="")),
      paste(
          "c_array",
          paste(vapply(SYMBOLS,function(symbol) words(symbol,forward$c[[symbol]]),character(1)),collapse=" ")
      ),
      words("occ interval",forward$interval,"checkpoints",nrow(forward$checkpoints)),
      words("sa_sample interval",params$SA_SAMPLE_INTERVAL[1L],"samples",sum(forward$samples >= 0L))
  )
  correct <- total_steps <- max_steps <- 0L
  for (i in seq_along(suffixes)) {
    located <- locate(forward,i-1L)
    correct <- correct+as.integer(located[1L] == suffixes[i])
    total_steps <- total_steps+located[2L]
    max_steps <- max(max_steps,located[2L])
  }
  lines <- c(
      lines,
      words(
          "locate rows",
          n,
          "correct",
          correct,
          "total_steps",
          total_steps,
          "max_steps",
          max_steps,
          "mean_steps",
          ratio(total_steps,n)
      ),
      paste("inverse_bwt identical",if (identical(inverse_bwt(forward),text$text)) "yes" else "no"),
      "",
      "reverse_index",
      words("suffix_array rounds",length(reverse_classes)-1L),
      words("sa_check pairs",n-1L,"ordered",adjacent_check(text$reverse,reverse_suffixes)$ordered),
      words(
          "bwt runs",
          length(operation_runs(reverse_index$bwt)),
          "head",
          paste(head(reverse_index$bwt,60L),collapse="")
      ),
      paste("inverse_bwt identical",if (identical(inverse_bwt(reverse_index),text$reverse)) "yes" else "no"),
      "",
      "direct_sort"
  )
  checks <- 0L
  for (r in references) if (length(r$bases) <= params$DIRECT_SORT_LIMIT[1L]) {
    sequence <- c(r$bases,"$")
    doubled <- build_suffix_array(sequence)
    lines <- c(
        lines,
        words(
            r$name,
            "length",
            length(sequence),
            "rounds",
            length(doubled$classes)-1L,
            "identical",
            if (identical(doubled$suffixes,direct_sort(sequence))) "yes" else "no"
        )
    )
    checks <- checks+1L
  }
  if (checks == 0L) lines <- c(lines,"none")
  occurrence_bytes <- 24L*nrow(forward$checkpoints)
  sample_bytes <- 4L*sum(forward$samples >= 0L)
  bitmap_bytes <- (n+7L) %/% 8L
  total <- n+occurrence_bytes+sample_bytes+bitmap_bytes
  c(
      lines,
      "",
      words(
          "index_size bwt_bytes",
          n,
          "occ_bytes",
          occurrence_bytes,
          "sample_bytes",
          sample_bytes,
          "bitmap_bytes",
          bitmap_bytes,
          "total_bytes",
          total,
          "full_bytes",
          5L*n,
          "ratio",
          ratio(total,5L*n)
      )
  )
}
coverage_and_variants <- function(results,references,params) {
  depths <- starts <- lapply(references,function(r) integer(length(r$bases)))
  pileups <- lapply(references,function(r) array(0L,c(length(r$bases),4L,2L)))
  min_depth <- params$VARIANTS[1L]
  min_quality <- params$VARIANTS[2L]
  min_alt <- params$VARIANTS[3L]
  hom_percent <- params$VARIANTS[4L]
  minimum_mapq <- params$COVERAGE_MIN_MAPQ[1L]
  for (result in results) {
    if (!result$mapped) next
    a <- result$primary
    r <- a$reference
    strand <- if (a$strand == "+") 1L else 2L
    if (result$mapq == 0L) starts[[r]][a$position+1L] <- starts[[r]][a$position+1L]+1L
    if (result$mapq < minimum_mapq) next
    for (pair in a$pairs) {
      i <- pair[1L]
      j <- pair[2L]
      depths[[r]][j+1L] <- depths[[r]][j+1L]+1L
      base <- a$oriented[i+1L]
      cycle <- if (strand == 1L) i+1L else result$length-i
      if (base != "N" && result$qualities[cycle] >= min_quality) {
        b <- match(base,BASES)
        pileups[[r]][j+1L,b,strand] <- pileups[[r]][j+1L,b,strand]+1L
      }
    }
  }
  window <- params$COVERAGE_WINDOW[1L]
  coverage <- words("window",window,"min_mapq",minimum_mapq)
  variants <- words(
      "min_depth",
      min_depth,
      "min_base_quality",
      min_quality,
      "min_alt_percent",
      min_alt,
      "hom_percent",
      hom_percent
  )
  callable_count <- variant_count <- heterozygous <- homozygous <- 0L
  for (r in seq_along(references)) {
    reference <- references[[r]]
    n <- length(reference$bases)
    depth <- depths[[r]]
    covered <- sum(depth > 0L)
    coverage <- c(
        coverage,
        words(
            "reference",
            reference$name,
            "length",
            n,
            "covered",
            covered,
            "breadth",
            ratio(covered,n),
            "mean_depth",
            ratio(sum(depth),n),
            "max_depth",
            max(depth)
        ),
        paste(
            "depth_histogram",
            paste(vapply(0:max(depth),function(d) paste0(d,":",sum(depth == d)),character(1)),collapse=" ")
        )
    )
    for (first in seq.int(0L,n-1L,window)) {
      last <- min(first+window,n)
      indices <- seq.int(first+1L,last)
      values <- depth[indices]
      sequence <- reference$bases[indices]
      total <- sum(values)
      size_window <- last-first
      coverage <- c(
          coverage,
          words(
              reference$name,
              first+1L,
              last,
              "gc",
              ratio(sum(sequence %in% c("G","C")),size_window),
              "sum",
              total,
              "mean",
              ratio(total,size_window),
              "max",
              max(values),
              "zero",
              sum(values == 0L),
              "mapq0",
              sum(starts[[r]][indices]),
              paste0("|",strrep("#",(10L*total) %/% size_window))
          )
      )
    }
    for (j in seq_len(n)) {
      counts <- pileups[[r]][j,,1L]+pileups[[r]][j,,2L]
      dp <- sum(counts)
      if (dp < min_depth) next
      callable_count <- callable_count+1L
      ref_base <- reference$bases[j]
      alternatives <- which(BASES != ref_base)
      alternative <- alternatives[which.max(counts[alternatives])]
      alt_count <- counts[alternative]
      if (alt_count < 2L || 100L*alt_count < min_alt*dp) next
      hom <- 100L*alt_count >= hom_percent*dp
      homozygous <- homozygous+as.integer(hom)
      heterozygous <- heterozygous+as.integer(!hom)
      variant_count <- variant_count+1L
      variants <- c(
          variants,
          words(
              reference$name,
              j,
              paste0(ref_base,">",BASES[alternative]),
              "depth",
              dp,
              "alt",
              alt_count,
              "fraction",
              ratio(alt_count,dp),
              "genotype",
              if (hom) "1/1" else "0/1",
              "strands",
              pileups[[r]][j,alternative,1L],
              pileups[[r]][j,alternative,2L],
              "counts",
              paste(counts,collapse=" ")
          )
      )
    }
  }
  list(
      coverage=coverage,
      variants=c(
          variants,
          words(
              "callable",
              callable_count,
              "variants",
              variant_count,
              "heterozygous",
              heterozygous,
              "homozygous",
              homozygous
          )
      )
  )
}
error_statistics <- function(results,references) {
  maximum_cycle <- max(vapply(results,function(r) length(r$read$bases),integer(1)))
  cycles <- matrix(0L,maximum_cycle,2L)
  substitutions <- matrix(0L,4L,5L)
  quality_counts <- quality_sums <- integer(2L)
  quality_bins <- matrix(0L,5L,2L)
  operation_counts <- setNames(integer(4L),c("M","I","D","S"))
  events <- indel_bases <- setNames(integer(2L),c("I","D"))
  for (result in results) {
    if (!result$mapped) next
    a <- result$primary
    for (op in a$operations) operation_counts[op] <- operation_counts[op]+1L
    operation_counts["S"] <- operation_counts["S"]+result$trimmed
    if (result$x0 != 1L) next
    sequence <- references[[a$reference]]$bases
    for (pair in a$pairs) {
      i <- pair[1L]
      j <- pair[2L]
      observed <- a$oriented[i+1L]
      reference <- sequence[j+1L]
      mismatch <- as.integer(observed != reference)
      cycle <- if (a$strand == "+") i+1L else result$length-i
      quality <- result$qualities[cycle]
      cycles[cycle,1L] <- cycles[cycle,1L]+1L
      cycles[cycle,2L] <- cycles[cycle,2L]+mismatch
      substitutions[match(reference,BASES),match(observed,c(BASES,"N"))] <- substitutions[
          match(reference,BASES),
          match(observed,c(BASES,"N"))
      ]+1L
      quality_counts[mismatch+1L] <- quality_counts[mismatch+1L]+1L
      quality_sums[mismatch+1L] <- quality_sums[mismatch+1L]+quality
      bin <- min(quality %/% 10L,4L)+1L
      quality_bins[bin,1L] <- quality_bins[bin,1L]+1L
      quality_bins[bin,2L] <- quality_bins[bin,2L]+mismatch
    }
    for (run in operation_runs(a$operations)) if (run$op %in% c("I","D")) {
      events[run$op] <- events[run$op]+1L
      indel_bases[run$op] <- indel_bases[run$op]+run$count
    }
  }
  aligned <- sum(quality_counts)
  mismatches <- quality_counts[2L]
  lines <- c(
      words("error_profile aligned_bases",aligned,"mismatches",mismatches,"rate",ratio(mismatches,aligned)),
      "substitutions",
      "ref A C G T N"
  )
  for (i in seq_along(BASES)) lines <- c(lines,words(BASES[i],paste(substitutions[i,],collapse=" ")))
  lines <- c(lines,"mismatch_by_cycle")
  for (cycle in seq_len(maximum_cycle)) lines <- c(
      lines,
      words(
          "cycle",
          cycle,
          "aligned",
          cycles[cycle,1L],
          "mismatches",
          cycles[cycle,2L],
          "rate",
          ratio(cycles[cycle,2L],cycles[cycle,1L])
      )
  )
  lines <- c(
      lines,
      words(
          "quality matched",
          quality_counts[1L],
          "mean",
          ratio(quality_sums[1L],quality_counts[1L]),
          "mismatched",
          quality_counts[2L],
          "mean",
          ratio(quality_sums[2L],quality_counts[2L])
      ),
      "quality_bins"
  )
  bin_names <- c("0-9","10-19","20-29","30-39","40-")
  for (i in seq_along(bin_names)) lines <- c(
      lines,
      words(
          bin_names[i],
          "aligned",
          quality_bins[i,1L],
          "mismatches",
          quality_bins[i,2L],
          "rate",
          ratio(quality_bins[i,2L],quality_bins[i,1L])
      )
  )
  c(
      lines,
      paste(
          "cigar",
          paste(
              vapply(c("M","I","D","S"),function(op) words(op,operation_counts[[op]]),character(1)),
              collapse=" "
          )
      ),
      words("indels insertions",events[["I"]],indel_bases[["I"]],"deletions",events[["D"]],indel_bases[["D"]])
  )
}
mapping_statistics <- function(results,references,search_counts,seed_counts) {
  total <- length(results)
  mapped <- Filter(function(r) r$mapped,results)
  unique_count <- sum(vapply(mapped,function(r) r$x0 == 1L,logical(1)))
  short <- sum(vapply(results,function(r) !r$mapped && r$reason == "SHORT",logical(1)))
  nohit <- sum(vapply(results,function(r) !r$mapped && r$reason == "NOHIT",logical(1)))
  lines <- c(
      words(
          "reads total",
          total,
          "trimmed",
          sum(vapply(results,function(r) r$trimmed > 0L,logical(1))),
          "trimmed_bases",
          sum(vapply(results,function(r) r$trimmed,integer(1))),
          "short",
          short
      ),
      words(
          "mapped",
          length(mapped),
          "rate",
          ratio(length(mapped),total),
          "unique",
          unique_count,
          "multi",
          length(mapped)-unique_count,
          "unmapped",
          total-length(mapped)
      ),
      words("unmapped short",short,"nohit",nohit),
      words(
          "method exact",
          sum(vapply(mapped,function(r) r$method == "EXACT",logical(1))),
          "mismatch",
          sum(vapply(mapped,function(r) r$method == "MISMATCH",logical(1))),
          "seed",
          sum(vapply(mapped,function(r) r$method == "SEED",logical(1)))
      ),
      words(
          "strand forward",
          sum(vapply(mapped,function(r) r$primary$strand == "+",logical(1))),
          "reverse",
          sum(vapply(mapped,function(r) r$primary$strand == "-",logical(1)))
      )
  )
  for (i in seq_along(references)) {
    on_reference <- Filter(function(r) r$primary$reference == i,mapped)
    forward <- sum(vapply(on_reference,function(r) r$primary$strand == "+",logical(1)))
    lines <- c(
        lines,
        words(
            "reference",
            references[[i]]$name,
            "mapped",
            length(on_reference),
            "unique",
            sum(vapply(on_reference,function(r) r$x0 == 1L,logical(1))),
            "forward",
            forward,
            "reverse",
            length(on_reference)-forward
        )
    )
  }
  lines <- c(lines,"length_bins")
  lengths <- vapply(results,function(r) r$length,integer(1))
  for (lower in seq.int((min(lengths) %/% 10L)*10L,(max(lengths) %/% 10L)*10L,10L)) {
    in_bin <- Filter(function(r) lower <= r$length && r$length <= lower+9L,results)
    mapped_bin <- Filter(function(r) r$mapped,in_bin)
    lines <- c(
        lines,
        words(
            paste0(lower,"-",lower+9L),
            "reads",
            length(in_bin),
            "mapped",
            length(mapped_bin),
            "unique",
            sum(vapply(mapped_bin,function(r) r$x0 == 1L,logical(1)))
        )
    )
  }
  with_n <- Filter(function(r) "N" %in% r$read$bases,results)
  lines <- c(
      lines,
      words(
          "n_reads",
          length(with_n),
          "n_bases",
          sum(vapply(with_n,function(r) sum(r$read$bases == "N"),integer(1))),
          "mapped",
          sum(vapply(with_n,function(r) r$mapped,logical(1)))
      )
  )
  target_counts <- integer()
  for (r in mapped) if (r$x0 >= 2L) {
    key <- paste(vapply(references[r$targets],function(reference) reference$name,character(1)),collapse="+")
    target_counts[key] <- if (key %in% names(target_counts)) target_counts[[key]]+1L else 1L
  }
  lines <- c(lines,"multi_targets")
  if (!length(target_counts)) lines <- c(lines,"none")
  for (key in sort(names(target_counts))) lines <- c(lines,words(key,target_counts[[key]]))
  lines <- c(lines,"mapq_histogram")
  mapqs <- vapply(mapped,function(r) r$mapq,integer(1))
  for (mapq in sort(unique(mapqs),decreasing=TRUE)) lines <- c(lines,words(mapq,sum(mapqs == mapq)))
  lines <- c(lines,"nm_histogram")
  nms <- vapply(mapped,function(r) r$primary$nm,integer(1))
  for (nm in sort(unique(nms))) lines <- c(lines,words(nm,sum(nms == nm)))
  lines <- c(
      lines,
      error_statistics(results,references),
      words(
          "search dfs_calls",
          search_counts[1L],
          "dfs_nodes",
          search_counts[2L],
          "dfs_leaves",
          search_counts[3L],
          "dfs_positions",
          search_counts[4L]
      )
  )
  seed_names <- c("reads","seeds","with_n","repetitive","without_hit","candidates","passing")
  c(lines,paste("seeds",paste(seed_names,seed_counts,collapse=" ")))
}
main <- function() {
  invisible(Sys.setlocale("LC_COLLATE","C"))
  input <- read_inputs()
  references <- input$references
  reads <- input$reads
  params <- input$params
  text <- reference_text(references)
  built <- build_suffix_array(text$text)
  reverse_built <- build_suffix_array(text$reverse)
  interval <- params$OCC_INTERVAL[1L]
  forward <- new_fm_index(text$text,built$suffixes,interval,params$SA_SAMPLE_INTERVAL[1L])
  reverse_index <- new_fm_index(text$reverse,reverse_built$suffixes,interval)
  index_lines <- index_statistics(
      text,
      built$suffixes,
      built$classes,
      forward,
      reverse_built$suffixes,
      reverse_built$classes,
      reverse_index,
      params
  )
  s <- list2env(
      list(
          text=text,
          references=references,
          forward=forward,
          reverse=reverse_index,
          params=params,
          search_counts=integer(4L),
          seed_counts=integer(7L)
      ),
      parent=emptyenv()
  )
  results <- lapply(reads,function(read) map_read(s,read))
  sam <- c(
      sam_header(references),
      vapply(results,function(r) sam_record(r,references,params$MAX_ALT_HITS[1L]),character(1))
  )
  coverage <- coverage_and_variants(results,references,params)
  outputs <- list(
      "alignments.sam"=sam,
      "coverage.txt"=coverage$coverage,
      "variants.txt"=coverage$variants,
      "index_stats.txt"=index_lines,
      "summary.txt"=mapping_statistics(results,references,s$search_counts,s$seed_counts)
  )
  for (name in names(outputs)) write_lines(name,outputs[[name]])
}
main()
