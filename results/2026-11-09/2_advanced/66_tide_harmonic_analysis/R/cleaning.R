median_value <- function(values) {
  ordered <- sort(values)
  n <- length(ordered)
  if (n %% 2L) ordered[(n+1L) %/% 2L] else (ordered[n %/% 2L]+ordered[n %/% 2L+1L])/2
}
prepare_record <- function(record,minimum_run) {
  values <- record$values
  numeric <- sort(as.integer(names(values)[!is.na(values)]))
  first <- numeric[1L]
  last <- tail(numeric,1L)
  reasons <- setNames(rep("",last-first+1L),as.character(first:last))
  for (t in first:last) {
    key <- as.character(t)
    if (!(key %in% names(values))) reasons[key] <- "absent" else if (is.na(values[[key]])) reasons[key] <- "na"
  }
  runs <- list()
  cursor <- 1L
  while (cursor <= length(numeric)) {
    start <- stop <- numeric[cursor]
    while (cursor < length(numeric) && numeric[cursor+1L] == stop+1L && values[[as.character(numeric[cursor+1L])]] == values[[as.character(start)]]) {
      cursor <- cursor+1L
      stop <- numeric[cursor]
    }
    if (stop-start+1L >= minimum_run) {
      runs[[length(runs)+1L]] <- list(start=start,stop=stop,value=values[[as.character(start)]])
      reasons[as.character(seq.int(start+1L,stop))] <- "flat"
    }
    cursor <- cursor+1L
  }
  list(
      first=first,
      last=last,
      record_length=last-first,
      numeric_times=numeric,
      reasons=reasons,
      flat_runs=runs,
      candidates=numeric[reasons[as.character(numeric)] == ""],
      values=values,
      rows=record$rows
  )
}
list_gaps <- function(cleaning) {
  gaps <- list()
  start <- cleaning$first
  while (start <= cleaning$last) {
    if (cleaning$reasons[[as.character(start)]] == "") {
      start <- start+1L
      next
    }
    stop <- start
    while (stop < cleaning$last && cleaning$reasons[[as.character(stop+1L)]] != "") stop <- stop+1L
    causes <- unique(cleaning$reasons[as.character(start:stop)])
    gaps[[length(gaps)+1L]] <- list(
        start=start,
        stop=stop,
        cause=if (length(causes) == 1L) causes[[1L]] else "mixed"
    )
    start <- stop+1L
  }
  gaps
}
detect_spikes <- function(cleaning,residuals,settings) {
  tested <- 0L
  spikes <- list()
  for (t in cleaning$candidates) {
    key <- as.character(t)
    neighbors <- residuals[as.character(cleaning$candidates[abs(cleaning$candidates-t) <= settings$spike_window])]
    if (length(neighbors) < settings$spike_minimum) next
    tested <- tested+1L
    center <- median_value(neighbors)
    mad <- median_value(abs(neighbors-center))
    limit <- max(settings$spike_factor*1.4826*mad,settings$spike_floor)
    if (abs(residuals[[key]]-center) > limit) {
      cleaning$reasons[key] <- "spike"
      spikes[[length(spikes)+1L]] <- list(
          time=t,
          value=cleaning$values[[key]],
          residual=residuals[[key]],
          median=center,
          mad=mad,
          limit=limit
      )
    }
  }
  cleaning$tested <- tested
  cleaning$spikes <- spikes
  cleaning$usable <- cleaning$candidates[cleaning$reasons[as.character(cleaning$candidates)] == ""]
  cleaning$gaps <- list_gaps(cleaning)
  cleaning
}
