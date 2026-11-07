position_choices <- function(total, size, visit) {
  choice <- seq_len(size)
  repeat {
    visit(choice)
    index <- size
    while (index >= 1L && choice[index] == total - size + index) index <- index - 1L
    if (index == 0L) break
    choice[index] <- choice[index] + 1L
    if (index < size) {
      for (next_index in seq.int(index + 1L, size)) choice[next_index] <- choice[next_index - 1L] + 1L
    }
  }
}

reduced_fraction <- function(numerator, denominator) {
  first <- numerator
  second <- denominator
  while (second != 0) {
    remainder <- first %% second
    first <- second
    second <- remainder
  }
  c(numerator / first, denominator / first)
}

contrast <- function(first_total, first_size, second_total, second_size) second_size * first_total - first_size * second_total

value_counts <- function(values) {
  ordered <- ordered_values(values)
  runs <- rle(ordered)
  list(values = runs$values, counts = as.numeric(runs$lengths))
}

doubled_ranks <- function(values) {
  counts <- value_counts(values)
  ranks <- numeric(length(counts$values))
  smaller <- 0
  for (index in seq_along(ranks)) {
    ranks[index] <- 2 * smaller + counts$counts[index] + 1
    smaller <- smaller + counts$counts[index]
  }
  ranks[match(values, counts$values)]
}

split_list <- function(items, sizes) {
  parts <- vector("list", length(sizes))
  start <- 1L
  for (index in seq_along(sizes)) {
    size <- sizes[index]
    parts[[index]] <- items[seq.int(start, start + size - 1L)]
    start <- start + size
  }
  parts
}

sums_of_squares <- function(samples) {
  count <- sum(vapply(samples, length, integer(1L)))
  grand_mean <- sum(vapply(samples, sum, numeric(1L))) / (100 * count)
  between <- within <- 0
  for (sample in samples) {
    center <- mean_value(sample)
    difference <- center - grand_mean
    between <- between + length(sample) * (difference * difference)
    squares <- 0
    for (value in sample) {
      deviation <- value / 100 - center
      squares <- squares + deviation * deviation
    }
    within <- within + squares
  }
  c(between, within)
}

f_statistic <- function(between, within, groups, total) between / (groups - 1L) / (within / (total - groups))

h_statistic <- function(rank_sums, sizes, correction) {
  total <- 0
  for (index in seq_along(rank_sums)) total <- total + rank_sums[index] * rank_sums[index] / (4 * sizes[index])
  count <- sum(sizes)
  (12 * total / (count * (count + 1L)) - 3 * (count + 1L)) / correction
}
