ordered_sum <- function(values) {
  total <- 0
  for (value in values) total <- total+value
  total
}
hidden_activation <- function(
    kind,
    value
) if (kind == "TANH") tanh(value) else if (kind == "SIGMOID") 1/(1+exp(-value)) else if (value > 0) value else 0
hidden_derivative <- function(
    kind,
    z,
    activated
) if (kind == "TANH") 1-activated*activated else if (kind == "SIGMOID") activated*(1-activated) else if (z > 0) 1 else 0
output_scores <- function(kind,z,label) {
  n <- length(z)
  if (kind == "SOFTMAX") {
    largest <- max(z)
    terms <- exp(z-largest)
    total <- ordered_sum(terms)
    scores <- terms/total
    return(list(
        scores=scores,
        loss=log(total)-(z[label+1L]-largest),
        error=scores-as.numeric(seq_len(n) == label+1L)
    ))
  }
  scores <- 1/(1+exp(-z))
  errors <- numeric(n)
  loss <- 0
  for (k in seq_len(n)) {
    value <- scores[k]
    residual <- value-as.numeric(k == label+1L)
    loss <- loss+residual*residual
    errors[k] <- 2*residual*value*(1-value)/n
  }
  list(scores=scores,loss=loss/n,error=errors)
}
weighted_pre_activation <- function(weights,biases,activation) vapply(
    seq_along(biases),
    function(j) ordered_sum(weights[j,]*activation)+biases[j],
    numeric(1)
)
backward_sum <- function(weights,error) vapply(
    seq_len(ncol(weights)),
    function(i) ordered_sum(weights[,i]*error),
    numeric(1)
)
