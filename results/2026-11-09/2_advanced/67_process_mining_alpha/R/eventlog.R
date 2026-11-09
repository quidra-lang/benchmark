MONTH_DAYS <- c(31L,28L,31L,30L,31L,30L,31L,31L,30L,31L,30L,31L)
timestamp_minutes <- function(text) {
  month <- as.integer(substring(text,6L,7L))
  day <- as.integer(substring(text,9L,10L))
  hour <- as.integer(substring(text,12L,13L))
  minute <- as.integer(substring(text,15L,16L))
  if (!(month >= 1L && month <= 12L && day >= 1L && day <= MONTH_DAYS[month] && hour >= 0L && hour <= 23L && minute >= 0L && minute <= 59L)) return(NULL)
  ((sum(MONTH_DAYS[seq_len(month-1L)])+day-1L)*24L+hour)*60L+minute
}
read_inputs <- function() {
  lines <- readLines("input/eventlog.csv")[-1L]
  rows <- lapply(seq_along(lines),function(i) {
    f <- strsplit(lines[i],",",fixed=TRUE)[[1L]]
    list(line=i+1L,case_id=f[1L],activity=f[2L],timestamp=f[3L],resource=f[4L])
  })
  params <- list()
  for (line in readLines("input/params.txt")) {
    fields <- strsplit(line," ",fixed=TRUE)[[1L]]
    params[[fields[1L]]] <- fields[2L]
  }
  list(rows=rows,params=params)
}
group_cases <- function(events) {
  ids <- sort(unique(vapply(events,function(e) e$case_id,character(1))))
  lapply(ids,function(id) {
    ordered <- Filter(function(e) e$case_id == id,events)
    ordered <- ordered[order(
        vapply(ordered,function(e) e$time,integer(1)),
        vapply(ordered,function(e) e$line,integer(1))
    )]
    list(
        identifier=id,
        events=ordered,
        trace=vapply(ordered,function(e) e$activity,character(1)),
        duration=ordered[[length(ordered)]]$time-ordered[[1L]]$time
    )
  })
}
integer_median <- function(values) {
  ordered <- sort(values)
  n <- length(ordered)
  if (n %% 2L) q(ordered[(n+1L) %/% 2L]) else q(ordered[n %/% 2L]+ordered[n %/% 2L+1L],2)
}
