read_rules <- function() {
  lapply(read_lines("input/segment_rules.txt"), function(line) {
    words <- strsplit(line, " ", fixed = TRUE)[[1L]]
    conditions <- list()
    if (length(words) > 1L) {
      for (index in seq.int(2L, length(words), by = 3L)) {
        conditions[[length(conditions) + 1L]] <- list(feature = match(words[index], feature_names),
          comparison = words[index + 1L], threshold = as.numeric(words[index + 2L]))
      }
    }
    list(name = words[1L], conditions = conditions)
  })
}

rule_number <- function(rules, center) {
  for (index in seq_along(rules)) {
    holds <- vapply(rules[[index]]$conditions, function(condition) {
      if (condition$comparison == ">") center[condition$feature] > condition$threshold
      else center[condition$feature] < condition$threshold
    }, logical(1L))
    if (all(holds)) return(index)
  }
}

original_scale <- function(center, means, sds) {
  values <- means + sds * center
  values[sqrt_features] <- values[sqrt_features] * values[sqrt_features]
  values
}
