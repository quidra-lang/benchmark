script_args <- grep("^--file=", commandArgs(), value = TRUE)
source_dir <- if (length(script_args)) dirname(sub("^--file=", "", script_args[1L])) else "R"
for (unit in c("graph_io", "components", "pagerank", "hits", "report")) source(file.path(source_dir, paste0(unit, ".R")))

region_names <- c("CORE", "IN", "OUT", "TUBE", "IN_TENDRIL", "OUT_TENDRIL", "OTHER")
quantity_names <- c("in_degree", "pagerank", "cheirank", "authority", "hub", "trustrank", "harmonic")
total <- function(values) {
  result <- 0
  for (value in values) result <- result + value
  result
}
integers <- function(values) paste(integer_text(values), collapse = " ")
join_blocks <- function(blocks) {
  lines <- character()
  for (index in seq_along(blocks)) {
    if (index > 1L) lines <- c(lines, "")
    lines <- c(lines, blocks[[index]])
  }
  lines
}
rank_order <- function(values) order(-scaled(values), seq_along(values), method = "radix")
positions <- function(order) {
  rank <- integer(length(order))
  rank[order] <- seq_along(order)
  rank
}
top_list <- function(values, limit) {
  order <- rank_order(values)
  head(order[scaled(values[order]) > 0], limit)
}
ranked_counts <- function(counts, limit) {
  nodes <- which(counts > 0)
  head(nodes[order(-counts[nodes], nodes, method = "radix")], limit)
}
distribution_lines <- function(values) {
  keys <- sort(unique(values), method = "radix")
  vapply(keys, function(value) paste(integer_text(value), sum(values == value)), character(1L))
}
run_pagerank <- function(edges, teleport, damping, settings) power_iteration(edges, teleport, damping, settings$iterations, settings$tolerance)

classify_links <- function(records, page_ids) {
  accepted <- new.env(hash = TRUE, parent = emptyenv())
  links <- ignored <- list()
  for (record in records) {
    source <- match(record$source, page_ids)
    target <- match(record$target, page_ids)
    key <- paste(source, target, sep = ",")
    reason <- if (is.na(source) || is.na(target)) {
      "unknown"
    } else if (source == target) {
      "self"
    } else if (exists(key, accepted, inherits = FALSE)) {
      "duplicate"
    } else ""
    if (nzchar(reason)) ignored[[length(ignored) + 1L]] <- list(record = record, reason = reason)
    else {
      assign(key, TRUE, accepted)
      links[[length(links) + 1L]] <- c(source, target)
    }
  }
  list(links = links, ignored = ignored)
}

new_graph <- function(pages, links) {
  if (length(links)) {
    order <- order(vapply(links, function(link) link[1L], integer(1L)), vapply(links, function(link) link[2L], integer(1L)), method = "radix")
    links <- links[order]
  }
  successors <- predecessors <- rep(list(integer()), length(pages))
  link_set <- matrix(FALSE, length(pages), length(pages))
  for (link in links) {
    successors[[link[1L]]] <- c(successors[[link[1L]]], link[2L])
    predecessors[[link[2L]]] <- c(predecessors[[link[2L]]], link[1L])
    link_set[link[1L], link[2L]] <- TRUE
  }
  list(pages = pages, links = links, link_set = link_set, successors = successors, predecessors = predecessors)
}
intra_host <- function(graph, link) graph$pages[[link[1L]]]$host == graph$pages[[link[2L]]]$host
inter_host_links <- function(graph, links) Filter(function(link) !intra_host(graph, link), links)
dangling <- function(graph) which(lengths(graph$successors) == 0L)
ids <- function(graph, nodes) vapply(nodes, function(node) graph$pages[[node]]$id, integer(1L))
forward_edges <- function(graph) lapply(graph$predecessors, function(sources) lapply(sources, function(source) c(source, 1L)))
reverse_edges <- function(graph) lapply(graph$successors, function(targets) lapply(targets, function(target) c(target, 1L)))
describe <- function(graph, position, node, values) {
  page <- graph$pages[[node]]
  paste(c(position, page$id, values, page$host, page$title), collapse = " ")
}

kcore_numbers <- function(neighbors) {
  remaining <- lengths(neighbors)
  removed <- logical(length(neighbors))
  core <- integer(length(neighbors))
  level <- 0L
  left <- length(neighbors)
  while (left > 0L) {
    candidates <- which(!removed & remaining <= level)
    if (!length(candidates)) { level <- level + 1L; next }
    candidate <- candidates[1L]
    removed[candidate] <- TRUE
    core[candidate] <- level
    left <- left - 1L
    for (neighbor in neighbors[[candidate]]) if (!removed[neighbor]) remaining[neighbor] <- remaining[neighbor] - 1L
  }
  core
}

new_undirected <- function(graph) {
  adjacent <- graph$link_set | t(graph$link_set)
  neighbors <- lapply(seq_along(graph$pages), function(node) which(adjacent[node, ]))
  closed <- possible <- eligible <- 0
  local_sum <- 0
  for (group in neighbors) {
    degree <- length(group)
    if (degree < 2L) next
    count <- 0L
    for (first in seq_len(degree - 1L)) {
      for (second in seq.int(first + 1L, degree)) if (adjacent[group[first], group[second]]) count <- count + 1L
    }
    pairs <- degree * (degree - 1L) / 2
    closed <- closed + count
    possible <- possible + pairs
    eligible <- eligible + 1
    local_sum <- local_sum + count / pairs
  }
  core <- kcore_numbers(neighbors)
  labels <- weak_components(neighbors)
  sizes <- tabulate(labels)
  list(neighbors = neighbors, edge_count = sum(lengths(neighbors)) / 2, closed = closed, possible = possible,
    eligible = eligible, average_clustering = local_sum / eligible, kcore = core, degeneracy = max(core),
    weak_count = max(labels), weak_largest = max(sizes))
}

longest_path <- function(count, edges) {
  successors <- rep(list(integer()), count)
  pending <- integer(count)
  for (edge in edges) {
    successors[[edge[1L]]] <- c(successors[[edge[1L]]], edge[2L])
    pending[edge[2L]] <- pending[edge[2L]] + 1L
  }
  length <- integer(count)
  ready <- which(pending == 0L)
  while (length(ready)) {
    node <- tail(ready, 1L)
    ready <- head(ready, -1L)
    for (target in successors[[node]]) {
      length[target] <- max(length[target], length[node] + 1L)
      pending[target] <- pending[target] - 1L
      if (pending[target] == 0L) ready <- c(ready, target)
    }
  }
  max(length)
}

new_component_table <- function(graph) {
  groups <- lapply(strong_components(graph$successors), sort, method = "radix")
  groups <- groups[order(vapply(groups, function(group) group[1L], integer(1L)), method = "radix")]
  label <- integer(length(graph$pages))
  for (number in seq_along(groups)) label[groups[[number]]] <- number
  incoming <- outgoing <- integer(length(groups))
  edge_set <- matrix(FALSE, length(groups), length(groups))
  edges <- list()
  for (link in graph$links) {
    first <- label[link[1L]]
    second <- label[link[2L]]
    if (first == second) next
    outgoing[first] <- outgoing[first] + 1L
    incoming[second] <- incoming[second] + 1L
    if (!edge_set[first, second]) {
      edge_set[first, second] <- TRUE
      edges[[length(edges) + 1L]] <- c(first, second)
    }
  }
  sizes <- lengths(groups)
  list(groups = groups, label = label, incoming = incoming, outgoing = outgoing,
    edge_count = length(edges), depth = longest_path(length(groups), edges), core = which.max(sizes), singletons = sum(sizes == 1L))
}

bowtie_regions <- function(graph, core_pages) {
  forward <- reachable(graph$successors, core_pages)
  backward <- reachable(graph$predecessors, core_pages)
  in_core <- seq_along(graph$pages) %in% core_pages
  regions <- rep(7L, length(graph$pages))
  for (node in seq_along(regions)) {
    if (in_core[node]) regions[node] <- 1L
    else if (backward[node]) regions[node] <- 2L
    else if (forward[node]) regions[node] <- 3L
  }
  from_in <- reachable(graph$successors, which(regions == 2L))
  to_out <- reachable(graph$predecessors, which(regions == 3L))
  for (node in seq_along(regions)) {
    if (in_core[node] || backward[node] || forward[node]) next
    if (from_in[node] && to_out[node]) regions[node] <- 4L
    else if (from_in[node]) regions[node] <- 5L
    else if (to_out[node]) regions[node] <- 6L
  }
  regions
}

new_distance_stats <- function(graph) {
  pairs <- total_distance <- diameter <- 0L
  diameter_pair <- c(1L, 1L)
  histogram <- integer(length(graph$pages))
  harmonic <- numeric(length(graph$pages))
  for (source in seq_along(graph$pages)) {
    distance <- bfs_distances(graph$successors, source)
    for (target in seq_along(distance)) {
      steps <- distance[target]
      if (target == source || steps < 0L) next
      pairs <- pairs + 1L
      total_distance <- total_distance + steps
      histogram[steps] <- histogram[steps] + 1L
      harmonic[target] <- harmonic[target] + 1 / steps
      if (steps > diameter) { diameter <- steps; diameter_pair <- c(source, target) }
    }
  }
  reached <- 0L
  effective <- diameter
  for (steps in seq_len(diameter)) {
    reached <- reached + histogram[steps]
    if (10 * reached >= 9 * pairs) { effective <- steps; break }
  }
  list(pairs = pairs, total = total_distance, diameter = diameter, diameter_pair = diameter_pair,
       histogram = histogram, harmonic = harmonic, effective = effective)
}

new_page_scores <- function(graph, settings, trusted, harmonic) {
  everyone <- seq_along(graph$pages)
  pagerank <- run_pagerank(forward_edges(graph), everyone, settings$damping, settings)
  cheirank <- run_pagerank(reverse_edges(graph), everyone, settings$damping, settings)
  trustrank <- run_pagerank(forward_edges(graph), trusted, settings$damping, settings)
  order <- rank_order(pagerank$values)
  scores <- hits(length(graph$pages), everyone, inter_host_links(graph, graph$links), settings$hits_iterations)
  list(damping = settings$damping, pagerank_run = pagerank, cheirank_run = cheirank, trustrank_run = trustrank,
    pagerank = pagerank$values, cheirank = cheirank$values, trustrank = trustrank$values,
    order = order, rank = positions(order), cheirank_rank = positions(rank_order(cheirank$values)),
    trust_ratio = trustrank$values / pagerank$values, trust_distance = bfs_distances(graph$successors, trusted),
    authority = scores$authority, hub = scores$hub, harmonic = harmonic)
}
contribution <- function(graph, scores, source) scores$damping * scores$pagerank[source] / length(graph$successors[[source]])
representative <- function(scores, nodes) nodes[which.min(scores$rank[nodes])]

kendall <- function(first, second) {
  concordant <- discordant <- 0L
  for (one in seq_len(length(first) - 1L)) {
    for (two in seq.int(one + 1L, length(first))) {
      dx <- first[one] - first[two]
      dy <- second[one] - second[two]
      if (dx == 0 || dy == 0) next
      if ((dx > 0) == (dy > 0)) concordant <- concordant + 1L
      else discordant <- discordant + 1L
    }
  }
  fraction(concordant - discordant, length(first) * (length(first) - 1L) / 2)
}

new_sweep <- function(damping, graph, scores, settings) {
  run <- run_pagerank(forward_edges(graph), seq_along(graph$pages), damping, settings)
  order <- rank_order(run$values)
  rank <- positions(order)
  differences <- abs(rank - scores$rank)
  shift <- which.max(differences)
  list(damping = damping, run = run, overlap = sum(rank <= settings$top_k & scores$rank <= settings$top_k),
    footrule = sum(differences), correlation = kendall(scaled(scores$pagerank), scaled(run$values)),
    shift = shift, shift_rank = rank[shift], top = head(order, settings$top_k))
}

new_spam <- function(graph, scores, settings) {
  suspects <- head(scores$order, settings$spam_top)
  suspects <- suspects[scaled(scores$trust_ratio[suspects], 4L) / 10000 < settings$spam_threshold]
  hosts <- sort(unique(vapply(suspects, function(node) graph$pages[[node]]$host, character(1L))), method = "radix")
  run <- rank <- NULL
  removed <- 0L
  if (length(suspects)) {
    kept <- Filter(function(link) !(intra_host(graph, link) && graph$pages[[link[1L]]]$host %in% hosts), graph$links)
    removed <- length(graph$links) - length(kept)
    demoted <- new_graph(graph$pages, kept)
    run <- run_pagerank(forward_edges(demoted), seq_along(graph$pages), settings$damping, settings)
    rank <- positions(rank_order(run$values))
  }
  list(suspects = suspects, hosts = hosts, removed = removed, run = run, rank = rank)
}

title_matches <- function(words, include, exclude) all(include %in% words) && !any(exclude %in% words)
base_membership <- function(graph, root, limit) {
  in_base <- logical(length(graph$pages))
  for (node in root) {
    in_base[node] <- TRUE
    in_base[head(graph$successors[[node]], limit)] <- TRUE
    in_base[head(graph$predecessors[[node]], limit)] <- TRUE
  }
  in_base
}

salsa_scores <- function(count, links) {
  degree <- integer(count)
  targets <- neighbors <- rep(list(integer()), count)
  for (link in links) {
    degree[link[2L]] <- degree[link[2L]] + 1L
    targets[[link[1L]]] <- c(targets[[link[1L]]], link[2L])
  }
  for (group in targets) {
    if (length(group) < 2L) next
    for (index in seq_len(length(group) - 1L)) {
      first <- group[index]
      second <- group[index + 1L]
      neighbors[[first]] <- c(neighbors[[first]], second)
      neighbors[[second]] <- c(neighbors[[second]], first)
    }
  }
  labels <- weak_components(neighbors)
  side <- which(degree > 0L)
  size <- mass <- integer(count)
  for (node in side) {
    size[labels[node]] <- size[labels[node]] + 1L
    mass[labels[node]] <- mass[labels[node]] + degree[node]
  }
  scores <- numeric(count)
  for (node in side) scores[node] <- (size[labels[node]] * degree[node]) / (length(side) * mass[labels[node]])
  scores
}

cocitation_counts <- function(graph, page) {
  counts <- integer(length(graph$pages))
  for (citing in graph$predecessors[[page]]) {
    for (cited in graph$successors[[citing]]) if (cited != page) counts[cited] <- counts[cited] + 1L
  }
  counts
}
coupling_counts <- function(graph, page) {
  counts <- integer(length(graph$pages))
  for (cited in graph$successors[[page]]) {
    for (citing in graph$predecessors[[cited]]) if (citing != page) counts[citing] <- counts[citing] + 1L
  }
  counts
}

new_subgraph <- function(graph, base, links, settings) {
  result <- hits(length(graph$pages), base, links, settings$hits_iterations)
  authority <- result$authority
  hub <- result$hub
  salsa_authority <- salsa_scores(length(graph$pages), links)
  salsa_hub <- salsa_scores(length(graph$pages), lapply(links, rev))
  authority_top <- top_list(authority, settings$top_k)
  hub_top <- top_list(hub, settings$top_k)
  salsa_authority_top <- top_list(salsa_authority, settings$top_k)
  salsa_hub_top <- top_list(salsa_hub, settings$top_k)
  cited <- authority_top[1L]
  citing <- hub_top[1L]
  cocitation <- cocitation_counts(graph, cited)
  coupling <- coupling_counts(graph, citing)
  list(authority = authority, hub = hub, salsa_authority = salsa_authority, salsa_hub = salsa_hub,
    authority_top = authority_top, hub_top = hub_top, salsa_authority_top = salsa_authority_top, salsa_hub_top = salsa_hub_top,
    authority_overlap = length(intersect(authority_top, salsa_authority_top)), hub_overlap = length(intersect(hub_top, salsa_hub_top)),
    authority_hosts = length(unique(vapply(authority_top, function(node) graph$pages[[node]]$host, character(1L)))),
    cited = cited, citing = citing, cocitation = cocitation, coupling = coupling,
    related = ranked_counts(cocitation, settings$top_k), similar = ranked_counts(coupling, settings$top_k))
}

new_query_result <- function(query, graph, scores, settings, page_ids) {
  include <- query$words[!startsWith(query$words, "-")]
  exclude <- substring(query$words[startsWith(query$words, "-")], 2L)
  matches <- Filter(function(node) title_matches(graph$pages[[node]]$words, include, exclude), scores$order)
  root <- head(matches, settings$root_limit)
  in_base <- base_membership(graph, root, settings$neighbor_limit)
  base <- which(in_base)
  inside <- Filter(function(link) in_base[link[1L]] && in_base[link[2L]], graph$links)
  subgraph <- inter_host_links(graph, inside)
  seeds <- sort(match(query$seeds, page_ids), method = "radix")
  personalized <- run_pagerank(forward_edges(graph), seeds, settings$damping, settings)
  personalized_top <- top_list(personalized$values, settings$top_k)
  list(query = query, matches = matches, root_size = length(root), base_size = length(base), subgraph = subgraph,
    dropped = length(inside) - length(subgraph), personalized = personalized, reach = sum(reachable(graph$successors, seeds)),
    seed_mass = total(personalized$values[seeds]), personalized_top = personalized_top,
    global_overlap = sum(scores$rank[personalized_top] <= settings$top_k),
    scores = if (length(subgraph)) new_subgraph(graph, base, subgraph, settings) else NULL)
}

new_host_graph <- function(graph, settings) {
  names <- sort(unique(vapply(graph$pages, function(page) page$host, character(1L))), method = "radix")
  count <- length(names)
  of_page <- match(vapply(graph$pages, function(page) page$host, character(1L)), names)
  members <- lapply(seq_len(count), function(number) which(of_page == number))
  weight <- matrix(0L, count, count)
  internal <- outgoing <- incoming <- integer(count)
  for (link in graph$links) {
    first <- of_page[link[1L]]
    second <- of_page[link[2L]]
    if (first == second) internal[first] <- internal[first] + 1L
    else {
      weight[first, second] <- weight[first, second] + 1L
      outgoing[first] <- outgoing[first] + 1L
      incoming[second] <- incoming[second] + 1L
    }
  }
  edges <- list()
  reciprocal <- 0L
  adjacency <- in_edges <- rep(list(list()), count)
  for (first in seq_len(count)) {
    adjacency[[first]] <- integer()
    for (second in seq_len(count)) {
      if (weight[first, second] <= 0L) next
      edges[[length(edges) + 1L]] <- c(first, second)
      adjacency[[first]] <- c(adjacency[[first]], second)
      in_edges[[second]] <- c(in_edges[[second]], list(c(first, weight[first, second])))
      if (weight[second, first] > 0L) reciprocal <- reciprocal + 1L
    }
  }
  groups <- strong_components(adjacency)
  run <- run_pagerank(in_edges, seq_len(count), settings$damping, settings)
  heavy <- edges[order(-vapply(edges, function(edge) weight[edge[1L], edge[2L]], integer(1L)),
    vapply(edges, function(edge) edge[1L], integer(1L)), vapply(edges, function(edge) edge[2L], integer(1L)), method = "radix")]
  list(names = names, of_page = of_page, members = members, weight = weight, internal = internal,
    outgoing = outgoing, incoming = incoming, edges = edges, reciprocal = reciprocal,
    component_count = length(groups), largest = max(lengths(groups)), run = run, rank = positions(rank_order(run$values)),
    heavy = head(heavy, settings$top_k))
}

new_analysis <- function(input) {
  input$pages <- input$pages[order(vapply(input$pages, function(page) page$id, integer(1L)), method = "radix")]
  page_ids <- vapply(input$pages, function(page) page$id, integer(1L))
  classified <- classify_links(input$records, page_ids)
  graph <- new_graph(input$pages, classified$links)
  undirected <- new_undirected(graph)
  components <- new_component_table(graph)
  regions <- bowtie_regions(graph, components$groups[[components$core]])
  distances <- new_distance_stats(graph)
  trusted <- sort(match(input$settings$trusted, page_ids), method = "radix")
  scores <- new_page_scores(graph, input$settings, trusted, distances$harmonic)
  sweeps <- lapply(input$settings$sweep, function(damping) new_sweep(damping, graph, scores, input$settings))
  spam <- new_spam(graph, scores, input$settings)
  queries <- lapply(input$queries, function(query) new_query_result(query, graph, scores, input$settings, page_ids))
  list(input = input, graph = graph, ignored = classified$ignored, undirected = undirected,
    components = components, regions = regions, distances = distances, scores = scores, sweeps = sweeps,
    spam = spam, queries = queries, hosts = new_host_graph(graph, input$settings))
}

link_lines <- function(a) {
  graph <- a$graph
  reasons <- vapply(a$ignored, function(ignored) ignored$reason, character(1L))
  intra <- sum(vapply(graph$links, function(link) intra_host(graph, link), logical(1L)))
  reciprocal <- sum(vapply(graph$links, function(link) graph$link_set[link[2L], link[1L]], logical(1L)))
  in_degrees <- lengths(graph$predecessors)
  out_degrees <- lengths(graph$successors)
  no_in <- which(in_degrees == 0L)
  max_in <- max(in_degrees)
  max_out <- max(out_degrees)
  nodes_line <- function(heading, nodes) {
    if (length(nodes)) paste(heading, integers(ids(graph, nodes))) else heading
  }
  lines <- c(paste("pages", length(graph$pages)), paste("hosts", length(a$hosts$names)),
    paste("link_rows", length(a$input$records)), paste("links", length(graph$links)),
    paste("ignored_unknown", sum(reasons == "unknown")), paste("ignored_self", sum(reasons == "self")),
    paste("ignored_duplicate", sum(reasons == "duplicate")))
  for (ignored in a$ignored) {
    record <- ignored$record
    lines <- c(lines, paste("ignored line", record$line, paste0(record$source, ",", record$target), ignored$reason))
  }
  dangling_nodes <- dangling(graph)
  c(lines, paste("intra_host_links", intra), paste("inter_host_links", length(graph$links) - intra),
    paste("mean_degree", fixed(length(graph$links) / length(graph$pages), 4L)),
    paste("reciprocity", fraction(reciprocal, length(graph$links))),
    nodes_line(paste("dangling", length(dangling_nodes)), dangling_nodes), nodes_line(paste("no_in_links", length(no_in)), no_in),
    nodes_line(paste("max_in_degree", max_in, "pages"), which(in_degrees == max_in)),
    nodes_line(paste("max_out_degree", max_out, "pages"), which(out_degrees == max_out)),
    "", "in_degree_distribution", distribution_lines(in_degrees), "", "out_degree_distribution", distribution_lines(out_degrees))
}

undirected_lines <- function(a) {
  u <- a$undirected
  c("", paste("undirected_links", integer_text(u$edge_count)), paste("transitivity", fraction(u$closed, u$possible)),
    paste("average_clustering", fixed(u$average_clustering, 4L), "pages", integer_text(u$eligible)),
    paste("degeneracy", u$degeneracy, "pages", sum(u$kcore == u$degeneracy)), "core_distribution", distribution_lines(u$kcore))
}
component_lines <- function(a) {
  table <- a$components
  lines <- c("", paste("strong_components", length(table$groups), "largest", length(table$groups[[table$core]]),
    "singletons", table$singletons, "condensation_links", table$edge_count),
    paste("weak_components", a$undirected$weak_count, "largest", a$undirected$weak_largest), paste("condensation_depth", table$depth))
  for (number in seq_along(table$groups)) {
    group <- table$groups[[number]]
    if (length(group) < 2L) next
    text <- paste("scc", number, "size", length(group), "min", a$graph$pages[[group[1L]]]$id,
      "incoming", table$incoming[number], "outgoing", table$outgoing[number], "pagerank", fixed(total(a$scores$pagerank[group])))
    if (table$outgoing[number] == 0L) text <- paste(text, "sink")
    lines <- c(lines, text)
  }
  lines
}
bowtie_lines <- function(a) {
  lines <- c("", paste("bowtie core_scc", a$components$core))
  for (region in seq_along(region_names)) {
    members <- which(a$regions == region)
    parts <- c(region_names[region], length(members), "pagerank", fixed(total(a$scores$pagerank[members])))
    if (length(members)) parts <- c(parts, "top", a$graph$pages[[representative(a$scores, members)]]$id)
    if (length(members) >= 1L && length(members) <= 10L) parts <- c(parts, "pages", ids(a$graph, members))
    lines <- c(lines, paste(parts, collapse = " "))
  }
  counts <- matrix(0L, length(region_names), length(region_names))
  for (link in a$graph$links) counts[a$regions[link[1L]], a$regions[link[2L]]] <- counts[a$regions[link[1L]], a$regions[link[2L]]] + 1L
  lines <- c(lines, "region_links")
  for (first in seq_along(region_names)) {
    for (second in seq_along(region_names)) {
      if (counts[first, second] > 0L) lines <- c(lines, paste(region_names[first], region_names[second], counts[first, second]))
    }
  }
  lines
}
distance_lines <- function(a) {
  d <- a$distances
  pair <- ids(a$graph, d$diameter_pair)
  c("", "distances", paste("reachable_pairs", d$pairs), paste("average", fraction(d$total, d$pairs)),
    paste("diameter", d$diameter, "from", pair[1L], "to", pair[2L]), paste("effective_diameter", d$effective),
    vapply(seq_len(d$diameter), function(steps) paste(steps, d$histogram[steps]), character(1L)))
}
graph_stats_lines <- function(a) c(link_lines(a), undirected_lines(a), component_lines(a), bowtie_lines(a), distance_lines(a))

pagerank_csv_lines <- function(a) {
  graph <- a$graph
  scores <- a$scores
  lines <- "id,in_degree,out_degree,scc,region,kcore,harmonic,pagerank,pagerank_rank,cheirank,cheirank_rank,authority,hub,trustrank,trust_ratio,trust_distance"
  for (node in seq_along(graph$pages)) {
    fields <- c(graph$pages[[node]]$id, length(graph$predecessors[[node]]), length(graph$successors[[node]]),
      a$components$label[node], region_names[a$regions[node]], a$undirected$kcore[node], fixed(scores$harmonic[node]),
      fixed(scores$pagerank[node]), scores$rank[node], fixed(scores$cheirank[node]), scores$cheirank_rank[node],
      fixed(scores$authority[node]), fixed(scores$hub[node]), fixed(scores$trustrank[node]), fixed(scores$trust_ratio[node], 4L), scores$trust_distance[node])
    lines <- c(lines, paste(fields, collapse = ","))
  }
  lines
}
rank_lines <- function(graph, nodes, values) vapply(seq_along(nodes), function(position) describe(graph, position, nodes[position], fixed(values[nodes[position]])), character(1L))
score_block <- function(name, a, values) c(paste(name, "top", integer_text(a$input$settings$top_k)), rank_lines(a$graph, top_list(values, a$input$settings$top_k), values))
pagerank_block <- function(a) {
  graph <- a$graph
  scores <- a$scores
  top <- top_list(scores$pagerank, a$input$settings$top_k)
  lines <- c(score_block("pagerank", a, scores$pagerank), paste("dangling_mass", fixed(total(scores$pagerank[dangling(graph)]))))
  for (node in top) {
    contributors <- graph$predecessors[[node]]
    values <- vapply(contributors, function(source) scaled(contribution(graph, scores, source)), numeric(1L))
    contributors <- head(contributors[order(-values, contributors, method = "radix")], 3L)
    parts <- c("contributors", graph$pages[[node]]$id)
    for (source in contributors) parts <- c(parts, graph$pages[[source]]$id, fixed(contribution(graph, scores, source)))
    lines <- c(lines, paste(parts, collapse = " "))
  }
  lines
}
correlation_block <- function(a) {
  scores <- a$scores
  series <- list(lengths(a$graph$predecessors), scaled(scores$pagerank), scaled(scores$cheirank), scaled(scores$authority),
    scaled(scores$hub), scaled(scores$trustrank), scaled(scores$harmonic))
  lines <- "correlation"
  for (first in seq_len(length(quantity_names) - 1L)) {
    for (second in seq.int(first + 1L, length(quantity_names))) lines <- c(lines, paste(quantity_names[first], quantity_names[second], kendall(series[[first]], series[[second]])))
  }
  lines
}
sweep_block <- function(a) {
  lines <- "damping_sweep"
  for (sweep in a$sweeps) {
    lines <- c(lines, paste("damping", fixed(sweep$damping, 4L), "overlap", sweep$overlap, "footrule", sweep$footrule,
      "kendall", sweep$correlation, "largest_shift", a$graph$pages[[sweep$shift]]$id, a$scores$rank[sweep$shift], sweep$shift_rank),
      paste("top", integers(ids(a$graph, sweep$top))))
  }
  lines
}
spam_block <- function(a) {
  scores <- a$scores
  settings <- a$input$settings
  lines <- paste("spam top", integer_text(settings$spam_top), "threshold", fixed(settings$spam_threshold, 4L))
  for (node in a$spam$suspects) {
    lines <- c(lines, paste("suspect", a$graph$pages[[node]]$id, "rank", scores$rank[node], "pagerank", fixed(scores$pagerank[node]),
      "trustrank", fixed(scores$trustrank[node]), "trust_ratio", fixed(scores$trust_ratio[node], 4L),
      "trust_distance", scores$trust_distance[node], "kcore", a$undirected$kcore[node], a$graph$pages[[node]]$host))
  }
  lines <- c(lines, paste("count", length(a$spam$suspects)), "trust_by_distance")
  distances <- sort(unique(scores$trust_distance[scores$trust_distance >= 0L]), method = "radix")
  if (-1L %in% scores$trust_distance) distances <- c(distances, -1L)
  for (distance in distances) {
    members <- which(scores$trust_distance == distance)
    name <- if (distance < 0L) "unreachable" else as.character(distance)
    lines <- c(lines, paste(name, "pages", length(members), "trustrank", fixed(total(scores$trustrank[members])), "pagerank", fixed(total(scores$pagerank[members]))))
  }
  lines
}
demotion_block <- function(a) {
  spam <- a$spam
  if (is.null(spam$run)) return("demotion none")
  values <- spam$run$values
  top <- top_list(values, a$input$settings$top_k)
  lines <- paste("demotion hosts", paste(spam$hosts, collapse = " "), "removed_links", spam$removed)
  for (position in seq_along(top)) {
    node <- top[position]
    lines <- c(lines, describe(a$graph, position, node, c(fixed(values[node]), "was", a$scores$rank[node])))
  }
  c(lines, vapply(spam$suspects, function(node) paste("suspect", a$graph$pages[[node]]$id, "before", a$scores$rank[node], "after", spam$rank[node]), character(1L)))
}
host_graph_block <- function(a) {
  hosts <- a$hosts
  c(paste("host_graph hosts", length(hosts$names), "links", length(hosts$edges), "reciprocal", hosts$reciprocal,
    "strong_components", hosts$component_count, "largest", hosts$largest), paste("host_links top", integer_text(a$input$settings$top_k)),
    vapply(hosts$heavy, function(edge) paste(hosts$names[edge[1L]], hosts$names[edge[2L]], hosts$weight[edge[1L], edge[2L]]), character(1L)))
}
rankings_lines <- function(a) join_blocks(list(pagerank_block(a), score_block("cheirank", a, a$scores$cheirank),
  score_block("authority", a, a$scores$authority), score_block("hub", a, a$scores$hub), score_block("trustrank", a, a$scores$trustrank),
  score_block("harmonic", a, a$scores$harmonic), correlation_block(a), sweep_block(a), spam_block(a), demotion_block(a), host_graph_block(a)))

convergence_block <- function(heading, run) {
  steps <- seq.int(10L, length(run$changes), by = 10L)
  lines <- c("", heading, vapply(steps, function(step) paste("iteration", step, "l1", fixed(run$changes[step], 10L)), character(1L)))
  c(lines, paste("converged_at", if (is.na(run$converged_at)) "none" else as.character(run$converged_at)))
}
convergence_lines <- function(a) {
  settings <- a$input$settings
  scores <- a$scores
  damping <- fixed(settings$damping, 4L)
  lines <- c(paste("iterations", integer_text(settings$iterations), "tolerance", fixed(settings$tolerance, 10L)),
    convergence_block(paste("pagerank damping", damping), scores$pagerank_run),
    convergence_block(paste("cheirank damping", damping), scores$cheirank_run),
    convergence_block(paste("trustrank damping", damping, "seeds", length(settings$trusted)), scores$trustrank_run))
  for (sweep in a$sweeps) lines <- c(lines, convergence_block(paste("sweep damping", fixed(sweep$damping, 4L)), sweep$run))
  if (!is.null(a$spam$run)) lines <- c(lines, convergence_block(paste("demoted damping", damping), a$spam$run))
  for (result in a$queries) lines <- c(lines, convergence_block(paste("personalized query", result$query$number, "damping", damping), result$personalized))
  c(lines, convergence_block(paste("host_pagerank damping", damping, "hosts", length(a$hosts$names)), a$hosts$run))
}

query_block <- function(a, result) {
  query <- result$query
  limit <- a$input$settings$top_k
  graph <- a$graph
  lines <- c(paste("query", query$number, "words", paste(query$words, collapse = " "), "seeds", integers(query$seeds)),
    paste("matched", length(result$matches), "root", result$root_size, "base", result$base_size, "links", length(result$subgraph), "dropped_intra_host", result$dropped),
    "results", rank_lines(graph, head(result$matches, limit), a$scores$pagerank),
    paste("personalized reach", result$reach, "seed_mass", fixed(result$seed_mass)), rank_lines(graph, result$personalized_top, result$personalized$values),
    paste("overlap_with_global", result$global_overlap))
  sub <- result$scores
  if (is.null(sub)) return(c(lines, "hits none"))
  lines <- c(lines, "hits authorities", rank_lines(graph, sub$authority_top, sub$authority), "hits hubs", rank_lines(graph, sub$hub_top, sub$hub),
    "salsa authorities", rank_lines(graph, sub$salsa_authority_top, sub$salsa_authority), "salsa hubs", rank_lines(graph, sub$salsa_hub_top, sub$salsa_hub),
    paste("hits_salsa_overlap authorities", sub$authority_overlap, "hubs", sub$hub_overlap, "authority_hosts", sub$authority_hosts),
    paste("related_to", graph$pages[[sub$cited]]$id, "citing", length(graph$predecessors[[sub$cited]])))
  for (position in seq_along(sub$related)) {
    node <- sub$related[position]
    lines <- c(lines, describe(graph, position, node, sub$cocitation[node]))
  }
  lines <- c(lines, paste("coupled_to", graph$pages[[sub$citing]]$id, "cited", length(graph$successors[[sub$citing]])))
  for (position in seq_along(sub$similar)) {
    node <- sub$similar[position]
    lines <- c(lines, describe(graph, position, node, sub$coupling[node]))
  }
  lines
}
queries_lines <- function(a) join_blocks(lapply(a$queries, function(result) query_block(a, result)))
hosts_csv_lines <- function(a) {
  hosts <- a$hosts
  scores <- a$scores
  graph <- a$graph
  lines <- "host,pages,core_pages,internal_links,internal_density,outgoing_links,incoming_links,dangling_pages,page_score_sum,top_page,score,rank"
  for (number in seq_along(hosts$names)) {
    members <- hosts$members[[number]]
    size <- length(members)
    density <- if (size >= 2L) hosts$internal[number] / (size * (size - 1L)) else 0
    fields <- c(hosts$names[number], size, sum(a$regions[members] == 1L), hosts$internal[number], fixed(density, 4L),
      hosts$outgoing[number], hosts$incoming[number], sum(lengths(graph$successors[members]) == 0L), fixed(total(scores$pagerank[members])),
      graph$pages[[representative(scores, members)]]$id, fixed(hosts$run$values[number]), hosts$rank[number])
    lines <- c(lines, paste(fields, collapse = ","))
  }
  lines
}

a <- new_analysis(read_input())
files <- list("graph_stats.txt" = graph_stats_lines(a), "pagerank.csv" = pagerank_csv_lines(a), "rankings.txt" = rankings_lines(a),
  "convergence.txt" = convergence_lines(a), "queries.txt" = queries_lines(a), "hosts.csv" = hosts_csv_lines(a))
dir.create("output", showWarnings = FALSE, recursive = TRUE)
for (name in names(files)) write_lines(name, files[[name]])
