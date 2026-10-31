real_text <- function(value) {
  text <- sprintf("%.4f", value)
  if (text == "-0.0000") "0.0000" else text
}
proportion_text <- function(numerator, denominator) sprintf("%.0f/%.0f %s", numerator, denominator, real_text(numerator / denominator))
gcd <- function(a, b) {
  while (b != 0) {
    remainder <- a %% b
    a <- b
    b <- remainder
  }
  a
}
fraction_text <- function(numerator, denominator) {
  if (denominator == 0) return("- -")
  divisor <- gcd(numerator, denominator)
  proportion_text(numerator / divisor, denominator / divisor)
}
evaluate <- function(class_count, truths, predictions) {
  confusion <- matrix(0L, class_count, class_count)
  for (i in seq_along(truths)) confusion[truths[i], predictions[i]] <- confusion[truths[i], predictions[i]] + 1L
  total <- length(truths)
  correct <- sum(diag(confusion))
  supports <- rowSums(confusion)
  predicted <- colSums(confusion)
  f1_sum <- 0
  scored <- 0L
  for (label in seq_len(class_count)) {
    denominator <- predicted[label] + supports[label]
    if (denominator > 0) {
      f1_sum <- f1_sum + (2 * confusion[label, label]) / denominator
      scored <- scored + 1L
    }
  }
  list(matrix = confusion, total = total, correct = correct, micro = correct / total, macro = f1_sum / scored,
       supports = supports, predicted = predicted)
}
evaluation_lines <- function(evaluation, names) {
  lines <- paste("true\\predicted", paste(names, collapse = " "))
  for (label in seq_along(names)) lines <- c(lines, paste(names[label], paste(evaluation$matrix[label, ], collapse = " ")))
  for (label in seq_along(names)) {
    hits <- evaluation$matrix[label, label]
    predicted <- evaluation$predicted[label]
    support <- evaluation$supports[label]
    lines <- c(lines, sprintf("class %s precision %s recall %s f1 %s support %.0f", names[label], fraction_text(hits, predicted),
      fraction_text(hits, support), fraction_text(2 * hits, predicted + support), support))
  }
  c(lines, paste("micro_f1", real_text(evaluation$micro), "macro_f1", real_text(evaluation$macro)))
}
