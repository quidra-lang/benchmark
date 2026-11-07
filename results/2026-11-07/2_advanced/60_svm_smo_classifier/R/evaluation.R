svm_sign <- function(value) ifelse(value > 0,1L,-1L)
folds <- function(size,count) lapply(
    seq_len(count)-1L,
    function(f) list(
        train=which((seq_len(size)-1L) %% count != f),
        test=which((seq_len(size)-1L) %% count == f)
    )
)
correct_count <- function(labels,values) sum(svm_sign(values) == labels)
binary_counts <- function(labels,values) {
  prediction <- svm_sign(values)
  c(
      sum(labels == 1L & prediction == 1L),
      sum(labels == -1L & prediction == 1L),
      sum(labels == -1L & prediction == -1L),
      sum(labels == 1L & prediction == -1L)
  )
}
auc <- function(labels,values) {
  positives <- which(labels == 1L)
  negatives <- which(labels == -1L)
  total <- 0
  for (positive in positives) for (negative in negatives) {
    if (values[positive] > values[negative]) total <- total+1 else if (values[positive] == values[negative]) total <- total+0.5
  }
  total/(length(positives)*length(negatives))
}
confusion_matrix <- function(classes,predictions) {
  matrix <- matrix(0L,3L,3L)
  for (i in seq_along(classes)) matrix[classes[i],predictions[i]] <- matrix[classes[i],predictions[i]]+1L
  matrix
}
confusion_lines <- function(matrix) {
  lines <- vapply(seq_len(3L),function(i) paste(matrix[i,],collapse=" "),character(1))
  for (k in seq_len(3L)) lines <- c(
      lines,
      paste(
          "class",
          k,
          "precision",
          ratio(matrix[k,k],sum(matrix[,k])),
          "recall",
          ratio(matrix[k,k],sum(matrix[k,]))
      )
  )
  lines
}
fixed_text <- function(value,decimals=4L) {
  result <- sprintf(paste0("%.",decimals,"f"),value)
  if (startsWith(result,"-") && as.numeric(result) == 0) substring(result,2L) else result
}
ratio <- function(numerator,denominator) if (denominator > 0L) fixed_text(numerator/denominator) else "-"
ordered_sum <- function(values) {
  total <- 0
  for (value in values) total <- total+value
  total
}
write_lines <- function(name,lines) {
  dir.create("output",showWarnings=FALSE)
  writeLines(lines,file.path("output",name),useBytes=TRUE)
}
