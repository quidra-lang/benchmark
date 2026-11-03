reduced_fraction <- function(a,b) {
  if (b == 0) return(NULL)
  x <- abs(a)
  y <- b
  while (y != 0) {
    remainder <- x %% y
    x <- y
    y <- remainder
  }
  c(a/x,b/x)
}
sum_fractions <- function(values) {
  result <- c(0,1)
  for (value in values) result <- reduced_fraction(
      result[1L]*value[2L]+value[1L]*result[2L],
      result[2L]*value[2L]
  )
  result
}
measures <- function(actual,predictions,classes) {
  matrix <- matrix(0,classes,classes)
  for (i in seq_along(actual)) matrix[actual[i],predictions[i]] <- matrix[actual[i],predictions[i]]+1
  support <- rowSums(matrix)
  predicted <- colSums(matrix)
  diagonal <- diag(matrix)
  correct <- sum(diagonal)
  n <- length(actual)
  recall <- lapply(seq_len(classes),function(k) reduced_fraction(diagonal[k],support[k]))
  precision <- lapply(seq_len(classes),function(k) reduced_fraction(diagonal[k],predicted[k]))
  f1 <- lapply(seq_len(classes),function(k) reduced_fraction(2*diagonal[k],support[k]+predicted[k]))
  total <- sum_fractions(recall)
  expected <- sum(support*predicted)
  list(matrix=matrix,support=support,correct=correct,accuracy=reduced_fraction(correct,n),
    balanced_accuracy=reduced_fraction(total[1L],total[2L]*classes),kappa=reduced_fraction(
        n*correct-expected,
        n*n-expected
    ),
    recall=recall,precision=precision,f1=f1,macro_f1=ordered_sum(2*diagonal/(support+predicted))/classes)
}
mcnemar <- function(actual,a,b) {
  b01 <- sum(a == actual & b != actual)
  b10 <- sum(a != actual & b == actual)
  chi2 <- if (b01 == b10) 0 else (abs(b01-b10)-1)^2/(b01+b10)
  list(b01=b01,b10=b10,chi2=chi2,significant=chi2 > 3.841)
}
random_generator <- function(seed) {
  state <- seed
  function() {
    state <<- (48271*state) %% 2147483647
    state
  }
}
