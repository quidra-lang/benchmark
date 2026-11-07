room_center <- function(room) c(room$x + room$width %/% 2L, room$y + room$height %/% 2L)

new_region <- function(x, y, width, height) {
  region <- new.env(parent = emptyenv())
  region$x <- x
  region$y <- y
  region$width <- width
  region$height <- height
  region$first <- region$second <- NULL
  region$leaf <- 0L
  region
}

new_level <- function(depth, width, height) {
  level <- new.env(parent = emptyenv())
  level$depth <- depth
  level$width <- width
  level$height <- height
  level$terrain <- matrix(" ", height, width)
  level$memory <- matrix(" ", height, width)
  level$rooms <- level$monsters <- level$items <- list()
  level$monsters_created <- level$items_placed <- level$kills <- level$picked <- 0L
  level
}

monster_at <- function(level, x, y) {
  for (monster in level$monsters) if (monster$x == x && monster$y == y) return(monster)
  NULL
}
item_at <- function(level, x, y) {
  for (item in level$items) if (item$x == x && item$y == y) return(item)
  NULL
}
draw_interior_cell <- function(level, rng, index) {
  room <- level$rooms[[index]]
  x <- room$x + 1 + rng_rnd(rng, room$width - 2L)
  y <- room$y + 1 + rng_rnd(rng, room$height - 2L)
  c(x, y)
}
draw_room_cell <- function(level, rng) {
  index <- rng_rnd(rng, length(level$rooms)) + 1L
  point <- draw_interior_cell(level, rng, index)
  list(room = index, x = point[1L], y = point[2L])
}

new_level_generator <- function(rng, min_size, max_split, room_min, room_max) {
  generator <- new.env(parent = emptyenv())
  generator$rng <- rng
  generator$min_size <- min_size
  generator$max_split <- max_split
  generator$room_min <- room_min
  generator$room_max <- room_max
  generator
}

split_region <- function(generator, region, depth) {
  cv <- region$width >= 2L * generator$min_size
  ch <- region$height >= 2L * generator$min_size
  if (depth == generator$max_split || (!cv && !ch)) {
    region$leaf <- length(generator$leaves) + 1L
    generator$leaves[[region$leaf]] <- region
    return(invisible(NULL))
  }
  vertical <- cv
  if (cv && ch) {
    if (4L * region$width >= 5L * region$height) vertical <- TRUE else if (4L * region$height >= 5L * region$width) vertical <- FALSE else vertical <- rng_rnd(generator$rng, 2L) == 0L
  }
  if (vertical) {
    cut <- generator$min_size + rng_rnd(generator$rng, region$width - 2L * generator$min_size + 1L)
    region$first <- new_region(region$x, region$y, cut, region$height)
    region$second <- new_region(region$x + cut, region$y, region$width - cut, region$height)
  } else {
    cut <- generator$min_size + rng_rnd(generator$rng, region$height - 2L * generator$min_size + 1L)
    region$first <- new_region(region$x, region$y, region$width, cut)
    region$second <- new_region(region$x, region$y + cut, region$width, region$height - cut)
  }
  split_region(generator, region$first, depth + 1L)
  split_region(generator, region$second, depth + 1L)
}

make_room <- function(generator, level, region) {
  width <- generator$room_min + rng_rnd(generator$rng, min(generator$room_max, region$width - 1L) - generator$room_min + 1L)
  height <- generator$room_min + rng_rnd(generator$rng, min(generator$room_max, region$height - 1L) - generator$room_min + 1L)
  x <- region$x + rng_rnd(generator$rng, region$width - width)
  y <- region$y + rng_rnd(generator$rng, region$height - height)
  for (row in seq.int(y, y + height - 1L)) {
    for (column in seq.int(x, x + width - 1L)) {
      terrain <- if (row == y || row == y + height - 1L) "-" else if (column == x || column == x + width - 1L) "|" else "."
      level$terrain[row + 1L, column + 1L] <- terrain
    }
  }
  list(x = x, y = y, width = width, height = height)
}

dig_corridor <- function(level, start, end, horizontal) {
  span <- function(first, last) seq.int(first, last, by = if (last >= first) 1L else -1L)
  if (horizontal) {
    path <- rbind(cbind(span(start[1L], end[1L]), start[2L]), cbind(end[1L], span(start[2L], end[2L])))
  } else {
    path <- rbind(cbind(start[1L], span(start[2L], end[2L])), cbind(span(start[1L], end[1L]), end[2L]))
  }
  for (i in seq_len(nrow(path))) {
    x <- path[i, 1L]
    y <- path[i, 2L]
    terrain <- level$terrain[y + 1L, x + 1L]
    if (terrain == " ") level$terrain[y + 1L, x + 1L] <- "#" else if (terrain %in% c("-", "|")) level$terrain[y + 1L, x + 1L] <- "+"
  }
}

connect_rooms <- function(generator, level, region) {
  if (region$leaf) return(region$leaf)
  first <- connect_rooms(generator, level, region$first)
  second <- connect_rooms(generator, level, region$second)
  best_a <- best_b <- 0L
  best_distance <- 0
  for (a in first) {
    pa <- room_center(level$rooms[[a]])
    for (b in second) {
      pb <- room_center(level$rooms[[b]])
      distance <- sum(abs(pa - pb))
      if (!best_a || distance < best_distance) {
        best_a <- a
        best_b <- b
        best_distance <- distance
      }
    }
  }
  horizontal <- rng_rnd(generator$rng, 2L) == 0L
  dig_corridor(level, room_center(level$rooms[[best_a]]), room_center(level$rooms[[best_b]]), horizontal)
  c(first, second)
}

generate_level <- function(generator, depth, width, height) {
  level <- new_level(depth, width, height)
  root <- new_region(0L, 0L, width, height)
  generator$leaves <- list()
  split_region(generator, root, 0L)
  for (leaf in generator$leaves) level$rooms[[length(level$rooms) + 1L]] <- make_room(generator, level, leaf)
  connect_rooms(generator, level, root)
  arrival <- draw_room_cell(level, generator$rng)
  level$terrain[arrival$y + 1L, arrival$x + 1L] <- "<"
  level$arrival <- c(arrival$x, arrival$y)
  level$arrival_room <- arrival$room
  other <- rng_rnd(generator$rng, length(level$rooms) - 1L) + 1L
  if (other >= arrival$room) other <- other + 1L
  level$target <- draw_interior_cell(level, generator$rng, other)
  level
}
