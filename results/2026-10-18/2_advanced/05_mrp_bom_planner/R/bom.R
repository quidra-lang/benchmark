need <- function(row, quantity) integer_divide(quantity * row$qty_per * (100 + row$scrap) + 99, 100)

find_path <- function(bom, start, target) {
  visited <- character()
  visit <- function(id) {
    if (id == target) return(id)
    visited <<- c(visited, id)
    for (row in bom$children[[id]]) {
      if (row$child %in% visited) next
      rest <- visit(row$child)
      if (!is.null(rest)) return(c(id, rest))
    }
    NULL
  }
  visit(start)
}

read_bom <- function(items, errors) {
  bom <- list(children = setNames(rep(list(list()), length(items)), names(items)),
              parents = setNames(rep(list(list()), length(items)), names(items)))
  for (input in read_rows("bom.csv")) {
    fields <- input$fields
    parent <- fields[1L]
    child <- fields[2L]
    quantity <- as.numeric(fields[3L])
    scrap <- as.numeric(fields[4L])
    reason <- if (!parent %in% names(items)) paste("unknown item", parent) else if (!child %in% names(items)) paste("unknown item", child) else if (quantity < 1) {
      paste("bad quantity", integer_text(quantity))
    } else if (scrap > 50) paste("bad scrap", integer_text(scrap)) else if (parent == child) paste("cycle", parent, "->", parent) else if (any(vapply(bom$children[[parent]], function(row) row$child == child, logical(1L)))) {
      paste("duplicate", parent, "->", child)
    } else NULL
    if (is.null(reason)) {
      path <- find_path(bom, child, parent)
      if (!is.null(path)) reason <- paste("cycle", parent, "->", paste(path, collapse = " -> "))
    }
    if (!is.null(reason)) {
      record_error(errors, "bom.csv", input$line, reason)
      next
    }
    row <- list(parent = parent, child = child, qty_per = quantity, scrap = scrap)
    children <- c(bom$children[[parent]], list(row))
    bom$children[[parent]] <- children[order(vapply(children, function(row) row$child, character(1L)), method = "radix")]
    parents <- c(bom$parents[[child]], list(row))
    bom$parents[[child]] <- parents[order(vapply(parents, function(row) row$parent, character(1L)), method = "radix")]
  }
  bom
}

low_level_codes <- function(bom, items) {
  codes <- integer()
  code <- function(id) {
    if (id %in% names(codes)) return(codes[[id]])
    value <- 0L
    for (row in bom$parents[[id]]) value <- max(value, code(row$parent) + 1L)
    codes[id] <<- value
    value
  }
  for (id in names(items)) code(id)
  codes
}

cumulative_lead_times <- function(bom, items) {
  times <- integer()
  lead <- function(id) {
    if (id %in% names(times)) return(times[[id]])
    longest <- 0L
    for (row in bom$children[[id]]) longest <- max(longest, lead(row$child))
    value <- items[[id]]$lead_time + longest
    times[id] <<- value
    value
  }
  for (id in names(items)) lead(id)
  times
}
