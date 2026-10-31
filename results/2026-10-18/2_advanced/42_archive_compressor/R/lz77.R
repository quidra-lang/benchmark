tokenize <- function(data,offset_bits,length_bits) {
  window <- 2^offset_bits
  lookahead <- 2^length_bits+2L
  prefixes <- new.env(hash=TRUE,parent=emptyenv())
  tokens <- list()
  position <- 1L
  while (position <= length(data)) {
    distance <- longest <- 0L
    limit <- min(lookahead,length(data)-position+1L)
    if (limit >= 3L) {
      key <- paste(data[seq.int(position,position+2L)],collapse=",")
      candidates <- if (exists(key,prefixes,inherits=FALSE)) get(key,prefixes,inherits=FALSE) else integer()
      for (start in rev(candidates)) {
        if (position-start > window) break
        d <- position-start
        matched <- 3L
        while (matched < limit && data[position+matched] == data[position+matched-d]) matched <- matched+1L
        if (matched > longest) {
          distance <- d
          longest <- matched
        }
        if (longest == limit) break
      }
    }
    if (longest >= 3L) {
      tokens[[length(tokens)+1L]] <- c(1L,distance,longest)
      consumed <- longest
    } else {
      tokens[[length(tokens)+1L]] <- c(0L,data[position],0L)
      consumed <- 1L
    }
    stop <- min(position+consumed-1L,length(data)-2L)
    if (stop >= position) for (start in seq.int(position,stop)) {
      key <- paste(data[seq.int(start,start+2L)],collapse=",")
      previous <- if (exists(key,prefixes,inherits=FALSE)) get(key,prefixes,inherits=FALSE) else integer()
      assign(key,c(previous,start),prefixes)
    }
    position <- position+consumed
  }
  tokens
}
copy_match <- function(output,distance,matched,original) {
  if (distance > output$n) decode_error("bad_offset",output$n)
  if (output$n+matched > original) decode_error("overrun",output$n)
  for (unused in seq_len(matched)) append_bytes(output,output$bytes[output$n-distance+1L])
}
