integer_text <- function(value) sprintf("%.0f", value)
itemset_text <- function(itemset) paste(itemset, collapse = "+")
split_itemset_text <- function(key) if (nzchar(key)) strsplit(key, "+", fixed = TRUE)[[1L]] else character()

fraction_text <- function(value) {
  numerator <- abs(value[1L])
  denominator <- value[2L]
  scaled <- integer_divide(10000 * numerator, denominator)
  decimal <- paste0(integer_text(integer_divide(scaled, 10000)), ".", sprintf("%04.0f", scaled - integer_divide(scaled, 10000) * 10000))
  if (value[1L] < 0 && scaled > 0) decimal <- paste0("-", decimal)
  paste0(if (value[1L] < 0) "-" else "", integer_text(numerator), "/", integer_text(denominator), "=", decimal)
}

percent_text <- function(part, whole) {
  scaled <- integer_divide(10000 * part, whole)
  paste0(integer_text(integer_divide(scaled, 100)), ".", sprintf("%02.0f", scaled - integer_divide(scaled, 100) * 100), "%")
}

money_text <- function(cents) paste0(integer_text(integer_divide(cents, 100)), ".", sprintf("%02.0f", cents - integer_divide(cents, 100) * 100))
rule_arrow <- function(rule) paste(itemset_text(rule$antecedent), "->", itemset_text(rule$consequent))
text_line <- function(...) paste(vapply(list(...), function(value) if (is.numeric(value)) integer_text(value) else value, character(1L)), collapse = " ")

rules_csv <- function(rules) c("rank,antecedent,consequent,count,support,confidence,lift,leverage,conviction,improvement", vapply(rules, function(rule) {
  paste(c(integer_text(rule$rank), itemset_text(rule$antecedent), itemset_text(rule$consequent), integer_text(rule$count),
          fraction_text(rule$support), fraction_text(rule$confidence), fraction_text(rule$lift), fraction_text(rule$leverage),
          if (is.null(rule$conviction)) "INF" else fraction_text(rule$conviction), fraction_text(rule$improvement)), collapse = ",")
}, character(1L)))

write_report <- function(name, lines) writeLines(lines, file.path("output", name), useBytes = TRUE)
