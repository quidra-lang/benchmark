WEIGHTS <- c("logrank","gehan_wilcoxon","tarone_ware")
empty_totals <- function(groups) {
  n <- length(groups)
  list(groups=groups,events=numeric(n),observed=numeric(n),expected=numeric(n),covariance=matrix(0,n,n))
}
weighted_totals <- function(subjects,groups,weight,population) {
  result <- empty_totals(groups)
  collections <- lapply(groups,function(group) Filter(function(s) s$group == group,subjects))
  times <- sort(unique(vapply(Filter(function(s) s$event == 1L,subjects),`[[`,integer(1),"time")))
  for (time in times) {
    risk <- vapply(
        collections,
        function(rows) sum(vapply(rows,function(s) s$time >= time,logical(1))),
        numeric(1)
    )
    deaths <- vapply(
        collections,
        function(rows) sum(vapply(rows,function(s) s$time == time && s$event == 1L,logical(1))),
        numeric(1)
    )
    n <- sum(risk)
    d <- sum(deaths)
    value <- if (weight == "logrank") 1 else if (weight == "gehan_wilcoxon") n/population else sqrt(n/population)
    for (h in seq_along(groups)) {
      result$events[h] <- result$events[h]+deaths[h]
      result$observed[h] <- result$observed[h]+value*deaths[h]
      result$expected[h] <- result$expected[h]+value*(d*risk[h]/n)
      if (n < 2L) next
      factor <- value*value*(d*(n-d)/((n-1)*n*n))
      for (l in seq_along(groups)) {
        multiple <- if (h == l) risk[h]*(n-risk[h]) else -(risk[h]*risk[l])
        result$covariance[h,l] <- result$covariance[h,l]+factor*multiple
      }
    }
  }
  result
}
finish_test <- function(result) {
  df <- length(result$groups)-1L
  indices <- seq_len(df)
  difference <- result$observed[indices]-result$expected[indices]
  solution <- solve_system(result$covariance[indices,indices,drop=FALSE],difference)
  result$statistic <- total(difference*solution)
  result$degrees <- df
  result$p <- chi_square_p(result$statistic,df)
  result
}
weighted_test <- function(subjects,groups,weight,population) finish_test(weighted_totals(
    subjects,
    groups,
    weight,
    population
))
combine_strata <- function(strata,groups) {
  result <- empty_totals(groups)
  for (stratum in strata) {
    result$events <- result$events+stratum$events
    result$observed <- result$observed+stratum$observed
    result$expected <- result$expected+stratum$expected
    result$covariance <- result$covariance+stratum$covariance
  }
  finish_test(result)
}
