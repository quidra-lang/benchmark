ordered_total <- function(items) {
  result <- 0
  for (item in items) result <- result+item
  result
}
parent_row <- function(parents,assignment,sizes) {
  row <- 0L
  for (p in parents) row <- row*sizes[p]+assignment[p]-1L
  row+1L
}
count_samples <- function(v,parents,samples,sizes) {
  counts <- matrix(0L,prod(sizes[parents]),sizes[v])
  for (sample in samples) {
    row <- parent_row(parents,sample,sizes)
    counts[row,sample[v]] <- counts[row,sample[v]]+1L
  }
  counts
}
learn_cpt <- function(counts,alpha) {
  cpt <- matrix(0,nrow(counts),ncol(counts))
  for (r in seq_len(nrow(counts))) {
    denominator <- ordered_total(counts[r,]+alpha)
    for (s in seq_len(ncol(counts))) cpt[r,s] <- (counts[r,s]+alpha)/denominator
  }
  cpt
}
log_likelihood <- function(counts,cpt) {
  result <- 0
  for (r in seq_len(nrow(counts))) for (s in seq_len(ncol(counts))) if (counts[r,s] > 0L) result <- result+counts[
      r,
      s
  ]*log(cpt[
      r,
      s
  ])
  result
}
parameter_count <- function(counts) nrow(counts)*(ncol(counts)-1L)
family_score <- function(v,parents,samples,sizes,alpha) {
  counts <- count_samples(v,sort(parents),samples,sizes)
  log_likelihood(counts,learn_cpt(counts,alpha))-parameter_count(counts)*log(length(samples))/2
}
