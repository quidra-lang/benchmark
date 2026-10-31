SYMBOLS <- c("$","#","A","C","G","T")
SYMBOL_NUMBER <- setNames(0:5,SYMBOLS)
BASES <- c("A","C","G","T")
counting_sort <- function(positions,keys,key_count) {
  counts <- integer(key_count)
  for (position in positions) counts[keys[position+1L]+1L] <- counts[keys[position+1L]+1L]+1L
  offset <- 0L
  for (key in seq_along(counts)) {
    n <- counts[key]
    counts[key] <- offset
    offset <- offset+n
  }
  result <- integer(length(positions))
  for (position in positions) {
    key <- keys[position+1L]+1L
    result[counts[key]+1L] <- position
    counts[key] <- counts[key]+1L
  }
  result
}
build_suffix_array <- function(text) {
  n <- length(text)
  codes <- unname(SYMBOL_NUMBER[text])
  order <- counting_sort(0:(n-1L),codes,length(SYMBOLS))
  ranks <- integer(n)
  count_classes <- 0L
  previous <- -1L
  for (position in order) {
    if (codes[position+1L] != previous) {
      count_classes <- count_classes+1L
      previous <- codes[position+1L]
    }
    ranks[position+1L] <- count_classes-1L
  }
  classes <- count_classes
  width <- 1L
  while (count_classes < n) {
    second <- integer(n)
    for (position in 0:(n-1L)) if (position+width < n) second[position+1L] <- ranks[position+width+1L]+1L
    order <- counting_sort(0:(n-1L),second,count_classes+1L)
    order <- counting_sort(order,ranks,count_classes)
    updated <- integer(n)
    count_classes <- 0L
    previous <- c(-1L,-1L)
    for (position in order) {
      key <- c(ranks[position+1L],second[position+1L])
      if (!identical(key,previous)) {
        count_classes <- count_classes+1L
        previous <- key
      }
      updated[position+1L] <- count_classes-1L
    }
    ranks <- updated
    classes <- c(classes,count_classes)
    width <- 2L*width
  }
  list(suffixes=order,classes=classes)
}
direct_sort <- function(text) {
  suffixes <- vapply(
      seq_along(text),
      function(position) paste(text[seq.int(position,length(text))],collapse=""),
      character(1)
  )
  order(suffixes,method="radix")-1L
}
adjacent_check <- function(text,suffixes) {
  ordered <- lcp_sum <- 0L
  longest <- -1L
  longest_row <- 1L
  for (row in seq_len(length(suffixes)-1L)) {
    left <- suffixes[row]
    right <- suffixes[row+1L]
    common <- 0L
    while (text[left+common+1L] == text[right+common+1L]) common <- common+1L
    ordered <- ordered+as.integer(SYMBOL_NUMBER[[text[left+common+1L]]] < SYMBOL_NUMBER[[text[right+common+1L]]])
    lcp_sum <- lcp_sum+common
    if (common > longest) {
      longest <- common
      longest_row <- row
    }
  }
  list(ordered=ordered,lcp_sum=lcp_sum,longest=longest,row=longest_row)
}
