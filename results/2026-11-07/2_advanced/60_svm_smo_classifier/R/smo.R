passes <- function(model) model$full_passes+model$nonbound_passes
nonbound <- function(model,i) model$alpha[i] > 0 && model$alpha[i] < model$C
snap <- function(
    model,
    value
) if (value < 0.00000001) 0 else if (value > model$C-0.00000001) model$C else value
take_step <- function(model,first,second) {
  if (first == second) return(FALSE)
  alpha1 <- model$alpha[first]
  alpha2 <- model$alpha[second]
  y1 <- model$labels[first]
  y2 <- model$labels[second]
  e1 <- model$errors[first]
  e2 <- model$errors[second]
  if (y1 != y2) {
    lo <- max(0,alpha2-alpha1)
    hi <- min(model$C,model$C+alpha2-alpha1)
  } else {
    lo <- max(0,alpha2+alpha1-model$C)
    hi <- min(model$C,alpha2+alpha1)
  }
  if (lo == hi) return(FALSE)
  k11 <- model$matrix[first,first]
  k12 <- model$matrix[first,second]
  k22 <- model$matrix[second,second]
  eta <- k11+k22-2*k12
  if (eta <= 0) return(FALSE)
  a2 <- alpha2+y2*(e1-e2)/eta
  clipping <- 1L
  if (a2 < lo) {
    a2 <- lo
    clipping <- 2L
  } else if (a2 > hi) {
    a2 <- hi
    clipping <- 3L
  }
  a2 <- snap(model,a2)
  if (abs(a2-alpha2) < model$eps*(a2+alpha2+model$eps)) return(FALSE)
  a1 <- snap(model,alpha1+y1*y2*(alpha2-a2))
  t1 <- y1*(a1-alpha1)
  t2 <- y2*(a2-alpha2)
  b1 <- e1+t1*k11+t2*k12+model$b
  b2 <- e2+t1*k12+t2*k22+model$b
  threshold <- if (a1 > 0 && a1 < model$C) b1 else if (a2 > 0 && a2 < model$C) b2 else (b1+b2)/2
  delta <- threshold-model$b
  for (i in seq_along(model$points)) model$errors[i] <- model$errors[i]+(t1*model$matrix[first,i]+t2*model$matrix[
      second,
      i
  ]-delta)
  if (a1 > 0 && a1 < model$C) model$errors[first] <- 0
  if (a2 > 0 && a2 < model$C) model$errors[second] <- 0
  model$alpha[first] <- a1
  model$alpha[second] <- a2
  model$b <- threshold
  model$steps <- model$steps+1L
  model$clipping[clipping] <- model$clipping[clipping]+1L
  TRUE
}
examine <- function(model,second) {
  model$examined <- model$examined+1L
  residual <- model$errors[second]*model$labels[second]
  if (!((residual < -model$tolerance && model$alpha[second] < model$C) || (residual > model$tolerance && model$alpha[second] > 0))) return(0L)
  partner <- 0L
  largest <- -1
  for (i in seq_along(model$points)) if (i != second && nonbound(model,i)) {
    difference <- abs(model$errors[i]-model$errors[second])
    if (difference > largest) {
      largest <- difference
      partner <- i
    }
  }
  if (partner != 0L && take_step(model,partner,second)) {
    model$choices[1L] <- model$choices[1L]+1L
    return(1L)
  }
  for (first in seq_along(model$points)) if (nonbound(model,first) && take_step(model,first,second)) {
    model$choices[2L] <- model$choices[2L]+1L
    return(1L)
  }
  for (first in seq_along(model$points)) if (take_step(model,first,second)) {
    model$choices[3L] <- model$choices[3L]+1L
    return(1L)
  }
  0L
}
train_model <- function(points,labels,kernel,matrix,C,settings) {
  model <- new.env(parent=emptyenv())
  model$points <- points
  model$labels <- labels
  model$kernel <- kernel
  model$matrix <- matrix
  model$C <- C
  model$tolerance <- settings$tolerance
  model$eps <- settings$eps
  model$max_passes <- settings$max_passes
  model$alpha <- numeric(length(points))
  model$b <- 0
  model$errors <- -as.numeric(labels)
  model$full_passes <- model$nonbound_passes <- model$examined <- model$steps <- 0L
  model$choices <- model$clipping <- integer(3L)
  model$records <- list()
  model$converged <- FALSE
  examine_all <- TRUE
  repeat {
    examined_before <- model$examined
    changed <- 0L
    for (i in seq_along(points)) if (examine_all || nonbound(model,i)) changed <- changed+examine(model,i)
    if (examine_all) model$full_passes <- model$full_passes+1L else model$nonbound_passes <- model$nonbound_passes+1L
    model$records[[length(model$records)+1L]] <- list(
        full=examine_all,
        examined=model$examined-examined_before,
        changed=changed,
        alpha=if (examine_all) model$alpha else numeric()
    )
    if (examine_all && changed == 0L) {
      model$converged <- TRUE
      break
    }
    if (passes(model) == model$max_passes) break
    if (examine_all) examine_all <- FALSE else if (changed == 0L) examine_all <- TRUE
  }
  model
}
decision <- function(model,point) {
  total <- 0
  for (i in seq_along(model$alpha)) if (model$alpha[i] > 0) total <- total+model$alpha[i]*model$labels[i]*kernel_value(
      model$kernel,
      model$points[[i]],
      point
  )
  total-model$b
}
training_decisions <- function(model) vapply(seq_along(model$points),function(i) {
  total <- 0
  for (j in seq_along(model$alpha)) if (model$alpha[j] > 0) total <- total+model$alpha[j]*model$labels[j]*model$matrix[
      i,
      j
  ]
  total-model$b
},numeric(1))
