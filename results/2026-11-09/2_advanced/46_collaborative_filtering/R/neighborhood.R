largest_neighbors <- function(candidates,n) {
  if (!length(candidates)) return(list())
  candidates[head(order(-vapply(candidates,`[`,numeric(1),2L),vapply(candidates,`[`,numeric(1),1L)),n)]
}
build_neighborhood <- function(data,shrinkage) {
  nu <- length(data$users)
  ni <- length(data$items)
  user <- matrix(NA_real_,nu,nu)
  item <- matrix(NA_real_,ni,ni)
  user_common <- matrix(0L,nu,nu)
  counts <- differences <- matrix(0,ni,ni)
  for (u in seq_len(nu-1L)) for (v in seq.int(u+1L,nu)) {
    common <- data$by_user[[u]][data$ratings[v,data$by_user[[u]]] > 0]
    n <- length(common)
    if (n < 2L) next
    x <- data$ratings[u,common]
    y <- data$ratings[v,common]
    sx <- sum(x)
    sy <- sum(y)
    sxx <- sum(x*x)
    syy <- sum(y*y)
    sxy <- sum(x*y)
    num <- n*sxy-sx*sy
    dx <- n*sxx-sx*sx
    dy <- n*syy-sy*sy
    if (dx == 0 || dy == 0) next
    a <- (num*n)*(num*n)
    b <- dx*dy*(n+shrinkage)*(n+shrinkage)
    user[u,v] <- user[v,u] <- sign(num)*sqrt(a/b)
    user_common[u,v] <- user_common[v,u] <- n
  }
  for (i in seq_len(ni-1L)) for (j in seq.int(i+1L,ni)) {
    common <- data$by_item[[i]][data$ratings[data$by_item[[i]],j] > 0]
    n <- length(common)
    if (!n) next
    counts[i,j] <- counts[j,i] <- n
    difference <- sum(data$ratings[common,i]-data$ratings[common,j])
    differences[i,j] <- difference
    differences[j,i] <- -difference
    if (n < 2L) next
    x <- data$ratings[common,i]-data$user_means[common]
    y <- data$ratings[common,j]-data$user_means[common]
    numerator <- sequential_sum(x*y)
    left <- sequential_sum(x*x)
    right <- sequential_sum(y*y)
    if (left == 0 || right == 0) next
    item[i,j] <- item[j,i] <- numerator/sqrt(left*right)*n/(n+shrinkage)
  }
  list(user=user,item=item,user_common=user_common,counts=counts,differences=differences,shrinkage=shrinkage)
}
deviation <- function(
    neighborhood,
    target,
    source
) neighborhood$differences[target,source]/(neighborhood$counts[target,source]+neighborhood$shrinkage)
