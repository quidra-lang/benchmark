TABLE_KEYS <- list(c(0L,0L),c(1L,0L),c(0L,1L),c(1L,1L))
TABLE_NAMES <- c("dc_luma","ac_luma","dc_chroma","ac_chroma")
table_key <- function(class,id) paste(class,id,sep=",")
power2 <- function(n) bitwShiftL(1L,n)
category <- function(value) {
  n <- 0L
  magnitude <- abs(value)
  while (magnitude != 0) {
    n <- n+1L
    magnitude <- magnitude %/% 2L
  }
  n
}
extra_bits <- function(value) {
  n <- category(value)
  c(if (value >= 0) value else value+power2(n)-1L,n)
}
amplitude <- function(bits,n) if (n == 0L) 0 else if (bits >= power2(n-1L)) bits else bits-power2(n)+1L
new_huffman <- function(counts,symbols) {
  codes <- list()
  decode <- new.env(hash=TRUE,parent=emptyenv())
  code <- offset <- 0L
  for (length in seq_len(16L)) {
    for (i in seq_len(counts[length])) {
      symbol <- symbols[offset+i]
      codes[[as.character(symbol)]] <- c(length,code)
      assign(table_key(length,code),symbol,decode)
      code <- code+1L
    }
    offset <- offset+counts[length]
    code <- 2L*code
  }
  list(counts=counts,symbols=symbols,codes=codes,decode=decode)
}
optimized_table <- function(frequencies) {
  frequencies <- c(frequencies,1L)
  sizes <- others <- integer(257L)
  repeat {
    available <- which(frequencies > 0L)
    if (length(available) < 2L) break
    available <- available[order(frequencies[available],-available)]
    first <- available[1L]
    second <- available[2L]
    frequencies[first] <- frequencies[first]+frequencies[second]
    frequencies[second] <- 0L
    sizes[first] <- sizes[first]+1L
    while (others[first] != 0L) {
      first <- others[first]
      sizes[first] <- sizes[first]+1L
    }
    others[first] <- second
    sizes[second] <- sizes[second]+1L
    while (others[second] != 0L) {
      second <- others[second]
      sizes[second] <- sizes[second]+1L
    }
  }
  counts <- integer(257L)
  for (size in sizes) if (size > 0L) counts[size] <- counts[size]+1L
  if (max(sizes) >= 17L) for (length in seq.int(max(sizes),17L)) while (counts[length] > 0L) {
    shorter <- length-2L
    while (counts[shorter] == 0L) shorter <- shorter-1L
    counts[length] <- counts[length]-2L
    counts[length-1L] <- counts[length-1L]+1L
    counts[shorter+1L] <- counts[shorter+1L]+2L
    counts[shorter] <- counts[shorter]-1L
  }
  longest <- max(which(counts[1:16] > 0L))
  counts[longest] <- counts[longest]-1L
  indices <- which(sizes[1:256] > 0L)
  symbols <- indices[order(sizes[indices],indices)]-1L
  new_huffman(counts[1:16],symbols)
}
