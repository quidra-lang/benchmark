script_args <- grep("^--file=", commandArgs(), value = TRUE)
source_dir <- if (length(script_args)) dirname(sub("^--file=", "", script_args[1L])) else "R"
for (unit in c("minstd", "road", "vehicles", "signals", "stats")) source(file.path(source_dir, paste0(unit, ".R")))

mutable <- function(...) list2env(list(...), parent = emptyenv())
time_text <- function(step) sprintf("%04.0f", step)
read_lines <- function(name) readLines(file.path("input", name), warn = FALSE)
queue_size <- function(source) max(0L, length(source$queue) - source$head + 1L)

load_simulation <- function() {
  a <- mutable(segments = list(), segment_by_id = list(), junctions = list(), incidents = list(), stops = list(), classes = list(), sources = list(), sinks = character(),
               detectors = list(), diagrams = list(), rings = list(), vehicles = list(), intervals = list(), events = character(), track_numbers = numeric(), tracks = list())
  for (file in c("network.txt", "demand.txt", "params.txt")) for (line in read_lines(file)) {
    tokens <- strsplit(line, " ", fixed = TRUE)[[1L]]
    kind <- tokens[1L]
    fields <- tokens[-1L]
    if (kind == "SEGMENT") {
      segment <- segment_record(fields[1L], fields[2L], fields[3L], as.numeric(fields[4L]), as.numeric(fields[5L]), as.numeric(fields[6L]))
      a$segments[[length(a$segments) + 1L]] <- segment
      a$segment_by_id[[segment$id]] <- segment
    } else if (kind == "JUNCTION") {
      junction <- junction_record(fields[1L], as.numeric(fields[2L]), fields[-c(1L, 2L)])
      for (segment in a$segments) if (segment$end == junction$node) {
        segment$junction <- junction
        junction$incoming[[length(junction$incoming) + 1L]] <- segment
      }
      a$junctions[[length(a$junctions) + 1L]] <- junction
    } else if (kind == "INCIDENT") {
      a$incidents[[length(a$incidents) + 1L]] <- do.call(incident_record, c(list(a$segment_by_id[[fields[1L]]]), as.list(as.numeric(fields[-1L]))))
    } else if (kind == "STOP") {
      segment <- a$segment_by_id[[fields[1L]]]
      segment$stop <- stop_record(segment, as.numeric(fields[2L]), as.numeric(fields[3L]))
      a$stops[[length(a$stops) + 1L]] <- segment$stop
    } else if (kind == "CLASS") {
      a$classes[[length(a$classes) + 1L]] <- class_record(fields[1L], as.numeric(fields[2L]), as.numeric(fields[3L]), fields[4L] == "Y", fields[5L] == "Y")
    } else if (kind == "SOURCE") {
      rates <- lapply(fields[-1L], function(token) as.numeric(strsplit(token, ":", fixed = TRUE)[[1L]]))
      entry <- Filter(function(segment) segment$start == fields[1L], a$segments)[[1L]]
      a$sources[[length(a$sources) + 1L]] <- mutable(node = fields[1L], rates = rates, segment = entry, queue = integer(), head = 1L, queue_start = 0, queue_max = 0)
    } else if (kind == "SINK") {
      a$sinks <- c(a$sinks, fields[1L])
    } else if (kind == "TURN") {
      segment <- a$segment_by_id[[fields[1L]]]
      segment$turns[[length(segment$turns) + 1L]] <- turn_record(a$segment_by_id[[fields[2L]]], as.numeric(fields[3L]))
    } else if (kind == "seed") a$seed <- as.numeric(fields[1L])
    else if (kind == "steps") a$steps <- as.numeric(fields[1L])
    else if (kind == "dawdle") {
      a$dawdle <- as.numeric(fields[1L])
      a$dawdle_stopped <- as.numeric(fields[2L])
    } else if (kind == "interval") a$interval_length <- as.numeric(fields[1L])
    else if (kind == "bin") a$bin_width <- as.numeric(fields[1L])
    else if (kind == "detector") {
      a$detectors[[length(a$detectors) + 1L]] <- list(name = fields[1L], segment = a$segment_by_id[[fields[2L]]], cell = as.numeric(fields[3L]), width = as.numeric(fields[4L]))
    } else if (kind == "diagram") {
      a$diagrams[[length(a$diagrams) + 1L]] <- mutable(segment = a$segment_by_id[[fields[1L]]], lane = as.numeric(fields[2L]), start = as.numeric(fields[3L]), end = as.numeric(fields[4L]), lines = character())
    } else if (kind == "track") {
      a$track_numbers <- as.numeric(fields)
      a$tracks <- setNames(lapply(fields, function(field) character()), fields)
    } else if (kind == "ring") {
      values <- as.numeric(fields)
      a$rings[[length(a$rings) + 1L]] <- list(number = length(a$rings) + 1L, length = values[1L], vmax = values[2L], warmup = values[3L], measure = values[4L], seed = values[5L], counts = values[-seq_len(5L)])
    }
  }
  a
}

record_event <- function(a, step, text) a$events <- c(a$events, paste(time_text(step), text))
vehicles_on <- function(a, segment) {
  numbers <- unlist(lapply(seq_len(segment$lanes), function(lane) vehicle_numbers(segment, lane)), use.names = FALSE)
  a$vehicles[numbers]
}
enter_segment <- function(a, vehicle, segment) {
  vehicle$route <- c(vehicle$route, segment$id)
  segment$entered <- segment$entered + 1
  if (!is.null(segment$junction)) {
    weights <- vapply(segment$turns, function(turn) turn$weight, numeric(1L))
    vehicle$turn <- segment$turns[[select_weighted(weights, draw(a$rng))]]
  }
}
source_rate <- function(source, step) {
  for (period in source$rates) if (step <= period[2L]) return(period[1L])
  0
}
new_interval <- function(count) mutable(arrivals = 0, insertions = 0, exits = 0, vehicle_steps = 0, speed_sum = 0, passing = rep(0, count), occupancy = rep(0, count), occupancy_speed = rep(0, count))

arrive <- function(a, step, interval) {
  weights <- vapply(a$classes, function(class) class$weight, numeric(1L))
  for (source in a$sources) if (integer_mod(draw(a$rng), 1000) < source_rate(source, step)) {
    class <- a$classes[[select_weighted(weights, draw(a$rng))]]
    number <- length(a$vehicles) + 1L
    vehicle <- vehicle_record(number, class, source$node, step)
    a$vehicles[[number]] <- vehicle
    source$queue <- c(source$queue, number)
    interval$arrivals <- interval$arrivals + 1
  }
}

insert_vehicles <- function(a, step, interval) {
  for (source in a$sources) {
    segment <- source$segment
    while (queue_size(source)) {
      best <- 0L
      best_first <- -1L
      for (lane in seq_len(segment$lanes)) if (road_empty(segment, lane, 0L)) {
        first <- road_first(segment, lane)
        if (first > best_first) {
          best <- lane
          best_first <- first
        }
      }
      if (!best) break
      vehicle <- a$vehicles[[source$queue[source$head]]]
      source$head <- source$head + 1L
      place_vehicle(vehicle, segment, best, 0L)
      vehicle$inserted <- step
      enter_segment(a, vehicle, segment)
      interval$insertions <- interval$insertions + 1
    }
    size <- queue_size(source)
    if (size && source$queue_start == 0L) {
      source$queue_start <- step
      source$queue_max <- 0
    }
    if (source$queue_start != 0L) {
      source$queue_max <- max(source$queue_max, size)
      if (!size) {
        record_event(a, step, line_text("QUEUE", source$node, "from", source$queue_start, "max", source$queue_max))
        source$queue_start <- 0
      }
    }
  }
}

desired_lane <- function(vehicle) {
  segment <- vehicle$segment
  lane <- vehicle$lane
  cell <- vehicle$cell
  top <- max_speed(vehicle)
  here <- road_free(segment, lane, cell, top + 1L)
  want <- min(vehicle$speed + 1L, top)
  ahead <- cell + here + 1L
  if (here < top + 1L && ahead < segment$length && segment$cells[lane, ahead + 1L] == -1L) {
    for (target in c(lane + 1L, lane - 1L)) if (target >= 1L && target <= segment$lanes && road_free(segment, target, cell, top + 1L) > here && road_safe(segment, target, cell)) return(list(lane = target, kind = "avoidance"))
  }
  if (heading_for_stop(vehicle)) return(if (lane >= 2L && road_safe(segment, lane - 1L, cell)) list(lane = lane - 1L, kind = "return") else list(lane = lane, kind = ""))
  if (vehicle$class$overtakes && lane + 1L <= segment$lanes && here < want && road_free(segment, lane + 1L, cell, top + 1L) > here && road_safe(segment, lane + 1L, cell)) return(list(lane = lane + 1L, kind = "overtaking"))
  if (lane >= 2L && road_free(segment, lane - 1L, cell, top + 1L) > want && road_safe(segment, lane - 1L, cell)) return(list(lane = lane - 1L, kind = "return"))
  list(lane = lane, kind = "")
}

change_lanes <- function(a) {
  changes <- list()
  for (segment in a$segments) {
    if (segment$lanes < 2L) next
    reserved <- matrix(FALSE, segment$lanes, segment$length)
    for (lane in seq_len(segment$lanes)) for (number in vehicle_numbers(segment, lane)) {
      vehicle <- a$vehicles[[number]]
      if (vehicle$dwell > 0L) next
      desired <- desired_lane(vehicle)
      if (desired$lane != lane && !reserved[desired$lane, vehicle$cell + 1L]) {
        reserved[desired$lane, vehicle$cell + 1L] <- TRUE
        changes[[length(changes) + 1L]] <- list(vehicle = vehicle, lane = desired$lane, kind = desired$kind)
      }
    }
  }
  for (change in changes) {
    vehicle <- change$vehicle
    segment <- vehicle$segment
    place_vehicle(vehicle, segment, change$lane, vehicle$cell)
    vehicle$lane_changes <- vehicle$lane_changes + 1
    segment$changes[change$kind] <- segment$changes[change$kind] + 1
  }
}

processing_order <- function(a) {
  moves <- list()
  for (segment in a$segments) for (lane in seq_len(segment$lanes)) for (number in rev(vehicle_numbers(segment, lane))) {
    vehicle <- a$vehicles[[number]]
    moves[[length(moves) + 1L]] <- mutable(vehicle = vehicle, segment = segment, cell = vehicle$cell, speed = 0)
  }
  moves
}

determine_speed <- function(a, vehicle, step) {
  segment <- vehicle$segment
  lane <- vehicle$lane
  cell <- vehicle$cell
  accelerated <- min(vehicle$speed + 1L, max_speed(vehicle))
  gap <- road_free(segment, lane, cell, accelerated)
  if (gap < accelerated && cell + gap == segment$length - 1L) {
    if (is.null(segment$junction)) gap <- accelerated else if (is_green(segment, step)) {
      target <- vehicle$turn$target
      gap <- gap + road_free(target, min(lane, target$lanes), -1L, accelerated - gap)
    }
  }
  if (heading_for_stop(vehicle)) gap <- min(gap, segment$stop$cell - cell)
  speed <- random_slowdown(min(accelerated, gap), vehicle$speed, draw(a$rng), a$dawdle, a$dawdle_stopped)
  if (vehicle$dwell > 0L) {
    speed <- 0L
    vehicle$dwell <- vehicle$dwell - 1L
  }
  speed
}

move_vehicles <- function(a, moves, step, interval) {
  passing <- list()
  for (move in moves) {
    vehicle <- move$vehicle
    segment <- move$segment
    if (move$cell + move$speed < segment$length) place_vehicle(vehicle, segment, vehicle$lane, move$cell + move$speed)
    else if (is.null(segment$junction)) {
      leave_vehicle(vehicle)
      vehicle$exited <- step
      vehicle$sink <- segment$end
      interval$exits <- interval$exits + 1
    } else passing[[length(passing) + 1L]] <- move
  }
  for (move in passing) {
    vehicle <- move$vehicle
    segment <- move$segment
    target <- vehicle$turn$target
    lane <- min(vehicle$lane, target$lanes)
    overshoot <- move$cell + move$speed - segment$length
    cell <- min(overshoot, road_first(target, lane) - 1L)
    if (cell < overshoot) segment$blocked <- segment$blocked + 1
    if (cell >= 0L) {
      place_vehicle(vehicle, target, lane, cell)
      move$speed <- segment$length - move$cell + cell
      segment$passed <- segment$passed + 1
      vehicle$turn$vehicles <- vehicle$turn$vehicles + 1
      enter_segment(a, vehicle, target)
    } else {
      place_vehicle(vehicle, segment, vehicle$lane, segment$length - 1L)
      move$speed <- segment$length - 1L - move$cell
    }
  }
}

aggregate_vehicle <- function(a, move, step, interval) {
  vehicle <- move$vehicle
  speed <- move$speed
  vehicle$steps <- vehicle$steps + 1
  vehicle$distance <- vehicle$distance + speed
  if (speed == 0L) {
    vehicle$stopped_steps <- vehicle$stopped_steps + 1
    if (vehicle$speed > 0L) vehicle$stop_count <- vehicle$stop_count + 1
  }
  vehicle$speed <- speed
  interval$vehicle_steps <- interval$vehicle_steps + 1
  interval$speed_sum <- interval$speed_sum + speed
  if (heading_for_stop(vehicle) && vehicle$lane == 1L && vehicle$cell == vehicle$segment$stop$cell) {
    stop <- vehicle$segment$stop
    vehicle$completed_stops <- c(vehicle$completed_stops, vehicle$segment$id)
    vehicle$dwell <- stop$dwell
    stop$buses <- stop$buses + 1
    record_event(a, step, line_text("BUS_STOP", vehicle$number, vehicle$segment$id, "cell", stop$cell))
  }
  if (vehicle$number %in% a$track_numbers) {
    text <- if (is.null(vehicle$segment)) line_text(time_text(step), "EXIT", vehicle$speed) else line_text(time_text(step), vehicle$segment$id, vehicle$lane, vehicle$cell, vehicle$speed)
    key <- integer_text(vehicle$number)
    a$tracks[[key]] <- c(a$tracks[[key]], text)
  }
  for (index in seq_along(a$detectors)) {
    detector <- a$detectors[[index]]
    if (!identical(move$segment, detector$segment) || move$cell >= detector$cell) next
    if (!identical(vehicle$segment, detector$segment) || vehicle$cell >= detector$cell) interval$passing[index] <- interval$passing[index] + 1
  }
}

aggregate_state <- function(a, step, interval) {
  for (index in seq_along(a$detectors)) {
    detector <- a$detectors[[index]]
    for (vehicle in vehicles_on(a, detector$segment)) if (vehicle$cell >= detector$cell && vehicle$cell < detector$cell + detector$width) {
      interval$occupancy[index] <- interval$occupancy[index] + 1
      interval$occupancy_speed[index] <- interval$occupancy_speed[index] + vehicle$speed
    }
  }
  for (segment in a$segments) {
    present <- vehicles_on(a, segment)
    segment$vehicle_sum <- segment$vehicle_sum + length(present)
    segment$speed_sum <- segment$speed_sum + sum(vapply(present, function(vehicle) vehicle$speed, numeric(1L)))
    segment$max_vehicles <- max(segment$max_vehicles, length(present))
    if (is.null(segment$junction)) next
    green <- is_green(segment, step)
    if (green) segment$green_steps <- segment$green_steps + 1
    queued <- sum(vapply(present, function(vehicle) vehicle$speed == 0L, logical(1L)))
    segment$queue_sum <- segment$queue_sum + queued
    segment$max_queue <- max(segment$max_queue, queued)
    if (step < a$steps && queued > 0L && green && !is_green(segment, step + 1L)) segment$failures <- segment$failures + 1
  }
  for (diagram in a$diagrams) if (step >= diagram$start && step <= diagram$end) {
    segment <- diagram$segment
    signal <- if (is.null(segment$junction)) "E" else if (is_green(segment, step)) "G" else "R"
    diagram$lines <- c(diagram$lines, paste(time_text(step), cells_text(segment, diagram$lane, a$vehicles), signal))
  }
}

run_simulation <- function(a) {
  a$rng <- minstd(a$seed)
  for (step in seq_len(a$steps)) {
    for (incident in a$incidents) {
      event <- update_incident(incident, step)
      if (nzchar(event)) record_event(a, step, line_text(event, incident$segment$id, "lane", incident$lane, "cell", incident$cell))
    }
    if (integer_mod(step - 1L, a$interval_length) == 0L) a$intervals[[length(a$intervals) + 1L]] <- new_interval(length(a$detectors))
    interval <- a$intervals[[length(a$intervals)]]
    arrive(a, step, interval)
    insert_vehicles(a, step, interval)
    change_lanes(a)
    moves <- processing_order(a)
    for (move in moves) move$speed <- determine_speed(a, move$vehicle, step)
    move_vehicles(a, moves, step, interval)
    for (move in moves) aggregate_vehicle(a, move, step, interval)
    aggregate_state(a, step, interval)
  }
  for (source in a$sources) if (source$queue_start != 0L) record_event(a, a$steps, line_text("QUEUE", source$node, "from", source$queue_start, "max", source$queue_max, "open"))
  invisible(a)
}

run_ring <- function(ring, count, dawdle, dawdle_stopped) {
  rng <- minstd(ring$seed)
  positions <- vapply(seq_len(count) - 1L, function(index) integer_divide(index * ring$length, count), numeric(1L))
  speeds <- rep(0, count)
  total <- 0
  for (step in seq_len(ring$warmup + ring$measure)) {
    order <- order(positions, decreasing = TRUE)
    next_speeds <- rep(0, count)
    for (rank in seq_len(count)) {
      index <- order[rank]
      ahead <- order[if (rank > 1L) rank - 1L else count]
      gap <- integer_mod(positions[ahead] - positions[index] - 1L, ring$length)
      speed <- min(speeds[index] + 1L, ring$vmax, gap)
      next_speeds[index] <- random_slowdown(speed, speeds[index], draw(rng), dawdle, dawdle_stopped)
    }
    positions <- vapply(seq_len(count), function(index) integer_mod(positions[index] + next_speeds[index], ring$length), numeric(1L))
    speeds <- next_speeds
    if (step > ring$warmup) total <- total + sum(speeds)
  }
  total
}

enumerate_routes <- function(segment) {
  if (is.null(segment$junction)) return(list(list(ids = segment$id, sink = segment$end, share = c(1, 1))))
  total <- sum(vapply(segment$turns, function(turn) turn$weight, numeric(1L)))
  routes <- list()
  for (turn in segment$turns) for (route in enumerate_routes(turn$target)) {
    routes[[length(routes) + 1L]] <- list(ids = c(segment$id, route$ids), sink = route$sink, share = share_multiply(c(turn$weight, total), route$share))
  }
  routes
}
vehicle_sum <- function(vehicles, field) sum(vapply(vehicles, function(vehicle) vehicle[[field]], numeric(1L)))
travel_sum <- function(vehicles) sum(vapply(vehicles, travel_time, numeric(1L)))
exited_vehicles <- function(vehicles) Filter(function(vehicle) vehicle$exited > 0L, vehicles)
flag_text <- function(value) if (value) "Y" else "N"
optional_step <- function(value) if (value > 0L) integer_text(value) else "-"
share_text <- function(share) frac(share[1L], share[2L])

travel_block <- function(heading, vehicles, width) {
  count <- length(vehicles)
  if (!count) return(line_text(heading, "exited", 0L))
  times <- sort(vapply(vehicles, travel_time, numeric(1L)))
  c(line_text(heading, "exited", count, "min", times[1L], "p50", percentile(times, 50), "p90", percentile(times, 90), "max", tail(times, 1L), "mean", dec(sum(times), count, 2L)), histogram_lines(times, width))
}

travel_report <- function(a) {
  exited <- exited_vehicles(a$vehicles)
  lines <- character()
  for (class in a$classes) lines <- c(lines, travel_block(paste("CLASS", class$name), Filter(function(vehicle) vehicle$class$name == class$name, exited), a$bin_width))
  lines <- c(lines, travel_block("ALL", exited, a$bin_width))
  for (source in a$sources) {
    vehicles <- Filter(function(vehicle) vehicle$source == source$node, exited)
    count <- length(vehicles)
    routes <- enumerate_routes(source$segment)
    lines <- c(lines, line_text("SOURCE", source$node, "exited", count))
    for (route in routes) {
      selected <- Filter(function(vehicle) identical(vehicle$route, route$ids), vehicles)
      lines <- c(lines, line_text("  ROUTE", paste(route$ids, collapse = ","), "expected", share_text(route$share), "vehicles", length(selected), "share", frac(length(selected), count), "mean", dec(travel_sum(selected), length(selected), 2L)))
    }
    for (sink in a$sinks) {
      ending <- Filter(function(route) route$sink == sink, routes)
      if (!length(ending)) next
      share <- c(0, 1)
      for (route in ending) share <- share_add(share, route$share)
      selected <- Filter(function(vehicle) vehicle$sink == sink, vehicles)
      lines <- c(lines, line_text("  SINK", sink, "expected", share_text(share), "vehicles", length(selected), "share", frac(length(selected), count), "mean", dec(travel_sum(selected), length(selected), 2L)))
    }
  }
  lines
}

class_block <- function(heading, vehicles) {
  generated <- length(vehicles)
  inserted <- sum(vapply(vehicles, function(vehicle) vehicle$inserted > 0L, logical(1L)))
  exited <- exited_vehicles(vehicles)
  count <- length(exited)
  steps <- vehicle_sum(vehicles, "steps")
  distance <- vehicle_sum(vehicles, "distance")
  delay <- sum(vapply(exited, function(vehicle) vehicle$inserted - vehicle$arrival, numeric(1L)))
  c(heading,
    line_text("  generated", generated, "inserted", inserted, "exited", count, "in_network", inserted - count, "queued", generated - inserted),
    line_text("  vehicle_steps", steps, "distance", distance, "mean_speed", frac(distance, steps), "=", dec(distance, steps, 3L)),
    line_text("  travel", dec(travel_sum(exited), count, 2L), "entry_delay", dec(delay, count, 2L), "stopped", dec(vehicle_sum(exited, "stopped_steps"), count, 2L), "stops", dec(vehicle_sum(exited, "stop_count"), count, 2L), "lane_changes", dec(vehicle_sum(exited, "lane_changes"), count, 2L)))
}
class_report <- function(a) {
  lines <- character()
  for (class in a$classes) {
    heading <- line_text("CLASS", class$name, "vmax", class$vmax, "weight", class$weight, "overtake", flag_text(class$overtakes), "stops", flag_text(class$stops))
    lines <- c(lines, class_block(heading, Filter(function(vehicle) vehicle$class$name == class$name, a$vehicles)))
  }
  c(lines, class_block("ALL", a$vehicles))
}

network_report <- function(a) {
  lines <- character()
  for (segment in a$segments) {
    changes <- paste(integer_text(segment$changes), collapse = "/")
    lines <- c(lines, line_text("SEGMENT", segment$id, segment$start, segment$end, "length", segment$length, "lanes", segment$lanes, "limit", segment$limit, "entered", segment$entered, "mean_vehicles", dec(segment$vehicle_sum, a$steps, 3L), "density", dec(segment$vehicle_sum, a$steps * segment$length * segment$lanes, 4L), "mean_speed", dec(segment$speed_sum, segment$vehicle_sum, 2L), "max_vehicles", segment$max_vehicles, "changes", changes))
  }
  for (junction in a$junctions) {
    lines <- c(lines, plan_lines(junction))
    for (segment in junction$incoming) {
      lines <- c(lines, line_text("  IN", segment$id, "green", segment$green_steps, "passed", segment$passed, "blocked", segment$blocked, "max_queue", segment$max_queue, "mean_queue", dec(segment$queue_sum, a$steps, 3L), "failures", segment$failures))
      for (turn in segment$turns) lines <- c(lines, line_text("    TURN", turn$target$id, "weight", turn$weight, "vehicles", turn$vehicles))
    }
  }
  for (stop in a$stops) lines <- c(lines, line_text("STOP", stop$segment$id, "cell", stop$cell, "dwell", stop$dwell, "buses", stop$buses))
  for (incident in a$incidents) {
    active <- if (incident$active_start > 0L) paste0(integer_text(incident$active_start), "-", integer_text(incident$active_end)) else "none"
    lines <- c(lines, line_text("INCIDENT", incident$segment$id, "lane", incident$lane, "cell", incident$cell, "planned", paste0(integer_text(incident$start), "-", integer_text(incident$end)), "active", active))
  }
  lines
}

write_reports <- function(a) {
  output <- list()
  output[["spacetime.txt"]] <- unlist(lapply(a$diagrams, function(diagram) c(line_text("DIAGRAM", diagram$segment$id, "lane", diagram$lane, "steps", paste0(integer_text(diagram$start), "-", integer_text(diagram$end))), diagram$lines)), use.names = FALSE)
  lines <- "detector,interval,flow,density,speed"
  for (index in seq_along(a$detectors)) {
    detector <- a$detectors[[index]]
    for (k in seq_along(a$intervals)) {
      interval <- a$intervals[[k]]
      lines <- c(lines, paste(detector$name, integer_text(k), integer_text(interval$passing[index]), dec(interval$occupancy[index], a$interval_length * detector$width * detector$segment$lanes, 4L), dec(interval$occupancy_speed[index], interval$occupancy[index], 2L), sep = ","))
    }
  }
  output[["detectors.csv"]] <- lines
  output[["travel_times.txt"]] <- travel_report(a)
  output[["class_stats.txt"]] <- class_report(a)
  output[["network_stats.txt"]] <- network_report(a)
  lines <- "interval,arrived,inserted,exited,in_network,queued,mean_speed"
  arrived <- inserted <- exited <- 0
  for (k in seq_along(a$intervals)) {
    interval <- a$intervals[[k]]
    arrived <- arrived + interval$arrivals
    inserted <- inserted + interval$insertions
    exited <- exited + interval$exits
    lines <- c(lines, paste(integer_text(k), integer_text(interval$arrivals), integer_text(interval$insertions), integer_text(interval$exits), integer_text(inserted - exited), integer_text(arrived - inserted), dec(interval$speed_sum, interval$vehicle_steps, 2L), sep = ","))
  }
  output[["timeline.csv"]] <- lines
  lines <- character()
  for (number in a$track_numbers) {
    if (number > length(a$vehicles)) {
      lines <- c(lines, line_text("VEHICLE", number, "none"))
      next
    }
    vehicle <- a$vehicles[[number]]
    lines <- c(lines, line_text("VEHICLE", number, "class", vehicle$class$name, "source", vehicle$source, "arrival", vehicle$arrival, "inserted", optional_step(vehicle$inserted), "exited", optional_step(vehicle$exited), "sink", if (vehicle$exited > 0L) vehicle$sink else "-"), paste("ROUTE", if (length(vehicle$route)) paste(vehicle$route, collapse = " ") else "-"), a$tracks[[integer_text(number)]])
  }
  output[["tracks.txt"]] <- lines
  lines <- "ring,vehicles,density,flow,speed"
  for (ring in a$rings) for (count in ring$counts) {
    total <- run_ring(ring, count, a$dawdle, a$dawdle_stopped)
    lines <- c(lines, paste(integer_text(ring$number), integer_text(count), dec(count, ring$length, 4L), dec(total, ring$length * ring$measure, 4L), dec(total, count * ring$measure, 3L), sep = ","))
  }
  output[["fundamental.csv"]] <- lines
  output[["events.txt"]] <- a$events
  dir.create("output", showWarnings = FALSE)
  for (name in names(output)) writeLines(output[[name]], file.path("output", name), useBytes = TRUE)
  invisible(NULL)
}

simulation <- load_simulation()
run_simulation(simulation)
write_reports(simulation)
