power_iteration <- function(in_edges, teleport, damping, iterations, tolerance) {
  count <- length(in_edges)
  out_weight <- numeric(count)
  for (edges in in_edges) for (edge in edges) out_weight[edge[1L]] <- out_weight[edge[1L]] + edge[2L]
  in_teleport <- seq_len(count) %in% teleport
  values <- ifelse(in_teleport, 1 / length(teleport), 0)
  changes <- numeric(iterations)
  converged_at <- NA_integer_
  for (step in seq_len(iterations)) {
    mass <- 0
    for (node in seq_len(count)) if (out_weight[node] == 0) mass <- mass + values[node]
    base <- ((1 - damping) + damping * mass) / length(teleport)
    updated <- numeric(count)
    change <- 0
    for (node in seq_len(count)) {
      inflow <- 0
      for (edge in in_edges[[node]]) inflow <- inflow + values[edge[1L]] * edge[2L] / out_weight[edge[1L]]
      updated[node] <- damping * inflow
      if (in_teleport[node]) updated[node] <- updated[node] + base
      change <- change + abs(updated[node] - values[node])
    }
    changes[step] <- change
    if (is.na(converged_at) && change < tolerance) converged_at <- step
    values <- updated
  }
  list(values = values, changes = changes, converged_at = converged_at)
}
