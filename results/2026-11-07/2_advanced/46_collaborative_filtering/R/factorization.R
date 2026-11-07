random_generator <- function(seed) {
  state <- seed
  function() {
    state <<- (48271*state) %% 2147483647
    state
  }
}
factor_value <- function(draw) ((draw() %% 2001)-1000)/10000
dot_product <- function(a,b) sequential_sum(a*b)
factor_prediction <- function(model,u,i) ((model$mean+model$user_bias[u])+model$item_bias[i])+dot_product(
    model$users[u,],
    model$items[i,]
)
train_svd <- function(data) {
  params <- data$params
  draw <- random_generator(params$SEED[1L])
  f <- params$FACTORS[1L]
  users <- matrix(0,length(data$users),f)
  items <- matrix(0,length(data$items),f)
  for (u in seq_len(nrow(users))) for (a in seq_len(f)) users[u,a] <- factor_value(draw)
  for (i in seq_len(nrow(items))) for (a in seq_len(f)) items[i,a] <- factor_value(draw)
  user_bias <- numeric(length(data$users))
  item_bias <- numeric(length(data$items))
  order <- seq_along(data$training)
  rate <- params$LEARNING_RATE[1L]
  regularization <- params$REGULARIZATION[1L]
  log <- list()
  for (epoch in seq_len(params$EPOCHS[1L])) {
    for (position in rev(seq.int(2L,length(order)))) {
      other <- draw() %% position+1L
      temporary <- order[position]
      order[position] <- order[other]
      order[other] <- temporary
    }
    for (position in order) {
      r <- data$training[[position]]
      u <- r$u
      i <- r$i
      prediction <- ((data$mean+user_bias[u])+item_bias[i])+dot_product(users[u,],items[i,])
      error <- r$rating-prediction
      user_bias[u] <- user_bias[u]+rate*(error-regularization*user_bias[u])
      item_bias[i] <- item_bias[i]+rate*(error-regularization*item_bias[i])
      for (a in seq_len(f)) {
        x <- users[u,a]
        y <- items[i,a]
        users[u,a] <- x+rate*(error*y-regularization*x)
        items[i,a] <- y+rate*(error*x-regularization*y)
      }
    }
    model <- list(mean=data$mean,users=users,items=items,user_bias=user_bias,item_bias=item_bias)
    log[[length(log)+1L]] <- list(
        method="SVD",
        epoch=epoch,
        error=training_rmse(data$training,function(u,i) factor_prediction(model,u,i))
    )
  }
  list(model=model,log=log)
}
cholesky_solve <- function(matrix,target) {
  n <- length(target)
  lower <- matrix(0,n,n)
  for (a in seq_len(n)) for (b in seq_len(a)) {
    t <- seq_len(b-1L)
    value <- matrix[a,b]-sequential_sum(lower[a,t]*lower[b,t])
    lower[a,b] <- if (a == b) sqrt(value) else value/lower[b,b]
  }
  z <- numeric(n)
  for (a in seq_len(n)) {
    t <- seq_len(a-1L)
    z[a] <- (target[a]-sequential_sum(lower[a,t]*z[t]))/lower[a,a]
  }
  x <- numeric(n)
  for (a in rev(seq_len(n))) {
    t <- seq_len(n)[seq_len(n) > a]
    x[a] <- (z[a]-sequential_sum(lower[t,a]*x[t]))/lower[a,a]
  }
  x
}
fit_vector <- function(observations,f,regularization) {
  matrix <- matrix(0,f,f)
  target <- numeric(f)
  for (observation in observations) {
    vector <- observation$vector
    residual <- observation$residual
    for (a in seq_len(f)) {
      target[a] <- target[a]+residual*vector[a]
      for (b in seq_len(f)) matrix[a,b] <- matrix[a,b]+vector[a]*vector[b]
    }
  }
  for (a in seq_len(f)) matrix[a,a] <- matrix[a,a]+regularization*length(observations)
  cholesky_solve(matrix,target)
}
train_als <- function(data,user_bias,item_bias) {
  params <- data$params
  f <- params$FACTORS[1L]
  draw <- random_generator(params$SEED[1L])
  users <- matrix(0,length(data$users),f)
  items <- matrix(0,length(data$items),f)
  for (i in seq_len(nrow(items))) for (a in seq_len(f)) items[i,a] <- factor_value(draw)
  residuals <- matrix(0,length(data$users),length(data$items))
  for (r in data$training) residuals[r$u,r$i] <- r$rating-((data$mean+user_bias[r$u])+item_bias[r$i])
  log <- list()
  for (iteration in seq_len(params$ALS_ITERATIONS[1L])) {
    for (u in seq_along(data$users)) users[u,] <- fit_vector(lapply(data$by_user[[u]],function(i)
      list(vector=items[i,],residual=residuals[u,i])),f,params$ALS_REG[1L])
    for (i in seq_along(data$items)) items[i,] <- fit_vector(lapply(data$by_item[[i]],function(u)
      list(vector=users[u,],residual=residuals[u,i])),f,params$ALS_REG[1L])
    model <- list(mean=data$mean,users=users,items=items,user_bias=user_bias,item_bias=item_bias)
    log[[length(log)+1L]] <- list(
        method="ALS",
        epoch=iteration,
        error=training_rmse(data$training,function(u,i) factor_prediction(model,u,i))
    )
  }
  list(model=model,log=log)
}
