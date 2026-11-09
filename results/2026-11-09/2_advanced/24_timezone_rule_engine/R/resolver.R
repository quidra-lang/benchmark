new_period <- function(start, offset, dst, abbreviation) {
  list(start = start, offset = offset, dst = dst, abbreviation = abbreviation)
}
same_state <- function(first, second) {
  first$offset == second$offset && first$dst == second$dst && first$abbreviation == second$abbreviation
}
new_timeline <- function(periods) {
  list(periods = periods, starts = vapply(periods, function(period) period$start, numeric(1)))
}
index_at <- function(timeline, time) findInterval(time, timeline$starts)
period_at <- function(timeline, time) timeline$periods[[index_at(timeline, time)]]
end_of <- function(timeline, index) {
  if (index < length(timeline$periods)) timeline$starts[index + 1] else pos_infinity
}
nearby <- function(timeline, first, last) {
  seq.int(index_at(timeline, first - 57600), index_at(timeline, last + 57600))
}
local_candidates <- function(timeline, local) {
  found <- integer()
  for (index in nearby(timeline, local, local)) {
    time <- local - timeline$periods[[index]]$offset
    if (timeline$starts[index] <= time && time < end_of(timeline, index)) found <- c(found, index)
  }
  found
}
skipping_transition <- function(timeline, local) {
  for (index in nearby(timeline, local, local)) if (index > 1) {
    start <- timeline$starts[index]
    if (start + timeline$periods[[index - 1]]$offset <= local && local < start + timeline$periods[[index]]$offset) return(index)
  }
  0L
}
