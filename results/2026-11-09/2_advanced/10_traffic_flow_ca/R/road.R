CHANGE_KINDS <- c("overtaking", "return", "avoidance")
turn_record <- function(target, weight) list2env(list(target = target, weight = weight, vehicles = 0), parent = emptyenv())
stop_record <- function(segment, cell, dwell) list2env(list(segment = segment, cell = cell, dwell = dwell, buses = 0), parent = emptyenv())

segment_record <- function(id, start, end, length, lanes, limit) {
  segment <- list2env(list(id = id, start = start, end = end, length = length, lanes = lanes, limit = limit,
    cells = matrix(0L, lanes, length), junction = NULL, turns = list(), stop = NULL,
    entered = 0, vehicle_sum = 0, speed_sum = 0, max_vehicles = 0, green_steps = 0,
    queue_sum = 0, max_queue = 0, failures = 0, passed = 0, blocked = 0,
    changes = setNames(rep(0, 3L), CHANGE_KINDS)), parent = emptyenv())
  segment
}

road_empty <- function(segment, lane, cell) segment$cells[lane, cell + 1L] == 0L
road_put <- function(segment, lane, cell, value) segment$cells[lane, cell + 1L] <- value
road_free <- function(segment, lane, cell, limit) {
  count <- 0L
  while (count < limit && cell + count + 1L < segment$length && road_empty(segment, lane, cell + count + 1L)) count <- count + 1L
  count
}
road_first <- function(segment, lane) {
  occupied <- which(segment$cells[lane, ] != 0L)
  if (length(occupied)) occupied[1L] - 1L else segment$length
}
road_safe <- function(segment, lane, cell) all(segment$cells[lane, seq.int(max(0L, cell - segment$limit) + 1L, cell + 1L)] == 0L)
vehicle_numbers <- function(segment, lane) unname(segment$cells[lane, segment$cells[lane, ] > 0L])
cells_text <- function(segment, lane, vehicles) paste(vapply(segment$cells[lane, ], function(value) if (value == 0L) "." else if (value == -1L) "#" else as.character(vehicles[[value]]$speed), character(1L)), collapse = "")

incident_record <- function(segment, lane, cell, start, end) list2env(list(segment = segment, lane = lane, cell = cell, start = start, end = end, state = "planned", active_start = 0, active_end = 0), parent = emptyenv())
update_incident <- function(incident, step) {
  event <- ""
  if (incident$state == "active" && step > incident$end) {
    incident$state <- "cleared"
    road_put(incident$segment, incident$lane, incident$cell, 0L)
    event <- "INCIDENT_END"
  } else if (incident$state == "planned" && step > incident$end) {
    incident$state <- "cancelled"
  } else if (incident$state == "planned" && step >= incident$start && road_empty(incident$segment, incident$lane, incident$cell)) {
    incident$state <- "active"
    road_put(incident$segment, incident$lane, incident$cell, -1L)
    incident$active_start <- step
    event <- "INCIDENT_START"
  }
  if (incident$state == "active") incident$active_end <- step
  event
}
