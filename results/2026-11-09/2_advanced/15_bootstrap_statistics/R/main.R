script_args <- grep("^--file=", commandArgs(), value = TRUE)
source_dir <- if (length(script_args)) dirname(sub("^--file=", "", script_args[1L])) else "R"
for (unit in c("dataset", "minstd", "resampling", "tests", "report")) {
  source(file.path(source_dir, paste0(unit, ".R")))
}

group_names <- c("mean", "median", "trimmed_mean", "sd")
group_functions <- list(mean_value, median_value, trimmed_mean, sd_value)
pair_names <- c("mean_diff", "median_ratio", "hodges_lehmann", "cohen_d")
pair_functions <- list(mean_difference, median_ratio, hodges_lehmann, cohen_d)
test_names <- c("mean", "median", "ranksum", "absdev")
ceil_div <- function(numerator, denominator) (numerator + denominator - 1L) %/% denominator

new_summary <- function(estimate, values, ranks) {
  moments <- mean_and_se(values)
  ordered <- ordered_values(values)
  low <- ordered[ranks[1L]]
  high <- ordered[ranks[2L]]
  list(estimate = estimate, values = values, ordered = ordered, average = moments[1L], se = moments[2L],
       bias = moments[1L] - estimate, low = low, high = high,
       basic_low = 2 * estimate - high, basic_high = 2 * estimate - low)
}

summary_csv <- function(summary, name, statistic) {
  values <- c(summary$estimate, summary$se, summary$bias, summary$low, summary$high, summary$basic_low, summary$basic_high)
  paste(c(name, statistic, real_text(values)), collapse = ",")
}

interval_text <- function(summary) {
  paste("se", real_text(summary$se), "bias", real_text(summary$bias),
        "percentile", real_text(summary$low), real_text(summary$high),
        "basic", real_text(summary$basic_low), real_text(summary$basic_high))
}

new_group_bootstrap <- function(group, indices, ranks) {
  samples <- lapply(indices, function(replicate) group$values[replicate])
  summaries <- lapply(group_functions, function(statistic) {
    new_summary(statistic(group$values), vapply(samples, statistic, numeric(1L)), ranks)
  })
  list(group = group, indices = indices, samples = samples, summaries = summaries)
}

new_pair_bootstrap <- function(first, second, ranks) {
  summaries <- lapply(pair_functions, function(statistic) {
    values <- vapply(seq_along(first$samples), function(index) {
      statistic(first$samples[[index]], second$samples[[index]])
    }, numeric(1L))
    new_summary(statistic(first$group$values, second$group$values), values, ranks)
  })
  list(first = first, second = second, name = paste0(first$group$name, "-", second$group$name), summaries = summaries)
}

jackknife_spread <- function(values) {
  count <- length(values)
  average <- sequential_sum(values) / count
  squares <- 0
  for (value in values) {
    difference <- value - average
    squares <- squares + difference * difference
  }
  c(average, (count - 1L) * squares / count)
}

new_jackknife <- function(estimate, values) {
  spread <- jackknife_spread(values)
  list(values = values, average = spread[1L], variance = spread[2L],
       bias = (length(values) - 1L) * (spread[1L] - estimate), se = sqrt(spread[2L]))
}

new_tally <- function(observed) list(observed = observed, extreme = 0, greater = 0)
count_tally <- function(tally, value) {
  if (abs(value) >= abs(tally$observed)) tally$extreme <- tally$extreme + 1
  if (value >= tally$observed) tally$greater <- tally$greater + 1
  tally
}

tally_text <- function(tally, offset, denominator) {
  paste("extreme", integer_text(tally$extreme), "greater", integer_text(tally$greater),
        "p_two", p_value(tally$extreme + offset, denominator),
        "p_greater", p_value(tally$greater + offset, denominator))
}

new_display_range <- function(values) list(low = min(values), delta = 100 * (max(values) - min(values)))
position_in <- function(display, value) (120 * (value - 100 * display$low) + display$delta) %/% (2 * display$delta)

outlier_indices <- function(values) {
  first <- quantile_numerator(values, 25)
  third <- quantile_numerator(values, 75)
  which(200 * values < 5 * first - 3 * third | 200 * values > 5 * third - 3 * first)
}

series_lines <- function(kind, name, values, display, stems) {
  count <- length(values)
  average <- mean_value(values)
  deviation <- sd_value(values)
  moments <- central_moments(values)
  clipped <- winsorized(values)
  first <- quantile_numerator(values, 25)
  third <- quantile_numerator(values, 75)
  outliers <- outlier_indices(values)
  inside <- values[!seq_along(values) %in% outliers]
  low_whisker <- min(inside)
  high_whisker <- max(inside)
  band <- rep(".", 61L)
  band[seq.int(position_in(display, 100 * low_whisker), position_in(display, 100 * high_whisker)) + 1L] <- "-"
  band[seq.int(position_in(display, first), position_in(display, third)) + 1L] <- "="
  band[position_in(display, quantile_numerator(values, 50)) + 1L] <- "|"
  for (index in outliers) band[position_in(display, 100 * values[index]) + 1L] <- "o"
  ordered <- ordered_values(values)
  lines <- c(paste(kind, name), paste("n", count), paste("mean", real_text(average)),
    paste("median", real_text(median_value(values))),
    paste("trimmed_mean", real_text(trimmed_mean(values)), "trim", count %/% 10L),
    paste("winsorized_mean", real_text(mean_value(clipped)), "winsorized_sd", real_text(sd_value(clipped))),
    paste("sd", real_text(deviation)), paste("se_mean", real_text(deviation / sqrt(count))),
    paste("cv", real_text(deviation / average)),
    paste("skewness", real_text(moments[2L] / (moments[1L] * sqrt(moments[1L])))),
    paste("kurtosis", real_text(moments[3L] / (moments[1L] * moments[1L]) - 3)),
    paste("mad", real_text(mad_value(values))), paste("min", real_text(ordered[1L] / 100)),
    paste("q1", real_text(first / 10000)), paste("q3", real_text(third / 10000)),
    paste("iqr", real_text((third - first) / 10000)), paste("max", real_text(ordered[count] / 100)))
  percentiles <- "percentiles"
  percentages <- c(5, 10, 90, 95)
  labels <- c("p05", "p10", "p90", "p95")
  for (index in seq_along(percentages)) {
    percentiles <- c(percentiles, labels[index], real_text(quantile_numerator(values, percentages[index]) / 10000))
  }
  lines <- c(lines, paste(percentiles, collapse = " "),
    paste("whiskers", real_text(low_whisker / 100), real_text(high_whisker / 100)),
    paste("outliers", number_list(outliers)), paste("box", paste(band, collapse = "")))
  if (stems) {
    for (stem in seq.int(ordered[1L] %/% 100, ordered[count] %/% 100)) {
      leaves <- paste((ordered[ordered %/% 100 == stem] %% 100) %/% 10, collapse = "")
      line <- paste("stem", integer_text(stem))
      if (nchar(leaves)) line <- paste(line, leaves)
      lines <- c(lines, line)
    }
  }
  lines
}

bootstrap_lines <- function(ordinary, balanced, pairs) {
  lines <- "group,statistic,estimate,se,bias,percentile_lo,percentile_hi,basic_lo,basic_hi"
  for (index in seq_along(ordinary)) {
    bootstrap <- ordinary[[index]]
    for (column in seq_along(group_names)) lines <- c(lines, summary_csv(bootstrap$summaries[[column]], bootstrap$group$name, group_names[column]))
    for (column in seq_along(group_names)) lines <- c(lines, summary_csv(balanced[[index]]$summaries[[column]], bootstrap$group$name, paste0("balanced_", group_names[column])))
  }
  for (pair in pairs) {
    for (column in seq_along(pair_names)) lines <- c(lines, summary_csv(pair$summaries[[column]], pair$name, pair_names[column]))
  }
  lines
}

pair_jackknife_lines <- function(pair) {
  x <- pair$first$group$values
  y <- pair$second$group$values
  lines <- character()
  for (column in seq_along(pair_names)) {
    statistic <- pair_functions[[column]]
    estimate <- pair$summaries[[column]]$estimate
    first <- new_jackknife(estimate, vapply(seq_along(x), function(index) statistic(without(x, index), y), numeric(1L)))
    second <- new_jackknife(estimate, vapply(seq_along(y), function(index) statistic(x, without(y, index)), numeric(1L)))
    bias <- variance <- 0
    bias <- bias + first$bias
    bias <- bias + second$bias
    variance <- variance + first$variance
    variance <- variance + second$variance
    lines <- c(lines, paste("pair", pair$name, pair_names[column], "estimate", real_text(estimate),
                            "bias", real_text(bias), "se", real_text(sqrt(variance))))
  }
  lines
}

deviation_total <- function(sample, center) sum(abs(2 * sample - center))
split_statistics <- function(values, ranks, order, size) {
  first_indices <- order[seq_len(size)]
  second_indices <- order[seq.int(size + 1L, length(order))]
  first <- values[first_indices]
  second <- values[second_indices]
  first_center <- doubled_median(first)
  second_center <- doubled_median(second)
  c(contrast(sum(first), length(first), sum(second), length(second)), first_center - second_center,
    sum(ranks[first_indices]) - length(first) * (length(first) + length(second) + 1L),
    contrast(deviation_total(first, first_center), length(first), deviation_total(second, second_center), length(second)))
}

signed_ranks <- function(differences) {
  nonzero <- differences != 0
  result <- numeric(length(differences))
  result[nonzero] <- doubled_ranks(abs(differences[nonzero])) * sign(differences[nonzero])
  result
}

welch_line <- function(samples) {
  count <- length(samples)
  means <- vapply(samples, mean_value, numeric(1L))
  weights <- vapply(samples, function(sample) {
    deviation <- sd_value(sample)
    length(sample) / (deviation * deviation)
  }, numeric(1L))
  total_weight <- sequential_sum(weights)
  weighted <- 0
  for (index in seq_along(samples)) weighted <- weighted + weights[index] * means[index]
  center <- weighted / total_weight
  spread <- lambda <- 0
  for (index in seq_along(samples)) {
    difference <- means[index] - center
    spread <- spread + weights[index] * (difference * difference)
    share <- 1 - weights[index] / total_weight
    lambda <- lambda + share * share / (length(samples[[index]]) - 1L)
  }
  spread <- spread / (count - 1L)
  f <- spread / (1 + 2 * (count - 2L) * lambda / (count * count - 1L))
  degrees <- (count * count - 1L) / (3 * lambda)
  paste("welch f", real_text(f), "df", count - 1L, real_text(degrees))
}

group_deltas <- function(samples, pairs) {
  lapply(pairs, function(pair) {
    x <- samples[[pair[1L]]]
    y <- samples[[pair[2L]]]
    c(abs(contrast(sum(x), length(x), sum(y), length(y))), length(x) * length(y))
  })
}

delta_at_least <- function(value, bound) value[1L] * bound[2L] >= bound[1L] * value[2L]
largest_delta <- function(values) {
  largest <- values[[1L]]
  for (value in values[-1L]) if (!delta_at_least(largest, value)) largest <- value
  largest
}

new_study <- function(data) {
  low <- ((data$settings$bootstrap + 1) * (100 - data$settings$confidence)) %/% 200
  list(data = data, generator = minstd(data$settings$seed),
       ranks = c(low, data$settings$bootstrap + 1 - low), z_low = phi_inverse((100 - data$settings$confidence) / 200))
}

descriptive_lines <- function(study) {
  data <- study$data
  all <- unlist(lapply(data$groups, function(group) group$values), use.names = FALSE)
  lines <- paste("groups", length(data$groups), "observations", length(all))
  display <- new_display_range(all)
  for (group in data$groups) lines <- c(lines, series_lines("group", group$name, group$values, display, TRUE))
  paired <- data$paired
  lines <- c(lines, paste("paired subjects", length(paired$differences)))
  display <- new_display_range(c(paired$before, paired$after))
  c(lines, series_lines("series", "before", paired$before, display, FALSE),
    series_lines("series", "after", paired$after, display, FALSE),
    series_lines("series", "diff", paired$differences, new_display_range(paired$differences), FALSE))
}

paired_bootstrap <- function(study) {
  paired <- study$data$paired
  indices <- ordinary_indices(study$generator, length(paired$differences), study$data$settings$bootstrap)
  means <- correlations <- numeric(length(indices))
  for (number in seq_along(indices)) {
    chosen <- indices[[number]]
    means[number] <- mean_value(paired$differences[chosen])
    correlations[number] <- correlation_value(paired$before[chosen], paired$after[chosen])
  }
  list(new_summary(mean_value(paired$differences), means, study$ranks),
       new_summary(correlation_value(paired$before, paired$after), correlations, study$ranks))
}

histogram_lines <- function(study, name, statistic, summary) {
  bins <- study$data$settings$bins
  values <- summary$values
  low <- summary$ordered[1L]
  high <- summary$ordered[length(values)]
  counts <- numeric(bins)
  marks <- rep(list(character()), bins)
  for (value in values) {
    index <- bin_number(value, low, high, bins)
    counts[index] <- counts[index] + 1
  }
  top <- max(counts)
  index <- bin_number(summary$low, low, high, bins)
  marks[[index]] <- c(marks[[index]], "L")
  estimate_bin <- "none"
  if (low <= summary$estimate && summary$estimate <= high) {
    index <- bin_number(summary$estimate, low, high, bins)
    estimate_bin <- integer_text(index)
    marks[[index]] <- c(marks[[index]], "E")
  }
  index <- bin_number(summary$high, low, high, bins)
  marks[[index]] <- c(marks[[index]], "H")
  convergence <- character()
  for (quarter in seq_len(4L)) {
    size <- (quarter * study$data$settings$bootstrap) %/% 4
    moments <- mean_and_se(values[seq_len(size)])
    convergence <- c(convergence, paste0(integer_text(size), ":", real_text(moments[2L])))
  }
  lines <- c(paste("histogram", name, statistic, "min", real_text(low), "max", real_text(high),
                   "width", real_text((high - low) / bins), "top", integer_text(top), "estimate_bin", estimate_bin),
             paste("convergence", paste(convergence, collapse = " ")))
  for (index in seq_len(bins)) {
    parts <- c("bin", integer_text(index), real_text(low + (high - low) * (index - 1L) / bins), integer_text(counts[index]))
    if (counts[index] > 0) parts <- c(parts, bar(counts[index], top))
    lines <- c(lines, paste(c(parts, marks[[index]]), collapse = " "))
  }
  lines
}

histogram_file <- function(study, ordinary, pairs) {
  lines <- character()
  for (bootstrap in ordinary) {
    for (column in seq_along(group_names)) lines <- c(lines, histogram_lines(study, bootstrap$group$name, group_names[column], bootstrap$summaries[[column]]))
  }
  for (pair in pairs) {
    for (column in seq_along(pair_names)) lines <- c(lines, histogram_lines(study, pair$name, pair_names[column], pair$summaries[[column]]))
  }
  lines
}

bca_line <- function(study, statistic, summary, jackknife) {
  replicates <- study$data$settings$bootstrap
  below <- sum(summary$values < summary$estimate)
  z0 <- phi_inverse(below / replicates)
  squares <- cubes <- 0
  for (value in jackknife$values) {
    u <- jackknife$average - value
    squares <- squares + u * u
    cubes <- cubes + u * u * u
  }
  acceleration <- cubes / (6 * squares * sqrt(squares))
  alpha <- function(z) phi(z0 + (z0 + z) / (1 - acceleration * (z0 + z)))
  lower <- min(max(floor((replicates + 1) * alpha(study$z_low)), 1), replicates)
  upper <- min(max(replicates + 1 - floor((replicates + 1) * (1 - alpha(-study$z_low))), 1), replicates)
  paste("bca", statistic, "below", integer_text(below), "z0", real_text(z0),
        "acceleration", real_text(acceleration), "ranks", integer_text(lower), integer_text(upper),
        "interval", real_text(summary$ordered[lower]), real_text(summary$ordered[upper]))
}

after_bootstrap_lines <- function(bootstrap, mean_jackknife) {
  values <- bootstrap$group$values
  count <- length(values)
  omitted <- rep(list(integer()), count)
  for (number in seq_along(bootstrap$indices)) {
    chosen <- bootstrap$indices[[number]]
    for (index in seq_len(count)) {
      if (!index %in% chosen) omitted[[index]] <- c(omitted[[index]], number)
    }
  }
  errors <- vector("list", 4L)
  lines <- character()
  for (column in seq_along(group_names)) {
    summary <- bootstrap$summaries[[column]]
    errors[[column]] <- vapply(omitted, function(numbers) mean_and_se(summary$values[numbers])[2L], numeric(1L))
    spread <- jackknife_spread(errors[[column]])
    lines <- c(lines, paste("after_bootstrap", group_names[column], "se", real_text(summary$se),
                            "average", real_text(spread[1L]), "se_of_se", real_text(sqrt(spread[2L]))))
  }
  sizes <- vapply(omitted, length, integer(1L))
  lines <- c(lines, paste("without min", min(sizes), "max", max(sizes)))
  total <- sum(values)
  ranking <- order(-abs(count * values - total), seq_along(values), method = "radix")
  summary <- bootstrap$summaries[[1L]]
  for (rank in seq_len(min(5L, count))) {
    index <- ranking[rank]
    influence <- (count - 1L) * (mean_jackknife$average - mean_jackknife$values[index])
    shifted <- ordered_values(summary$values[omitted[[index]]] - summary$estimate)
    quantiles <- vapply(c(5, 50, 95), function(percent) shifted[ceil_div(percent * sizes[index], 100)], numeric(1L))
    lines <- c(lines, paste("influence", rank, "obs", index, "value", real_text(values[index] / 100),
      "l", real_text(influence), "without", sizes[index], "se", real_text(errors[[1L]][index]),
      "q05", real_text(quantiles[1L]), "q50", real_text(quantiles[2L]), "q95", real_text(quantiles[3L])))
  }
  lines
}

group_jackknife_lines <- function(study, bootstrap) {
  values <- bootstrap$group$values
  jackknives <- vector("list", 4L)
  lines <- paste("group", bootstrap$group$name, "n", length(values))
  for (column in seq_along(group_names)) {
    statistic <- group_functions[[column]]
    summary <- bootstrap$summaries[[column]]
    jackknife <- new_jackknife(summary$estimate, vapply(seq_along(values), function(index) statistic(without(values, index)), numeric(1L)))
    jackknives[[column]] <- jackknife
    lines <- c(lines, paste("jackknife", group_names[column], "estimate", real_text(summary$estimate),
      "average", real_text(jackknife$average), "bias", real_text(jackknife$bias), "se", real_text(jackknife$se)))
  }
  for (column in seq_along(group_names)) lines <- c(lines, bca_line(study, group_names[column], bootstrap$summaries[[column]], jackknives[[column]]))
  c(lines, after_bootstrap_lines(bootstrap, jackknives[[1L]]))
}

jackknife_file <- function(study, ordinary, pairs) {
  lines <- character()
  for (bootstrap in ordinary) lines <- c(lines, group_jackknife_lines(study, bootstrap))
  for (pair in pairs) lines <- c(lines, pair_jackknife_lines(pair))
  lines
}

permutation_lines <- function(study, x, y) {
  permutations <- study$data$settings$permutations
  combined <- c(x, y)
  ranks <- doubled_ranks(combined)
  positions <- seq_along(combined)
  observed <- split_statistics(combined, ranks, positions, length(x))
  tallies <- lapply(observed, new_tally)
  for (replicate in seq_len(permutations)) {
    order <- study$generator$shuffle(positions)
    values <- split_statistics(combined, ranks, order, length(x))
    for (column in seq_along(tallies)) tallies[[column]] <- count_tally(tallies[[column]], values[column])
  }
  k <- length(x)
  m <- length(y)
  rank_total <- sum(ranks[seq_len(k)])
  results <- vapply(tallies, function(tally) tally_text(tally, 1, permutations + 1), character(1L))
  list(lines = c(paste("permutation n", k, m, "perms", integer_text(permutations)),
    paste("mean diff", real_text(mean_difference(x, y)), results[1L]),
    paste("median diff", real_text(observed[2L] / 200), results[2L]),
    paste("ranksum w", real_text(rank_total / 2), "u", real_text((rank_total - k * (k + 1L)) / 2), results[3L]),
    paste("absdev diff", real_text(observed[4L] / (200 * k * m)), results[4L])),
    extremes = vapply(tallies, function(tally) tally$extreme, numeric(1L)))
}

simulation_rejects <- function(study, first, second) {
  settings <- study$data$settings
  k <- length(first)
  m <- length(second)
  combined <- c(first, second)
  total <- sum(combined)
  observed <- abs(contrast(sum(first), k, sum(second), m))
  count <- 0
  for (replicate in seq_len(settings$power_perms)) {
    shuffled <- study$generator$shuffle(combined)
    head <- sum(shuffled[seq_len(k)])
    if (abs(contrast(head, k, total - head, m)) >= observed) count <- count + 1
  }
  100 * (count + 1) <= (100 - settings$confidence) * (settings$power_perms + 1)
}

power_line <- function(study, x, y) {
  settings <- study$data$settings
  rejections <- 0
  for (simulation in seq_len(settings$power_sims)) {
    first <- x[resample_indices(study$generator, length(x))]
    second <- y[resample_indices(study$generator, length(y))]
    if (simulation_rejects(study, first, second)) rejections <- rejections + 1
  }
  power <- rejections / settings$power_sims
  error <- sqrt(power * (1 - power) / settings$power_sims)
  paste("power sims", integer_text(settings$power_sims), "perms", integer_text(settings$power_perms),
        "rejections", integer_text(rejections), "power", real_text(power), "se", real_text(error))
}

exact_lines <- function(study, x, y) {
  size <- study$data$settings$pilot
  combined <- c(x[seq_len(size)], y[seq_len(size)])
  ranks <- doubled_ranks(combined)
  total <- sum(combined)
  mean_values <- rank_values <- numeric()
  position_choices(2 * size, size, function(choice) {
    chosen <- sum(combined[choice])
    mean_values <<- c(mean_values, contrast(chosen, size, total - chosen, size))
    rank_values <<- c(rank_values, sum(ranks[choice]) - size * (2 * size + 1))
  })
  splits <- length(mean_values)
  mean_tally <- new_tally(mean_values[1L])
  rank_tally <- new_tally(rank_values[1L])
  for (index in seq_len(splits)) {
    mean_tally <- count_tally(mean_tally, mean_values[index])
    rank_tally <- count_tally(rank_tally, rank_values[index])
  }
  critical <- "critical diff none attained none"
  frequencies <- value_counts(abs(mean_values))
  cumulative <- 0
  for (index in rev(seq_along(frequencies$values))) {
    cumulative <- cumulative + frequencies$counts[index]
    if (100 * cumulative > (100 - study$data$settings$confidence) * splits) break
    critical <- paste("critical diff", real_text(frequencies$values[index] / (100 * size * size)),
                      "attained", p_value(cumulative, splits))
  }
  rank_total <- sum(ranks[seq_len(size)])
  c(paste("exact size", integer_text(size), "splits", splits),
    paste("mean diff", real_text(mean_difference(x[seq_len(size)], y[seq_len(size)])), tally_text(mean_tally, 0, splits)),
    paste("ranksum w", real_text(rank_total / 2), "u", real_text((rank_total - size * (size + 1)) / 2), tally_text(rank_tally, 0, splits)), critical)
}

studentized_lines <- function(study, pair) {
  x <- pair$first$group$values
  y <- pair$second$group$values
  k <- length(x)
  m <- length(y)
  estimate <- mean_difference(x, y)
  first_sd <- sd_value(x)
  second_sd <- sd_value(y)
  first_variance <- first_sd * first_sd / k
  second_variance <- second_sd * second_sd / m
  se0 <- sqrt(first_variance + second_variance)
  t <- estimate / se0
  statistics <- numeric(length(pair$summaries[[1L]]$values))
  extreme <- 0
  for (index in seq_along(statistics)) {
    first <- pair$first$summaries[[4L]]$values[index]
    second <- pair$second$summaries[[4L]]$values[index]
    spread <- sqrt(first * first / k + second * second / m)
    value <- (pair$summaries[[1L]]$values[index] - estimate) / spread
    statistics[index] <- value
    if (abs(value) >= abs(t)) extreme <- extreme + 1
  }
  ordered <- ordered_values(statistics)
  lower <- estimate - ordered[study$ranks[2L]] * se0
  upper <- estimate - ordered[study$ranks[1L]] * se0
  degrees <- (first_variance + second_variance) * (first_variance + second_variance) /
    (first_variance * first_variance / (k - 1L) + second_variance * second_variance / (m - 1L))
  greater <- equal <- 0
  for (first in x) {
    for (second in y) {
      if (first > second) greater <- greater + 1
      if (first == second) equal <- equal + 1
    }
  }
  d <- cohen_d(x, y)
  hedges <- d * (1 - 3 / (4 * (k + m - 2L) - 1L))
  cles <- (2 * greater + equal) / (2 * k * m)
  c(paste("bootstrap_t t", real_text(t), "df", real_text(degrees), "extreme", integer_text(extreme),
          "p", p_value(extreme + 1, study$data$settings$bootstrap + 1), "interval", real_text(lower), real_text(upper)),
    paste("effect pooled_sd", real_text(pooled_sd(x, y)), "cohen_d", real_text(d), "hedges_g", real_text(hedges), "cles", real_text(cles)))
}

pair_test_lines <- function(study, pair) {
  first <- pair$first$group
  second <- pair$second$group
  permutation <- permutation_lines(study, first$values, second$values)
  power <- power_line(study, first$values, second$values)
  list(lines = c(paste("compare", first$name, second$name), permutation$lines, power,
                 exact_lines(study, first$values, second$values), studentized_lines(study, pair)),
       extremes = permutation$extremes)
}

holm_lines <- function(study, extremes) {
  settings <- study$data$settings
  count <- length(study$data$pairs)
  lines <- character()
  for (column in seq_along(test_names)) {
    values <- vapply(extremes, function(record) record[column], numeric(1L))
    order <- order(values, seq_along(values), method = "radix")
    adjusted <- 0
    for (rank in seq_along(order)) {
      index <- order[rank]
      extreme <- values[index]
      adjusted <- max(adjusted, min(settings$permutations + 1, (count - rank + 1L) * (extreme + 1)))
      decision <- if (100 * adjusted <= (100 - settings$confidence) * (settings$permutations + 1)) "reject" else "retain"
      pair <- study$data$pairs[[index]]
      lines <- c(lines, paste("holm", test_names[column], "rank", rank,
        study$data$groups[[pair[1L]]]$name, study$data$groups[[pair[2L]]]$name,
        "p", p_value(extreme + 1, settings$permutations + 1), "adjusted", p_value(adjusted, settings$permutations + 1), decision))
    }
  }
  lines
}

hyperbolic_tangent <- function(value) {
  growth <- exp(2 * value)
  (growth - 1) / (growth + 1)
}

paired_lines <- function(study, mean_summary, correlation_summary) {
  paired <- study$data$paired
  count <- length(paired$differences)
  positive <- sum(paired$differences > 0)
  negative <- sum(paired$differences < 0)
  average <- mean_value(paired$differences)
  deviation <- sd_value(paired$differences)
  r <- correlation_value(paired$before, paired$after)
  z <- 0.5 * log((1 + r) / (1 - r))
  half_width <- -study$z_low / sqrt(count - 3L)
  c(paste("paired subjects", count, "positive", positive, "negative", negative, "zero", count - positive - negative),
    paste("paired before", real_text(mean_value(paired$before)), "after", real_text(mean_value(paired$after)),
          "diff", real_text(average), "sd_diff", real_text(deviation), "t", real_text(average / (deviation / sqrt(count))), "dz", real_text(average / deviation)),
    paste("paired_bootstrap", interval_text(mean_summary)),
    paste("correlation r", real_text(r), interval_text(correlation_summary), "fisher",
          real_text(hyperbolic_tangent(z - half_width)), real_text(hyperbolic_tangent(z + half_width))))
}

sign_flip_lines <- function(study) {
  permutations <- study$data$settings$permutations
  differences <- study$data$paired$differences
  signed <- signed_ranks(differences)
  mean_tally <- new_tally(sum(differences))
  rank_tally <- new_tally(sum(signed))
  for (replicate in seq_len(permutations)) {
    mean_total <- rank_total <- 0
    for (index in seq_along(differences)) {
      sign <- if (study$generator$draw() %% 2 == 1) -1 else 1
      mean_total <- mean_total + sign * differences[index]
      rank_total <- rank_total + sign * signed[index]
    }
    mean_tally <- count_tally(mean_tally, mean_total)
    rank_tally <- count_tally(rank_tally, rank_total)
  }
  positive <- sum(signed[signed > 0])
  c(paste("signflip flips", integer_text(permutations)),
    paste("mean diff", real_text(mean_value(differences)), tally_text(mean_tally, 1, permutations + 1)),
    paste("signedrank w_plus", real_text(positive / 2), tally_text(rank_tally, 1, permutations + 1)))
}

anova_permutation_lines <- function(study, combined, ranks, sizes, f, h, correction) {
  permutations <- study$data$settings$permutations
  group_count <- length(sizes)
  total_count <- length(combined)
  pairs <- list()
  for (first in seq_len(group_count - 1L)) {
    for (second in seq.int(first + 1L, group_count)) pairs[[length(pairs) + 1L]] <- c(first, second)
  }
  observed <- group_deltas(split_list(combined, sizes), pairs)
  extremes <- maxima <- numeric(length(pairs))
  f_extreme <- h_extreme <- 0
  positions <- seq_along(combined)
  for (replicate in seq_len(permutations)) {
    order <- study$generator$shuffle(positions)
    parts <- split_list(order, sizes)
    samples <- lapply(parts, function(part) combined[part])
    rank_sums <- vapply(parts, function(part) sum(ranks[part]), numeric(1L))
    squares <- sums_of_squares(samples)
    if (f_statistic(squares[1L], squares[2L], group_count, total_count) >= f - 0.000000001 * f) f_extreme <- f_extreme + 1
    if (h_statistic(rank_sums, sizes, correction) >= h - 0.000000001 * h) h_extreme <- h_extreme + 1
    deltas <- group_deltas(samples, pairs)
    largest <- largest_delta(deltas)
    for (index in seq_along(observed)) {
      if (delta_at_least(deltas[[index]], observed[[index]])) extremes[index] <- extremes[index] + 1
      if (delta_at_least(largest, observed[[index]])) maxima[index] <- maxima[index] + 1
    }
  }
  lines <- paste("anova_permutation perms", integer_text(permutations), "f_extreme", integer_text(f_extreme),
                 "f_p", p_value(f_extreme + 1, permutations + 1), "h_extreme", integer_text(h_extreme), "h_p", p_value(h_extreme + 1, permutations + 1))
  for (index in seq_along(pairs)) {
    pair <- pairs[[index]]
    first <- study$data$groups[[pair[1L]]]
    second <- study$data$groups[[pair[2L]]]
    lines <- c(lines, paste("pairwise", first$name, second$name, "diff", real_text(mean_difference(first$values, second$values)),
      "extreme", integer_text(extremes[index]), "p", p_value(extremes[index] + 1, permutations + 1),
      "maxt", integer_text(maxima[index]), "adjusted", p_value(maxima[index] + 1, permutations + 1)))
  }
  lines
}

anova_lines <- function(study, ordinary) {
  samples <- lapply(study$data$groups, function(group) group$values)
  sizes <- vapply(samples, length, integer(1L))
  combined <- unlist(samples, use.names = FALSE)
  group_count <- length(samples)
  total_count <- length(combined)
  squares <- sums_of_squares(samples)
  between <- squares[1L]
  within <- squares[2L]
  f <- f_statistic(between, within, group_count, total_count)
  eta <- between / (between + within)
  msw <- within / (total_count - group_count)
  omega <- (between - (group_count - 1L) * msw) / (between + within + msw)
  eta_values <- vapply(seq_len(study$data$settings$bootstrap), function(number) {
    replicate <- lapply(ordinary, function(bootstrap) bootstrap$samples[[number]])
    parts <- sums_of_squares(replicate)
    parts[1L] / (parts[1L] + parts[2L])
  }, numeric(1L))
  eta_summary <- new_summary(eta, eta_values, study$ranks)
  ranks <- doubled_ranks(combined)
  rank_sums <- vapply(split_list(ranks, sizes), sum, numeric(1L))
  counts <- value_counts(combined)$counts
  tied <- counts[counts >= 2]
  tie_total <- sum(tied * tied * tied - tied)
  correction <- 1 - tie_total / (total_count * total_count * total_count - total_count)
  h <- h_statistic(rank_sums, sizes, correction)
  lines <- c(paste("anova groups", group_count, "observations", total_count, "ssb", real_text(between), "ssw", real_text(within),
    "df", group_count - 1L, total_count - group_count, "f", real_text(f), "eta_squared", real_text(eta), "omega_squared", real_text(omega)),
    paste("eta_bootstrap", interval_text(eta_summary)), welch_line(samples), paste("kruskal h", real_text(h), "tie_groups", length(tied)))
  c(lines, anova_permutation_lines(study, combined, ranks, sizes, f, h, correction))
}

run_study <- function(study) {
  data <- study$data
  count <- data$settings$bootstrap
  ordinary <- lapply(data$groups, function(group) new_group_bootstrap(group, ordinary_indices(study$generator, length(group$values), count), study$ranks))
  balanced <- lapply(data$groups, function(group) new_group_bootstrap(group, balanced_indices(study$generator, length(group$values), count), study$ranks))
  paired <- paired_bootstrap(study)
  pairs <- lapply(data$pairs, function(pair) new_pair_bootstrap(ordinary[[pair[1L]]], ordinary[[pair[2L]]], study$ranks))
  lines <- character()
  extremes <- list()
  for (pair in pairs) {
    records <- pair_test_lines(study, pair)
    lines <- c(lines, records$lines)
    extremes[[length(extremes) + 1L]] <- records$extremes
  }
  lines <- c(lines, holm_lines(study, extremes), paired_lines(study, paired[[1L]], paired[[2L]]))
  lines <- c(lines, sign_flip_lines(study))
  lines <- c(lines, anova_lines(study, ordinary))
  list("descriptives.txt" = descriptive_lines(study), "bootstrap.csv" = bootstrap_lines(ordinary, balanced, pairs),
       "jackknife.txt" = jackknife_file(study, ordinary, pairs), "tests.txt" = lines,
       "histograms.txt" = histogram_file(study, ordinary, pairs))
}

files <- run_study(new_study(load_dataset()))
dir.create("output", showWarnings = FALSE, recursive = TRUE)
for (name in names(files)) write_lines(name, files[[name]])
