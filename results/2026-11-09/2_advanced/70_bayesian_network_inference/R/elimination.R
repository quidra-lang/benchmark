interaction_graph <- function(factors) {
  variables <- sort(unique(unlist(lapply(factors,function(f) f$variables))))
  graph <- vector("list",if (length(variables)) max(variables) else 0L)
  for (v in variables) graph[[v]] <- integer()
  for (factor in factors) for (v in factor$variables) graph[[v]] <- union(
      graph[[v]],
      setdiff(factor$variables,v)
  )
  graph
}
make_plan <- function(factors,eliminate,method,given_order,sizes) {
  graph <- interaction_graph(factors)
  remaining <- sort(eliminate)
  steps <- list()
  ranks <- match(seq_along(sizes),given_order)
  while (length(remaining)) {
    fills <- vapply(remaining,function(v) {
      neighbors <- sort(graph[[v]])
      result <- 0L
      for (i in seq_along(neighbors)) if (i < length(neighbors)) for (j in seq.int(
          i+1L,
          length(neighbors)
      )) if (!(neighbors[j] %in% graph[[neighbors[i]]])) result <- result+1L
      result
    },integer(1))
    selected <- if (method == "MINFILL") order(
        fills,
        lengths(graph)[remaining],
        remaining
    )[1L] else which.min(ranks[remaining])
    v <- remaining[selected]
    neighbors <- sort(graph[[v]])
    scope <- sort(c(v,neighbors))
    steps[[length(steps)+1L]] <- list(
        variable=v,
        fill=fills[selected],
        scope=scope,
        size=entry_count(scope,sizes)
    )
    for (left in neighbors) graph[[left]] <- setdiff(union(graph[[left]],neighbors),c(left,v))
    graph[v] <- list(integer())
    remaining <- setdiff(remaining,v)
  }
  costs <- vapply(steps,function(s) s$size,numeric(1))
  list(steps=steps,maximum=if (length(costs)) max(costs) else 0,total=sum(costs))
}
execute_plan <- function(initial,plan,sizes,maximize=FALSE) {
  factors <- initial
  products <- list()
  for (step in plan$steps) {
    selected <- vapply(factors,function(f) step$variable %in% f$variables,logical(1))
    product <- multiply_factors(factors[selected],sizes)
    factors <- c(factors[!selected],list(eliminate_factor(product,step$variable,sizes,maximize)))
    if (maximize) products[[length(products)+1L]] <- list(variable=step$variable,product=product)
  }
  list(factor=multiply_factors(factors,sizes),products=products)
}
traceback <- function(products,sizes) {
  assignment <- integer(length(sizes))
  for (step in rev(products)) {
    candidates <- vapply(seq_len(sizes[step$variable]),function(state) {
      assignment[step$variable] <- state
      factor_value(step$product,assignment,sizes)
    },numeric(1))
    assignment[step$variable] <- which.max(candidates)
  }
  assignment
}
