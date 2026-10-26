instance_sequence <- function(rules) {
  instances <- list()
  for (rule in rules) for (year in seq.int(rule$from, rule$to)) {
    instances[[length(instances) + 1]] <- list(rule = rule, nominal = day_spec_value(rule$day, year, rule$month) * seconds_per_day + rule$at)
  }
  if (length(instances)) {
    nominal <- vapply(instances, function(item) item$nominal, numeric(1))
    numbers <- vapply(instances, function(item) item$rule$number, numeric(1))
    instances <- instances[order(nominal, numbers, method = "radix")]
  }
  instances
}
adjustment <- function(type, offset, save) {
  if (type == "u") 0 else if (type == "s") offset else offset + save
}
run_instances <- function(instances, offset, start, until) {
  pre_start <- list()
  applied <- list()
  save <- 0
  for (instance in instances) {
    rule <- instance$rule
    time <- instance$nominal - adjustment(rule$at_type, offset, save)
    if (!is.null(until) && time >= until$value - adjustment(until$type, offset, save)) break
    if (time <= start) {
      pre_start[[length(pre_start) + 1]] <- rule
    } else {
      applied[[length(applied) + 1]] <- list(time = time, rule = rule)
    }
    save <- rule$save
  }
  end <- if (is.null(until)) pos_infinity else until$value - adjustment(until$type, offset, save)
  list(pre_start = pre_start, applied = applied, end = end)
}
abbreviation <- function(format_text, save, letter) {
  position <- regexpr("/", format_text, fixed = TRUE)[1]
  if (position > 0) {
    if (save == 0) return(substr(format_text, 1, position - 1))
    return(substring(format_text, position + 1))
  }
  gsub("%s", letter, format_text, fixed = TRUE)
}
