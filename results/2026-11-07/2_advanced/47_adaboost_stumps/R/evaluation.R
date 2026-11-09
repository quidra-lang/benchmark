number <- function(value,decimals=4L) {
  text <- sprintf(paste0("%.",decimals,"f"),value)
  if (startsWith(text,"-") && as.numeric(text) == 0) substring(text,2L) else text
}
ratio <- function(a,b) if (b > 0) number(a/b) else "-"
prediction <- function(score) if (score > 0) 1L else -1L
auc <- function(rows,scores) {
  positive <- scores[vapply(rows,function(row) row$label == 1L,logical(1))]
  negative <- scores[vapply(rows,function(row) row$label == -1L,logical(1))]
  wins <- ties <- 0L
  for (a in positive) for (b in negative) {
    wins <- wins+as.integer(a > b)
    ties <- ties+as.integer(a == b)
  }
  c(2L*wins+ties,2L*length(positive)*length(negative))
}
confusion <- function(rows,predictions,classes) {
  matrix <- matrix(0L,classes,classes)
  for (i in seq_along(rows)) matrix[rows[[i]]$label,predictions[i]] <- matrix[
      rows[[i]]$label,
      predictions[i]
  ]+1L
  matrix
}
count_at_most <- function(margins,threshold) sum(margins <= threshold)
write_lines <- function(name,lines) writeLines(lines,file.path("output",name),useBytes=TRUE)
