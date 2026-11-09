domain_point <- function(domains,index) {
  result <- list()
  for (domain in rev(domains)) {
    result[[domain$name]] <- domain$values[[index %% length(domain$values)+1L]]
    index <- index %/% length(domain$values)
  }
  result
}
domain_points <- function(domains) lapply(
    seq_len(prod(vapply(domains,function(d) length(d$values),integer(1))))-1L,
    function(i) domain_point(domains,i)
)
day_notation <- function(days) {
  ordered <- sort(unique(days))
  first <- last <- ordered[1L]
  runs <- character()
  for (day in ordered[-1L]) {
    if (day != last+1L) {
      runs <- c(runs,paste(first,last,sep="-"))
      first <- day
    }
    last <- day
  }
  paste(c(runs,paste(first,last,sep="-")),collapse=",")
}
rule_blocker <- function(rule,elements,standalone) {
  for (earlier in elements[[rule$parent]]$children) {
    if (earlier == rule$index) break
    if (standalone[earlier] != NOT_APPLICABLE) return(earlier)
  }
  0L
}
conflict_winner <- function(policy,earlier,later) {
  if (policy$behavior == "first-applicable") return(earlier$index)
  effect <- if (policy$behavior %in% c("deny-overrides","permit-unless-deny")) "DENY" else "PERMIT"
  if (earlier$behavior == effect) earlier$index else later$index
}
