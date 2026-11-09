load_rooms <- function(path, state) {
  rooms <- list()
  records <- read_records(path)
  for (index in seq_along(records)) {
    fields <- records[[index]]
    id <- fields[1L]
    capacity <- as.integer(fields[2L])
    if (id %in% names(rooms)) {
      state$errors <- c(state$errors, sprintf("rooms.csv line %d: duplicate room %s", index + 1L, id))
    } else if (capacity < 1L) {
      state$errors <- c(state$errors, sprintf("rooms.csv line %d: bad capacity %s", index + 1L, fields[2L]))
    } else {
      rooms[[id]] <- list(id = id, capacity = capacity)
    }
  }
  state$rooms <- unname(rooms[order(vapply(rooms, `[[`, 0L, "capacity"), names(rooms), method = "radix")])
}

pack <- function(rooms, courses) {
  remaining <- vapply(rooms, `[[`, 0L, "capacity")
  durations <- integer(length(rooms))
  placements <- list()
  ids <- vapply(courses, `[[`, "", "id")
  sizes <- vapply(courses, enrolment_count, 0L)
  courses <- courses[order(-sizes, ids, method = "radix")]
  for (course in courses) {
    fits <- which(remaining >= enrolment_count(course) & (durations == 0L | durations == course$duration))
    if (!length(fits)) return(NULL)
    index <- fits[1L]
    first <- rooms[[index]]$capacity - remaining[index] + 1L
    placements[[length(placements) + 1L]] <- list(course = course, room = rooms[[index]], first_seat = first, last_seat = first + enrolment_count(course) - 1L)
    remaining[index] <- remaining[index] - enrolment_count(course)
    durations[index] <- course$duration
  }
  placements
}
