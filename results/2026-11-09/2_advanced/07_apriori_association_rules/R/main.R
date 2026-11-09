script_args <- grep("^--file=", commandArgs(), value = TRUE)
source_dir <- if (length(script_args)) dirname(sub("^--file=", "", script_args[1L])) else "R"
for (unit in c("baskets", "apriori", "fpgrowth", "rules", "report")) source(file.path(source_dir, paste0(unit, ".R")))

SEGMENTS <- c("NEW", "LOYAL", "AT_RISK", "REGULAR")

read_params <- function() {
  values <- list()
  for (line in readLines("input/params.txt", warn = FALSE)) {
    fields <- strsplit(line, " ", fixed = TRUE)[[1L]]
    pieces <- as.numeric(strsplit(fields[2L], "/", fixed = TRUE)[[1L]])
    values[[fields[1L]]] <- if (length(pieces) == 1L) pieces else fraction(pieces[1L], pieces[2L])
  }
  values
}

read_dataset <- function() {
  data <- list(errors = character(), products = list(), transactions = list(), adopted = 0L, rejected = 0L, duplicates = 0L)
  rows <- read_records("items.csv")
  data$item_rows <- length(rows)
  for (index in seq_along(rows)) {
    row <- rows[[index]]
    name <- row[1L]
    price <- as.numeric(row[3L])
    problem <- if (name %in% names(data$products)) paste("duplicate item", name) else if (price == 0) "bad price 0" else ""
    if (nzchar(problem)) {
      data$errors <- c(data$errors, text_line("items.csv line", paste0(index + 1L, ":"), problem))
    } else data$products[[name]] <- product_record(name, row[2L], price)
  }
  rows <- read_records("transactions.csv")
  data$transaction_lines <- length(rows)
  known <- character()
  current <- NULL
  for (index in seq_along(rows)) {
    row <- rows[[index]]
    tid <- row[1L]
    customer <- row[2L]
    day <- as.numeric(row[3L])
    item <- row[4L]
    problem <- ""
    if (tid %in% known && tid != current$tid) {
      problem <- paste("tid", tid, "not contiguous")
    } else {
      if (!tid %in% known) {
        current <- transaction_record(tid, customer, day)
        data$transactions[[length(data$transactions) + 1L]] <- current
        known <- c(known, tid)
      }
      if (customer != current$customer) {
        problem <- paste("tid", tid, "customer", customer, "differs from", current$customer)
      } else if (day != current$day) {
        problem <- text_line("tid", tid, "day", day, "differs from", current$day)
      } else if (!item %in% names(data$products)) problem <- paste("unknown item", item)
    }
    if (nzchar(problem)) {
      data$errors <- c(data$errors, text_line("transactions.csv line", paste0(index + 1L, ":"), problem))
      data$rejected <- data$rejected + 1L
    } else {
      data$adopted <- data$adopted + 1L
      if (add_product(current, item)) data$duplicates <- data$duplicates + 1L
    }
  }
  data
}

sort_records <- function(records, compare) {
  merge <- function(indices) {
    if (length(indices) < 2L) return(indices)
    middle <- integer_divide(length(indices), 2)
    left <- merge(head(indices, middle))
    right <- merge(tail(indices, length(indices) - middle))
    result <- integer(length(indices))
    i <- j <- 1L
    position <- 1L
    while (i <= length(left) && j <= length(right)) {
      if (compare(records[[left[i]]], records[[right[j]]]) <= 0L) {
        result[position] <- left[i]
        i <- i + 1L
      } else {
        result[position] <- right[j]
        j <- j + 1L
      }
      position <- position + 1L
    }
    if (i <= length(left)) result[seq.int(position, length(result))] <- left[seq.int(i, length(left))]
    if (j <= length(right)) result[seq.int(position, length(result))] <- right[seq.int(j, length(right))]
    result
  }
  records[merge(seq_along(records))]
}

size_keys <- function(keys) keys[order(vapply(keys, function(key) length(split_itemset_text(key)), integer(1L)), keys, method = "radix")]
support_in <- function(supports, total, items) if (length(items)) unname(supports[itemset_text(items)]) else total
split_mask <- function(items, mask) {
  included <- bitwAnd(as.integer(mask), bitwShiftL(1L, seq_along(items) - 1L)) != 0L
  list(first = items[included], second = items[!included])
}
exact_median <- function(values) {
  ordered <- sort(values)
  middle <- integer_divide(length(ordered), 2)
  if (length(ordered) == 2 * middle) fraction(ordered[middle] + ordered[middle + 1L], 2) else fraction(ordered[middle + 1L])
}

run_apriori <- function(baskets, universe, minimum, maximum, taxonomy = NULL) {
  previous <- lapply(sort(universe, method = "radix"), function(item) item)
  levels <- list()
  supports <- numeric()
  singles <- numeric()
  size <- 1L
  repeat {
    generation <- if (size == 1L) list(joined = length(previous), excluded = 0L, pruned = 0L, itemsets = previous) else generate_candidates(previous, size, taxonomy)
    candidates <- generation$itemsets
    counts <- count_supports(baskets, candidates)
    if (size == 1L) singles <- setNames(unname(counts), universe[order(universe, method = "radix")])
    previous <- candidates[counts >= minimum]
    levels[[size]] <- list(number = size, candidates = generation$joined, excluded = generation$excluded,
                           pruned = generation$pruned, counted = length(candidates), itemsets = previous)
    supports <- c(supports, counts[counts >= minimum])
    size <- size + 1L
    if (size > maximum || !length(previous)) break
  }
  list(levels = levels, supports = supports, singles = singles)
}

make_rules <- function(supports, total, params, required = NULL) {
  generated <- 0L
  rules <- list()
  for (key in names(supports)) {
    items <- split_itemset_text(key)
    if (length(items) < 2L || (!is.null(required) && !any(items %in% required))) next
    for (mask in seq_len(bitwShiftL(1L, length(items)) - 2L)) {
      split <- split_mask(items, mask)
      first <- split$first
      second <- split$second
      generated <- generated + 1L
      rule <- rule_record(items, first, second, unname(supports[key]), total,
                          support_in(supports, total, first), support_in(supports, total, second))
      if (!meets_thresholds(rule$confidence, rule$lift, params)) next
      reference <- fraction(0)
      for (subset_mask in seq.int(0L, bitwShiftL(1L, length(first)) - 2L)) {
        subset <- split_mask(first, subset_mask)$first
        joined <- sort(c(subset, second), method = "radix")
        candidate <- fraction(support_in(supports, total, joined), support_in(supports, total, subset))
        if (fraction_compare(candidate, reference) > 0L) reference <- candidate
      }
      rule$improvement <- fraction_subtract(rule$confidence, reference)
      rules[[length(rules) + 1L]] <- rule
    }
  }
  rules <- sort_records(rules, rule_compare)
  for (rank in seq_along(rules)) rules[[rank]]$rank <- rank
  list(generated = generated, rules = rules, productive = sum(vapply(rules, function(rule) rule$improvement[1L] > 0, logical(1L))))
}

recommend <- function(held, candidates, limit) {
  result <- character()
  for (item in candidates) {
    if (length(result) == limit) break
    if (!item %in% c(held, result)) result <- c(result, item)
  }
  result
}

rule_candidates <- function(rules, held) unlist(lapply(Filter(function(rule) length(rule$consequent) == 1L && contains(held, rule$antecedent), rules), function(rule) rule$consequent), use.names = FALSE)

analyze_frequent <- function(a) {
  a$main <- run_apriori(a$item_sets, a$product_names, a$params$min_support, a$params$max_size)
  a$frequent <- a$main$supports
  a$counts <- a$main$singles
  a$growth <- fp_growth(lapply(a$item_sets, function(items) list(items = items, weight = 1)), a$params$min_support, a$params$max_size)
  a$closed <- a$maximal <- names(a$frequent)
  a$generators <- character()
  for (key in names(a$frequent)) {
    items <- split_itemset_text(key)
    subsets <- one_smaller_subsets(items)
    count <- unname(a$frequent[key])
    if (all(vapply(subsets, function(subset) support_in(a$frequent, a$total, subset) > count, logical(1L)))) a$generators <- c(a$generators, key)
    for (subset in subsets) if (length(subset)) {
      smaller <- itemset_text(subset)
      a$maximal <- setdiff(a$maximal, smaller)
      if (a$frequent[smaller] == count) a$closed <- setdiff(a$closed, smaller)
    }
  }
  a$closed <- size_keys(a$closed)
  a$maximal <- size_keys(a$maximal)
  a$generators <- size_keys(a$generators)
  a$main_rules <- make_rules(a$frequent, a$total, a$params)
  a$pairs <- lapply(names(a$frequent)[vapply(names(a$frequent), function(key) length(split_itemset_text(key)) == 2L, logical(1L))], split_itemset_text)
  a$extended_sets <- lapply(a$item_sets, extended_basket, taxonomy = a$taxonomy)
  a$category_run <- run_apriori(a$extended_sets, c(a$product_names, a$categories), a$params$category_min_support, a$params$max_size, a$taxonomy)
  a$category_rules <- make_rules(a$category_run$supports, a$total, a$params, a$categories)
}

analyze_sequences <- function(a) {
  a$histories <- setNames(vector("list", length(a$customers)), a$customers)
  a$buyers <- setNames(rep(0, length(a$product_names)), a$product_names)
  gaps <- list()
  intervals <- list()
  repeaters <- setNames(rep(0, length(a$product_names)), a$product_names)
  for (customer in a$customers) {
    history <- list()
    for (basket in a$customer_baskets[[customer]]) for (item in basket_items(basket)) history[[item]] <- c(history[[item]], basket$day)
    history <- lapply(history, function(days) sort(unique(days)))
    a$histories[[customer]] <- history
    for (first in names(history)) {
      a$buyers[first] <- a$buyers[first] + 1
      days <- history[[first]]
      if (length(days) > 1L) {
        intervals[[first]] <- c(intervals[[first]], diff(days))
        repeaters[first] <- repeaters[first] + 1
      }
      for (second in names(history)) if (min(days) < max(history[[second]])) {
        found <- outer(history[[second]], days, "-")
        key <- paste(first, second, sep = "/")
        gaps[[key]] <- c(gaps[[key]], min(found[found > 0]))
      }
    }
  }
  a$sequence_pairs <- length(gaps)
  sequences <- list()
  for (key in names(gaps)) {
    count <- length(gaps[[key]])
    if (count < a$params$sequence_min_support) next
    pair <- strsplit(key, "/", fixed = TRUE)[[1L]]
    sequences[[length(sequences) + 1L]] <- list(first = pair[1L], second = pair[2L], count = count, base = unname(a$buyers[pair[1L]]),
      confidence = fraction(count, a$buyers[pair[1L]]), lift = lift_of(length(a$customers), count, a$buyers[pair[1L]], a$buyers[pair[2L]]), gap = exact_median(gaps[[key]]))
  }
  a$sequences <- sort_records(sequences, function(x, y) {
    if (x$count != y$count) return(sign(y$count - x$count))
    compared <- fraction_compare(y$confidence, x$confidence)
    if (compared) return(compared)
    compared <- string_compare(x$first, y$first)
    if (compared) compared else string_compare(x$second, y$second)
  })
  repeats <- lapply(names(intervals), function(name) {
    found <- intervals[[name]]
    list(name = name, customers = unname(repeaters[name]), count = length(found), minimum = min(found), maximum = max(found), mean = fraction(sum(found), length(found)), median = exact_median(found))
  })
  a$repeats <- sort_records(repeats, function(x, y) {
    compared <- fraction_compare(x$mean, y$mean)
    if (compared) compared else string_compare(x$name, y$name)
  })
}

new_tally <- function() setNames(rep(0, 5L), c("cases", "covered", "hit1", "hit", "baseline"))
add_tally <- function(tally, heldout, suggestion, baseline) tally + c(1, as.integer(length(suggestion) > 0L), as.integer(length(suggestion) > 0L && suggestion[1L] == heldout), as.integer(heldout %in% suggestion), as.integer(heldout %in% baseline))

analyze_validation <- function(a) {
  train <- a$item_sets[vapply(a$baskets, function(basket) basket$day <= a$params$split_day, logical(1L))]
  test <- a$item_sets[vapply(a$baskets, function(basket) basket$day > a$params$split_day, logical(1L))]
  a$train_total <- length(train)
  a$test_total <- length(test)
  a$train_run <- run_apriori(train, a$product_names, a$params$train_min_support, a$params$max_size)
  a$train_rules <- make_rules(a$train_run$supports, length(train), a$params)$rules
  needed <- unlist(lapply(a$train_rules, function(rule) list(rule$antecedent, rule$consequent, rule$itemset)), recursive = FALSE)
  counts <- count_supports(test, needed)
  a$checks <- lapply(a$train_rules, function(rule) {
    first <- support_in(counts, length(test), rule$antecedent)
    second <- support_in(counts, length(test), rule$consequent)
    together <- support_in(counts, length(test), rule$itemset)
    if (first == 0 || second == 0) return(list(rule = rule, first = first, count = together, confidence = NULL, lift = NULL, verdict = "UNSEEN"))
    confidence <- fraction(together, first)
    lift <- lift_of(length(test), together, first, second)
    list(rule = rule, first = first, count = together, confidence = confidence, lift = lift, verdict = if (meets_thresholds(confidence, lift, a$params)) "HOLD" else "FAIL")
  })
  test_run <- run_apriori(test, a$product_names, a$params$test_min_support, a$params$max_size)
  test_rules <- make_rules(test_run$supports, length(test), a$params)$rules
  known <- vapply(a$train_rules, rule_arrow, character(1L))
  a$emerging <- Filter(function(rule) !rule_arrow(rule) %in% known, test_rules)
  popularity <- a$product_names[order(-a$train_run$singles[a$product_names], a$product_names, method = "radix")]
  a$tallies <- list()
  a$overall <- new_tally()
  a$held_out <- a$held_hits <- setNames(rep(0, length(a$product_names)), a$product_names)
  for (items in test) {
    if (length(items) < 2L) next
    key <- as.character(length(items))
    tally <- a$tallies[[key]]
    if (is.null(tally)) tally <- new_tally()
    for (heldout in items) {
      held <- setdiff(items, heldout)
      suggestion <- recommend(held, rule_candidates(a$train_rules, held), a$params$recommend_top)
      baseline <- recommend(held, popularity, a$params$recommend_top)
      tally <- add_tally(tally, heldout, suggestion, baseline)
      a$overall <- add_tally(a$overall, heldout, suggestion, baseline)
      a$held_out[heldout] <- a$held_out[heldout] + 1
      if (heldout %in% suggestion) a$held_hits[heldout] <- a$held_hits[heldout] + 1
    }
    a$tallies[[key]] <- tally
  }
}

pair_lift <- function(a, pair) lift_of(a$total, a$frequent[itemset_text(pair)], a$counts[pair[1L]], a$counts[pair[2L]])

analyze_products <- function(a) {
  a$units <- setNames(rep(0, length(a$product_names)), a$product_names)
  for (basket in a$baskets) a$units[names(basket$counts)] <- a$units[names(basket$counts)] + basket$counts
  prices <- vapply(a$products, function(product) product$price, numeric(1L))
  a$revenue <- a$units * prices[a$product_names]
  a$total_revenue <- sum(a$revenue)
  a$category_summaries <- lapply(a$categories, function(category) {
    members <- a$product_names[a$taxonomy[a$product_names] == category]
    list(name = category, products = length(members), units = sum(a$units[members]), revenue = sum(a$revenue[members]), baskets = unname(a$category_run$singles[category]))
  })
  a$category_summaries <- a$category_summaries[order(-vapply(a$category_summaries, function(summary) summary$revenue, numeric(1L)), a$categories, method = "radix")]
  neighbors <- setNames(vector("list", length(a$product_names)), a$product_names)
  edges <- list()
  for (pair in a$pairs) if (fraction_compare(pair_lift(a, pair), a$params$group_min_lift) >= 0L) {
    edges[[length(edges) + 1L]] <- pair
    neighbors[[pair[1L]]] <- c(neighbors[[pair[1L]]], pair[2L])
    neighbors[[pair[2L]]] <- c(neighbors[[pair[2L]]], pair[1L])
  }
  visited <- character()
  groups <- list()
  for (name in a$product_names) {
    if (name %in% visited || !length(neighbors[[name]])) next
    members <- character()
    stack <- name
    visited <- c(visited, name)
    while (length(stack)) {
      current <- tail(stack, 1L)
      stack <- head(stack, -1L)
      members <- c(members, current)
      added <- setdiff(neighbors[[current]], visited)
      visited <- c(visited, added)
      stack <- c(stack, added)
    }
    members <- sort(members, method = "radix")
    core <- members[order(-vapply(neighbors[members], length, integer(1L)), -a$counts[members], members, method = "radix")][1L]
    groups[[length(groups) + 1L]] <- list(members = members, edges = sum(vapply(edges, function(edge) edge[1L] %in% members, logical(1L))), core = core, revenue = sum(a$revenue[members]))
  }
  a$groups <- groups[order(-vapply(groups, function(group) length(group$members), integer(1L)), vapply(groups, function(group) group$members[1L], character(1L)), method = "radix")]
  singles <- vapply(a$main$levels[[1L]]$itemsets, function(items) items[1L], character(1L))
  candidates <- list()
  for (index in seq_along(singles)) if (index < length(singles)) for (second in singles[seq.int(index + 1L, length(singles))]) {
    first <- singles[index]
    if (a$counts[first] * a$counts[second] >= a$params$negative_min_expected * a$total) candidates[[length(candidates) + 1L]] <- c(first, second)
  }
  counts <- count_supports(a$item_sets, candidates)
  substitutes <- list()
  for (pair in candidates) {
    together <- unname(counts[itemset_text(pair)])
    lift <- lift_of(a$total, together, a$counts[pair[1L]], a$counts[pair[2L]])
    if (fraction_compare(lift, a$params$negative_max_lift) <= 0L) substitutes[[length(substitutes) + 1L]] <- list(first = pair[1L], second = pair[2L], count = together, lift = lift, expected = fraction(a$counts[pair[1L]] * a$counts[pair[2L]], a$total))
  }
  a$substitutes <- sort_records(substitutes, function(x, y) {
    compared <- fraction_compare(x$lift, y$lift)
    if (compared) return(compared)
    compared <- fraction_compare(y$expected, x$expected)
    if (compared) return(compared)
    compared <- string_compare(x$first, y$first)
    if (compared) compared else string_compare(x$second, y$second)
  })
}

analyze_trends <- function(a) {
  a$week_count <- integer_divide(a$last_day - 1, 7) + 1L
  a$week_baskets <- a$week_units <- rep(0, a$week_count)
  week_customers <- vector("list", a$week_count)
  a$series <- setNames(lapply(c(a$categories, a$product_names), function(name) rep(0, a$week_count)), c(a$categories, a$product_names))
  for (basket in a$baskets) {
    week <- integer_divide(basket$day - 1, 7) + 1L
    a$week_baskets[week] <- a$week_baskets[week] + 1
    a$week_units[week] <- a$week_units[week] + sum(basket$counts)
    week_customers[[week]] <- union(week_customers[[week]], basket$customer)
    for (product in names(basket$counts)) {
      count <- basket$counts[product]
      category <- a$taxonomy[product]
      a$series[[product]][week] <- a$series[[product]][week] + count
      a$series[[category]][week] <- a$series[[category]][week] + count
    }
  }
  a$week_customers <- vapply(week_customers, length, integer(1L))
  weeks <- seq_len(a$week_count)
  week_sum <- sum(weeks)
  denominator <- a$week_count * sum(weeks * weeks) - week_sum * week_sum
  trends <- lapply(names(a$series), function(name) {
    series <- a$series[[name]]
    units <- sum(series)
    slope <- fraction(a$week_count * sum(weeks * series) - week_sum * units, denominator)
    relative <- if (units) fraction_multiply(slope, fraction(a$week_count, units)) else NULL
    verdict <- if (is.null(relative)) "NONE" else if (fraction_compare(relative, a$params$trend_threshold) >= 0L) "RISING" else if (fraction_compare(relative, c(-a$params$trend_threshold[1L], a$params$trend_threshold[2L])) <= 0L) "FALLING" else "FLAT"
    list(name = name, units = units, slope = slope, relative = relative, verdict = verdict)
  })
  a$trends <- sort_records(trends, function(x, y) {
    if (is.null(x$relative) != is.null(y$relative)) return(if (is.null(x$relative)) 1L else -1L)
    compared <- if (is.null(x$relative)) 0L else fraction_compare(y$relative, x$relative)
    if (compared) compared else string_compare(x$name, y$name)
  })
}

analyze_customers <- function(a) {
  a$customer_summaries <- lapply(a$customers, function(customer) {
    baskets <- a$customer_baskets[[customer]]
    days <- sort(unique(vapply(baskets, function(basket) basket$day, numeric(1L))))
    units <- revenue <- 0
    category_units <- setNames(rep(0, length(a$categories)), a$categories)
    for (basket in baskets) for (name in names(basket$counts)) {
      count <- basket$counts[name]
      units <- units + count
      revenue <- revenue + count * a$products[[name]]$price
      category <- a$taxonomy[name]
      category_units[category] <- category_units[category] + count
    }
    first <- min(days)
    last <- max(days)
    segment <- if (first > a$last_day - 28L) "NEW" else if (length(baskets) >= 4L && a$last_day - last <= 14L) "LOYAL" else if (a$last_day - last > 28L) "AT_RISK" else "REGULAR"
    held <- names(a$histories[[customer]])
    list(customer = customer, baskets = length(baskets), days = length(days), first = first, last = last, products = length(held), units = unname(units), revenue = unname(revenue),
         average = integer_divide(revenue, length(baskets)), favorite = a$categories[order(-category_units, a$categories, method = "radix")][1L], segment = segment,
         offer = recommend(held, rule_candidates(a$main_rules$rules, held), a$params$recommend_top))
  })
}

run_analysis <- function(params, data) {
  a <- new.env(parent = emptyenv())
  a$params <- params
  a$data <- data
  a$products <- data$products
  a$product_names <- sort(names(data$products), method = "radix")
  a$taxonomy <- vapply(data$products, function(product) product$category, character(1L))
  a$categories <- sort(unique(unname(a$taxonomy)), method = "radix")
  a$baskets <- Filter(function(basket) length(basket$counts) > 0L, data$transactions)
  a$item_sets <- lapply(a$baskets, basket_items)
  a$total <- length(a$baskets)
  a$customer_baskets <- split(a$baskets, vapply(a$baskets, function(basket) basket$customer, character(1L)))
  a$customers <- sort(names(a$customer_baskets), method = "radix")
  days <- vapply(a$baskets, function(basket) basket$day, numeric(1L))
  a$first_day <- min(days)
  a$last_day <- max(days)
  analyze_frequent(a)
  analyze_sequences(a)
  analyze_validation(a)
  analyze_products(a)
  analyze_trends(a)
  analyze_customers(a)
  a
}

growth_lines <- function(a) {
  found <- a$growth$supports
  expected <- a$frequent
  only_main <- names(expected)[!names(expected) %in% names(found) | expected != found[names(expected)]]
  only_growth <- names(found)[!names(found) %in% names(expected) | found != expected[names(found)]]
  only_main <- only_main[!is.na(only_main)]
  only_growth <- only_growth[!is.na(only_growth)]
  status <- if (length(only_main) || length(only_growth)) "MISMATCH" else "MATCH"
  lines <- text_line("FPGROWTH header", a$growth$header, "nodes", a$growth$nodes, "conditional_trees", a$growth$conditional_trees, "conditional_nodes", a$growth$conditional_nodes, "itemsets", length(found), status)
  for (key in size_keys(only_main)) lines <- c(lines, text_line("ONLY_APRIORI", key, unname(expected[key])))
  for (key in size_keys(only_growth)) lines <- c(lines, text_line("ONLY_FPGROWTH", key, unname(found[key])))
  lines
}

summary_lines <- function(a) {
  data <- a$data
  sizes <- lengths(a$item_sets)
  largest <- max(sizes)
  lines <- paste("ERROR", data$errors)
  if (!length(data$errors)) lines <- character()
  lines <- c(lines, text_line("ITEMS rows", data$item_rows, "adopted", length(a$products), "categories", length(a$categories)),
             text_line("TRANSACTIONS lines", data$transaction_lines, "adopted", data$adopted, "rejected", data$rejected, "duplicates", data$duplicates, "transactions", length(data$transactions), "empty", length(data$transactions) - a$total),
             text_line("BASKETS count", a$total, "customers", length(a$customers), "first_day", a$first_day, "last_day", a$last_day, "average_size", fraction_text(fraction(sum(sizes), a$total)), "largest", largest))
  for (size in seq_len(largest)) {
    count <- sum(sizes == size)
    lines <- c(lines, text_line("SIZE", size, "baskets", count, "share", percent_text(count, a$total)))
  }
  lines <- c(lines, text_line("FREQUENT itemsets", length(a$frequent), "closed", length(a$closed), "maximal", length(a$maximal), "generators", length(a$generators), "levels", length(a$main$levels)), growth_lines(a),
             text_line("RULES generated", a$main_rules$generated, "passed", length(a$main_rules$rules), "productive", a$main_rules$productive))
  for (level in a$category_run$levels) lines <- c(lines, text_line("CATEGORY_LEVEL", level$number, "candidates", level$candidates, "taxonomy", level$excluded, "pruned", level$pruned, "counted", level$counted, "frequent", length(level$itemsets)))
  c(lines, text_line("CATEGORY_RULES itemsets", length(a$category_run$supports), "generated", a$category_rules$generated, "passed", length(a$category_rules$rules), "productive", a$category_rules$productive),
    text_line("SEQUENCES customers", length(a$customers), "multi_day", sum(vapply(a$customer_summaries, function(customer) customer$days >= 2L, logical(1L))), "pairs", a$sequence_pairs, "frequent", length(a$sequences)))
}

itemset_lines <- function(a) {
  lines <- character()
  for (level in a$main$levels) {
    lines <- c(lines, text_line("LEVEL", level$number, "candidates", level$candidates, "pruned", level$pruned, "counted", level$counted, "frequent", length(level$itemsets)))
    for (items in level$itemsets) lines <- c(lines, text_line(itemset_text(items), unname(a$frequent[itemset_text(items)])))
  }
  lines
}

closed_lines <- function(a) {
  lines <- character()
  sections <- list(CLOSED = a$closed, MAXIMAL = a$maximal, GENERATOR = a$generators)
  for (label in names(sections)) for (key in sections[[label]]) lines <- c(lines, text_line(label, key, unname(a$frequent[key])))
  lines
}

sequence_lines <- function(a) {
  lines <- character()
  for (rank in seq_along(a$sequences)) {
    sequence <- a$sequences[[rank]]
    lines <- c(lines, text_line("SEQ", rank, sequence$first, "->", sequence$second, "customers", sequence$count, "base", sequence$base, "confidence", fraction_text(sequence$confidence), "lift", fraction_text(sequence$lift), "gap", fraction_text(sequence$gap)))
  }
  for (repeat_record in a$repeats) lines <- c(lines, text_line("REPEAT", repeat_record$name, "customers", repeat_record$customers, "intervals", repeat_record$count, "min", repeat_record$minimum, "max", repeat_record$maximum, "mean", fraction_text(repeat_record$mean), "median", fraction_text(repeat_record$median)))
  lines
}

tally_text <- function(tally) text_line("cases", unname(tally["cases"]), "covered", unname(tally["covered"]), "hit1", unname(tally["hit1"]), "hit", unname(tally["hit"]), "rate", fraction_text(fraction(tally["hit"], tally["cases"])), "baseline", unname(tally["baseline"]), "rate", fraction_text(fraction(tally["baseline"], tally["cases"])))

validation_lines <- function(a) {
  lines <- character()
  for (check in a$checks) {
    rule <- check$rule
    measured <- if (check$verdict == "UNSEEN") "confidence - lift -" else text_line("confidence", fraction_text(check$confidence), "lift", fraction_text(check$lift))
    lines <- c(lines, text_line("RULE", rule$rank, rule_arrow(rule), "train", rule$count, "confidence", fraction_text(rule$confidence), "lift", fraction_text(rule$lift), "test", check$count, "of", check$first, measured, check$verdict))
  }
  for (rule in a$emerging) lines <- c(lines, text_line("EMERGING", rule$rank, rule_arrow(rule), "test", rule$count, "confidence", fraction_text(rule$confidence), "lift", fraction_text(rule$lift)))
  verdicts <- vapply(a$checks, function(check) check$verdict, character(1L))
  lines <- c(lines, text_line("VALIDATION train", a$train_total, "test", a$test_total, "itemsets", length(a$train_run$supports), "rules", length(a$train_rules), "hold", sum(verdicts == "HOLD"), "fail", sum(verdicts == "FAIL"), "unseen", sum(verdicts == "UNSEEN"), "emerging", length(a$emerging)))
  for (size in sort(as.numeric(names(a$tallies)))) lines <- c(lines, text_line("RECOMMEND size", size, tally_text(a$tallies[[as.character(size)]])))
  c(lines, paste("RECOMMEND total", tally_text(a$overall)))
}

partner_text <- function(a, name) {
  pairs <- Filter(function(pair) name %in% pair, a$pairs)
  if (!length(pairs)) return("none")
  pairs <- sort_records(pairs, function(x, y) {
    compared <- fraction_compare(pair_lift(a, y), pair_lift(a, x))
    if (compared) return(compared)
    x_count <- a$frequent[itemset_text(x)]
    y_count <- a$frequent[itemset_text(y)]
    if (x_count != y_count) return(sign(y_count - x_count))
    string_compare(setdiff(x, name), setdiff(y, name))
  })
  paste(setdiff(pairs[[1L]], name), fraction_text(pair_lift(a, pairs[[1L]])))
}

strongest_text <- function(a, name) {
  for (rule in a$main_rules$rules) if (name %in% c(rule$antecedent, rule$consequent)) return(text_line(rule$rank, rule_arrow(rule)))
  "none"
}

matrix_lines <- function(label, items, counts, baskets) {
  pairs <- list()
  for (first in seq_along(items)) if (first < length(items)) for (second in seq.int(first + 1L, length(items))) pairs[[length(pairs) + 1L]] <- sort(c(items[first], items[second]), method = "radix")
  together <- count_supports(baskets, pairs)
  lines <- vapply(seq_along(items), function(index) text_line(label, index, items[index], "baskets", unname(counts[items[index]])), character(1L))
  lines <- c(lines, paste0("    ", paste(sprintf("%7d", seq_along(items)), collapse = "")))
  for (first in seq_along(items)) {
    cells <- vapply(seq_along(items), function(second) {
      if (first == second) return("-")
      key <- itemset_text(sort(c(items[first], items[second]), method = "radix"))
      integer_text(integer_divide(100 * length(baskets) * together[key], counts[items[first]] * counts[items[second]]))
    }, character(1L))
    lines <- c(lines, paste0(sprintf("%4d", first), paste(sprintf("%7s", cells), collapse = "")))
  }
  lines
}

item_lines <- function(a) {
  ranked <- a$product_names[order(-a$revenue, a$product_names, method = "radix")]
  lines <- character()
  for (rank in seq_along(ranked)) {
    name <- ranked[rank]
    product <- a$products[[name]]
    count <- unname(a$counts[name])
    containing <- sum(vapply(names(a$frequent), function(key) name %in% split_itemset_text(key), logical(1L)))
    lines <- c(lines, text_line("ITEM", rank, name, product$category, "price", money_text(product$price), "units", unname(a$units[name]), "revenue", money_text(a$revenue[name]), "share", percent_text(a$revenue[name], a$total_revenue), "baskets", count, "support", fraction_text(fraction(count, a$total)), "customers", unname(a$buyers[name]), "itemsets", containing, "heldout", unname(a$held_out[name]), "hits", unname(a$held_hits[name]), "partner", partner_text(a, name), "best", strongest_text(a, name)))
  }
  for (category in a$category_summaries) lines <- c(lines, text_line("CATEGORY", category$name, "items", category$products, "units", category$units, "revenue", money_text(category$revenue), "share", percent_text(category$revenue, a$total_revenue), "baskets", category$baskets, "support", fraction_text(fraction(category$baskets, a$total))))
  lines <- c(lines, text_line("TOTAL items", length(a$products), "units", sum(a$units), "revenue", money_text(a$total_revenue), "baskets", a$total, "customers", length(a$customers)))
  for (number in seq_along(a$groups)) {
    group <- a$groups[[number]]
    lines <- c(lines, text_line("GROUP", number, "items", length(group$members), "edges", group$edges, "core", group$core, "revenue", money_text(group$revenue), "share", percent_text(group$revenue, a$total_revenue), "members", itemset_text(group$members)))
  }
  for (relation in a$substitutes) lines <- c(lines, text_line("SUBSTITUTE", relation$first, relation$second, "count", relation$count, "expected", fraction_text(relation$expected), "lift", fraction_text(relation$lift)))
  products <- head(a$product_names[order(-a$counts[a$product_names], a$product_names, method = "radix")], a$params$matrix_size)
  categories <- a$categories[order(-a$category_run$singles[a$categories], a$categories, method = "radix")]
  c(lines, matrix_lines("MATRIX", products, a$counts, a$item_sets), matrix_lines("CATEGORY_MATRIX", categories, a$category_run$singles, a$extended_sets))
}

table_row <- function(label, values) paste0(sprintf("%-17s", label), paste(sprintf("%6.0f", values), collapse = ""))

trend_lines <- function(a) {
  lines <- c(table_row("WEEK", seq_len(a$week_count)), table_row("BASKETS", a$week_baskets), table_row("UNITS", a$week_units), table_row("CUSTOMERS", a$week_customers))
  for (name in c(a$categories, a$product_names)) lines <- c(lines, table_row(name, a$series[[name]]))
  for (trend in a$trends) lines <- c(lines, text_line("TREND", trend$name, "units", trend$units, "slope", fraction_text(trend$slope), "relative", if (is.null(trend$relative)) "-" else fraction_text(trend$relative), trend$verdict))
  lines
}

customer_lines <- function(a) {
  lines <- character()
  for (customer in a$customer_summaries) lines <- c(lines, text_line("CUSTOMER", customer$customer, "baskets", customer$baskets, "days", customer$days, "first", customer$first, "last", customer$last, "items", customer$products, "units", customer$units, "revenue", money_text(customer$revenue), "average", money_text(customer$average), "favorite", customer$favorite, "segment", customer$segment, "offer", if (length(customer$offer)) itemset_text(customer$offer) else "none"))
  for (segment in SEGMENTS) {
    customers <- Filter(function(customer) customer$segment == segment, a$customer_summaries)
    revenue <- sum(vapply(customers, function(customer) customer$revenue, numeric(1L)))
    lines <- c(lines, text_line("SEGMENT", segment, "customers", length(customers), "revenue", money_text(revenue), "share", percent_text(revenue, a$total_revenue)))
  }
  lines
}

main <- function() {
  analysis <- run_analysis(read_params(), read_dataset())
  dir.create("output", showWarnings = FALSE)
  outputs <- list("summary.txt" = summary_lines(analysis), "itemsets.txt" = itemset_lines(analysis), "closed_maximal.txt" = closed_lines(analysis),
                  "rules.csv" = rules_csv(analysis$main_rules$rules), "category_rules.csv" = rules_csv(analysis$category_rules$rules),
                  "sequences.txt" = sequence_lines(analysis), "validation.txt" = validation_lines(analysis), "items_report.txt" = item_lines(analysis),
                  "trends.txt" = trend_lines(analysis), "customers.txt" = customer_lines(analysis))
  for (name in names(outputs)) write_report(name, outputs[[name]])
}

main()
