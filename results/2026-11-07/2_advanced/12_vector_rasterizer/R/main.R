script_args <- grep("^--file=", commandArgs(), value = TRUE)
source_dir <- if (length(script_args)) dirname(sub("^--file=", "", script_args[1L])) else "R"
for (unit in c("canvas", "primitives", "clipping", "fill", "ppm_writer")) source(file.path(source_dir, paste0(unit, ".R")))
PEN_COMMANDS <- c("LINE", "RECT", "CIRCLE", "ELLIPSE", "POLYLINE", "POLYGON", "PATH")
BRUSH_COMMANDS <- c("FILLRECT", "FILLCIRCLE", "FILLELLIPSE", "FILLPOLYGON", "FILLPATH", "FLOOD", "TEXT")
STATE_COMMANDS <- c("TRANSLATE", "SCALE", "ROTATE", "SAVE", "RESTORE", "CLIP", "NOCLIP", "USE")
COMMANDS <- c(PEN_COMMANDS, BRUSH_COMMANDS, "ERASE", STATE_COMMANDS)
ERROR_NAMES <- c("unknown_command", "bad_arguments", "unknown_style", "unknown_symbol", "unknown_glyph", "bad_value", "stack_empty")
PATH_ARITY <- c(M = 2L, m = 2L, L = 2L, l = 2L, H = 1L, h = 1L, V = 1L, v = 1L, Q = 4L, q = 4L, C = 6L, c = 6L, Z = 0L, z = 0L)
read_lines <- function(name) readLines(file.path("input", name), warn = FALSE)
words <- function(line) strsplit(trimws(line), " +")[[1L]]
is_integer <- function(word) grepl("^-?[0-9]+$", word)
intersect_rect <- function(first, second) c(max(first[1L], second[1L]), max(first[2L], second[2L]), min(first[3L], second[3L]), min(first[4L], second[4L]))
empty_rect <- function(rect) rect[1L] > rect[3L] || rect[2L] > rect[4L]
contains <- function(rect, point) point[1L] >= rect[1L] && point[1L] <= rect[3L] && point[2L] >= rect[2L] && point[2L] <= rect[4L]
rect_pixels <- function(rect, width) {
  if (empty_rect(rect)) return(integer())
  unlist(lapply(seq.int(rect[2L], rect[4L]), function(y) y * width + seq.int(rect[1L], rect[3L]) + 1L), use.names = FALSE)
}
points_pixels <- function(points, clip, width) {
  if (!nrow(points)) return(integer())
  inside <- points[, 1L] >= clip[1L] & points[, 1L] <= clip[3L] & points[, 2L] >= clip[2L] & points[, 2L] <= clip[4L]
  points <- points[inside, , drop = FALSE]
  unique(points[, 2L] * width + points[, 1L] + 1L)
}
bounding_box <- function(pixels, width) {
  if (!length(pixels)) return(NULL)
  x <- (pixels - 1L) %% width
  y <- (pixels - 1L) %/% width
  c(min(x), min(y), max(x), max(y))
}
box_text <- function(pixels, width) {
  box <- bounding_box(pixels, width)
  if (is.null(box)) "none" else paste(box, collapse = " ")
}
open_segments <- function(points, closed = FALSE) {
  segments <- list()
  if (nrow(points) > 1L) for (index in seq_len(nrow(points) - 1L)) segments[[length(segments) + 1L]] <- rbind(points[index, ], points[index + 1L, ])
  if (closed) segments[[length(segments) + 1L]] <- rbind(points[nrow(points), ], points[1L, ])
  segments
}
parse_path <- function(tokens) {
  commands <- list()
  position <- 1L
  previous <- "Z"
  while (position <= length(tokens)) {
    letter <- tokens[position]
    if (!letter %in% names(PATH_ARITY)) return(NULL)
    count <- PATH_ARITY[[letter]]
    if (position + count > length(tokens)) return(NULL)
    values <- if (count) tokens[position + seq_len(count)] else character()
    if (!all(is_integer(values)) || (previous %in% c("Z", "z") && !letter %in% c("M", "m"))) return(NULL)
    commands[[length(commands) + 1L]] <- list(letter = letter, values = as.integer(values))
    previous <- letter
    position <- position + count + 1L
  }
  if (length(commands)) commands else NULL
}
load_inputs <- function() {
  a <- list2env(list(colors = list(), pens = list(), brushes = list(), symbols = list(), layers = list(), glyphs = list(), executions = list(), used_colors = character(), used_pens = character(), used_brushes = character(), uses = integer()), parent = emptyenv())
  for (line in read_lines("styles.txt")) {
    if (!nzchar(line) || startsWith(line, "#")) next
    fields <- words(line)
    kind <- fields[1L]
    name <- fields[2L]
    values <- fields[-c(1L, 2L)]
    if (kind == "color") a$colors[[name]] <- as.integer(values)
    else if (kind == "pen") a$pens[[name]] <- list(width = as.integer(values[1L]), color = values[2L], on = as.integer(values[3L]), off = as.integer(values[4L]))
    else if (kind == "brush") a$brushes[[name]] <- list(colors = values[1L], axis = "", rule = values[2L])
    else a$brushes[[name]] <- list(colors = values[1:2], axis = values[3L], rule = values[4L])
  }
  lines <- read_lines("font.txt")
  font <- as.integer(words(lines[1L])[-1L])
  a$font_width <- font[1L]
  a$font_height <- font[2L]
  position <- 2L
  while (position <= length(lines)) {
    glyph <- words(lines[position])[2L]
    dots <- empty_points()
    for (row in seq_len(a$font_height)) {
      marks <- strsplit(lines[position + row], "", fixed = TRUE)[[1L]]
      columns <- which(marks == "#") - 1L
      if (length(columns)) dots <- rbind(dots, cbind(columns, rep(row - 1L, length(columns))))
    }
    a$glyphs[[glyph]] <- dots
    position <- position + a$font_height + 1L
  }
  instructions <- list()
  lines <- read_lines("scene.txt")
  for (index in seq_along(lines)) {
    text <- trimws(lines[index])
    if (!nzchar(text) || startsWith(text, "#")) next
    fields <- words(text)
    instructions[[length(instructions) + 1L]] <- list(line = index, keyword = fields[1L], arguments = fields[-1L])
  }
  position <- 1L
  read_body <- function() {
    body <- list()
    repeat {
      item <- instructions[[position]]
      position <<- position + 1L
      if (item$keyword %in% c("END", "ENDREPEAT")) return(list(body = body, end = item$line))
      if (item$keyword == "REPEAT") {
        values <- as.integer(item$arguments)
        item <- list(keyword = "REPEAT", count = values[1L], dx = values[2L], dy = values[3L], body = read_body()$body)
      }
      body[[length(body) + 1L]] <- item
    }
  }
  while (position <= length(instructions)) {
    item <- instructions[[position]]
    position <- position + 1L
    fields <- item$arguments
    if (item$keyword == "CANVAS") {
      a$width <- as.integer(fields[1L])
      a$height <- as.integer(fields[2L])
      a$background <- fields[3L]
    } else {
      block <- read_body()
      if (item$keyword == "LAYER") a$layers[[length(a$layers) + 1L]] <- layer_record(a$width, a$height, fields[1L], as.integer(fields[2L]), fields[3L], block$body)
      else a$symbols[[fields[1L]]] <- block
    }
  }
  a$screen <- c(0L, 0L, a$width - 1L, a$height - 1L)
  a$uses <- setNames(integer(length(a$symbols)), names(a$symbols))
  a$used_colors <- a$background
  a$probes <- lapply(read_lines("probes.txt")[-1L], function(line) {
    fields <- words(line)
    list(kind = fields[1L], values = as.integer(fields[-1L]))
  })
  a
}
new_state <- function(screen) list(matrix = c(1L, 0L, 0L, 1L, 0L, 0L), clip = screen, stack = list())
transform_point <- function(state, point) {
  m <- state$matrix
  c(m[1L] * point[1L] + m[2L] * point[2L] + m[5L], m[3L] * point[1L] + m[4L] * point[2L] + m[6L])
}
device_rect <- function(state, values) {
  first <- transform_point(state, values[1:2])
  last <- transform_point(state, values[3:4])
  c(pmin(first, last), pmax(first, last))
}
translate_state <- function(state, dx, dy) {
  m <- state$matrix
  state$matrix[5L] <- m[5L] + m[1L] * dx + m[2L] * dy
  state$matrix[6L] <- m[6L] + m[3L] * dx + m[4L] * dy
  state
}
valid_form <- function(keyword, arguments) {
  fixed <- list(LINE = c(5L, 1L), RECT = c(5L, 1L), FILLRECT = c(5L, 1L), CIRCLE = c(4L, 1L), FILLCIRCLE = c(4L, 1L), ELLIPSE = c(5L, 1L), FILLELLIPSE = c(5L, 1L), FLOOD = c(3L, 1L), ERASE = c(4L, 0L), TRANSLATE = c(2L, 0L), SCALE = c(2L, 0L), ROTATE = c(1L, 0L), SAVE = c(0L, 0L), RESTORE = c(0L, 0L), NOCLIP = c(0L, 0L), CLIP = c(4L, 0L), USE = c(3L, 1L))
  if (keyword %in% names(fixed)) {
    form <- fixed[[keyword]]
    return(length(arguments) == form[1L] && all(is_integer(if (form[2L]) arguments[-1L] else arguments)))
  }
  if (keyword == "TEXT") return(length(arguments) == 5L && all(is_integer(arguments[2:3])))
  if (keyword %in% c("POLYLINE", "POLYGON", "FILLPOLYGON")) return(length(arguments) >= 2L && all(is_integer(arguments[-1L])) && length(arguments) == 2L + 2L * as.integer(arguments[2L]))
  length(arguments) >= 2L && is_integer(arguments[2L]) && !is.null(parse_path(arguments[-c(1L, 2L)]))
}
check_command <- function(a, command) {
  key <- command$keyword
  args <- command$arguments
  if (!key %in% COMMANDS) return("unknown_command")
  if (!valid_form(key, args)) return("bad_arguments")
  if (key %in% PEN_COMMANDS && !args[1L] %in% names(a$pens)) return("unknown_style")
  if (key %in% BRUSH_COMMANDS && !args[1L] %in% names(a$brushes)) return("unknown_style")
  if (key == "USE" && (!args[1L] %in% names(a$symbols) || a$symbols[[args[1L]]]$end >= command$line)) return("unknown_symbol")
  if (key == "TEXT") {
    characters <- strsplit(args[5L], "", fixed = TRUE)[[1L]]
    if (any(!characters %in% c("_", names(a$glyphs)))) return("unknown_glyph")
  }
  if (key == "RESTORE" && !length(a$state$stack)) return("stack_empty")
  values <- switch(key, CIRCLE = as.integer(args[4L]) >= 1L, FILLCIRCLE = as.integer(args[4L]) >= 1L,
    ELLIPSE = all(as.integer(args[4:5]) >= 1L), FILLELLIPSE = all(as.integer(args[4:5]) >= 1L),
    POLYLINE = as.integer(args[2L]) >= 2L, POLYGON = as.integer(args[2L]) >= 3L, FILLPOLYGON = as.integer(args[2L]) >= 3L,
    PATH = as.integer(args[2L]) >= 1L && as.integer(args[2L]) <= 32L, FILLPATH = as.integer(args[2L]) >= 1L && as.integer(args[2L]) <= 32L,
    FLOOD = contains(a$state$clip, transform_point(a$state, as.integer(args[2:3]))), TEXT = args[4L] %in% c("left", "center", "right"),
    SCALE = all(as.integer(args) != 0L), CLIP = !empty_rect(intersect_rect(device_rect(a$state, as.integer(args)), a$state$clip)), TRUE)
  if (!values) "bad_value" else ""
}
transform_points <- function(state, points) {
  output <- empty_points()
  for (index in seq_len(nrow(points))) output <- rbind(output, transform_point(state, points[index, ]))
  output
}
build_subpaths <- function(state, commands, segments) {
  subpaths <- list()
  current <- start <- c(0L, 0L)
  for (command in commands) {
    kind <- toupper(command$letter)
    if (kind == "Z") {
      subpaths[[length(subpaths)]]$closed <- TRUE
      current <- start
      next
    }
    offset <- if (command$letter == tolower(command$letter)) current else c(0L, 0L)
    values <- command$values
    if (kind == "H") points <- matrix(c(values[1L] + offset[1L], current[2L]), 1L, 2L)
    else if (kind == "V") points <- matrix(c(current[1L], values[1L] + offset[2L]), 1L, 2L)
    else points <- sweep(matrix(values, ncol = 2L, byrow = TRUE), 2L, offset, "+")
    device <- transform_points(state, points)
    if (kind == "M") {
      subpaths[[length(subpaths) + 1L]] <- list(points = device, closed = FALSE)
      start <- points[1L, ]
    } else {
      index <- length(subpaths)
      if (kind %in% c("L", "H", "V")) subpaths[[index]]$points <- rbind(subpaths[[index]]$points, device)
      else {
        controls <- rbind(tail(subpaths[[index]]$points, 1L), device)
        subpaths[[index]]$points <- rbind(subpaths[[index]]$points, bezier_points(controls, segments)[-1L, , drop = FALSE])
      }
    }
    current <- tail(points, 1L)[1L, ]
  }
  subpaths
}
expand_points <- function(a, points, width) {
  pixels <- integer()
  for (index in seq_len(nrow(points))) pixels <- c(pixels, points_pixels(expand_square(points[index, ], width), a$state$clip, a$width))
  unique(pixels)
}
stroke <- function(a, pen, segments) {
  points <- empty_points()
  for (segment in segments) {
    clipped <- clip_segment(segment[1L, ], segment[2L, ], a$state$clip)
    if (!is.null(clipped)) points <- rbind(points, bresenham(clipped[1L, ], clipped[2L, ]))
  }
  if (pen$off > 0L && nrow(points)) points <- points[(seq_len(nrow(points)) - 1L) %% (pen$on + pen$off) < pen$on, , drop = FALSE]
  expand_points(a, points, pen$width)
}
shape <- function(a, key, values) {
  center <- transform_point(a$state, values[1:2])
  m <- abs(a$state$matrix)
  radii <- if (key %in% c("CIRCLE", "FILLCIRCLE")) rep(values[3L], 2L) else values[3:4]
  rx <- m[1L] * radii[1L] + m[2L] * radii[2L]
  ry <- m[3L] * radii[1L] + m[4L] * radii[2L]
  points <- if (key %in% c("CIRCLE", "FILLCIRCLE") && rx == ry) circle_points(rx) else ellipse_points(rx, ry)
  list(center = center, points = points)
}
text_coverage <- function(a, args) {
  x <- as.integer(args[1L])
  y <- as.integer(args[2L])
  characters <- strsplit(args[4L], "", fixed = TRUE)[[1L]]
  advance <- a$font_width + 1L
  extent <- length(characters) * advance - 1L
  left <- switch(args[3L], left = x, center = x - extent %/% 2L, right = x - extent + 1L)
  pixels <- integer()
  for (index in seq_along(characters)) {
    if (characters[index] == "_") next
    dots <- a$glyphs[[characters[index]]]
    origin <- left + (index - 1L) * advance
    for (dot in seq_len(nrow(dots))) {
      first <- transform_point(a$state, c(origin + dots[dot, 1L], y + dots[dot, 2L]))
      last <- transform_point(a$state, c(origin + dots[dot, 1L] + 1L, y + dots[dot, 2L] + 1L))
      rect <- c(pmin(first, last), pmax(first, last) - 1L)
      pixels <- c(pixels, rect_pixels(intersect_rect(rect, a$state$clip), a$width))
    }
  }
  unique(pixels)
}
coverage <- function(a, key, args, style) {
  state <- a$state
  if (key == "TEXT") return(text_coverage(a, args))
  if (key == "FLOOD") return(flood_fill(a$current, transform_point(state, as.integer(args)), state$clip))
  if (key %in% c("CIRCLE", "ELLIPSE", "FILLCIRCLE", "FILLELLIPSE")) {
    object <- shape(a, key, as.integer(args))
    if (key %in% PEN_COMMANDS) return(expand_points(a, sweep(object$points, 2L, object$center, "+"), style$width))
    return(fill_shape(object$center, object$points, state$clip, a$width))
  }
  if (key == "FILLRECT") return(rect_pixels(intersect_rect(device_rect(state, as.integer(args)), state$clip), a$width))
  if (key %in% c("PATH", "FILLPATH")) {
    subpaths <- build_subpaths(state, parse_path(args[-1L]), as.integer(args[1L]))
    if (key == "FILLPATH") return(fill_polygons(lapply(subpaths, function(path) clip_polygon(path$points, state$clip)), style$rule, state$clip, a$width))
    segments <- list()
    for (path in subpaths) segments <- c(segments, open_segments(path$points, path$closed))
  } else if (key %in% c("POLYLINE", "POLYGON", "FILLPOLYGON")) {
    points <- transform_points(state, matrix(as.integer(args[-1L]), ncol = 2L, byrow = TRUE))
    if (key == "FILLPOLYGON") return(fill_polygons(list(clip_polygon(points, state$clip)), style$rule, state$clip, a$width))
    segments <- open_segments(points, key == "POLYGON")
  } else if (key == "RECT") {
    rect <- device_rect(state, as.integer(args))
    points <- rbind(rect[1:2], rect[c(3L, 2L)], rect[3:4], rect[c(1L, 4L)])
    segments <- open_segments(points, TRUE)
  } else {
    points <- transform_points(state, matrix(as.integer(args), ncol = 2L, byrow = TRUE))
    segments <- list(points)
  }
  stroke(a, style, segments)
}
paint_pixels <- function(a, pixels, style, pen, line) {
  if (!length(pixels)) return(invisible(NULL))
  if (pen) color <- a$colors[[style$color]] else color <- a$colors[[style$colors[1L]]]
  colors <- matrix(rep(color, each = length(pixels)), length(pixels), 4L)
  if (!pen && nzchar(style$axis)) {
    box <- bounding_box(pixels, a$width)
    axis <- if (style$axis == "x") 1L else 2L
    extent <- box[axis + 2L] - box[axis]
    if (extent > 0L) {
      second <- a$colors[[style$colors[2L]]]
      position <- if (axis == 1L) (pixels - 1L) %% a$width else (pixels - 1L) %/% a$width
      offset <- position - box[axis]
      for (channel in 1:4) colors[, channel] <- color[channel] + round_ratio((second[channel] - color[channel]) * offset, extent)
    }
  }
  a$current$painted[pixels] <- TRUE
  a$current$colors[pixels, ] <- colors
  a$current$lines[pixels] <- line
  invisible(NULL)
}
execute_body <- function(a, body) {
  for (item in body) {
    if (item$keyword == "REPEAT") {
      saved <- a$state
      for (index in seq_len(item$count) - 1L) {
        a$state <- translate_state(saved, index * item$dx, index * item$dy)
        execute_body(a, item$body)
      }
      a$state <- saved
      next
    }
    execute_command(a, item)
  }
  invisible(NULL)
}
execute_command <- function(a, command) {
  key <- command$keyword
  args <- command$arguments
  execution <- list2env(list(sequence = length(a$executions) + 1L, layer = a$layer_index, line = command$line, keyword = key, kind = "", error = "", pixels = integer()), parent = emptyenv())
  a$executions[[length(a$executions) + 1L]] <- execution
  a$current$commands <- a$current$commands + 1L
  error <- check_command(a, command)
  if (nzchar(error)) {
    execution$kind <- "error"
    execution$error <- error
    a$current$errors <- a$current$errors + 1L
    return(invisible(NULL))
  }
  if (key %in% STATE_COMMANDS) {
    execution$kind <- "state"
    m <- a$state$matrix
    if (key == "TRANSLATE") a$state <- translate_state(a$state, as.integer(args[1L]), as.integer(args[2L]))
    else if (key == "SCALE") {
      scale <- as.integer(args)
      a$state$matrix[1:4] <- m[1:4] * c(scale[1L], scale[2L], scale[1L], scale[2L])
    } else if (key == "ROTATE") {
      for (turn in seq_len(as.integer(args[1L]) %% 4L)) {
        m <- a$state$matrix
        a$state$matrix[1:4] <- c(m[2L], -m[1L], m[4L], -m[3L])
      }
    } else if (key == "SAVE") a$state$stack[[length(a$state$stack) + 1L]] <- list(matrix = m, clip = a$state$clip)
    else if (key == "RESTORE") {
      saved <- a$state$stack[[length(a$state$stack)]]
      a$state$stack <- head(a$state$stack, -1L)
      a$state$matrix <- saved$matrix
      a$state$clip <- saved$clip
    } else if (key == "CLIP") a$state$clip <- intersect_rect(device_rect(a$state, as.integer(args)), a$state$clip)
    else if (key == "NOCLIP") a$state$clip <- a$screen
    else {
      a$uses[args[1L]] <- a$uses[args[1L]] + 1L
      saved <- a$state
      a$state <- translate_state(saved, as.integer(args[2L]), as.integer(args[3L]))
      execute_body(a, a$symbols[[args[1L]]]$body)
      a$state <- saved
    }
    return(invisible(NULL))
  }
  execution$kind <- "drawing"
  if (key == "ERASE") {
    pixels <- rect_pixels(intersect_rect(device_rect(a$state, as.integer(args)), a$state$clip), a$width)
    pixels <- pixels[a$current$painted[pixels]]
    a$current$painted[pixels] <- FALSE
  } else {
    pen <- key %in% PEN_COMMANDS
    style <- if (pen) a$pens[[args[1L]]] else a$brushes[[args[1L]]]
    pixels <- coverage(a, key, args[-1L], style)
    paint_pixels(a, pixels, style, pen, command$line)
    if (pen) {
      a$used_pens <- union(a$used_pens, args[1L])
      a$used_colors <- union(a$used_colors, style$color)
    } else {
      a$used_brushes <- union(a$used_brushes, args[1L])
      a$used_colors <- union(a$used_colors, style$colors)
    }
  }
  execution$pixels <- pixels
  invisible(NULL)
}
rank_colors <- function(colors) {
  if (!nrow(colors)) return(list(colors = colors, counts = integer()))
  keys <- do.call(paste, c(as.data.frame(colors), sep = ","))
  palette <- unique(colors)
  palette_keys <- do.call(paste, c(as.data.frame(palette), sep = ","))
  counts <- tabulate(match(keys, palette_keys), nrow(palette))
  order <- do.call(order, c(list(-counts), as.list(as.data.frame(palette)), list(method = "radix")))
  list(colors = palette[order, , drop = FALSE], counts = counts[order])
}
write_reports <- function(a) {
  image <- composite(a$layers, a$colors[[a$background]], a$width, a$height)
  write_ppm(image, a$width, a$height)
  write_preview(image, a$width, a$height)
  commands <- vapply(a$executions, function(execution) {
    prefix <- paste("cmd", execution$sequence, "line", execution$line, execution$keyword)
    if (execution$kind == "error") paste(prefix, "error", execution$error)
    else if (execution$kind == "state") paste(prefix, "ok")
    else paste(prefix, "pixels", length(execution$pixels), "box", box_text(execution$pixels, a$width))
  }, character(1L))
  writeLines(commands, "output/commands.txt", useBytes = TRUE)
  alpha <- vapply(a$layers, effective_alpha, integer(a$width * a$height))
  lines <- paste("layers", length(a$layers))
  for (index in seq_along(a$layers)) {
    layer <- a$layers[[index]]
    pixels <- which(layer$painted)
    visible <- alpha[, index] > 0L
    if (index < length(a$layers)) for (later in seq.int(index + 1L, length(a$layers))) visible <- visible & alpha[, later] < 255L
    colors <- rank_colors(layer$colors[pixels, , drop = FALSE])
    lines <- c(lines, paste("layer", index, layer$name, "opacity", layer$opacity, "mode", layer$mode, "commands", layer$commands, "errors", layer$errors, "pixels", length(pixels), "box", box_text(pixels, a$width), "visible", sum(visible), "colors", nrow(colors$colors)))
    for (color in seq_len(min(5L, length(colors$counts)))) lines <- c(lines, paste("color", paste(colors$colors[color, ], collapse = " "), "pixels", colors$counts[color]))
  }
  writeLines(lines, "output/layers.txt", useBytes = TRUE)
  kinds <- vapply(a$executions, function(execution) execution$kind, character(1L))
  errors <- vapply(a$executions, function(execution) execution$error, character(1L))
  keywords <- vapply(a$executions, function(execution) execution$keyword, character(1L))
  counts <- vapply(a$executions, function(execution) length(execution$pixels), integer(1L))
  palette <- rank_colors(image)
  lines <- c(paste("canvas", a$width, a$height), paste("background", paste(a$colors[[a$background]][1:3], collapse = " ")), paste("layers", length(a$layers)), paste("symbols", length(a$symbols)),
    paste("commands", length(a$executions)), paste("drawing", sum(kinds == "drawing")), paste("state", sum(kinds == "state")), paste("errors", sum(kinds == "error")))
  for (error in ERROR_NAMES) lines <- c(lines, paste("error", error, sum(errors == error)))
  lines <- c(lines, paste("painted", sum(counts[kinds == "drawing" & keywords != "ERASE"])), paste("erased", sum(counts[kinds == "drawing" & keywords == "ERASE"])), paste("colors", nrow(palette$colors)))
  for (index in seq_len(min(8L, length(palette$counts)))) lines <- c(lines, paste("top", index, paste(palette$colors[index, ], collapse = " "), "pixels", palette$counts[index]))
  for (name in sort(names(a$symbols), method = "radix")) lines <- c(lines, paste("symbol", name, "uses", a$uses[name]))
  for (key in sort(unique(keywords), method = "radix")) {
    selected <- keywords == key
    lines <- c(lines, paste("keyword", key, "executed", sum(selected), "errors", sum(selected & kinds == "error"), "pixels", sum(counts[selected])))
  }
  unused <- character()
  tables <- list(color = names(a$colors), pen = names(a$pens), brush = names(a$brushes), symbol = names(a$symbols))
  used <- list(color = a$used_colors, pen = a$used_pens, brush = a$used_brushes, symbol = names(a$uses)[a$uses > 0L])
  for (kind in names(tables)) for (name in sort(setdiff(tables[[kind]], used[[kind]]), method = "radix")) unused <- c(unused, paste("unused", kind, name))
  lines <- c(lines, paste("unused", length(unused)), unused)
  writeLines(lines, "output/summary.txt", useBytes = TRUE)
  lines <- character()
  for (index in seq_along(a$probes)) {
    probe <- a$probes[[index]]
    values <- probe$values
    if (probe$kind == "point") {
      id <- values[2L] * a$width + values[1L] + 1L
      layers <- which(alpha[id, ] > 0L)
      stack <- if (length(layers)) paste(vapply(layers, function(layer) paste0(layer, ":", a$layers[[layer]]$lines[id]), character(1L)), collapse = " ") else "none"
      lines <- c(lines, paste("point", index, values[1L], values[2L], "rgb", paste(image[id, ], collapse = " "), "layers", length(layers), "stack", stack))
    } else {
      pixels <- rect_pixels(values, a$width)
      means <- vapply(1:3, function(channel) sum(image[pixels, channel]) %/% length(pixels), integer(1L))
      cover <- vapply(seq_along(a$layers), function(layer) sum(alpha[pixels, layer] > 0L), integer(1L))
      colors <- rank_colors(image[pixels, , drop = FALSE])
      lines <- c(lines, paste("area", index, paste(values, collapse = " "), "pixels", length(pixels), "mean", paste(means, collapse = " "), "colors", nrow(colors$colors), "cover", paste(cover, collapse = " ")))
    }
  }
  writeLines(lines, "output/probes.txt", useBytes = TRUE)
  invisible(NULL)
}

scene <- load_inputs()
for (index in seq_along(scene$layers)) {
  scene$layer_index <- index
  scene$current <- scene$layers[[index]]
  scene$state <- new_state(scene$screen)
  execute_body(scene, scene$current$body)
}
dir.create("output", showWarnings = FALSE)
write_reports(scene)
