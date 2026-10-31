class_record <- function(name, vmax, weight, overtakes, stops) list(name = name, vmax = vmax, weight = weight, overtakes = overtakes, stops = stops)
vehicle_record <- function(number, class, source, arrival) list2env(list(number = number, class = class, source = source, arrival = arrival,
  inserted = 0, exited = 0, sink = "", segment = NULL, lane = 0, cell = 0, speed = 0, turn = NULL, route = character(),
  steps = 0, distance = 0, stopped_steps = 0, stop_count = 0, lane_changes = 0, dwell = 0, completed_stops = character()), parent = emptyenv())
max_speed <- function(vehicle) min(vehicle$class$vmax, vehicle$segment$limit)
place_vehicle <- function(vehicle, segment, lane, cell) {
  if (!is.null(vehicle$segment)) road_put(vehicle$segment, vehicle$lane, vehicle$cell, 0L)
  road_put(segment, lane, cell, vehicle$number)
  vehicle$segment <- segment
  vehicle$lane <- lane
  vehicle$cell <- cell
}
leave_vehicle <- function(vehicle) {
  road_put(vehicle$segment, vehicle$lane, vehicle$cell, 0L)
  vehicle$segment <- NULL
}
heading_for_stop <- function(vehicle) {
  if (is.null(vehicle$segment) || !vehicle$class$stops || is.null(vehicle$segment$stop) || vehicle$segment$id %in% vehicle$completed_stops) return(FALSE)
  vehicle$cell <= vehicle$segment$stop$cell
}
travel_time <- function(vehicle) vehicle$exited - vehicle$inserted + 1L
random_slowdown <- function(speed, previous, value, moving_probability, stopped_probability) {
  probability <- if (previous == 0L) stopped_probability else moving_probability
  if (speed > 0L && integer_mod(value, 1000) < probability) speed - 1L else speed
}
