new_branch_node <- function(lower, upper, depth, parent, branch, parent_value) {
  list(lower = lower, upper = upper, depth = depth, parent = parent, branch = branch, parent_value = parent_value)
}
branch_search <- function(model, limit, solve) {
  stack <- list(new_branch_node(model$lower, model$upper, 0L, NULL, "root", NULL))
  solves <- list()
  lines <- character()
  incumbent <- objective <- status <- NULL
  incumbents <- pruned <- infeasible <- 0L
  while (length(stack)) {
    if (length(solves) == limit) {
      status <- "NODE_LIMIT"
      break
    }
    node <- stack[[length(stack)]]
    stack <- head(stack, -1L)
    number <- length(solves) + 1L
    result <- solve(node$lower, node$upper, number)
    solves[[number]] <- result
    if (result$status == "INFEASIBLE") {
      outcome <- "infeasible"
      infeasible <- infeasible + 1L
    } else if (result$status == "UNBOUNDED") {
      outcome <- "unbounded"
      status <- "UNBOUNDED"
    } else if (!is.null(objective) && (if (model$direction == "maximize") result$objective <= objective else result$objective >= objective)) {
      outcome <- "pruned"
      pruned <- pruned + 1L
    } else {
      fractional <- which(vapply(seq_along(model$variables), function(j) model$integer[[j]] && q_den(result$solution[[j]]) != 1, logical(1L)))
      if (!length(fractional)) {
        incumbent <- result$solution
        objective <- result$objective
        outcome <- "incumbent"
        incumbents <- incumbents + 1L
      } else {
        j <- fractional[[1L]]
        value <- result$solution[[j]]
        name <- model$variables[[j]]
        down <- floor(value)
        up <- ceiling(value)
        lower <- node$lower
        upper <- node$upper
        lower[[j]] <- fraction(up)
        upper[[j]] <- fraction(down)
        stack[[length(stack) + 1L]] <- new_branch_node(lower, node$upper, node$depth + 1L, number, paste0(name, ">=", sprintf("%.0f", up)), result$objective)
        stack[[length(stack) + 1L]] <- new_branch_node(node$lower, upper, node$depth + 1L, number, paste0(name, "<=", sprintf("%.0f", down)), result$objective)
        outcome <- paste("branch", name, fraction_text(value))
      }
    }
    parent <- if (is.null(node$parent)) "-" else as.character(node$parent)
    lp <- if (result$status == "OPTIMAL") fraction_text(result$objective) else tolower(result$status)
    lines <- c(lines, paste("NODE", number, "depth", node$depth, "parent", parent, "branch", node$branch, "lp", lp, "pivots", result$pivots, "action", outcome))
    if (identical(status, "UNBOUNDED")) break
  }
  if (is.null(status)) status <- if (is.null(incumbent)) "INFEASIBLE" else "OPTIMAL"
  if (status == "NODE_LIMIT") {
    for (node in rev(stack)) lines <- c(lines, paste("OPEN parent", node$parent, "branch", node$branch, "bound", fraction_text(node$parent_value)))
    bounds <- lapply(stack, function(node) node$parent_value)
    if (!is.null(objective)) bounds[[length(bounds) + 1L]] <- objective
    bound <- if (model$direction == "maximize") qmax(bounds) else qmin(bounds)
  } else {
    bound <- objective
  }
  lines <- c(lines, paste("RESULT", status, "objective", shown(objective), "nodes", length(solves), "incumbents", incumbents, "pruned", pruned, "infeasible", infeasible, "open", length(stack), "bound", shown(bound)))
  list(status = status, objective = objective, solution = incumbent, solves = solves, root = solves[[1L]], lines = lines, nodes = length(solves))
}
