capability_indices <- function(mean, sigma, settings) {
  potential <- (settings$usl - settings$lsl) / (6 * sigma)
  upper <- (settings$usl - mean) / (3 * sigma)
  lower <- (mean - settings$lsl) / (3 * sigma)
  c(potential, upper, lower, min(upper, lower))
}

confidence_interval <- function(index, count, z) {
  delta <- z * sqrt(1 / (9 * count) + index * index / (2 * (count - 1L)))
  c(index - delta, index + delta)
}

capability_verdict <- function(cpk) {
  if (cpk >= 1.33) "capable" else if (cpk >= 1.00) "marginal" else "incapable"
}

histogram_rows <- function(values, settings) {
  width <- settings$histogram_bin
  low <- width * floor(min(min(values), settings$lsl) / width)
  high <- width * floor(max(max(values), settings$usl) / width) + width
  frequencies <- tabulate(as.integer((values - low) %/% width + 1), nbins = as.integer((high - low) %/% width))
  top <- max(frequencies)
  points <- c(lsl = settings$lsl, target = settings$target, usl = settings$usl)
  lapply(seq_along(frequencies), function(index) {
    lower <- low + (index - 1L) * width
    upper <- lower + width - 1L
    frequency <- frequencies[index]
    list(lower = lower, upper = upper, frequency = frequency, length = (50L * frequency + top - 1L) %/% top,
         marks = names(points)[points >= lower & points <= upper])
  })
}

capability <- function(subgroups, settings, constants) {
  values <- unlist(lapply(subgroups, function(group) group$values), use.names = FALSE)
  count <- length(values)
  mean <- sum(values) / count
  rbar <- sum(vapply(subgroups, function(group) group$range, numeric(1L))) / length(subgroups)
  sbar <- real_sum(vapply(subgroups, function(group) group$sd, numeric(1L))) / length(subgroups)
  within <- rbar / constants$d2
  sbar_sigma <- sbar / constants$c4
  squares <- real_sum((values - mean) * (values - mean))
  overall <- sqrt(squares / (count - 1L))
  cp <- capability_indices(mean, within, settings)
  pp <- capability_indices(mean, overall, settings)
  offset <- mean - settings$target
  cpm <- (settings$usl - settings$lsl) / (6 * sqrt(overall * overall + offset * offset))
  below <- sum(values < settings$lsl)
  above <- sum(values > settings$usl)
  list(count = count, mean = mean, sigma_within = within, sigma_sbar = sbar_sigma, sigma_overall = overall,
       cp = cp[1L], cpu = cp[2L], cpl = cp[3L], cpk = cp[4L], pp = pp[1L], ppu = pp[2L], ppl = pp[3L], ppk = pp[4L], cpm = cpm,
       cpk_ci = confidence_interval(cp[4L], count, settings$ci_z), ppk_ci = confidence_interval(pp[4L], count, settings$ci_z),
       below = below, above = above, ppm = 1000000 * (below + above) / count,
       verdict = capability_verdict(cp[4L]), bins = histogram_rows(values, settings))
}
