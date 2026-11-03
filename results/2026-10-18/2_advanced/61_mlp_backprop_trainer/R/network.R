layout_for <- function(architecture) {
  previous <- architecture$width*architecture$height
  index <- 1L
  layers <- list()
  mask <- logical()
  for (definition in architecture$layers) {
    outputs <- definition$units
    weights <- outputs*previous
    layers[[length(layers)+1L]] <- list(inputs=previous,outputs=outputs,activation=definition$activation,kind=definition$kind,
      weight_start=index,weight_end=index+weights-1L,bias_start=index+weights,bias_end=index+weights+outputs-1L)
    mask <- c(mask,rep(TRUE,weights),rep(FALSE,outputs))
    index <- index+weights+outputs
    previous <- outputs
  }
  list(layers=layers,is_weight=mask,parameters=index-1L,weight_count=sum(mask))
}
layer_values <- function(theta,layer) list(
    weights=matrix(
        theta[seq.int(layer$weight_start,layer$weight_end)],
        nrow=layer$outputs,
        ncol=layer$inputs,
        byrow=TRUE
    ),
    biases=theta[seq.int(layer$bias_start,layer$bias_end)]
)
forward <- function(layout,theta,image) {
  activations <- list(image$vector)
  preactivations <- weights <- list()
  scores <- delta <- numeric()
  loss <- 0
  for (l in seq_along(layout$layers)) {
    layer <- layout$layers[[l]]
    values <- layer_values(theta,layer)
    weights[[l]] <- values$weights
    z <- weighted_pre_activation(values$weights,values$biases,tail(activations,1L)[[1L]])
    preactivations[[l]] <- z
    if (l == length(layout$layers)) {
      output <- output_scores(layer$activation,z,image$label)
      scores <- output$scores
      loss <- output$loss
      delta <- output$error
      activations[[l+1L]] <- scores
    } else activations[[l+1L]] <- vapply(
        z,
        function(value) hidden_activation(layer$activation,value),
        numeric(1)
    )
  }
  list(z=preactivations,a=activations,weights=weights,scores=scores,loss=loss,output_delta=delta)
}
gradient <- function(layout,theta,image,include_input=FALSE) {
  cache <- forward(layout,theta,image)
  layers <- layout$layers
  deltas <- vector("list",length(layers))
  deltas[[length(layers)]] <- cache$output_delta
  if (length(layers) > 1L) for (l in seq.int(length(layers)-1L,1L)) {
    propagated <- backward_sum(cache$weights[[l+1L]],deltas[[l+1L]])
    layer <- layers[[l]]
    deltas[[l]] <- vapply(
        seq_along(propagated),
        function(j) propagated[j]*hidden_derivative(layer$activation,cache$z[[l]][j],cache$a[[l+1L]][j]),
        numeric(1)
    )
  }
  grad <- numeric(layout$parameters)
  for (l in seq_along(layers)) {
    layer <- layers[[l]]
    destination <- layer$weight_start
    for (j in seq_len(layer$outputs)) for (i in seq_len(layer$inputs)) {
      grad[destination] <- deltas[[l]][j]*cache$a[[l]][i]
      destination <- destination+1L
    }
    grad[seq.int(layer$bias_start,layer$bias_end)] <- deltas[[l]]
  }
  list(
      gradient=grad,
      cache=cache,
      input_gradient=if (include_input) backward_sum(cache$weights[[1L]],deltas[[1L]]) else numeric()
  )
}
average_gradient <- function(layout,theta,images) {
  result <- numeric(layout$parameters)
  loss <- 0
  for (image in images) {
    evaluated <- gradient(layout,theta,image)
    loss <- loss+evaluated$cache$loss
    for (i in seq_along(result)) result[i] <- result[i]+evaluated$gradient[i]
  }
  list(gradient=result/length(images),loss=loss/length(images))
}
evaluate_network <- function(layout,theta,images) {
  outcomes <- list()
  loss <- 0
  correct <- 0L
  for (image in images) {
    cache <- forward(layout,theta,image)
    predicted <- which.max(cache$scores)-1L
    outcomes[[length(outcomes)+1L]] <- list(id=image$id,label=image$label,predicted=predicted,confidence=cache$scores[predicted+1L],scores=cache$scores,
      loss=cache$loss,hidden=cache$a[seq.int(2L,length(cache$a)-1L)])
    loss <- loss+cache$loss
    correct <- correct+as.integer(predicted == image$label)
  }
  list(loss=loss/length(images),correct=correct,outcomes=outcomes)
}
