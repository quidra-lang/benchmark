script_args <- grep("^--file=", commandArgs(), value = TRUE)
source_dir <- if (length(script_args)) dirname(sub("^--file=", "", script_args[1L])) else "R"
for (unit in c("dataset", "impurity", "tree_builder", "evaluation", "pruning")) {
  source(file.path(source_dir, paste0(unit, ".R")))
}

minstd <- function(seed) {
  state <- as.numeric(seed)
  function() {
    state <<- (48271 * state) %% 2147483647
    state
  }
}

counts_text <- function(counts) paste(integer_text(counts), collapse = " ")

join_sections <- function(sections) {
  result <- character()
  for (index in seq_along(sections)) {
    if (index > 1L) result <- c(result, "")
    result <- c(result, sections[[index]])
  }
  result
}

direction_text <- function(left) if (left) "left" else "right"

simplify <- function(steps, attributes) {
  conditions <- list()
  for (attribute in attributes) {
    related <- Filter(function(step) step$split$attribute$index == attribute$index, steps)
    if (!length(related)) next
    condition <- list(attribute = attribute, lower = NULL, upper = NULL, equal = NULL, excluded = numeric())
    for (step in related) {
      point <- step$split$point
      if (attribute$integer) {
        if (step$left) condition$upper <- if (is.null(condition$upper)) point else min(condition$upper, point)
        else condition$lower <- if (is.null(condition$lower)) point else max(condition$lower, point)
      } else if (step$left) condition$equal <- point
      else condition$excluded <- unique(c(condition$excluded, point))
    }
    condition$excluded <- sort(condition$excluded, method = "radix")
    conditions[[length(conditions) + 1L]] <- condition
  }
  conditions
}

condition_text <- function(condition) {
  attribute <- condition$attribute
  if (attribute$integer) {
    if (!is.null(condition$lower) && !is.null(condition$upper)) {
      return(paste(half_text(condition$lower), "<", attribute$name, "<=", half_text(condition$upper)))
    }
    if (!is.null(condition$lower)) return(paste(attribute$name, ">", half_text(condition$lower)))
    return(paste(attribute$name, "<=", half_text(condition$upper)))
  }
  if (!is.null(condition$equal)) return(paste(attribute$name, "=", attribute$values[condition$equal]))
  names <- attribute$values[condition$excluded]
  if (length(names) == 1L) paste(attribute$name, "!=", names[1L])
  else paste0(attribute$name, " not in {", paste(names, collapse = ","), "}")
}

conditions_text <- function(conditions) {
  if (!length(conditions)) "true" else paste(vapply(conditions, condition_text, character(1L)), collapse = " and ")
}

holds <- function(condition, row) {
  value <- row$values[condition$attribute$index]
  if (is.na(value)) return(FALSE)
  if (condition$attribute$integer) {
    return((is.null(condition$lower) || 2 * value > condition$lower) &&
           (is.null(condition$upper) || 2 * value <= condition$upper))
  }
  if (!is.null(condition$equal)) value == condition$equal else !value %in% condition$excluded
}

coverage <- function(conditions, rows, label) {
  hits <- 0
  covered <- 0
  for (row in rows) {
    if (!all(vapply(conditions, function(condition) holds(condition, row), logical(1L)))) next
    covered <- covered + 1
    if (row$label == label) hits <- hits + 1
  }
  c(hits, covered)
}

laplace <- function(conditions, rows, label, classes) coverage(conditions, rows, label) + c(1, classes)

generalize <- function(conditions, rows, label, classes) {
  current <- conditions
  removed <- character()
  while (length(current)) {
    estimate <- laplace(current, rows, label, classes)
    best <- NULL
    best_index <- 1L
    for (index in seq_along(current)) {
      value <- laplace(current[-index], rows, label, classes)
      if (is.null(best) || compare_fractions(value, best) > 0L) {
        best <- value
        best_index <- index
      }
    }
    if (compare_fractions(estimate, best) > 0L) break
    removed <- c(removed, current[[best_index]]$attribute$name)
    current <- current[-best_index]
  }
  list(conditions = current, removed = removed)
}

build_rules <- function(tree, data) {
  rules <- list()
  collect <- function(node, steps) {
    if (is_leaf(node, tree)) {
      conditions <- simplify(steps, data$attributes)
      general <- generalize(conditions, data$validation, node$stats$majority, length(data$classes))
      rules[[length(rules) + 1L]] <<- list(number = length(rules) + 1L, leaf = node,
          conditions = conditions, general = general$conditions, removed = general$removed)
    } else {
      collect(node$left, c(steps, list(list(split = node$split, left = TRUE))))
      collect(node$right, c(steps, list(list(split = node$split, left = FALSE))))
    }
  }
  collect(tree$root, list())
  rules
}

limited <- function(tree, depth) {
  selected <- Filter(function(node) node$depth == depth, internal_nodes(tree))
  tree_view(tree$root, vapply(selected, function(node) node$number, numeric(1L)))
}

accuracy <- function(tree, rows) ratio_text(correct_count(tree, rows), length(rows))

bagging <- function(data) {
  draw <- minstd(data$settings$bag_seed)
  size <- length(data$train)
  classes <- length(data$classes)
  votes <- matrix(0, nrow = size, ncol = classes)
  bags <- list()
  for (bag in seq_len(data$settings$bag_trees)) {
    indices <- vapply(seq_len(size), function(index) draw() %% size + 1, numeric(1L))
    tree <- tree_view(grow_tree(data$train[indices], data$attributes, classes, data$settings))
    sampled <- unique(indices)
    outside <- setdiff(seq_len(size), sampled)
    correct <- 0
    for (index in outside) {
      prediction <- predict_tree(tree, data$train[[index]])
      votes[index, prediction] <- votes[index, prediction] + 1
      if (prediction == data$train[[index]]$label) correct <- correct + 1
    }
    bags[[length(bags) + 1L]] <- list(tree = tree, distinct = length(sampled), outside = length(outside), correct = correct)
  }
  list(bags = bags, votes = votes)
}

build_analysis <- function(data) {
  a <- list(data = data)
  a$grown <- tree_view(grow_tree(data$train, data$attributes, length(data$classes), data$settings))
  pruning <- reduced_error_pruning(a$grown$root, data$validation)
  a$pruned <- pruning$tree
  a$decisions <- pruning$decisions
  a$rules <- build_rules(a$pruned, data)
  a$bounds <- (seq.int(0, data$settings$folds) * length(data$train)) %/% data$settings$folds
  a$fold_trees <- list()
  a$fold_rows <- list()
  for (fold in seq_len(data$settings$folds)) {
    indices <- seq_len(length(data$train))
    held <- indices > a$bounds[fold] & indices <= a$bounds[fold + 1L]
    a$fold_rows[[fold]] <- data$train[held]
    a$fold_trees[[fold]] <- tree_view(grow_tree(data$train[!held], data$attributes, length(data$classes), data$settings))
  }
  a$depths <- list()
  a$selected_depth <- 1L
  for (depth in seq.int(0, data$settings$max_depth)) {
    correct <- 0
    for (fold in seq_along(a$fold_trees)) {
      correct <- correct + correct_count(limited(a$fold_trees[[fold]], depth), a$fold_rows[[fold]])
    }
    a$depths[[depth + 1L]] <- list(depth = depth, tree = limited(a$grown, depth), correct = correct)
    if (correct > a$depths[[a$selected_depth]]$correct) a$selected_depth <- depth + 1L
  }
  a$sequence <- cost_complexity_sequence(a$grown$root)
  a$selected_index <- 1L
  for (index in seq_along(a$sequence)) {
    errors <- length(data$validation) - correct_count(a$sequence[[index]]$tree, data$validation)
    selected_errors <- length(data$validation) - correct_count(a$sequence[[a$selected_index]]$tree, data$validation)
    if (errors <= selected_errors) a$selected_index <- index
  }
  bag <- bagging(data)
  a$bags <- bag$bags
  a$oob_votes <- bag$votes
  a$test_votes <- matrix(0, nrow = length(data$test), ncol = length(data$classes))
  for (index in seq_along(data$test)) {
    for (bag in a$bags) {
      prediction <- predict_tree(bag$tree, data$test[[index]])
      a$test_votes[index, prediction] <- a$test_votes[index, prediction] + 1
    }
  }
  models <- list(grown = a$grown, pruned = a$pruned, depth = a$depths[[a$selected_depth]]$tree,
                 cost_complexity = a$sequence[[a$selected_index]]$tree)
  a$predictions <- lapply(models, function(tree) vapply(data$test, function(row) predict_tree(tree, row), integer(1L)))
  a$predictions$bagging <- vapply(seq_along(data$test), function(index) majority(a$test_votes[index, ]), integer(1L))
  a
}

tree_lines <- function(a, tree) {
  lines <- character()
  visit <- function(node, condition) {
    text <- paste0(strrep("  ", node$depth), node$number, " ", condition,
                   " n ", node$stats$size, " counts ", counts_text(node$stats$counts))
    if (is_leaf(node, tree)) lines <<- c(lines, paste(text, "leaf", a$data$classes[node$stats$majority]))
    else {
      lines <<- c(lines, text)
      visit(node$left, split_text(node$split, TRUE))
      visit(node$right, split_text(node$split, FALSE))
    }
  }
  visit(tree$root, "root")
  nodes <- preorder(tree)
  leaf_nodes <- leaves(tree)
  depth <- tree_depth(tree)
  lines <- c(lines, "", paste("nodes", length(nodes), "leaves", length(leaf_nodes), "depth", depth,
                              "errors", ratio_text(training_errors(tree), length(a$data$train))))
  for (level in seq.int(0, depth)) {
    at_level <- Filter(function(node) node$depth == level, nodes)
    level_leaves <- Filter(function(node) is_leaf(node, tree), at_level)
    rows <- sum(vapply(level_leaves, function(node) node$stats$size, numeric(1L)))
    errors <- sum(vapply(level_leaves, function(node) node$stats$errors, numeric(1L)))
    lines <- c(lines, paste("level", level, "nodes", length(at_level), "leaves", length(level_leaves), "rows", rows, "errors", errors))
  }
  lines
}

root_candidate_lines <- function(a) {
  data <- a$data
  found <- list()
  for (attribute in data$attributes) {
    candidate <- best_for_attribute(data$train, attribute, length(data$classes), data$settings)
    if (is.null(candidate)) next
    position <- length(found) + 1L
    found[[position]] <- candidate
    while (position > 1L && compare_fractions(candidate$value, found[[position - 1L]]$value) > 0L) {
      found[[position]] <- found[[position - 1L]]
      position <- position - 1L
    }
    found[[position]] <- candidate
  }
  size <- length(data$train)
  lines <- paste("root candidates n", size, "counts", counts_text(a$grown$root$stats$counts))
  for (index in seq_along(found)) {
    candidate <- found[[index]]
    gain <- candidate$value[1L] / candidate$value[2L] / size - a$grown$root$stats$squares / (size * size)
    lines <- c(lines, paste(index, split_text(candidate$split, TRUE), "left", length(candidate$left),
                            "right", length(candidate$right), "gain", real_text(gain, 6L)))
  }
  lines
}

surrogate_lines <- function(a) {
  lines <- "surrogates"
  for (node in internal_nodes(a$grown)) {
    parts <- vapply(node$surrogates, function(surrogate) {
      paste(split_text(surrogate$split, TRUE), direction_text(surrogate$left), paste0(surrogate$score, "/", node$stats$size))
    }, character(1L))
    listed <- if (length(parts)) paste(parts, collapse = " ; ") else "none"
    lines <- c(lines, paste("node", node$number, "split", split_text(node$split, TRUE),
                            "default", direction_text(node$default_left), "surrogates", listed))
  }
  lines
}

pruning_lines <- function(a) {
  lines <- paste("reduced_error_pruning validation", length(a$data$validation))
  count <- 0
  for (decision in a$decisions) {
    if (decision$pruned) count <- count + 1
    lines <- c(lines, paste("node", decision$node$number, "depth", decision$node$depth, "rows", decision$rows,
                            "leaf", decision$leaf_error, "subtree", decision$subtree_error,
                            if (decision$pruned) "pruned" else "kept"))
  }
  c(lines, paste("examined", length(a$decisions), "pruned", count, "kept", length(a$decisions) - count))
}

prediction_lines <- function(a) {
  lines <- "id,predicted,actual,grown,leaf,path,missing"
  data <- a$data
  for (row in data$test) {
    result <- route(a$pruned, row)
    path <- paste(vapply(result$path, function(node) node$number, numeric(1L)), collapse = "-")
    missing <- sum(vapply(result$steps, function(step) step$method != "primary", logical(1L)))
    lines <- c(lines, paste(c(row$id, data$classes[result$leaf$stats$majority], data$classes[row$label],
        data$classes[predict_tree(a$grown, row)], result$leaf$number, path, missing), collapse = ","))
  }
  lines
}

rule_lines <- function(a) {
  lines <- paste("rules", length(a$rules))
  for (rule in a$rules) {
    reached <- Filter(function(row) route(a$pruned, row)$leaf$number == rule$leaf$number, a$data$test)
    label <- rule$leaf$stats$majority
    hits <- sum(vapply(reached, function(row) row$label == label, logical(1L)))
    lines <- c(lines, paste("rule", rule$number, "node", rule$leaf$number, "if", conditions_text(rule$conditions),
        "then", a$data$classes[label], "train", ratio_text(rule$leaf$stats$counts[label], rule$leaf$stats$size),
        "test", ratio_text(hits, length(reached))))
  }
  lines
}

generalized_lines <- function(a) {
  lines <- paste("generalized", length(a$rules))
  for (rule in a$rules) {
    label <- rule$leaf$stats$majority
    counts <- coverage(rule$general, a$data$validation, label)
    test <- coverage(rule$general, a$data$test, label)
    removed <- if (length(rule$removed)) paste(rule$removed, collapse = ",") else "none"
    lines <- c(lines, paste("general", rule$number, "if", conditions_text(rule$general), "then", a$data$classes[label],
        "removed", removed, "laplace", fraction_text(counts[1L] + 1, counts[2L] + length(a$data$classes)),
        "validation", paste(counts, collapse = "/"), "test", paste(test, collapse = "/")))
  }
  lines
}

misclassified_lines <- function(a) {
  numbers <- setNames(vapply(a$rules, function(rule) rule$number, integer(1L)),
                      vapply(a$rules, function(rule) as.character(rule$leaf$number), character(1L)))
  records <- character()
  for (row in a$data$test) {
    result <- route(a$pruned, row)
    label <- result$leaf$stats$majority
    if (label == row$label) next
    parts <- vapply(result$steps, function(step) {
      paste0(split_text(step$node$split, step$left), if (step$method == "primary") "" else paste0(" [", step$method, "]"))
    }, character(1L))
    explanation <- if (length(parts)) paste(parts, collapse = "; ") else "root"
    records <- c(records, paste(row$id, "actual", a$data$classes[row$label], "predicted", a$data$classes[label],
        "rule", numbers[[as.character(result$leaf$number)]], "path", explanation))
  }
  c(paste("misclassified", length(records)), records)
}
data_lines <- function(a) {
  data <- a$data
  counts <- lapply(list(data$train, data$validation, data$test), function(rows) statistics(rows, length(data$classes))$counts)
  lines <- paste("data train", length(data$train), "validation", length(data$validation), "test", length(data$test),
                 "attributes", length(data$attributes), "classes", length(data$classes), "target", data$target)
  for (index in seq_along(data$classes)) {
    lines <- c(lines, paste("class", data$classes[index], "train", counts[[1L]][index],
                            "validation", counts[[2L]][index], "test", counts[[3L]][index]))
  }
  missing <- lapply(list(data$validation, data$test), function(rows) {
    vapply(data$attributes, function(attribute) sum(vapply(rows, function(row) is.na(row$values[attribute$index]), logical(1L))), numeric(1L))
  })
  lines <- c(lines, paste("missing validation", sum(missing[[1L]]), "test", sum(missing[[2L]])))
  for (index in seq_along(data$attributes)) {
    lines <- c(lines, paste("missing", data$attributes[[index]]$name, "validation", missing[[1L]][index], "test", missing[[2L]][index]))
  }
  lines
}

summary_line <- function(a, name, tree) {
  paste(name, "nodes", length(preorder(tree)), "leaves", length(leaves(tree)), "depth", tree_depth(tree),
        "train", accuracy(tree, a$data$train), "validation", accuracy(tree, a$data$validation), "test", accuracy(tree, a$data$test))
}

model_evaluation <- function(a, model) classification_lines(paste(model, "test"), a$data$classes, a$data$test, a$predictions[[model]])

routing_lines <- function(a) {
  nodes <- internal_nodes(a$pruned)
  tally <- matrix(0, nrow = max(vapply(preorder(a$pruned), function(node) node$number, numeric(1L))), ncol = 3L)
  groups <- list(list(), list())
  for (row in a$data$test) {
    for (step in route(a$pruned, row)$steps) {
      method <- match(step$method, c("primary", "surrogate", "default"))
      tally[step$node$number, method] <- tally[step$node$number, method] + 1
    }
    group <- if (anyNA(row$values)) 2L else 1L
    groups[[group]][[length(groups[[group]]) + 1L]] <- row
  }
  lines <- "routing pruned test"
  for (node in nodes) {
    counts <- tally[node$number, ]
    lines <- c(lines, paste("node", node$number, "rows", sum(counts), "primary", counts[1L],
                            "surrogate", counts[2L], "default", counts[3L]))
  }
  c(lines, paste("complete rows", length(groups[[1L]]), "correct", accuracy(a$pruned, groups[[1L]])),
    paste("incomplete rows", length(groups[[2L]]), "correct", accuracy(a$pruned, groups[[2L]])))
}

cross_validation_lines <- function(a) {
  lines <- paste("cross_validation folds", a$data$settings$folds)
  total <- 0
  for (index in seq_along(a$fold_trees)) {
    tree <- a$fold_trees[[index]]
    rows <- a$fold_rows[[index]]
    correct <- correct_count(tree, rows)
    total <- total + correct
    lines <- c(lines, paste("fold", index, "rows", paste0(a$bounds[index] + 1, "-", a$bounds[index + 1L]),
                            "leaves", length(leaves(tree)), "correct", ratio_text(correct, length(rows))))
  }
  c(lines, paste("cv accuracy", ratio_text(total, length(a$data$train))))
}

depth_lines <- function(a) {
  lines <- "depth_selection"
  for (result in a$depths) {
    tree <- result$tree
    lines <- c(lines, paste("depth", result$depth, "leaves", length(leaves(tree)), "cv", ratio_text(result$correct, length(a$data$train)),
        "train", accuracy(tree, a$data$train), "validation", accuracy(tree, a$data$validation), "test", accuracy(tree, a$data$test)))
  }
  selected <- a$depths[[a$selected_depth]]
  c(lines, paste("selected depth", selected$depth, "leaves", length(leaves(selected$tree)), "test", accuracy(selected$tree, a$data$test)))
}

complexity_lines <- function(a) {
  lines <- "cost_complexity"
  for (index in seq_along(a$sequence)) {
    step <- a$sequence[[index]]
    alpha <- fraction_text(step$alpha[1L], step$alpha[2L] * length(a$data$train), 6L)
    errors <- length(a$data$validation) - correct_count(step$tree, a$data$validation)
    lines <- c(lines, paste("subtree", index - 1L, "alpha", alpha, "leaves", length(leaves(step$tree)),
                            "train_errors", training_errors(step$tree), "validation_errors", errors))
  }
  selected <- a$sequence[[a$selected_index]]$tree
  c(lines, paste("selected subtree", a$selected_index - 1L, "leaves", length(leaves(selected)), "test", accuracy(selected, a$data$test)))
}

bagging_lines <- function(a) {
  lines <- paste("bagging trees", a$data$settings$bag_trees, "seed", integer_text(a$data$settings$bag_seed))
  for (index in seq_along(a$bags)) {
    bag <- a$bags[[index]]
    lines <- c(lines, paste("bag", index, "distinct", bag$distinct, "leaves", length(leaves(bag$tree)),
                            "oob", ratio_text(bag$correct, bag$outside)))
  }
  voted <- 0
  hits <- 0
  for (index in seq_along(a$data$train)) {
    votes <- a$oob_votes[index, ]
    if (sum(votes) == 0) next
    voted <- voted + 1
    if (majority(votes) == a$data$train[[index]]$label) hits <- hits + 1
  }
  c(lines, paste("oob accuracy", ratio_text(hits, voted), "unvoted", length(a$data$train) - voted), model_evaluation(a, "bagging"))
}

mcnemar_lines <- function(a) {
  lines <- "mcnemar pruned test"
  labels <- vapply(a$data$test, function(row) row$label, integer(1L))
  pruned <- a$predictions$pruned == labels
  for (model in c("grown", "depth", "cost_complexity", "bagging")) {
    other <- a$predictions[[model]] == labels
    b <- as.numeric(sum(pruned & !other))
    c <- as.numeric(sum(other & !pruned))
    difference <- max(0, abs(b - c) - 1)
    numerator <- difference * difference
    statistic <- if (b + c == 0) "0/1 0.0000" else fraction_text(numerator, b + c)
    significant <- if (1000 * numerator > 3841 * (b + c)) "yes" else "no"
    lines <- c(lines, paste("versus", model, "b", b, "c", c, "statistic", statistic, "significant", significant))
  }
  lines
}

model_scores <- function(a, model) {
  if (model == "bagging") {
    return(lapply(seq_along(a$data$test), function(index) list(counts = a$test_votes[index, ], size = a$data$settings$bag_trees)))
  }
  tree <- if (model == "grown") a$grown else a$pruned
  lapply(a$data$test, function(row) route(tree, row)$leaf$stats)
}

auc_lines <- function(a) {
  labels <- vapply(a$data$test, function(row) row$label, integer(1L))
  lines <- character()
  for (model in c("grown", "pruned", "bagging")) {
    scores <- model_scores(a, model)
    fields <- c("auc", model)
    macro <- 0
    defined <- 0
    for (label in seq_along(a$data$classes)) {
      positives <- which(labels == label)
      negatives <- which(labels != label)
      wins <- 0
      for (positive in positives) {
        for (negative in negatives) {
          comparison <- compare_fractions(c(scores[[positive]]$counts[label], scores[[positive]]$size),
                                          c(scores[[negative]]$counts[label], scores[[negative]]$size))
          if (comparison > 0L) wins <- wins + 2
          else if (comparison == 0L) wins <- wins + 1
        }
      }
      denominator <- 2 * length(positives) * length(negatives)
      fields <- c(fields, a$data$classes[label], fraction_text(wins, denominator))
      if (denominator > 0) {
        macro <- macro + wins / denominator
        defined <- defined + 1
      }
    }
    fields <- c(fields, "macro", if (defined == 0) "-" else real_text(macro / defined))
    lines <- c(lines, paste(fields, collapse = " "))
  }
  lines
}

learning_lines <- function(a) {
  data <- a$data
  lines <- "learning_curve"
  for (size in data$settings$curve) {
    grown <- tree_view(grow_tree(data$train[seq_len(size)], data$attributes, length(data$classes), data$settings))
    pruned <- reduced_error_pruning(grown$root, data$validation)$tree
    lines <- c(lines, paste("size", size, "grown leaves", length(leaves(grown)), "test", accuracy(grown, data$test),
                            "pruned leaves", length(leaves(pruned)), "test", accuracy(pruned, data$test)))
  }
  lines
}

impurity_lines <- function(a, title, tree) {
  importance <- numeric(length(a$data$attributes))
  splits <- integer(length(importance))
  for (node in internal_nodes(tree)) {
    index <- node$split$attribute$index
    importance[index] <- importance[index] + impurity_decrease(node$stats, node$left$stats, node$right$stats)
    splits[index] <- splits[index] + 1L
  }
  total <- 0
  for (value in importance) total <- total + value
  shares <- if (total == 0) numeric(length(importance)) else importance / total
  rounded <- as.numeric(vapply(shares, real_text, character(1L)))
  ranking <- order(-rounded, seq_along(importance), method = "radix")
  lines <- paste("impurity", title)
  for (rank in seq_along(ranking)) {
    index <- ranking[rank]
    lines <- c(lines, paste(rank, a$data$attributes[[index]]$name, "decrease", real_text(importance[index] / length(a$data$train)),
                            "share", real_text(shares[index]), "splits", splits[index]))
  }
  lines
}

permutation_lines <- function(a) {
  data <- a$data
  draw <- minstd(data$settings$permutation_seed)
  repeats <- data$settings$permutation_repeats
  size <- length(data$test)
  base <- correct_count(a$pruned, data$test)
  results <- list()
  for (attribute in data$attributes) {
    counts <- numeric(repeats)
    for (repeat_index in seq_len(repeats)) {
      values <- vapply(data$test, function(row) row$values[attribute$index], numeric(1L))
      if (size > 1L) for (position in seq.int(size, 2L)) {
        other <- draw() %% position + 1
        saved <- values[position]
        values[position] <- values[other]
        values[other] <- saved
      }
      rows <- lapply(seq_along(data$test), function(index) {
        row <- data$test[[index]]
        row$values[attribute$index] <- values[index]
        row
      })
      counts[repeat_index] <- correct_count(a$pruned, rows)
    }
    results[[length(results) + 1L]] <- list(attribute = attribute, counts = counts, drop = repeats * base - sum(counts))
  }
  drops <- vapply(results, function(result) result$drop, numeric(1L))
  ranking <- order(-drops, seq_along(results), method = "radix")
  lines <- paste("permutation pruned test repeats", repeats, "seed", integer_text(data$settings$permutation_seed), "base", ratio_text(base, size))
  for (rank in seq_along(ranking)) {
    result <- results[[ranking[rank]]]
    lines <- c(lines, paste(rank, result$attribute$name, "correct", counts_text(result$counts),
                            "drop", fraction_text(result$drop, repeats * size)))
  }
  lines
}

write_sections <- function(name, sections) writeLines(join_sections(sections), file.path("output", name), useBytes = TRUE)

main <- function() {
  a <- build_analysis(load_dataset())
  dir.create("output", showWarnings = FALSE, recursive = TRUE)
  write_sections("tree.txt", list(root_candidate_lines(a), tree_lines(a, a$grown), surrogate_lines(a)))
  write_sections("pruned_tree.txt", list(pruning_lines(a), tree_lines(a, a$pruned)))
  write_sections("predictions.csv", list(prediction_lines(a)))
  write_sections("rules.txt", list(rule_lines(a), generalized_lines(a), misclassified_lines(a)))
  write_sections("evaluation.txt", list(
      data_lines(a), c(summary_line(a, "grown", a$grown), summary_line(a, "pruned", a$pruned)),
      model_evaluation(a, "grown"), model_evaluation(a, "pruned"), routing_lines(a), cross_validation_lines(a),
      depth_lines(a), complexity_lines(a), bagging_lines(a), mcnemar_lines(a), auc_lines(a), learning_lines(a)))
  write_sections("importance.txt", list(impurity_lines(a, "grown", a$grown), impurity_lines(a, "pruned", a$pruned), permutation_lines(a)))
}

main()
