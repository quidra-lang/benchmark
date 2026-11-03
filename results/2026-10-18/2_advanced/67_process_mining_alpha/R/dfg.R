pair_key <- function(a,b) paste(a,b,sep="|")
count_at <- function(counts,a,b) {
  key <- pair_key(a,b)
  if (key %in% names(counts)) counts[[key]] else 0
}
add_count <- function(counts,key,value=1) {
  counts[key] <- if (key %in% names(counts)) counts[[key]]+value else value
  counts
}
directly_follows <- function(log) {
  counts <- numeric()
  for (entry in log) if (length(entry$trace) > 1L) for (i in seq_len(length(entry$trace)-1L)) counts <- add_count(
      counts,
      pair_key(entry$trace[i],entry$trace[i+1L]),
      entry$weight
  )
  counts
}
basic_relation <- function(counts,a,b) {
  forward <- count_at(counts,a,b) > 0
  backward <- count_at(counts,b,a) > 0
  if (forward && !backward) "->" else if (backward && !forward) "<-" else if (forward) "||" else "#"
}
table_lines <- function(rows,width) {
  n <- length(rows)
  pad <- function(values,w) sprintf(paste0("%",w,"s"),as.character(values))
  lines <- paste0("    ",paste(pad(seq_len(n),width),collapse=""))
  for (i in seq_along(rows)) lines <- c(lines,paste0(pad(i,4L),paste(pad(rows[[i]],width),collapse="")))
  lines
}
footprint <- function(activities,relation) {
  c(
      vapply(seq_along(activities),function(i) paste("ACTIVITY",i,activities[i]),character(1)),
      table_lines(lapply(activities,function(a) vapply(activities,function(b) relation(a,b),character(1))),4L)
  )
}
