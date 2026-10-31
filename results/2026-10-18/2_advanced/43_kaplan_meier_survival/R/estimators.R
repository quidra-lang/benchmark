risk_sets <- function(subjects) {
  times <- sort(unique(vapply(subjects,`[[`,integer(1),"time")))
  risk <- length(subjects)
  rows <- list()
  for (time in times) {
    events <- sum(vapply(subjects,function(s) s$time == time && s$event == 1L,logical(1)))
    censored <- sum(vapply(subjects,function(s) s$time == time && s$event == 0L,logical(1)))
    rows[[length(rows)+1L]] <- list(time=time,risk=risk,events=events,censored=censored)
    risk <- risk-events-censored
  }
  rows
}
kaplan_meier <- function(subjects) {
  events <- Filter(function(r) r$events > 0L,risk_sets(subjects))
  survival <- 1
  greenwood <- hazard <- variance <- 0
  rows <- list()
  for (i in seq_along(events)) {
    event <- events[[i]]
    time <- event$time
    risk <- event$risk
    deaths <- event$events
    survival <- survival*((risk-deaths)/risk)
    if (risk == deaths) greenwood <- NULL else if (!is.null(greenwood)) greenwood <- greenwood+deaths/(risk*(risk-deaths))
    if (survival == 0) error <- lower <- upper <- NULL else {
      error <- survival*sqrt(greenwood)
      logarithm <- log(survival)
      omega <- Z95*sqrt(greenwood)/(-logarithm)
      lower <- exp(logarithm*exp(omega))
      upper <- exp(logarithm*exp(-omega))
    }
    hazard <- hazard+deaths/risk
    variance <- variance+deaths/(risk*risk)
    next_time <- if (i < length(events)) events[[i+1L]]$time else NULL
    censored <- sum(vapply(subjects,function(s) s$event == 0L && s$time >= time &&
      (is.null(next_time) || s$time < next_time),logical(1)))
    rows[[length(rows)+1L]] <- list(time=time,risk=risk,events=deaths,censored=censored,
      survival=survival,se=error,lower=lower,upper=upper,hazard=hazard,hazard_se=sqrt(variance))
  }
  rows
}
row_at <- function(rows,time) {
  for (row in rev(rows)) if (row$time <= time) return(row)
  list(survival=1,se=0,lower=NULL,upper=NULL,hazard=0,hazard_se=0)
}
life_table <- function(subjects,width,n) {
  survival <- 1
  variance <- 0
  rows <- list()
  for (i in seq_len(n)-1L) {
    start <- i*width
    stop <- (i+1L)*width
    risk <- sum(vapply(subjects,function(s) s$time >= start,logical(1)))
    deaths <- sum(vapply(subjects,function(s) start <= s$time && s$time < stop && s$event == 1L,logical(1)))
    withdrawn <- sum(vapply(
        subjects,
        function(s) start <= s$time && s$time < stop && s$event == 0L,
        logical(1)
    ))
    f <- 2*risk-withdrawn
    survival <- survival*((f-2*deaths)/f)
    variance <- variance+4*deaths/(f*(f-2*deaths))
    rows[[length(rows)+1L]] <- list(start=start,stop=stop,risk=risk,events=deaths,withdrawn=withdrawn,
      exposed=f/2,q=2*deaths/f,survival=survival,se=survival*sqrt(variance),hazard=2000*deaths/(width*(f-deaths)))
  }
  rows
}
