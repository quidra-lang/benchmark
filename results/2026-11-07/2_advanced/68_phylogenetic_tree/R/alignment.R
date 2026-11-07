BASES <- c("A","C","G","T")
AMBIGUOUS <- strsplit("RYSWKMBDHV","",fixed=TRUE)[[1L]]
BASE_SETS <- setNames(
    c(1L,2L,4L,8L,5L,10L,6L,9L,12L,3L,14L,13L,11L,7L,15L,15L),
    strsplit("ACGTRYSWKMBDHVN-","",fixed=TRUE)[[1L]]
)
read_fasta <- function() {
  records <- list()
  name <- ""
  pieces <- character()
  header <- 0L
  lines <- readLines("input/alignment.fasta")
  for (line_number in seq_along(lines)) {
    line <- lines[line_number]
    if (startsWith(line,">")) {
      if (header != 0L) records[[length(records)+1L]] <- list(
          line=header,
          name=name,
          sequence=toupper(paste(pieces,collapse=""))
      )
      name <- strsplit(substring(line,2L)," ",fixed=TRUE)[[1L]][1L]
      header <- line_number
      pieces <- character()
    } else pieces <- c(pieces,line)
  }
  records[[length(records)+1L]] <- list(line=header,name=name,sequence=toupper(paste(pieces,collapse="")))
  records
}
compress_patterns <- function(sequences) {
  patterns <- character()
  columns <- weights <- integer()
  for (c in seq_len(length(sequences[[1L]]))) {
    pattern <- paste(vapply(sequences,function(sequence) sequence[c],character(1)),collapse="")
    index <- match(pattern,patterns)
    if (is.na(index)) {
      patterns <- c(patterns,pattern)
      weights <- c(weights,0L)
      index <- length(patterns)
    }
    columns <- c(columns,index)
    weights[index] <- weights[index]+1L
  }
  encoded <- lapply(patterns,function(pattern) unname(BASE_SETS[strsplit(pattern,"",fixed=TRUE)[[1L]]]))
  list(patterns=patterns,columns=columns,weights=weights,encoded=encoded)
}
classify_columns <- function(sequences) {
  totals <- integer(5L)
  for (c in seq_len(length(sequences[[1L]]))) {
    characters <- vapply(sequences,function(sequence) sequence[c],character(1))
    counts <- vapply(BASES,function(base) sum(characters == base),integer(1))
    kinds <- sum(counts > 0L)
    index <- if (kinds == 0L) 5L else if (kinds == 1L) 1L else 2L
    totals[index] <- totals[index]+1L
    totals[3L] <- totals[3L]+as.integer(sum(counts >= 2L) >= 2L)
    totals[4L] <- totals[4L]+as.integer("-" %in% characters)
  }
  totals
}
