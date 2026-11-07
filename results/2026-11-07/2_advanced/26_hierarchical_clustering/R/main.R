source("dataset.R")
source("distances.R")
source("agglomerative.R")
source("dendrogram.R")
source("validation.R")

real_text <- function(value) {
  if (is.null(value)) return("-")
  text <- sprintf("%.4f", value)
  if (text == "-0.0000") "0.0000" else text
}
integer_text <- function(value) sprintf("%.0f", value)
reals <- function(values) paste(vapply(values, real_text, character(1)), collapse = " ")
integers <- function(values) paste(vapply(values, integer_text, character(1)), collapse = " ")
four_digit <- function(value) round(value, 4)
ari_text <- function(ari) paste0(integer_text(ari$p), "/", integer_text(ari$q), " ", real_text(ari_value(ari)))
pair_values <- function(matrix) {
  values <- numeric()
  count <- nrow(matrix)
  for (i in seq_len(count - 1)) for (j in seq.int(i + 1, count)) values <- c(values, matrix[i, j])
  values
}
histogram_bin <- function(value, maximum) min(9, floor(10 * value / maximum))
centroid <- function(vectors) vapply(seq_len(ncol(vectors)), function(f) sequential_sum(vectors[, f]) / nrow(vectors), numeric(1))
cluster_members <- function(partition, groups) lapply(seq_len(groups), function(g) which(partition == g))
majority_class <- function(row) which.max(row)
connected_components <- function(count, edges) {
  component <- seq_len(count)
  for (edge in edges) {
    old <- component[edge$child]
    current <- component[edge$parent]
    component[component == old] <- current
  }
  component
}
join_parts <- function(parts) {
  lines <- character()
  for (i in seq_along(parts)) {
    if (i > 1) lines <- c(lines, "")
    lines <- c(lines, parts[[i]])
  }
  lines
}
ranked_indices <- function(values, descending, rounded) {
  keys <- if (rounded) four_digit(values) else values
  if (descending) keys <- -keys
  order(keys, seq_along(keys), method = "radix")
}
partition_ari <- function(first, second) adjusted_rand_index(contingency_table(first, second, max(first), max(second)))
mean_silhouette <- function(partition, delta) {
  groups <- max(partition)
  if (groups < 2) NULL else sequential_sum(silhouette_values(partition, groups, delta)) / length(partition)
}
new_settings <- function(entries) {
  depth <- 0
  for (digit in utf8ToInt(entries$INCONSISTENCY[1])) depth <- min(120, depth * 10 + digit - 48)
  list(distance = entries$DISTANCE[1], standardize = entries$STANDARDIZE[1], linkages = entries$LINKAGES,
       cut_heights = as.numeric(entries$CUT_HEIGHTS), cut_counts = as.numeric(entries$CUT_K),
       inconsistency_depth = depth, inconsistency_depth_text = entries$INCONSISTENCY[1], inconsistency_count = as.numeric(entries$INCONSISTENCY[2]),
       gap_max_k = as.numeric(entries$GAP_MAX_K[1]), list_size = as.numeric(entries$LIST_SIZE[1]), width = as.numeric(entries$DENDROGRAM_WIDTH[1]),
       compare_linkage = entries$COMPARE_LINKAGE[1], replicates = as.numeric(entries$SUBSAMPLES[1]), percent = as.numeric(entries$SUBSAMPLES[2]),
       seed = as.numeric(entries$SUBSAMPLES[3]), refine_iterations = as.numeric(entries$REFINE_ITERATIONS[1]))
}
new_minstd <- function(seed) {
  state <- seed
  function() {
    state <<- (48271 * state) %% 2147483647
    state
  }
}
tree_height_of <- function(tree, node) if (node <= tree$count) 0 else tree$heights[node - tree$count]
tree_subtree_height <- function(tree, node) if (node <= tree$count) 0 else tree$subtree_heights[node - tree$count]
new_tree <- function(merges, count) {
  tree <- list(merges = merges, count = count, heights = vapply(merges, function(merge) merge$height, numeric(1)),
               children = ordered_children(merges, count), members = lapply(seq_len(count), function(u) u),
               depths = rep(0, count), subtree_heights = numeric())
  tree$order <- leaf_order(tree$children, count)
  for (merge in merges) {
    tree$members[[length(tree$members) + 1]] <- c(tree$members[[merge$a]], tree$members[[merge$b]])
    tree$depths <- c(tree$depths, 1 + max(tree$depths[merge$a], tree$depths[merge$b]))
    tree$subtree_heights <- c(tree$subtree_heights, max(merge$height, tree_subtree_height(tree, merge$a), tree_subtree_height(tree, merge$b)))
  }
  tree
}
tree_root <- function(tree) 2 * tree$count - 1
tree_partition <- function(tree, selected) {
  owner <- seq_len(tree$count)
  for (step in seq_along(selected)) if (selected[step]) {
    node <- tree$count + step
    owner[tree$members[[node]]] <- node
  }
  numbers <- numeric(2 * tree$count - 1)
  groups <- 0
  for (u in tree$order) if (numbers[owner[u]] == 0) {
    groups <- groups + 1
    numbers[owner[u]] <- groups
  }
  numbers[owner]
}
tree_cut_at_height <- function(tree, height) tree_partition(tree, tree$subtree_heights <= height)
tree_cut_into <- function(tree, k) tree_partition(tree, seq_along(tree$merges) <= tree$count - k)
tree_cophenetic <- function(tree) {
  matrix <- matrix(0, tree$count, tree$count)
  for (merge in tree$merges) for (i in tree$members[[merge$a]]) for (j in tree$members[[merge$b]]) matrix[i, j] <- matrix[j, i] <- merge$height
  matrix
}
tree_joining_heights <- function(tree) {
  heights <- numeric(tree$count)
  for (merge in tree$merges) for (child in c(merge$a, merge$b)) if (child <= tree$count) heights[child] <- merge$height
  heights
}
tree_height_sequence <- function(tree, step, depth) {
  if (depth == 0) return(numeric())
  merge <- tree$merges[[step]]
  sequence <- merge$height
  for (child in c(merge$a, merge$b)) if (child > tree$count) sequence <- c(sequence, tree_height_sequence(tree, child - tree$count, depth - 1))
  sequence
}
tree_newick <- function(tree, node, idents) {
  if (node <= tree$count) return(idents[node])
  branches <- vapply(tree$children[[node - tree$count]], function(child) {
    paste0(tree_newick(tree, child, idents), ":", real_text(tree_height_of(tree, node) - tree_height_of(tree, child)))
  }, character(1))
  paste0("(", paste(branches, collapse = ","), ")")
}
evaluation_text <- function(evaluation) {
  paste("sizes", integers(evaluation$sizes), "silhouette", real_text(evaluation$silhouette), "dunn", real_text(evaluation$dunn),
        "wss", real_text(evaluation$wss), "ch", real_text(evaluation$ch), "ari", ari_text(evaluation$ari))
}
class_table <- function(study, partition) contingency_table(partition, study$targets, max(partition), length(study$classes))
label_ari <- function(study, partition) adjusted_rand_index(class_table(study, partition))
match_count <- function(study, partition) {
  table <- class_table(study, partition)
  sum(vapply(seq_len(nrow(table)), function(g) max(table[g, ]), numeric(1)))
}
centroids <- function(study, partition) lapply(cluster_members(partition, max(partition)), function(group) centroid(study$vectors[group, , drop = FALSE]))
within_sum <- function(study, partition) {
  centers <- centroids(study, partition)
  total <- 0
  for (i in seq_along(partition)) total <- total + squared_distance(study$vectors[i, ], centers[[partition[i]]])
  total
}
dunn_index <- function(study, partition, groups) {
  diameter <- 0
  separation <- Inf
  for (i in seq_len(study$count - 1)) for (j in seq.int(i + 1, study$count)) {
    value <- study$distances[i, j]
    if (partition[i] == partition[j]) diameter <- max(diameter, value) else separation <- min(separation, value)
  }
  if (groups >= 2 && diameter > 0) separation / diameter else NULL
}
evaluate <- function(study, partition) {
  groups <- max(partition)
  sizes <- vapply(cluster_members(partition, groups), length, integer(1))
  wss <- within_sum(study, partition)
  ch <- NULL
  if (groups >= 2 && groups < study$count) {
    overall <- centroid(study$vectors)
    centers <- centroids(study, partition)
    bss <- 0
    for (g in seq_len(groups)) bss <- bss + sizes[g] * squared_distance(centers[[g]], overall)
    ch <- (bss / (groups - 1)) / (wss / (study$count - groups))
  }
  list(partition = partition, sizes = sizes, silhouette = mean_silhouette(partition, study$distances),
       dunn = dunn_index(study, partition, groups), wss = wss, ch = ch, ari = label_ari(study, partition))
}
analyse_linkage <- function(study, method) {
  tree <- new_tree(agglomerate(study$distances, method), study$count)
  coph <- pair_values(tree_cophenetic(tree))
  list(method = method, tree = tree, cophenetic = coph, coefficient = correlation(study$distance_pairs, coph),
       height_cuts = lapply(study$settings$cut_heights, function(height) evaluate(study, tree_cut_at_height(tree, height))),
       count_cuts = lapply(study$settings$cut_counts, function(k) evaluate(study, tree_cut_into(tree, k))),
       label_partition = tree_cut_into(tree, length(study$classes)))
}
new_study <- function(names, observations, settings) {
  study <- new.env(parent = emptyenv())
  study$feature_names <- names
  study$settings <- settings
  study$count <- length(observations)
  study$idents <- vapply(observations, function(observation) observation$ident, character(1))
  study$labels <- vapply(observations, function(observation) observation$label, character(1))
  study$classes <- sort(unique(study$labels), method = "radix")
  study$targets <- match(study$labels, study$classes)
  study$raw <- do.call(rbind, lapply(observations, function(observation) observation$values))
  statistics <- feature_statistics(study$raw)
  study$means <- statistics$means
  study$deviations <- statistics$deviations
  study$vectors <- if (settings$standardize == "yes") standardize_data(study$raw, study$means, study$deviations) else study$raw
  study$distances <- distance_matrix(study$vectors, settings$distance)
  study$distance_pairs <- pair_values(study$distances)
  study$distance_max <- max(study$distance_pairs)
  study$neighbors <- vapply(seq_len(study$count), function(i) {
    candidates <- setdiff(seq_len(study$count), i)
    candidates[which.min(study$distances[i, candidates])]
  }, integer(1))
  study$results <- lapply(settings$linkages, function(method) analyse_linkage(study, method))
  best_method <- 1L
  position <- 1L
  for (m in seq_along(study$results)) for (i in seq_along(settings$cut_counts)) {
    if (ari_greater(study$results[[m]]$count_cuts[[i]]$ari, study$results[[best_method]]$count_cuts[[position]]$ari)) {
      best_method <- m
      position <- i
    }
  }
  study$chosen <- study$results[[best_method]]
  study$kappa <- settings$cut_counts[position]
  study$selected_cut <- study$chosen$count_cuts[[position]]
  study$selected <- study$selected_cut$partition
  study$members <- cluster_members(study$selected, study$kappa)
  study$silhouettes <- silhouette_values(study$selected, study$kappa, study$distances)
  study$table <- class_table(study, study$selected)
  study$majority <- vapply(seq_len(nrow(study$table)), function(g) majority_class(study$table[g, ]), integer(1))
  study
}
linkage_table <- function(study) {
  lines <- "method,step,a,b,height,size"
  for (result in study$results) for (step in seq_along(result$tree$merges)) {
    merge <- result$tree$merges[[step]]
    lines <- c(lines, paste(result$method, step, merge$a - 1, merge$b - 1, real_text(merge$height), merge$size, sep = ","))
  }
  lines
}
clusters_table <- function(study) {
  header <- c("id", "label")
  for (result in study$results) {
    header <- c(header, paste0(result$method, "_h", seq_along(study$settings$cut_heights)), paste0(result$method, "_k", study$settings$cut_counts))
  }
  lines <- paste(header, collapse = ",")
  for (i in seq_len(study$count)) {
    fields <- c(study$idents[i], study$labels[i])
    for (result in study$results) for (cut in c(result$height_cuts, result$count_cuts)) fields <- c(fields, integer_text(cut$partition[i]))
    lines <- c(lines, paste(fields, collapse = ","))
  }
  lines
}
dendrogram_report <- function(study) {
  blocks <- list()
  width <- study$settings$width
  for (result in study$results) {
    tree <- result$tree
    maximum <- max(tree$heights)
    cuts <- vapply(study$settings$cut_heights, function(height) column(height, maximum, width), numeric(1))
    lines <- c(paste("dendrogram", result$method, "height_max", real_text(maximum), "width", width),
               dendrogram_rows(tree$merges, tree$children, tree$order, study$idents, study$labels, maximum, cuts, width))
    for (i in seq_along(cuts)) lines <- c(lines, paste("cut", real_text(study$settings$cut_heights[i]), "column", if (cuts[i] <= width) integer_text(cuts[i]) else "-"))
    blocks[[length(blocks) + 1]] <- lines
  }
  join_parts(blocks)
}
trees_report <- function(study) vapply(study$results, function(result) paste0(result$method, " ", tree_newick(result$tree, tree_root(result$tree), study$idents), ";"), character(1))
pair_text <- function(study, i, j) paste(real_text(study$distances[i, j]), study$idents[i], study$idents[j])
data_part <- function(study) {
  settings <- study$settings
  n <- study$count
  lines <- paste("data n", n, "features", length(study$feature_names), "classes", length(study$classes), "distance", settings$distance, "standardize", settings$standardize)
  for (f in seq_along(study$feature_names)) lines <- c(lines, paste("feature", study$feature_names[f], "mean", real_text(study$means[f]), "sd", real_text(study$deviations[f])))
  smallest <- largest <- c(1L, 2L)
  for (i in seq_len(n - 1)) for (j in seq.int(i + 1, n)) {
    if (study$distances[i, j] < study$distances[smallest[1], smallest[2]]) smallest <- c(i, j)
    if (study$distances[i, j] > study$distances[largest[1], largest[2]]) largest <- c(i, j)
  }
  lines <- c(lines, paste("distances pairs", length(study$distance_pairs), "min", pair_text(study, smallest[1], smallest[2]), "max", pair_text(study, largest[1], largest[2]), "mean", real_text(sequential_sum(study$distance_pairs) / length(study$distance_pairs))))
  nearest <- 0
  reciprocal <- 0
  for (i in seq_len(n)) {
    j <- study$neighbors[i]
    nearest <- nearest + study$distances[i, j]
    if (i < j && study$neighbors[j] == i) reciprocal <- reciprocal + 1
  }
  c(lines, paste("nearest_neighbors mean", real_text(nearest / n), "reciprocal_pairs", reciprocal), paste("labels", evaluation_text(evaluate(study, study$targets))))
}
correlation_part <- function(study) {
  columns <- lapply(seq_along(study$feature_names), function(f) study$raw[, f])
  lines <- paste("correlation", paste(study$feature_names, collapse = " "))
  for (f in seq_along(columns)) lines <- c(lines, paste(study$feature_names[f], reals(vapply(columns, function(second) correlation(columns[[f]], second), numeric(1)))))
  lines
}
histogram_part <- function(study) {
  counts <- numeric(10)
  for (value in study$distance_pairs) {
    bin <- histogram_bin(value, study$distance_max) + 1
    counts[bin] <- counts[bin] + 1
  }
  highest <- max(counts)
  lines <- "histogram"
  for (b in 0:9) {
    line <- paste(real_text(b * study$distance_max / 10), real_text((b + 1) * study$distance_max / 10), integer_text(counts[b + 1]))
    length <- (counts[b + 1] * 50) %/% highest
    if (length > 0) line <- paste(line, strrep("#", length))
    lines <- c(lines, line)
  }
  lines
}
gaps <- function(study, tree) {
  ordered <- sort(tree$subtree_heights, method = "radix")
  vapply(seq.int(2, study$settings$gap_max_k), function(k) ordered[study$count - k + 1] - ordered[study$count - k], numeric(1))
}
inconsistency_line <- function(study, tree, step) {
  sequence <- tree_height_sequence(tree, step, study$settings$inconsistency_depth)
  size <- length(sequence)
  mean <- sequential_sum(sequence) / size
  deviation <- coefficient <- 0
  if (size >= 2) {
    squares <- 0
    for (value in sequence) squares <- squares + (value - mean) * (value - mean)
    deviation <- sqrt(squares / (size - 1))
    coefficient <- (tree$heights[step] - mean) / deviation
  }
  paste("step", step, "height", real_text(tree$heights[step]), "mean", real_text(mean), "sd", real_text(deviation), "count", size, "coefficient", real_text(coefficient))
}
linkage_part <- function(study, result) {
  tree <- result$tree
  heights <- tree$heights
  n <- study$count
  leaf_path <- 0
  for (r in seq_len(n - 1)) leaf_path <- leaf_path + study$distances[tree$order[r], tree$order[r + 1]]
  inversions <- which(heights[-1] < heights[-length(heights)]) + 1
  lines <- c(paste("linkage", result$method), paste("cophenetic", real_text(result$coefficient), "leaf_path", real_text(leaf_path)),
             paste("heights min", real_text(min(heights)), "max", real_text(max(heights)), "inversions", length(inversions)))
  for (step in inversions) lines <- c(lines, paste("inversion step", step, "height", real_text(heights[step]), "previous", real_text(heights[step - 1])))
  values <- gaps(study, tree)
  suggested <- which.max(four_digit(values)) + 1
  lines <- c(lines, paste("gaps", reals(values)), paste("suggested_k", suggested))
  joining <- tree_joining_heights(tree)
  late <- head(ranked_indices(joining, TRUE, FALSE), study$settings$list_size)
  texts <- vapply(late, function(i) paste0(study$idents[i], ":", real_text(joining[i])), character(1))
  kinds <- numeric(3)
  for (merge in tree$merges) {
    leaves <- as.numeric(merge$a <= n) + as.numeric(merge$b <= n)
    kinds[3 - leaves] <- kinds[3 - leaves] + 1
  }
  matches <- match_count(study, result$label_partition)
  lines <- c(lines, paste("late_joiners", paste(texts, collapse = " ")),
             paste("merges leaf_leaf", kinds[1], "leaf_cluster", kinds[2], "cluster_cluster", kinds[3], "depth", tree$depths[tree_root(tree)]),
             paste("label_cut k", length(study$classes), "purity", paste0(matches, "/", n), real_text(matches / n)), paste("inconsistency depth", study$settings$inconsistency_depth_text))
  for (step in seq.int(n - study$settings$inconsistency_count, n - 1)) lines <- c(lines, inconsistency_line(study, tree, step))
  for (i in seq_along(study$settings$cut_heights)) {
    cut <- result$height_cuts[[i]]
    lines <- c(lines, paste("cut height", real_text(study$settings$cut_heights[i]), "clusters", length(cut$sizes), evaluation_text(cut)))
  }
  for (i in seq_along(study$settings$cut_counts)) lines <- c(lines, paste("cut k", study$settings$cut_counts[i], evaluation_text(result$count_cuts[[i]])))
  lines
}
result_of <- function(study, method) {
  for (result in study$results) if (result$method == method) return(result)
  NULL
}
mst_part <- function(study) {
  single <- result_of(study, "single")
  n <- study$count
  edges <- minimum_spanning_tree(study$distances)
  weights <- vapply(edges, function(edge) edge$weight, numeric(1))
  total <- sequential_sum(weights)
  heights_match <- all(abs(sort(weights, method = "radix") - single$tree$heights) <= 1e-9)
  linked <- matrix(FALSE, n, n)
  for (edge in edges) linked[edge$parent, edge$child] <- linked[edge$child, edge$parent] <- TRUE
  nn_edges <- sum(vapply(seq_len(n), function(i) linked[i, study$neighbors[i]], logical(1)))
  lines <- paste("mst total", real_text(total), "heights", if (heights_match) "match" else "mismatch", "nn_edges", paste0(nn_edges, "/", n))
  ordered <- edges[order(weights, seq_along(edges), method = "radix")]
  for (position in seq_along(study$settings$cut_counts)) {
    k <- study$settings$cut_counts[position]
    component <- connected_components(n, head(ordered, n - k))
    partition <- single$count_cuts[[position]]$partition
    agrees <- TRUE
    for (i in seq_len(n - 1)) for (j in seq.int(i + 1, n)) if ((component[i] == component[j]) != (partition[i] == partition[j])) agrees <- FALSE
    lines <- c(lines, paste("mst partition k", k, if (agrees) "match" else "mismatch"))
  }
  lines
}
compare_part <- function(study) {
  method <- study$settings$compare_linkage
  label_count <- length(study$classes)
  lines <- paste("compare linkage", method, "k", label_count)
  for (kind in distance_types) {
    delta <- distance_matrix(study$vectors, kind)
    tree <- new_tree(agglomerate(delta, method), study$count)
    coefficient <- correlation(pair_values(delta), pair_values(tree_cophenetic(tree)))
    partition <- tree_cut_into(tree, label_count)
    lines <- c(lines, paste("metric", kind, "cophenetic", real_text(coefficient), "silhouette", real_text(mean_silhouette(partition, delta)), "ari", ari_text(label_ari(study, partition))))
  }
  lines
}
cophenetic_part <- function(study) {
  names <- vapply(study$results, function(result) result$method, character(1))
  lines <- c("cophenetic_matrix", paste("linkage", paste(names, collapse = " ")))
  for (first in study$results) lines <- c(lines, paste(first$method, reals(vapply(study$results, function(second) correlation(first$cophenetic, second$cophenetic), numeric(1)))))
  lines
}
agreement_part <- function(study) {
  names <- vapply(study$results, function(result) result$method, character(1))
  lines <- c(paste("agreement k", length(study$classes)), paste("linkage", paste(names, collapse = " ")))
  for (first in study$results) lines <- c(lines, paste(first$method, reals(vapply(study$results, function(second) ari_value(partition_ari(first$label_partition, second$label_partition)), numeric(1)))))
  lines
}
summary_part <- function(study) {
  coefficients <- vapply(study$results, function(result) result$coefficient, numeric(1))
  ranking <- ranked_indices(coefficients, TRUE, TRUE)
  names <- vapply(study$results[ranking], function(result) result$method, character(1))
  lines <- c("summary", paste("cophenetic_ranking", paste(names, collapse = " ")))
  for (position in seq_along(study$settings$cut_counts)) {
    best <- study$results[[1]]
    for (result in study$results[-1]) if (ari_greater(result$count_cuts[[position]]$ari, best$count_cuts[[position]]$ari)) best <- result
    lines <- c(lines, paste("best_ari k", study$settings$cut_counts[position], best$method, ari_text(best$count_cuts[[position]]$ari)))
  }
  for (result in study$results) {
    values <- vapply(result$count_cuts, function(cut) cut$silhouette, numeric(1))
    best <- which.max(four_digit(values))
    lines <- c(lines, paste("best_silhouette", result$method, "k", study$settings$cut_counts[best], real_text(values[best])))
  }
  c(lines, paste("selected", study$chosen$method, "k", study$kappa))
}
validation_report <- function(study) {
  parts <- list(data_part(study), correlation_part(study), histogram_part(study))
  for (result in study$results) parts[[length(parts) + 1]] <- linkage_part(study, result)
  if (!is.null(result_of(study, "single"))) parts[[length(parts) + 1]] <- mst_part(study)
  cparts <- list(compare_part(study), cophenetic_part(study), agreement_part(study), summary_part(study))
  join_parts(c(parts, cparts))
}
separation <- function(study, first, second) {
  best <- Inf
  for (i in first) for (j in second) best <- min(best, study$distances[i, j])
  best
}
cluster_lines <- function(study, g) {
  group <- study$members[[g]]
  size <- length(group)
  silhouette <- sequential_sum(study$silhouettes[group]) / size
  majority <- study$majority[g]
  majority_count <- study$table[g, majority]
  means <- vapply(seq_along(study$feature_names), function(f) sequential_sum(study$raw[group, f]) / size, numeric(1))
  medoid <- 0L
  medoid_sum <- 0
  for (i in group) {
    total <- sequential_sum(study$distances[i, group])
    if (!medoid || total < medoid_sum) {
      medoid <- i
      medoid_sum <- total
    }
  }
  diameter <- "0.0000 - -"
  widest <- NULL
  if (size > 1) for (position in seq_len(size - 1)) for (j in group[seq.int(position + 1, size)]) {
    i <- group[position]
    if (is.null(widest) || study$distances[i, j] > study$distances[widest[1], widest[2]]) widest <- c(i, j)
  }
  if (!is.null(widest)) diameter <- pair_text(study, widest[1], widest[2])
  nearest <- 0L
  nearest_separation <- 0
  for (h in seq_len(study$kappa)) if (h != g) {
    value <- separation(study, group, study$members[[h]])
    if (!nearest || value < nearest_separation) {
      nearest <- h
      nearest_separation <- value
    }
  }
  c(paste("cluster", g, "size", size, "silhouette", real_text(silhouette), "majority", study$classes[majority], "purity", paste0(majority_count, "/", size), real_text(majority_count / size)),
    paste("  mean", reals(means)), paste("  medoid", study$idents[medoid], "diameter", diameter, "nearest", nearest, "separation", real_text(nearest_separation)))
}
selection_part <- function(study) {
  lines <- paste("selected linkage", study$chosen$method, "k", study$kappa, "ari", ari_text(study$selected_cut$ari), "silhouette", real_text(study$selected_cut$silhouette))
  for (g in seq_len(study$kappa)) lines <- c(lines, cluster_lines(study, g))
  lines
}
centroid_part <- function(study) {
  centers <- centroids(study, study$selected)
  lines <- "centroid_distances"
  for (g in seq_along(centers)) lines <- c(lines, paste(g, reals(vapply(centers, function(second) sqrt(squared_distance(centers[[g]], second)), numeric(1)))))
  lines
}
profile_part <- function(study) {
  name_width <- max(nchar(study$feature_names))
  lines <- "profile_bars"
  for (g in seq_len(study$kappa)) {
    group <- study$members[[g]]
    lines <- c(lines, paste("cluster", g))
    for (f in seq_along(study$feature_names)) {
      zeta <- sequential_sum((study$raw[group, f] - study$means[f]) / study$deviations[f]) / length(group)
      length <- min(10, floor(abs(zeta) * 4))
      bar <- strrep("#", length)
      left <- if (zeta < 0) paste0(strrep(" ", 10 - length), bar) else strrep(" ", 10)
      right <- if (zeta < 0) strrep(" ", 10) else paste0(bar, strrep(" ", 10 - length))
      name <- study$feature_names[f]
      lines <- c(lines, paste0(name, strrep(" ", name_width - nchar(name)), " ", left, "|", right, " ", real_text(zeta)))
    }
  }
  lines
}
contingency_part <- function(study) {
  lines <- c("contingency", paste("cluster", paste(study$classes, collapse = " "), "total"))
  totals <- numeric(length(study$classes))
  for (g in seq_len(nrow(study$table))) {
    row <- study$table[g, ]
    totals <- totals + row
    lines <- c(lines, paste(g, integers(row), sum(row)))
  }
  matches <- match_count(study, study$selected)
  c(lines, paste("total", integers(totals), study$count), paste("purity", paste0(matches, "/", study$count), real_text(matches / study$count)))
}
misplaced_part <- function(study) {
  lines <- "misplaced"
  count <- 0
  for (i in seq_len(study$count)) {
    majority <- study$majority[study$selected[i]]
    if (study$targets[i] != majority) {
      count <- count + 1
      lines <- c(lines, paste(study$idents[i], "label", study$labels[i], "cluster", study$selected[i], "majority", study$classes[majority]))
    }
  }
  c(lines, paste("count", count))
}
weakest_part <- function(study) {
  lines <- "weakest"
  for (i in head(ranked_indices(study$silhouettes, FALSE, FALSE), study$settings$list_size)) lines <- c(lines, paste(study$idents[i], "label", study$labels[i], "cluster", study$selected[i], "silhouette", real_text(study$silhouettes[i])))
  lines
}
feature_part <- function(study) {
  ratios <- numeric(length(study$feature_names))
  for (f in seq_along(study$feature_names)) {
    values <- study$vectors[, f]
    overall <- sequential_sum(values) / study$count
    means <- vapply(study$members, function(group) sequential_sum(values[group]) / length(group), numeric(1))
    between <- 0
    for (g in seq_len(study$kappa)) between <- between + length(study$members[[g]]) * (means[g] - overall) * (means[g] - overall)
    within <- 0
    for (i in seq_len(study$count)) within <- within + (values[i] - means[study$selected[i]]) * (values[i] - means[study$selected[i]])
    ratios[f] <- (between / (study$kappa - 1)) / (within / (study$count - study$kappa))
  }
  ranking <- ranked_indices(ratios, TRUE, TRUE)
  lines <- "features"
  for (rank in seq_along(ranking)) {
    f <- ranking[rank]
    lines <- c(lines, paste(rank, study$feature_names[f], "f_ratio", real_text(ratios[f])))
  }
  lines
}
class_counts <- function(study, tree, node) {
  counts <- tabulate(study$targets[tree$members[[node]]], nbins = length(study$classes))
  paste(counts, collapse = "/")
}
top_merges_part <- function(study) {
  tree <- study$chosen$tree
  lines <- "top_merges"
  for (step in seq.int(study$count - study$settings$inconsistency_count, study$count - 1)) {
    merge <- tree$merges[[step]]
    lines <- c(lines, paste("step", step, "height", real_text(merge$height), "a", merge$a - 1, length(tree$members[[merge$a]]), class_counts(study, tree, merge$a),
                           "b", merge$b - 1, length(tree$members[[merge$b]]), class_counts(study, tree, merge$b)))
  }
  lines
}
drop_feature_part <- function(study) {
  lines <- "drop_feature"
  for (f in seq_along(study$feature_names)) {
    reduced <- study$vectors[, -f, drop = FALSE]
    partition <- tree_cut_into(new_tree(agglomerate(distance_matrix(reduced, study$settings$distance), study$chosen$method), study$count), study$kappa)
    lines <- c(lines, paste(study$feature_names[f], "ari_selected", ari_text(partition_ari(partition, study$selected)), "ari_labels", ari_text(label_ari(study, partition))))
  }
  lines
}
nearest_center <- function(vector, centers) {
  best <- 1L
  best_value <- squared_distance(vector, centers[[1]])
  if (length(centers) > 1) for (g in seq.int(2, length(centers))) {
    value <- squared_distance(vector, centers[[g]])
    if (value < best_value) {
      best <- g
      best_value <- value
    }
  }
  as.integer(best)
}
refinement_part <- function(study) {
  limit <- study$settings$refine_iterations
  centers <- centroids(study, study$selected)
  previous <- study$selected
  iterations <- limit
  for (t in seq_len(limit)) {
    assignment <- vapply(seq_len(study$count), function(i) nearest_center(study$vectors[i, ], centers), integer(1))
    if (all(assignment == previous)) {
      iterations <- t
      previous <- assignment
      break
    }
    members <- cluster_members(assignment, study$kappa)
    for (g in seq_len(study$kappa)) if (length(members[[g]])) centers[[g]] <- centroid(study$vectors[members[[g]], , drop = FALSE])
    previous <- assignment
  }
  changed <- sum(previous != study$selected)
  sizes <- vapply(cluster_members(previous, study$kappa), length, integer(1))
  c(paste("refinement max_iterations", limit), paste("iterations", iterations, "changed", changed, "wss", real_text(within_sum(study, study$selected)), "->", real_text(within_sum(study, previous))),
    paste("sizes", integers(sizes), "silhouette", real_text(mean_silhouette(previous, study$distances))),
    paste("ari_selected", ari_text(partition_ari(previous, study$selected)), "ari_labels", ari_text(label_ari(study, previous))))
}
jaccard <- function(study, sample_partition, restricted) {
  table <- contingency_table(restricted, sample_partition, study$kappa, max(sample_partition))
  columns <- colSums(table)
  values <- numeric(study$kappa)
  for (g in seq_len(study$kappa)) {
    row <- table[g, ]
    size <- sum(row)
    best <- new_fraction(0, 1)
    if (size > 0) for (h in seq_along(row)) {
      candidate <- new_fraction(row[h], size + columns[h] - row[h])
      if (ari_greater(candidate, best)) best <- candidate
    }
    values[g] <- ari_value(best)
  }
  values
}
stability_part <- function(study) {
  settings <- study$settings
  n <- study$count
  draw <- new_minstd(settings$seed)
  size <- (n * settings$percent) %/% 100
  aris <- numeric()
  jaccards <- list()
  lines <- paste("stability replicates", settings$replicates, "percent", settings$percent, "seed", integer_text(settings$seed))
  for (b in seq_len(settings$replicates)) {
    array <- seq_len(n)
    for (t in seq_len(size)) {
      j <- t + draw() %% (n - t + 1)
      saved <- array[t]
      array[t] <- array[j]
      array[j] <- saved
    }
    sample <- sort(array[seq_len(size)], method = "radix")
    delta <- study$distances[sample, sample, drop = FALSE]
    partition <- tree_cut_into(new_tree(agglomerate(delta, study$chosen$method), size), study$kappa)
    restricted <- study$selected[sample]
    ari <- partition_ari(partition, restricted)
    values <- jaccard(study, partition, restricted)
    aris <- c(aris, ari_value(ari))
    jaccards[[b]] <- values
    lines <- c(lines, paste("replicate", b, "size", size, "ari", ari_text(ari), "jaccard", reals(values)))
  }
  means <- vapply(seq_len(study$kappa), function(g) sequential_sum(vapply(jaccards, function(row) row[g], numeric(1))) / settings$replicates, numeric(1))
  c(lines, paste("mean_ari", real_text(sequential_sum(aris) / settings$replicates)), paste("mean_jaccard", reals(means)))
}
distance_map_part <- function(study) {
  order <- study$chosen$tree$order
  frame <- paste0("+", strrep("-", study$count), "+")
  shades <- strsplit("@%#*+=-:. ", "", fixed = TRUE)[[1]]
  lines <- c(paste("distance_map", study$chosen$method), frame)
  for (u in order) {
    row <- vapply(order, function(w) shades[histogram_bin(study$distances[u, w], study$distance_max) + 1], character(1))
    lines <- c(lines, paste0("|", paste(row, collapse = ""), "|"))
  }
  c(lines, frame)
}
profiles_report <- function(study) {
  join_parts(list(selection_part(study), centroid_part(study), profile_part(study), contingency_part(study), misplaced_part(study),
                  weakest_part(study), feature_part(study), top_merges_part(study), drop_feature_part(study), refinement_part(study), stability_part(study), distance_map_part(study)))
}
main <- function() {
  data <- read_observations()
  study <- new_study(data$feature_names, data$observations, new_settings(read_settings()))
  dir.create("output", showWarnings = FALSE, recursive = TRUE)
  write_lines("linkage.csv", linkage_table(study))
  write_lines("clusters.csv", clusters_table(study))
  write_lines("dendrogram.txt", dendrogram_report(study))
  write_lines("trees.txt", trees_report(study))
  write_lines("validation.txt", validation_report(study))
  write_lines("profiles.txt", profiles_report(study))
}
main()
