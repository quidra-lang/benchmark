ordered_sum <- function(values) {
  total <- 0
  for (value in values) total <- total + value
  total
}
cross_validation_score <- function(observed, predicted) {
  if (any(vapply(predicted, is.null, FALSE))) return(NULL)
  estimates <- unlist(predicted, use.names = FALSE)
  ordered_sum((observed - estimates) * (observed - estimates)) / length(observed)
}
generalized_score <- function(observed, fitted, edf) {
  rss <- ordered_sum((observed - fitted) * (observed - fitted))
  factor <- 1 - edf / length(observed)
  rss / length(observed) / (factor * factor)
}
choose_candidate <- function(candidates) {
  eligible <- which(!vapply(candidates, function(candidate) is.null(candidate$score), FALSE))
  eligible[[which.min(vapply(candidates[eligible], function(candidate) candidate$score, 0))]]
}
