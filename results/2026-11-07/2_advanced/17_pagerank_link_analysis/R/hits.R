norm_values <- function(values, nodes) {
  squares <- 0
  for (node in nodes) squares <- squares + values[node] * values[node]
  sqrt(squares)
}

hits <- function(count, nodes, links, iterations) {
  sources <- targets <- rep(list(integer()), count)
  if (length(links)) {
    order <- order(vapply(links, function(link) link[1L], integer(1L)), vapply(links, function(link) link[2L], integer(1L)), method = "radix")
    for (link in links[order]) {
      sources[[link[2L]]] <- c(sources[[link[2L]]], link[1L])
      targets[[link[1L]]] <- c(targets[[link[1L]]], link[2L])
    }
  }
  authority <- hub <- numeric(count)
  authority[nodes] <- hub[nodes] <- 1
  for (step in seq_len(iterations)) {
    incoming <- outgoing <- numeric(count)
    for (node in nodes) for (source in sources[[node]]) incoming[node] <- incoming[node] + hub[source]
    for (node in nodes) for (target in targets[[node]]) outgoing[node] <- outgoing[node] + incoming[target]
    authority_norm <- norm_values(incoming, nodes)
    hub_norm <- norm_values(outgoing, nodes)
    authority[nodes] <- incoming[nodes] / authority_norm
    hub[nodes] <- outgoing[nodes] / hub_norm
  }
  list(authority = authority, hub = hub)
}
