integer_divide <- function(a, b) {
  quotient <- floor(a / b)
  while (quotient * b > a) quotient <- quotient - 1
  while ((quotient + 1) * b <= a) quotient <- quotient + 1
  quotient
}

integer_gcd <- function(a, b) {
  a <- abs(a)
  while (b) {
    remainder <- a - integer_divide(a, b) * b
    a <- b
    b <- remainder
  }
  a
}

fraction <- function(numerator, denominator = 1) {
  divisor <- integer_gcd(numerator, denominator)
  c(integer_divide(abs(numerator), divisor) * sign(numerator), integer_divide(denominator, divisor))
}

fraction_compare <- function(a, b) sign(a[1L] * b[2L] - b[1L] * a[2L])
fraction_subtract <- function(a, b) fraction(a[1L] * b[2L] - b[1L] * a[2L], a[2L] * b[2L])
fraction_multiply <- function(a, b) fraction(a[1L] * b[1L], a[2L] * b[2L])
lift_of <- function(total, count, first, second) fraction(total * count, first * second)
meets_thresholds <- function(confidence, lift, params) fraction_compare(confidence, params$min_confidence) >= 0L && fraction_compare(lift, params$min_lift) >= 0L

rule_record <- function(itemset, antecedent, consequent, count, total, first, second) {
  list(itemset = itemset, antecedent = antecedent, consequent = consequent, count = count,
       support = fraction(count, total), confidence = fraction(count, first), lift = lift_of(total, count, first, second),
       leverage = fraction(total * count - first * second, total * total),
       conviction = if (first == count) NULL else fraction((total - second) * first, total * (first - count)),
       improvement = fraction(0), rank = 0L)
}

string_compare <- function(a, b) {
  if (identical(a, b)) return(0L)
  if (identical(sort(c(a, b), method = "radix")[1L], a)) -1L else 1L
}

rule_compare <- function(a, b) {
  confidence <- fraction_compare(b$confidence, a$confidence)
  if (confidence) return(confidence)
  lift <- fraction_compare(b$lift, a$lift)
  if (lift) return(lift)
  if (a$count != b$count) return(sign(b$count - a$count))
  first <- string_compare(itemset_text(a$antecedent), itemset_text(b$antecedent))
  if (first) first else string_compare(itemset_text(a$consequent), itemset_text(b$consequent))
}
