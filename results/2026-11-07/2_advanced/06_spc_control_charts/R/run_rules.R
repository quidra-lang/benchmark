zones <- function(limits) {
  upper <- (limits$ucl - limits$cl) / 3
  lower <- (limits$cl - limits$lcl) / 3
  c(limits, list(u1 = limits$cl + upper, u2 = limits$cl + 2 * upper, l1 = limits$cl - lower, l2 = limits$cl - 2 * lower))
}

new_signal <- function(chart, rule, start, end, value, direction) {
  list(chart = chart, rule = as.character(rule), start = start, end = end, value = value, direction = direction)
}

rule_direction <- function(rule, window, zone) {
  value <- tail(window, 1L)
  if (rule == 1L) {
    if (value > zone$ucl || value < zone$lcl) return(if (value > zone$cl) "UP" else "DOWN")
  } else if (rule %in% c(2L, 3L)) {
    upper <- if (rule == 2L) zone$u2 else zone$u1
    lower <- if (rule == 2L) zone$l2 else zone$l1
    count <- if (rule == 2L) 2L else 4L
    if (value > upper && sum(window > upper) >= count) return("UP")
    if (value < lower && sum(window < lower) >= count) return("DOWN")
  } else if (rule == 4L) {
    if (all(window > zone$cl)) return("UP")
    if (all(window < zone$cl)) return("DOWN")
  } else if (rule == 5L) {
    differences <- diff(window)
    if (all(differences > 0)) return("UP")
    if (all(differences < 0)) return("DOWN")
  } else if (rule == 6L) {
    differences <- diff(window)
    if (all(differences != 0) && all(head(differences > 0, -1L) != tail(differences > 0, -1L))) return("NONE")
  } else if (rule == 7L) {
    if (all(window > zone$l1 & window < zone$u1)) return("NONE")
  } else {
    if (all(window > zone$u1 | window < zone$l1) && any(window > zone$u1) && any(window < zone$l1)) return("NONE")
  }
  NULL
}

check_rules <- function(chart, numbers, values, limits, rules) {
  zone <- zones(limits)
  lengths <- c(1L, 3L, 5L, 8L, 6L, 14L, 15L, 8L)
  signals <- list()
  for (k in seq_along(values)) for (rule in rules) {
    size <- lengths[rule]
    if (k < size) next
    first <- k - size + 1L
    direction <- rule_direction(rule, values[seq.int(first, k)], zone)
    if (!is.null(direction)) signals[[length(signals) + 1L]] <- new_signal(chart, rule, numbers[first], numbers[k], values[k], direction)
  }
  signals
}
