fraction <- function(numerator,denominator) {
  if (denominator == 0) return("-")
  if (denominator < 0) {
    numerator <- -numerator
    denominator <- -denominator
  }
  a <- abs(numerator)
  b <- denominator
  while (b != 0) {
    remainder <- a %% b
    a <- b
    b <- remainder
  }
  paste0(sprintf("%.0f",numerator %/% a),"/",sprintf("%.0f",denominator %/% a))
}
confusion_matrix <- function(k) matrix(0L,k,k)
accumulate_confusion <- function(matrix,truth,prediction) {
  for (i in seq_along(truth)) matrix[truth[i],prediction[i]] <- matrix[truth[i],prediction[i]]+1L
  matrix
}
correct_count <- function(truth,prediction) sum(truth == prediction)
matrix_lines <- function(states,matrix) {
  width <- max(nchar(as.character(matrix)))
  padded <- function(value) paste0(strrep(" ",width-nchar(as.character(value))),value)
  lines <- paste0(" ",paste0(" ",vapply(states,padded,character(1)),collapse=""))
  for (i in seq_along(states)) lines <- c(
      lines,
      paste0(states[i],paste0(" ",vapply(matrix[i,],padded,character(1)),collapse=""))
  )
  lines
}
metric_lines <- function(states,matrix) {
  k <- length(states)
  rows <- rowSums(matrix)
  columns <- colSums(matrix)
  total <- sum(rows)
  correct <- sum(diag(matrix))
  expected <- sum(rows*columns)
  lines <- c(
      paste("ACCURACY",fraction(correct,total)),
      paste("KAPPA",fraction(total*correct-expected,total*total-expected))
  )
  for (i in seq_len(k)) {
    tp <- matrix[i,i]
    lines <- c(
        lines,
        paste(
            "STATE",
            states[i],
            "precision",
            fraction(tp,columns[i]),
            "recall",
            fraction(tp,rows[i]),
            "f1",
            fraction(2L*tp,columns[i]+rows[i])
        )
    )
  }
  lines
}
runs <- function(path) {
  result <- list()
  if (!length(path)) return(result)
  start <- 1L
  state <- path[1L]
  if (length(path) > 1L) for (t in seq.int(2L,length(path))) if (path[t] != state) {
    result[[length(result)+1L]] <- c(state,start,t-1L)
    start <- t
    state <- path[t]
  }
  result[[length(result)+1L]] <- c(state,start,length(path))
  result
}
regions_overlap <- function(a,b) a[1L] <= b[2L] && b[1L] <= a[2L]
region_counts <- function(predicted,truth) c(length(predicted),length(truth),
  sum(vapply(
      predicted,
      function(region) any(vapply(truth,function(other) regions_overlap(region,other),logical(1))),
      logical(1)
  )),
  sum(vapply(
      truth,
      function(region) any(vapply(predicted,function(other) regions_overlap(region,other),logical(1))),
      logical(1)
  )))
boundaries <- function(path) if (length(path) < 2L) integer() else which(head(path,-1L) != tail(path,-1L))+1L
boundary_counts <- function(predicted_path,true_path,tolerance) {
  predicted <- boundaries(predicted_path)
  truth <- boundaries(true_path)
  c(
      length(predicted),
      length(truth),
      sum(vapply(predicted,function(p) any(abs(p-truth) <= tolerance),logical(1))),
      sum(vapply(truth,function(t) any(abs(predicted-t) <= tolerance),logical(1)))
  )
}
