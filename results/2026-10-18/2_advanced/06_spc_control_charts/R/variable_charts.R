real_sum <- function(values) {
  total <- 0
  for (value in values) total <- total + value
  total
}

subgroup_statistics <- function(values, size) {
  lapply(seq_len(length(values) %/% size), function(number) {
    samples <- values[(number - 1L) * size + seq_len(size)]
    total <- sum(samples)
    squares <- sum(samples * samples)
    list(number = number, values = samples, total = total, squares = squares, mean = total / size,
         range = max(samples) - min(samples), sd = sqrt((size * squares - total * total) / (size * (size - 1L))))
  })
}

new_limits <- function(lcl, cl, ucl) list(lcl = lcl, cl = cl, ucl = ucl)
outside <- function(limits, value) value > limits$ucl | value < limits$lcl
moving_ranges <- function(values) abs(diff(values))

xbar_r_limits <- function(subgroups, size, constants) {
  count <- length(subgroups)
  mean <- sum(vapply(subgroups, function(group) group$total, numeric(1L))) / (count * size)
  range <- sum(vapply(subgroups, function(group) group$range, numeric(1L))) / count
  list(new_limits(mean - constants$a2 * range, mean, mean + constants$a2 * range),
       new_limits(constants$d3 * range, range, constants$d4 * range))
}

xbar_s_limits <- function(subgroups, size, constants) {
  count <- length(subgroups)
  mean <- sum(vapply(subgroups, function(group) group$total, numeric(1L))) / (count * size)
  sd <- real_sum(vapply(subgroups, function(group) group$sd, numeric(1L))) / count
  list(new_limits(mean - constants$a3 * sd, mean, mean + constants$a3 * sd),
       new_limits(constants$b3 * sd, sd, constants$b4 * sd))
}

i_mr_limits <- function(values, constants) {
  mean <- sum(values) / length(values)
  range <- sum(moving_ranges(values)) / (length(values) - 1L)
  list(new_limits(mean - 3 * range / constants$d2, mean, mean + 3 * range / constants$d2),
       new_limits(constants$d3 * range, range, constants$d4 * range))
}
