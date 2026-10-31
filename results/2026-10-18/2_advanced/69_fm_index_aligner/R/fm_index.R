new_fm_index <- function(text,suffixes,interval,sample_interval=0L) {
  n <- length(text)
  bwt <- text[ifelse(suffixes > 0L,suffixes,n)]
  c_array <- setNames(integer(length(SYMBOLS)),SYMBOLS)
  offset <- 0L
  for (symbol in SYMBOLS) {
    c_array[symbol] <- offset
    offset <- offset+sum(text == symbol)
  }
  counts <- integer(length(SYMBOLS))
  checkpoints <- matrix(0L,n %/% interval+1L,length(SYMBOLS))
  for (position in seq_len(n)) {
    key <- SYMBOL_NUMBER[[bwt[position]]]+1L
    counts[key] <- counts[key]+1L
    if (position %% interval == 0L) checkpoints[position %/% interval+1L,] <- counts
  }
  samples <- rep(-1L,n)
  if (sample_interval > 0L) {
    sampled <- which(suffixes %% sample_interval == 0L)
    samples[sampled] <- suffixes[sampled]
  }
  list(size=n,bwt=bwt,interval=interval,c=c_array,checkpoints=checkpoints,samples=samples)
}
occurrence <- function(index,symbol,position) {
  checkpoint <- position %/% index$interval
  start <- checkpoint*index$interval
  extra <- if (position > start) sum(index$bwt[seq.int(start+1L,position)] == symbol) else 0L
  index$checkpoints[checkpoint+1L,SYMBOL_NUMBER[[symbol]]+1L]+extra
}
lf <- function(index,row) {
  symbol <- index$bwt[row+1L]
  index$c[[symbol]]+occurrence(index,symbol,row)
}
extend_interval <- function(index,lower,upper,base) {
  if (base == "N") return(c(0L,0L))
  c(index$c[[base]]+occurrence(index,base,lower),index$c[[base]]+occurrence(index,base,upper))
}
locate <- function(index,row) {
  steps <- 0L
  while (index$samples[row+1L] < 0L) {
    row <- lf(index,row)
    steps <- steps+1L
  }
  c(index$samples[row+1L]+steps,steps)
}
inverse_bwt <- function(index) {
  result <- rep("$",index$size)
  row <- 0L
  for (position in seq.int(index$size-2L,0L)) {
    result[position+1L] <- index$bwt[row+1L]
    row <- lf(index,row)
  }
  result
}
backward_search <- function(index,sequence) {
  interval <- c(0L,index$size)
  for (base in rev(sequence)) {
    interval <- extend_interval(index,interval[1L],interval[2L],base)
    if (interval[1L] >= interval[2L]) break
  }
  interval
}
