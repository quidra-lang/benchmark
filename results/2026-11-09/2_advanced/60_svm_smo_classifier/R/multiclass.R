CLASS_PAIRS <- list(c(1L,2L),c(1L,3L),c(2L,3L))
train_multiclass <- function(examples,kernel,C,settings) {
  points <- lapply(examples,function(example) example$point)
  classes <- vapply(examples,function(example) example$class_number,integer(1))
  matrix <- kernel_matrix(kernel,points)
  ovr <- lapply(
      seq_len(3L),
      function(k) train_model(points,ifelse(classes == k,1L,-1L),kernel,matrix,C,settings)
  )
  ovo <- lapply(CLASS_PAIRS,function(pair) {
    indices <- which(classes %in% pair)
    labels <- ifelse(classes[indices] == pair[1L],1L,-1L)
    train_model(points[indices],labels,kernel,submatrix(matrix,indices),C,settings)
  })
  list(kernel=kernel,C=C,ovr=ovr,ovo=ovo)
}
classify <- function(models,point) {
  rest <- vapply(models$ovr,function(model) decision(model,point),numeric(1))
  pairs <- vapply(models$ovo,function(model) decision(model,point),numeric(1))
  votes <- integer(3L)
  scores <- numeric(3L)
  for (i in seq_along(CLASS_PAIRS)) {
    pair <- CLASS_PAIRS[[i]]
    value <- pairs[i]
    winner <- if (value > 0) pair[1L] else pair[2L]
    votes[winner] <- votes[winner]+1L
    scores[pair[1L]] <- scores[pair[1L]]+value
    scores[pair[2L]] <- scores[pair[2L]]-value
  }
  candidates <- which(votes == max(votes))
  chosen <- candidates[which.max(scores[candidates])]
  list(
      ovr_values=rest,
      ovo_values=pairs,
      ovr=which.max(rest),
      ovo=chosen,
      votes=votes,
      tied=length(candidates) > 1L
  )
}
