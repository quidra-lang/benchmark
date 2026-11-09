record <- function(...) list2env(list(...), parent = emptyenv())
integer_word <- function(word) grepl("^-?[0-9]+$", word)
new_face <- function(triangle, polygon, line, group, vertices) record(
    triangle = triangle,
    polygon = polygon,
    line = line,
    group = group,
    vertices = as.integer(vertices)
)
copy_face <- function(face) new_face(face$triangle, face$polygon, face$line, face$group, face$vertices)
read_obj <- function(path = file.path("input", "model.obj")) {
  lines <- readLines(path, warn = FALSE)
  vertices <- matrix(numeric(), 0L, 3L)
  polygons <- errors <- list()
  ignored <- 0L
  group <- "default"
  for (number in seq_along(lines)) {
    text <- lines[[number]]
    if (!nzchar(text) || startsWith(text, "#")) next
    words <- strsplit(text, " ", fixed = TRUE)[[1L]]
    command <- words[[1L]]
    args <- words[-1L]
    if (command == "v") {
      if (length(args) != 3L || !all(vapply(args, integer_word, FALSE))) errors[[length(errors) + 1L]] <- list(number, "bad_vertex") else vertices <- rbind(
          vertices,
          as.numeric(args)
      )
    } else if (command == "f") {
      if (length(args) < 3L) {
        errors[[length(errors) + 1L]] <- list(number, "short_face")
        next
      }
      resolved <- integer()
      error <- NULL
      for (argument in args) {
        part <- strsplit(argument, "/", fixed = TRUE)[[1L]]
        part <- if (length(part)) part[[1L]] else ""
        if (!integer_word(part) || as.numeric(part) == 0) {
          error <- "bad_index"
          break
        }
        value <- as.numeric(part)
        if (value < 0) value <- nrow(vertices) + 1L + value
        if (value < 1 || value > nrow(vertices)) {
          error <- "out_of_range"
          break
        }
        resolved <- c(resolved, as.integer(value))
      }
      if (is.null(error)) polygons[[length(polygons) + 1L]] <- record(
          number = length(polygons) + 1L,
          line = number,
          group = group,
          vertices = resolved
      ) else errors[[length(errors) + 1L]] <- list(number, error)
    } else if (command == "g") group <- if (length(args)) args[[1L]] else "default" else if (command %in% c(
        "vt",
        "vn",
        "s",
        "o",
        "usemtl",
        "mtllib"
    )) ignored <- ignored + 1L else errors[[length(errors) + 1L]] <- list(number, "unknown_keyword")
  }
  list(lines = length(lines), vertices = vertices, polygons = polygons, errors = errors, ignored = ignored)
}
write_repaired_obj <- function(vertices, faces) {
  lines <- paste0("# vertices ", nrow(vertices), " faces ", length(faces))
  for (i in seq_len(nrow(vertices))) lines <- c(
      lines,
      paste("v", paste(sprintf("%.0f", vertices[i, ]), collapse = " "))
  )
  previous <- NULL
  for (face in faces) {
    if (!identical(face$group, previous)) {
      lines <- c(lines, paste("g", face$group))
      previous <- face$group
    }
    lines <- c(lines, paste("f", paste(face$vertices, collapse = " ")))
  }
  lines
}
