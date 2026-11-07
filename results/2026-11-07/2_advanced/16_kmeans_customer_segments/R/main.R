script_args <- grep("^--file=", commandArgs(), value = TRUE)
source_dir <- if (length(script_args)) dirname(sub("^--file=", "", script_args[1L])) else "R"
for (unit in c("transactions", "features", "kmeans", "validation", "profiles", "report")) {
  source(file.path(source_dir, paste0(unit, ".R")))
}

minstd <- function(seed) {
  state <- as.numeric(seed)
  function() {
    state <<- (48271 * state) %% 2147483647
    state
  }
}

nearest_gaps <- function(points, chosen) {
  vapply(points, function(point) min(vapply(chosen, function(index) squared_distance(point, points[[index]]), numeric(1L))), numeric(1L))
}

maximin <- function(points, k, number) {
  center <- mean_point(points)
  spread <- vapply(points, function(point) squared_distance(point, center), numeric(1L))
  ranking <- order(spread, seq_along(points), method = "radix")
  chosen <- ranking[number]
  while (length(chosen) < k) chosen <- c(chosen, which.max(nearest_gaps(points, chosen)))
  chosen
}

initial_seeds <- function(method, points, k, number, draw) {
  if (method == "maximin") return(maximin(points, k, number))
  chosen <- integer()
  if (method == "forgy") {
    while (length(chosen) < k) {
      index <- draw() %% length(points) + 1L
      if (!index %in% chosen) chosen <- c(chosen, index)
    }
    return(chosen)
  }
  chosen <- draw() %% length(points) + 1L
  while (length(chosen) < k) {
    gaps <- nearest_gaps(points, chosen)
    weight <- ordered_sum(gaps)
    threshold <- (draw() / 2147483647) * weight
    total <- 0
    selected <- NA_integer_
    for (index in seq_along(gaps)) {
      total <- total + gaps[index]
      if (total > threshold) {
        selected <- index
        break
      }
    }
    if (is.na(selected)) selected <- tail(which(gaps > 0), 1L)
    chosen <- c(chosen, selected)
  }
  chosen
}

improve <- function(points, original, k, limit) {
  labels <- original
  sizes <- cluster_sizes(labels, k)
  centers <- cluster_centers(points, labels, k)
  passes <- transfers <- 0L
  while (passes < limit) {
    moved <- FALSE
    passes <- passes + 1L
    for (index in seq_along(points)) {
      own <- labels[index]
      if (sizes[own] == 1L) next
      removal <- (sizes[own] / (sizes[own] - 1L)) * squared_distance(points[[index]], centers[[own]])
      target <- NA_integer_
      cost <- 0
      for (cluster in seq_len(k)) {
        if (cluster == own) next
        candidate <- (sizes[cluster] / (sizes[cluster] + 1L)) * squared_distance(points[[index]], centers[[cluster]])
        if (is.na(target) || candidate < cost) {
          target <- cluster
          cost <- candidate
        }
      }
      if (cost < removal) {
        labels[index] <- target
        sizes[own] <- sizes[own] - 1L
        sizes[target] <- sizes[target] + 1L
        centers[[own]] <- cluster_center(points, labels, own)
        centers[[target]] <- cluster_center(points, labels, target)
        transfers <- transfers + 1L
        moved <- TRUE
      }
    }
    if (!moved) break
  }
  list(labels = labels, passes = passes, transfers = transfers,
       sse = sse(points, labels, cluster_centers(points, labels, k)))
}

new_run <- function(method, number, seeds, points, limit) {
  result <- lloyd(points, points[seeds], limit)
  list(method = method, number = number, seeds = seeds, lloyd = result,
       lloyd_sse = sse(points, result$labels, result$centers), improved = improve(points, result$labels, length(seeds), limit))
}

best_run <- function(runs) {
  best <- runs[[1L]]
  for (run in runs[-1L]) if (four_decimal(run$improved$sse) < four_decimal(best$improved$sse)) best <- run
  best
}

new_solution <- function(points, labels, k) {
  groups <- lapply(seq_len(k), function(cluster) which(labels == cluster))
  sizes <- vapply(groups, length, integer(1L))
  smallest <- vapply(groups, function(group) group[1L], integer(1L))
  groups <- groups[order(-sizes, smallest, method = "radix")]
  updated <- integer(length(labels))
  for (cluster in seq_len(k)) updated[groups[[cluster]]] <- cluster
  centers <- cluster_centers(points, updated, k)
  list(k = k, members = groups, sizes = vapply(groups, length, integer(1L)), labels = updated,
       centers = centers, sse = sse(points, updated, centers))
}

segment_names <- function(rules, centers) {
  numbers <- vapply(centers, function(center) rule_number(rules, center), integer(1L))
  names <- character(length(numbers))
  for (index in seq_along(numbers)) {
    repeat_count <- sum(numbers[seq_len(index)] == numbers[index])
    name <- rules[[numbers[index]]]$name
    names[index] <- if (repeat_count == 1L) name else paste0(name, "_", repeat_count)
  }
  list(numbers = numbers, names = names)
}

rfm_scores <- function(customers) {
  count <- length(customers)
  lapply(customers, function(customer) {
    ranks <- c(sum(vapply(customers, function(other) other$recency > customer$recency, logical(1L))),
      sum(vapply(customers, function(other) other$frequency < customer$frequency, logical(1L))),
      sum(vapply(customers, function(other) other$spend < customer$spend, logical(1L))))
    1 + (5 * ranks) %/% count
  })
}

gini <- function(spends) {
  ordered <- sort(spends, method = "radix")
  count <- length(ordered)
  total <- sum(ordered)
  weighted <- sum(seq_along(ordered) * ordered)
  (2 * weighted - (count + 1L) * total) / (count * total)
}
lower_median <- function(values) sort(values, method = "radix")[(length(values) - 1L) %/% 2L + 1L]
traits <- function(center) {
  ranking <- order(-abs(center), seq_along(center), method = "radix")[1:2]
  paste0(ifelse(center[ranking] > 0, "high_", "low_"), feature_names[ranking])
}
category_totals <- function(customers) {
  totals <- numeric()
  for (customer in customers) {
    for (category in names(customer$category_spend)) {
      previous <- totals[category]
      totals[category] <- if (is.na(previous)) customer$category_spend[category] else previous + customer$category_spend[category]
    }
  }
  totals
}
category_ranking <- function(totals) {
  positive <- totals[totals > 0]
  names(positive)[order(-positive, names(positive), method = "radix")]
}
category_amount <- function(totals, category) {
  value <- totals[category]
  if (is.na(value)) 0 else unname(value)
}
yes_no <- function(flag) if (flag) "yes" else "no"
integers <- function(values) paste(integer_text(values), collapse = " ")
join_blocks <- function(blocks) {
  lines <- character()
  for (index in seq_along(blocks)) {
    if (index > 1L) lines <- c(lines, "")
    lines <- c(lines, blocks[[index]])
  }
  lines
}

new_analysis <- function(params, data, rules) {
  a <- new.env(parent = emptyenv())
  a$params <- params
  a$data <- data
  a$rules <- rules
  a$draw <- minstd(params$seed)
  a$reference_orders <- group_orders(data$valid_rows, 1, params$reference_day)
  a$customer_orders <- orders_by_customer(a$reference_orders)
  a$customers <- eligible_customers(a$reference_orders, params$reference_day)
  a$ids <- vapply(a$customers, function(customer) customer$id, character(1L))
  transformed <- lapply(a$customers, transformed_values)
  scaling <- standardization(transformed)
  a$means <- scaling$means
  a$sds <- scaling$sds
  a$points <- lapply(transformed, function(values) standardize(values, a$means, a$sds))
  a$candidates <- list()
  a
}
ids_text <- function(a, numbers) paste(a$ids[numbers], collapse = " ")
candidate_at <- function(a, k) a$candidates[[k - a$params$k_min + 1L]]

search <- function(a, k) {
  runs <- bests <- list()
  for (method in a$params$methods) {
    method_runs <- lapply(seq_len(a$params$restarts), function(number) {
      seeds <- initial_seeds(method, a$points, k, number, a$draw)
      new_run(method, number, seeds, a$points, a$params$max_iterations)
    })
    runs <- c(runs, method_runs)
    bests[[length(bests) + 1L]] <- best_run(method_runs)
  }
  best <- best_run(bests)
  list(k = k, runs = runs, method_bests = bests, best = best,
       solution = new_solution(a$points, best$improved$labels, k))
}

evaluate <- function(a) {
  table <- distance_table(a$points)
  first <- a$candidates[[1L]]$solution$sse
  last <- a$candidates[[length(a$candidates)]]$solution$sse
  for (position in seq_along(a$candidates)) {
    item <- a$candidates[[position]]
    solution <- item$solution
    item$silhouettes <- silhouettes(table, solution$labels, solution$sizes)
    item$silhouette <- mean_value(item$silhouettes)
    item$calinski_harabasz <- calinski_harabasz(a$points, solution$centers, solution$sizes, solution$sse)
    item$davies_bouldin <- davies_bouldin(a$points, solution$labels, solution$centers, solution$sizes)
    item$elbow <- elbow(item$k, a$params$k_min, a$params$k_max, solution$sse, first, last)
    item$hartigan <- if (item$k < a$params$k_max) hartigan(solution$sse, a$candidates[[position + 1L]]$solution$sse, length(a$points), item$k) else NULL
    names <- segment_names(a$rules, solution$centers)
    item$rule_numbers <- names$numbers
    item$names <- names$names
    a$candidates[[position]] <- item
  }
}

choose_k <- function(a) {
  criteria <- c("elbow", "silhouette", "calinski_harabasz", "davies_bouldin")
  votes <- integer(5L)
  for (column in seq_along(criteria)) {
    options <- if (column == 1L) a$candidates[seq.int(2L, length(a$candidates) - 1L)] else a$candidates
    values <- vapply(options, function(item) four_decimal(item[[criteria[column]]]), numeric(1L))
    index <- if (column == 4L) which.min(values) else which.max(values)
    votes[column] <- options[[index]]$k
  }
  votes[5L] <- a$params$k_max
  for (item in a$candidates) {
    if (!is.null(item$hartigan) && item$hartigan <= 10) {
      votes[5L] <- item$k
      break
    }
  }
  counts <- vapply(a$candidates, function(item) sum(votes == item$k), integer(1L))
  silhouettes <- vapply(a$candidates, function(item) four_decimal(item$silhouette), numeric(1L))
  ranking <- order(-counts, -silhouettes, seq_along(a$candidates), method = "radix")
  a$final <- a$candidates[[ranking[1L]]]
  a$final_votes <- counts[ranking[1L]]
  a$votes <- votes
  a$criteria <- c(criteria, "hartigan")
}

describe_final <- function(a) {
  solution <- a$final$solution
  a$k <- solution$k
  a$labels <- solution$labels
  a$centers <- solution$centers
  a$names <- a$final$names
  a$silhouettes <- a$final$silhouettes
  a$distances <- numeric(length(a$points))
  a$others <- integer(length(a$points))
  a$other_distances <- numeric(length(a$points))
  for (index in seq_along(a$points)) {
    label <- a$labels[index]
    distances <- vapply(a$centers, function(center) squared_distance(a$points[[index]], center), numeric(1L))
    alternatives <- setdiff(seq_len(a$k), label)
    other <- alternatives[which.min(distances[alternatives])]
    a$distances[index] <- sqrt(distances[label])
    a$others[index] <- other
    a$other_distances[index] <- sqrt(distances[other])
  }
  a$scores <- rfm_scores(a$customers)
  a$codes <- vapply(a$scores, function(score) paste(integer_text(score), collapse = ""), character(1L))
  a$total_spend <- sum(vapply(a$customers, function(customer) customer$spend, numeric(1L)))
  a$overall_categories <- category_totals(a$customers)
  a$category_names <- sort(names(a$overall_categories), method = "radix")
  a$segment_customers <- lapply(solution$members, function(members) a$customers[members])
  a$segment_spends <- vapply(a$segment_customers, function(customers) sum(vapply(customers, function(customer) customer$spend, numeric(1L))), numeric(1L))
  a$segment_categories <- lapply(a$segment_customers, category_totals)
  a$rankings <- lapply(a$segment_categories, category_ranking)
  a$segment_sse <- vapply(seq_len(a$k), function(segment) {
    ordered_sum(vapply(solution$members[[segment]], function(number) squared_distance(a$points[[number]], a$centers[[segment]]), numeric(1L)))
  }, numeric(1L))
}

subsample_jaccards <- function(a) {
  count <- length(a$points)
  size <- (count * a$params$subsample_percent) %/% 100
  jaccards <- rep(list(numeric()), a$k)
  for (repeat_index in seq_len(a$params$subsamples)) {
    order <- seq_len(count)
    for (position in seq_len(size)) {
      other <- position + a$draw() %% (count - position + 1L)
      saved <- order[position]
      order[position] <- order[other]
      order[other] <- saved
    }
    sample <- sort(order[seq_len(size)], method = "radix")
    result <- lloyd(a$points[sample], a$centers, a$params$max_iterations)
    for (segment in seq_len(a$k)) {
      expected <- a$labels[sample] == segment
      best <- 0
      for (cluster in seq_len(a$k)) {
        actual <- result$labels == cluster
        both <- sum(expected & actual)
        either <- sum(expected | actual)
        if (either > 0) best <- max(best, both / either)
      }
      jaccards[[segment]] <- c(jaccards[[segment]], best)
    }
  }
  jaccards
}

analyze <- function(a) {
  for (k in seq.int(a$params$k_min, a$params$k_max)) a$candidates[[length(a$candidates) + 1L]] <- search(a, k)
  evaluate(a)
  choose_k(a)
  describe_final(a)
  a$jaccards <- subsample_jaccards(a)
}

recommendation <- function(a, number) {
  for (category in a$rankings[[a$labels[number]]]) {
    if (category_amount(a$customers[[number]]$category_spend, category) <= 0) return(category)
  }
  "-"
}

features_lines <- function(a) {
  lines <- "customer,recency,frequency,monetary,basket,categories,tenure,z_recency,z_frequency,z_monetary,z_basket,z_categories,z_tenure"
  for (index in seq_along(a$customers)) {
    customer <- a$customers[[index]]
    fields <- c(customer$id, integer_text(customer$recency), integer_text(customer$frequency), amount(customer$spend),
      real_text(customer$basket), integer_text(customer$categories), integer_text(customer$tenure), real_text(a$points[[index]]))
    lines <- c(lines, paste(fields, collapse = ","))
  }
  lines
}

run_line <- function(a, run) {
  paste("run", run$method, run$number, "seeds", ids_text(a, run$seeds), "iterations", run$lloyd$iterations,
    "converged", yes_no(run$lloyd$converged), "reseeds", run$lloyd$reseeds, "sse", real_text(run$lloyd_sse),
    "passes", run$improved$passes, "transfers", run$improved$transfers, "refined", real_text(run$improved$sse))
}
run_summary <- function(run) paste(run$method, "restart", run$number, "sse", real_text(run$improved$sse))
runs_lines <- function(a) {
  join_blocks(lapply(a$candidates, function(item) {
    c(paste("k", item$k), vapply(item$runs, function(run) run_line(a, run), character(1L)),
      paste("best", vapply(item$method_bests, run_summary, character(1L))),
      paste("chosen", run_summary(item$best)), paste("sizes", integers(item$solution$sizes)))
  }))
}

stability_line <- function(a, position, item) {
  parts <- paste0("k=", item$k)
  bests <- item$method_bests
  for (first in seq_along(bests)) {
    if (first == length(bests)) next
    for (second in seq.int(first + 1L, length(bests))) {
      parts <- c(parts, paste0(bests[[first]]$method, ":", bests[[second]]$method),
                 real_text(adjusted_rand(bests[[first]]$improved$labels, bests[[second]]$improved$labels)))
    }
  }
  parts <- c(parts, "final")
  for (run in bests) parts <- c(parts, run$method, real_text(adjusted_rand(run$improved$labels, item$solution$labels)))
  following <- if (position < length(a$candidates)) real_text(adjusted_rand(item$solution$labels, a$candidates[[position + 1L]]$solution$labels)) else "-"
  paste(c(parts, "next", following), collapse = " ")
}

selection_lines <- function(a) {
  indices <- "indices"
  name_lines <- "segments"
  stability <- "stability"
  for (position in seq_along(a$candidates)) {
    item <- a$candidates[[position]]
    h <- if (is.null(item$hartigan)) "-" else real_text(item$hartigan)
    indices <- c(indices, paste0("k=", item$k, " sse ", real_text(item$solution$sse), " elbow ", real_text(item$elbow),
      " silhouette ", real_text(item$silhouette), " calinski_harabasz ", real_text(item$calinski_harabasz),
      " davies_bouldin ", real_text(item$davies_bouldin), " hartigan ", h))
    name_lines <- c(name_lines, paste(c(paste0("k=", item$k), paste0(item$names, ":", item$solution$sizes)), collapse = " "))
    stability <- c(stability, stability_line(a, position, item))
  }
  votes <- c("votes", paste0(a$criteria, " k=", a$votes), paste0("chosen k=", a$k, " votes ", a$final_votes))
  join_blocks(list(indices, votes, name_lines, stability))
}

segments_lines <- function(a) {
  lines <- "customer,segment,name,distance,other,other_distance,silhouette,recommend"
  for (index in seq_along(a$customers)) {
    label <- a$labels[index]
    lines <- c(lines, paste(c(a$customers[[index]]$id, label, a$names[label], real_text(a$distances[index]),
      a$others[index], real_text(a$other_distances[index]), real_text(a$silhouettes[index]), recommendation(a, index)), collapse = ","))
  }
  lines
}

median_line <- function(customers) {
  values <- lapply(seq_along(feature_names), function(feature) vapply(customers, function(customer) {
    if (feature == 3L) customer$spend else customer_values(customer)[feature]
  }, numeric(1L)))
  medians <- vapply(values, lower_median, numeric(1L))
  paste("  median recency", integer_text(medians[1L]), "frequency", integer_text(medians[2L]), "monetary", amount(medians[3L]),
        "basket", real_text(medians[4L]), "categories", integer_text(medians[5L]), "tenure", integer_text(medians[6L]))
}

related <- function(a, members, k) {
  if (k < a$params$k_min || k > a$params$k_max) return(paste0("k=", k, " -"))
  labels <- candidate_at(a, k)$solution$labels
  counts <- tabulate(labels[members], nbins = k)
  best <- which.max(counts)
  paste0("k=", k, " segment ", best, " shared ", counts[best])
}

cadence_line <- function(a, customers) {
  gaps <- numeric()
  overdue <- 0L
  for (customer in customers) {
    if (customer$frequency < 2L) next
    active <- customer$tenure - customer$recency
    intervals <- customer$frequency - 1L
    gaps <- c(gaps, active / intervals)
    if (customer$recency * intervals > a$params$overdue_factor * active) overdue <- overdue + 1L
  }
  mean_gap <- if (length(gaps)) real_text(mean_value(gaps)) else "-"
  paste("  cadence customers", length(gaps), "mean_gap", mean_gap, "overdue", overdue)
}

order_sizes_line <- function(a, customers) {
  bins <- integer(length(a$params$order_bins) + 1L)
  for (customer in customers) {
    for (order in customer$orders) {
      index <- sum(order$net >= a$params$order_bins * 100) + 1L
      bins[index] <- bins[index] + 1L
    }
  }
  paste("  order_sizes", integers(bins))
}

returns_line <- function(a, customers) {
  gross <- returned <- 0
  cancelled <- 0L
  for (customer in customers) {
    for (order in a$customer_orders[[customer$id]]) {
      if (order$net <= 0) cancelled <- cancelled + 1L
      for (row in order$rows) {
        if (row$amount > 0) gross <- gross + row$amount
        else returned <- returned - row$amount
      }
    }
  }
  paste("  returns rate", real_text(returned / gross), "returned", amount(returned), "cancelled", cancelled)
}

rfm_line <- function(a, members) {
  means <- vapply(seq_len(3L), function(part) {
    ordered_sum(vapply(members, function(number) a$scores[[number]][part], numeric(1L))) / length(members)
  }, numeric(1L))
  codes <- a$codes[members]
  options <- sort(unique(codes), method = "radix")
  counts <- vapply(options, function(code) sum(codes == code), integer(1L))
  mode <- which.max(counts)
  paste("  rfm r", real_text(means[1L]), "f", real_text(means[2L]), "m", real_text(means[3L]), "mode", options[mode], counts[mode])
}

categories_line <- function(a, segment) {
  parts <- "  categories"
  for (category in head(a$rankings[[segment]], a$params$top_categories)) {
    share <- a$segment_categories[[segment]][category] / a$segment_spends[segment]
    lift <- share / (a$overall_categories[category] / a$total_spend)
    parts <- c(parts, category, real_text(share), real_text(lift))
  }
  paste(parts, collapse = " ")
}

outliers_line <- function(a, members) {
  outliers <- character()
  if (length(members) >= 2L) {
    distances <- a$distances[members]
    limit <- mean_value(distances) + a$params$outlier_sd * sample_sd(distances)
    outliers <- a$ids[members[distances > limit]]
  }
  paste(c("  outliers", length(outliers), outliers), collapse = " ")
}

segment_profile <- function(a, segment) {
  members <- a$final$solution$members[[segment]]
  customers <- a$segment_customers[[segment]]
  size <- length(members)
  center <- a$centers[[segment]]
  spend <- a$segment_spends[segment]
  values <- original_scale(center, a$means, a$sds)
  spends <- vapply(customers, function(customer) customer$spend, numeric(1L))
  top <- members[order(-spends, members, method = "radix")]
  top <- head(top, a$params$top_customers)
  silhouettes <- a$silhouettes[members]
  c(paste("segment", segment, a$names[segment], "rule", a$final$rule_numbers[segment], "size", size,
      "share", real_text(size / length(a$customers)), "revenue", amount(spend), "revenue_share", real_text(spend / a$total_spend)),
    paste("  center", reals(center)), paste("  value", paste(feature_names, real_text(values), collapse = " ")),
    paste("  traits", paste(traits(center), collapse = " ")), median_line(customers),
    paste("  related", related(a, members, a$k - 1L), related(a, members, a$k + 1L)),
    paste("  top_customers", paste(vapply(top, function(number) paste(a$ids[number], amount(a$customers[[number]]$spend)), character(1L)), collapse = " ")),
    cadence_line(a, customers), order_sizes_line(a, customers),
    paste("  sse", real_text(a$segment_sse[segment]), "share", real_text(a$segment_sse[segment] / a$final$solution$sse)),
    paste("  gini", real_text(gini(spends))), returns_line(a, customers),
    paste("  silhouette", real_text(mean_value(silhouettes)), "negative", sum(silhouettes < 0)),
    rfm_line(a, members), categories_line(a, segment), outliers_line(a, members))
}

segment_numbers <- function(a) integers(seq_len(a$k))
category_mix_lines <- function(a) {
  lines <- paste("category_mix", segment_numbers(a))
  for (category in a$category_names) {
    shares <- vapply(seq_len(a$k), function(segment) category_amount(a$segment_categories[[segment]], category) / a$segment_spends[segment], numeric(1L))
    lines <- c(lines, paste(category, reals(shares)))
  }
  lines
}
recency_table_lines <- function(a) {
  lines <- paste("rfm_recency", segment_numbers(a))
  for (score in 5:1) {
    counts <- vapply(a$final$solution$members, function(members) sum(vapply(members, function(number) a$scores[[number]][1L] == score, logical(1L))), integer(1L))
    lines <- c(lines, paste0("r=", score, " ", integers(counts)))
  }
  c(lines, paste("ari rfm_codes", real_text(adjusted_rand(a$codes, a$labels))))
}
center_distance_lines <- function(a) {
  c("center_distances", vapply(seq_len(a$k), function(segment) {
    distances <- vapply(a$centers, function(other) sqrt(squared_distance(a$centers[[segment]], other)), numeric(1L))
    paste(segment, reals(distances))
  }, character(1L)))
}
profiles_lines <- function(a) {
  spends <- vapply(a$customers, function(customer) customer$spend, numeric(1L))
  blocks <- list(paste0("segments k=", a$k, " customers ", length(a$customers), " revenue ", amount(a$total_spend), " gini ", real_text(gini(spends))))
  blocks <- c(blocks, lapply(seq_len(a$k), function(segment) segment_profile(a, segment)))
  join_blocks(c(blocks, list(category_mix_lines(a), recency_table_lines(a), center_distance_lines(a))))
}

subsample_lines <- function(a) {
  lines <- paste("subsamples", integer_text(a$params$subsamples), "size", (length(a$customers) * a$params$subsample_percent) %/% 100)
  for (segment in seq_len(a$k)) {
    values <- a$jaccards[[segment]]
    lines <- c(lines, paste("segment", segment, a$names[segment], "mean_jaccard", real_text(mean_value(values)), "min_jaccard", real_text(min(values))))
  }
  lines
}

ablation_lines <- function(a) {
  lines <- "ablation"
  for (feature in seq_along(feature_names)) {
    points <- lapply(a$points, function(point) point[-feature])
    seeds <- maximin(points, a$k, 1L)
    run <- new_run("maximin", 1L, seeds, points, a$params$max_iterations)
    index <- adjusted_rand(run$improved$labels, a$labels)
    lines <- c(lines, paste("without", feature_names[feature], "seeds", ids_text(a, seeds), "iterations", run$lloyd$iterations,
      "converged", yes_no(run$lloyd$converged), "transfers", run$improved$transfers, "sse", real_text(run$improved$sse), "ari", real_text(index)))
  }
  lines
}

drilldown_lines <- function(a) {
  members <- a$final$solution$members[[1L]]
  points <- a$points[members]
  seeds <- maximin(points, 2L, 1L)
  run <- new_run("maximin", 1L, seeds, points, a$params$max_iterations)
  parts <- new_solution(points, run$improved$labels, 2L)
  before <- a$segment_sse[1L]
  after <- run$improved$sse
  c(paste("drilldown segment 1", a$names[1L], "size", length(members), "seeds", ids_text(a, members[seeds]),
    "iterations", run$lloyd$iterations, "converged", yes_no(run$lloyd$converged), "transfers", run$improved$transfers),
    paste("sse before", real_text(before), "after", real_text(after), "gain", real_text(before - after)),
    vapply(seq_len(2L), function(part) paste("part", part, "size", parts$sizes[part], "center", reals(parts$centers[[part]])), character(1L)))
}
robustness_lines <- function(a) join_blocks(list(subsample_lines(a), ablation_lines(a), drilldown_lines(a)))

period_lines <- function(a) {
  p <- a$params
  lines <- paste("periods", integer_text(p$periods), "days", integer_text(p$period_days))
  for (period in seq_len(p$periods)) {
    first <- p$reference_day - period * p$period_days + 1
    last <- p$reference_day - (period - 1L) * p$period_days
    revenue <- numeric(a$k)
    active <- acquired <- integer(a$k)
    for (number in seq_along(a$customers)) {
      customer <- a$customers[[number]]
      label <- a$labels[number]
      orders <- Filter(function(order) first <= order$day && order$day <= last, customer$orders)
      if (length(orders)) {
        revenue[label] <- revenue[label] + sum(vapply(orders, function(order) order$net, numeric(1L)))
        active[label] <- active[label] + 1L
      }
      day <- p$reference_day - customer$tenure
      if (first <= day && day <= last) acquired[label] <- acquired[label] + 1L
    }
    lines <- c(lines, paste("period", period, "days", integer_text(first), integer_text(last), "revenue",
      paste(amount(revenue), collapse = " "), "active", integers(active), "acquired", integers(acquired)))
  }
  lines
}

migration_lines <- function(a) {
  day <- a$params$snapshot_day
  snapshot <- eligible_customers(group_orders(a$data$valid_rows, 1, day), day)
  previous <- integer()
  for (customer in snapshot) {
    point <- standardize(transformed_values(customer), a$means, a$sds)
    previous[customer$id] <- assign_points(list(point), a$centers)$labels[1L]
  }
  table <- matrix(0L, a$k + 1L, a$k)
  moved <- character()
  stayed <- fresh <- 0L
  for (number in seq_along(a$customers)) {
    id <- a$ids[number]
    label <- a$labels[number]
    origin <- previous[id]
    if (is.na(origin)) {
      table[a$k + 1L, label] <- table[a$k + 1L, label] + 1L
      fresh <- fresh + 1L
      next
    }
    table[origin, label] <- table[origin, label] + 1L
    if (origin == label) stayed <- stayed + 1L
    else moved <- c(moved, paste(id, origin, label))
  }
  lost <- sum(!names(previous) %in% a$ids)
  lines <- c(paste("migration day", integer_text(day), "customers", length(snapshot)), paste("from\\to", segment_numbers(a)))
  for (origin in seq_len(a$k + 1L)) {
    label <- if (origin == a$k + 1L) "none" else as.character(origin)
    lines <- c(lines, paste(label, integers(table[origin, ])))
  }
  c(lines, "moved_customers", moved, paste("stayed", stayed, "moved", length(moved), "new", fresh, "lost", lost))
}

outcome_lines <- function(a) {
  first <- a$params$reference_day + 1
  last <- a$params$reference_day + a$params$outcome_days
  purchases <- numeric()
  for (order in group_orders(a$data$valid_rows, first, last)) {
    if (order$net <= 0) next
    previous <- purchases[order$customer]
    purchases[order$customer] <- if (is.na(previous)) order$net else previous + order$net
  }
  lines <- paste("outcome days", integer_text(first), integer_text(last))
  for (segment in seq_len(a$k)) {
    members <- a$final$solution$members[[segment]]
    amounts <- purchases[a$ids[members]]
    buyers <- sum(!is.na(amounts))
    spend <- sum(amounts, na.rm = TRUE)
    size <- length(members)
    lines <- c(lines, paste("segment", segment, a$names[segment], "size", size, "buyers", buyers, "rate", real_text(buyers / size),
      "revenue", amount(spend), "per_customer", real_text((spend / 100) / size)))
  }
  outsiders <- purchases[!names(purchases) %in% a$ids]
  c(lines, paste("unsegmented buyers", length(outsiders), "revenue", amount(sum(outsiders))))
}
tracking_lines <- function(a) join_blocks(list(period_lines(a), migration_lines(a), outcome_lines(a)))

data_lines <- function(a) {
  used <- Filter(function(row) row$day <= a$params$reference_day, a$data$valid_rows)
  returns <- sum(vapply(used, function(row) row$amount < 0, logical(1L)))
  valid <- sum(vapply(a$reference_orders, function(order) order$net > 0, logical(1L)))
  excluded <- sort(setdiff(a$data$customers, a$ids), method = "radix")
  c(paste("rows", a$data$row_count, "duplicates", a$data$duplicates, "zero", a$data$free, "used", length(used),
      "returns", returns, "later", length(a$data$valid_rows) - length(used)),
    paste("orders", length(a$reference_orders), "valid", valid, "cancelled", length(a$reference_orders) - valid),
    paste("customers", length(a$data$customers), "clustered", length(a$customers), "excluded", length(excluded)),
    paste("excluded_ids", if (length(excluded)) paste(excluded, collapse = " ") else "-"))
}
category_lines <- function(a) {
  vapply(a$category_names, function(category) {
    total <- a$overall_categories[category]
    buyers <- sum(vapply(a$customers, function(customer) category_amount(customer$category_spend, category) > 0, logical(1L)))
    paste("category", category, "revenue", amount(total), "share", real_text(total / a$total_spend), "customers", buyers)
  }, character(1L))
}
feature_summary_lines <- function(a) {
  vapply(seq_along(feature_names), function(feature) {
    column <- vapply(a$customers, function(customer) customer_values(customer)[feature], numeric(1L))
    transform <- if (sqrt_features[feature]) "sqrt" else "none"
    paste("feature", feature_names[feature], "transform", transform, "raw_mean", real_text(mean_value(column)),
      "raw_sd", real_text(sample_sd(column)), "mean", real_text(a$means[feature]), "sd", real_text(a$sds[feature]))
  }, character(1L))
}
correlation_lines <- function(a) {
  c(paste("correlation", paste(feature_names, collapse = " ")), vapply(seq_along(feature_names), function(first) {
    values <- vapply(seq_along(feature_names), function(second) correlation_value(a$points, first, second), numeric(1L))
    paste(feature_names[first], reals(values))
  }, character(1L)))
}
summary_lines <- function(a) join_blocks(list(data_lines(a), category_lines(a), feature_summary_lines(a), correlation_lines(a)))

a <- new_analysis(read_params(), read_transactions(), read_rules())
analyze(a)
files <- list("features.csv" = features_lines(a), "runs.txt" = runs_lines(a), "selection.txt" = selection_lines(a),
  "segments.csv" = segments_lines(a), "profiles.txt" = profiles_lines(a), "robustness.txt" = robustness_lines(a),
  "tracking.txt" = tracking_lines(a), "summary.txt" = summary_lines(a))
dir.create("output", showWarnings = FALSE, recursive = TRUE)
for (name in names(files)) write_lines(name, files[[name]])
