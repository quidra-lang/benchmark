NOT_APPLICABLE <- "NOT_APPLICABLE"
INDETERMINATE_P <- "INDETERMINATE{P}"
INDETERMINATE_D <- "INDETERMINATE{D}"
INDETERMINATE_DP <- "INDETERMINATE{DP}"
combine_children <- function(algorithm,children,evaluate,target,identifier) {
  states <- vector("list",length(children))
  outcome <- function(decision,reason="") list(decision=decision,reason=reason,states=states)
  if (algorithm == "only-one-applicable") {
    matched <- 0L
    for (i in seq_along(children)) {
      child <- children[i]
      checked <- target(child)
      states[[i]] <- list(kind="checked",target=checked)
      if (checked$status == "INDETERMINATE") return(outcome(INDETERMINATE_DP,checked$reason))
      if (checked$status == "MATCH") {
        if (matched != 0L) return(outcome(
            INDETERMINATE_DP,
            paste("multiple applicable",identifier(children[matched]),identifier(child))
        ))
        matched <- i
      }
    }
    if (matched == 0L) return(outcome(NOT_APPLICABLE))
    result <- evaluate(children[matched])
    states[[matched]] <- list(kind="evaluated",result=result)
    return(outcome(result$decision,result$reason))
  }
  decisions <- character()
  first_error <- ""
  for (i in seq_along(children)) {
    result <- evaluate(children[i])
    states[[i]] <- list(kind="evaluated",result=result)
    d <- result$decision
    decisions <- union(decisions,d)
    if (startsWith(d,"INDETERMINATE") && !nzchar(first_error)) first_error <- result$reason
    if (algorithm == "first-applicable" && d != NOT_APPLICABLE) return(outcome(d,result$reason))
    if (algorithm %in% c("deny-overrides","permit-unless-deny") && d == "DENY") return(outcome("DENY"))
    if (algorithm %in% c("permit-overrides","deny-unless-permit") && d == "PERMIT") return(outcome("PERMIT"))
  }
  if (algorithm == "deny-unless-permit") {
    d <- "DENY"
  } else if (algorithm == "permit-unless-deny") {
    d <- "PERMIT"
  } else if (algorithm == "first-applicable") {
    d <- NOT_APPLICABLE
  } else if (algorithm == "deny-overrides") {
    if (INDETERMINATE_DP %in% decisions || (INDETERMINATE_D %in% decisions && any(c(
        INDETERMINATE_P,
        "PERMIT"
    ) %in% decisions))) {
      d <- INDETERMINATE_DP
    } else if (INDETERMINATE_D %in% decisions) {
      d <- INDETERMINATE_D
    } else if ("PERMIT" %in% decisions) {
      d <- "PERMIT"
    } else if (INDETERMINATE_P %in% decisions) {
      d <- INDETERMINATE_P
    } else {
      d <- NOT_APPLICABLE
    }
  } else {
    if (INDETERMINATE_DP %in% decisions || (INDETERMINATE_P %in% decisions && any(c(
        INDETERMINATE_D,
        "DENY"
    ) %in% decisions))) {
      d <- INDETERMINATE_DP
    } else if (INDETERMINATE_P %in% decisions) {
      d <- INDETERMINATE_P
    } else if ("DENY" %in% decisions) {
      d <- "DENY"
    } else if (INDETERMINATE_D %in% decisions) {
      d <- INDETERMINATE_D
    } else {
      d <- NOT_APPLICABLE
    }
  }
  outcome(d,if (startsWith(d,"INDETERMINATE")) first_error else "")
}
