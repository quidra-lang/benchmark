script_args <- grep("^--file=", commandArgs(), value = TRUE)
source_dir <- if (length(script_args)) dirname(sub("^--file=", "", script_args[1L])) else "R"
for (unit in c("line_solver", "clues", "propagation", "search", "render")) source(file.path(source_dir, paste0(unit, ".R")))

valid_name <- function(name) grepl("^[a-z0-9_]{1,20}$", name)
number_list <- function(values) if (length(values)) paste(values, collapse = ",") else "-"
cell_text <- function(cell) paste(cell, collapse = ",")
read_blocks <- function(name) {
  blocks <- list()
  block <- NULL
  for (line in readLines(file.path("input", name), warn = FALSE)) {
    if (is.null(block)) {
      if (nzchar(line) && !startsWith(line, "#")) block <- line
    } else if (line == "END") {
      blocks[[length(blocks) + 1L]] <- block
      block <- NULL
    } else block <- c(block, line)
  }
  blocks
}
join_paragraphs <- function(paragraphs) {
  lines <- character()
  for (paragraph in paragraphs) lines <- c(lines, if (length(lines)) "", paragraph)
  lines
}
parse_puzzle <- function(lines) {
  size <- as.integer(strsplit(lines[2L], " ", fixed = TRUE)[[1L]][-1L])
  at <- match("COLUMNS", lines)
  rows <- if (at > 4L) lines[seq.int(4L, at - 1L)] else character()
  columns <- character()
  givens <- list()
  position <- at + 1L
  while (position <= length(lines) && is_clue_line(lines[position])) {
    columns <- c(columns, lines[position])
    position <- position + 1L
  }
  while (position <= length(lines) && startsWith(lines[position], "GIVEN ")) {
    fields <- strsplit(lines[position], " ", fixed = TRUE)[[1L]]
    givens[[length(givens) + 1L]] <- list(row = as.integer(fields[2L]), column = as.integer(fields[3L]), value = fields[4L])
    position <- position + 1L
  }
  answer <- if (position <= length(lines)) if (position < length(lines)) lines[seq.int(position + 1L, length(lines))] else character() else NULL
  list(name = substring(lines[1L], 8L), width = size[1L], height = size[2L], row_lines = rows, column_lines = columns, given_lines = givens, answer_lines = answer)
}
validate_puzzle <- function(block, names) {
  error <- NULL
  if (!valid_name(block$name)) error <- "bad name"
  else if (block$name %in% names) error <- "duplicate name"
  else if (block$width < 1L || block$width > 30L || block$height < 1L || block$height > 30L) error <- "bad size"
  else if (length(block$row_lines) != block$height) error <- paste("row count", length(block$row_lines), "expected", block$height)
  else if (length(block$column_lines) != block$width) error <- paste("column count", length(block$column_lines), "expected", block$width)
  block$row_clues <- block$column_clues <- list()
  if (is.null(error)) for (row in c(TRUE, FALSE)) {
    texts <- if (row) block$row_lines else block$column_lines
    kind <- if (row) "row" else "column"
    clues <- list()
    for (index in seq_along(texts)) {
      clue <- parse_clue(texts[index])
      if (is.null(clue)) error <- paste("bad clue", kind, index)
      else if (!clue_fits(clue, if (row) block$width else block$height)) error <- paste(kind, index, "too long")
      if (!is.null(error)) break
      clues[[length(clues) + 1L]] <- clue
    }
    if (!is.null(error)) break
    if (row) block$row_clues <- clues else block$column_clues <- clues
  }
  if (is.null(error)) {
    a <- sum(unlist(block$row_clues))
    b <- sum(unlist(block$column_clues))
    if (a != b) error <- paste0("total mismatch rows=", a, " columns=", b)
  }
  block$givens <- list()
  if (is.null(error)) for (index in seq_along(block$given_lines)) {
    given <- block$given_lines[[index]]
    if (given$row < 1L || given$row > block$height || given$column < 1L || given$column > block$width || !given$value %in% c("#", ".")) error <- paste("bad given", index)
    else if (any(vapply(block$givens, function(other) other[1L] == given$row && other[2L] == given$column, logical(1L)))) error <- paste("duplicate given", index)
    if (!is.null(error)) break
    block$givens[[length(block$givens) + 1L]] <- c(given$row, given$column, char_state(given$value))
  }
  if (is.null(error) && !is.null(block$answer_lines)) {
    valid <- length(block$answer_lines) == block$height && all(nchar(block$answer_lines) == block$width) && all(grepl("^[#.?]+$", block$answer_lines))
    if (!valid) error <- "bad answer" else block$answer <- state_grid(block$answer_lines)
  }
  block$error <- error
  block
}
logical_solve <- function(rows, columns, givens, precise) {
  grid <- matrix(UNKNOWN, length(rows), length(columns))
  for (given in givens) grid[given[1L], given[2L]] <- given[3L]
  propagate(grid, rows, columns, precise)
}
solving_result <- function(propagation) {
  if (!is.null(propagation$conflict)) return(paste0("contradiction at=", line_label(propagation$conflict$row, propagation$conflict$index)))
  if (determined_count(propagation$grid) == length(propagation$grid)) "solved" else "stuck"
}
analyze <- function(rows, columns, givens = list()) {
  simple <- logical_solve(rows, columns, givens, FALSE)
  logic <- logical_solve(rows, columns, givens, TRUE)
  simple_result <- solving_result(simple)
  logic_result <- solving_result(logic)
  search <- NULL
  solutions <- list()
  difficulty <- "-"
  if (!is.null(logic$conflict)) status <- "contradiction"
  else if (logic_result == "solved") {
    status <- "unique"
    solutions <- list(logic$grid)
    difficulty <- if (simple_result == "solved") "easy" else "medium"
  } else {
    search <- search_grid(logic$grid, rows, columns)
    solutions <- search$solutions
    status <- c("none", "unique", "multiple")[length(solutions) + 1L]
    if (status == "unique") difficulty <- "hard"
  }
  list(simple = simple, logic = logic, simple_result = simple_result, logic_result = logic_result, search = search, solutions = solutions, status = status, difficulty = difficulty,
       line_solves = length(logic$steps) + if (is.null(search)) 0L else search$line_solves, guesses = if (is.null(search)) 0L else length(search$guesses), max_depth = if (is.null(search)) 0L else search$max_depth)
}
clue_statistics <- function(rows, columns) {
  fixed <- function(clue, length) !length(clue) || clue_span(clue) == length
  sizes <- unlist(c(rows, columns), use.names = FALSE)
  paste0("row_blocks=", sum(lengths(rows)), " column_blocks=", sum(lengths(columns)), " filled=", sum(unlist(rows)), " max_block=", if (length(sizes)) max(sizes) else 0L,
         " fixed_lines=", sum(vapply(rows, fixed, logical(1L), length(columns))) + sum(vapply(columns, fixed, logical(1L), length(rows))))
}
step_statistics <- function(propagation) {
  productive <- idle <- best <- 0L
  at <- "-"
  for (step in propagation$steps) if (!step$contradiction) {
    if (step$gain) productive <- productive + 1L else idle <- idle + 1L
    if (step$gain > best) {
      best <- step$gain
      at <- line_label(step$row, step$index)
    }
  }
  paste0("productive=", productive, " idle=", idle, " best=", best, " at=", at)
}
differing_cells <- function(first, second) {
  cells <- which(t(first != second), arr.ind = TRUE)
  if (!nrow(cells)) return(matrix(integer(), 0L, 2L))
  unname(cells[, 2:1, drop = FALSE])
}
features_text <- function(grid) {
  height <- nrow(grid)
  width <- ncol(grid)
  seen <- matrix(FALSE, height, width)
  sizes <- integer()
  for (row in seq_len(height)) for (column in seq_len(width)) {
    if (grid[row, column] != FILLED || seen[row, column]) next
    seen[row, column] <- TRUE
    pending <- list(c(row, column))
    size <- 0L
    while (length(pending)) {
      cell <- pending[[length(pending)]]
      pending <- head(pending, -1L)
      size <- size + 1L
      for (delta in list(c(-1L, 0L), c(1L, 0L), c(0L, -1L), c(0L, 1L))) {
        next_cell <- cell + delta
        r <- next_cell[1L]
        c <- next_cell[2L]
        if (r < 1L || r > height || c < 1L || c > width) next
        if (grid[r, c] == FILLED && !seen[r, c]) {
          seen[r, c] <- TRUE
          pending[[length(pending) + 1L]] <- next_cell
        }
      }
    }
    sizes <- c(sizes, size)
  }
  filled_rows <- which(rowSums(grid == FILLED) > 0L)
  filled_columns <- which(colSums(grid == FILLED) > 0L)
  bbox <- if (length(filled_rows)) paste(c(filled_rows[1L], filled_columns[1L], tail(filled_rows, 1L), tail(filled_columns, 1L)), collapse = ",") else "-"
  symmetries <- character()
  if (all(grid == grid[, rev(seq_len(width)), drop = FALSE])) symmetries <- c(symmetries, "lr")
  if (all(grid == grid[rev(seq_len(height)), , drop = FALSE])) symmetries <- c(symmetries, "ud")
  if (all(grid == grid[rev(seq_len(height)), rev(seq_len(width)), drop = FALSE])) symmetries <- c(symmetries, "rot180")
  paste0("filled=", sum(grid == FILLED), " components=", length(sizes), " largest=", if (length(sizes)) max(sizes) else 0L, " bbox=", bbox, " symmetry=", if (length(symmetries)) paste(symmetries, collapse = ",") else "none")
}
unknown_summary <- function(grid, rows) {
  counts <- if (rows) rowSums(grid == UNKNOWN) else colSums(grid == UNKNOWN)
  indices <- which(counts > 0L)
  paste(paste0(indices, ":", counts[indices]), collapse = " ")
}
evaluate_givens <- function(block, analysis) {
  if (!length(block$givens) || analysis$status == "multiple") return(character())
  accepted <- if (analysis$status == "unique") "unique" else c("unique", "multiple")
  numbers <- which(vapply(seq_along(block$givens), function(index) analyze(block$row_clues, block$column_clues, block$givens[-index])$status %in% accepted, logical(1L)))
  paste0("givens ", if (analysis$status == "unique") "redundant=" else "blame=", number_list(numbers))
}
grade_answer <- function(block, analysis) {
  answer <- block$answer
  rows <- which(!vapply(seq_len(block$height), function(index) has_placement(answer[index, ], block$row_clues[[index]]), logical(1L)))
  columns <- which(!vapply(seq_len(block$width), function(index) has_placement(answer[, index], block$column_clues[[index]]), logical(1L)))
  givens <- which(vapply(block$givens, function(given) answer[given[1L], given[2L]] != UNKNOWN && answer[given[1L], given[2L]] != given[3L], logical(1L)))
  known <- determined_count(answer)
  mismatch <- length(rows) + length(columns) + length(givens) > 0L
  result <- if (known < length(answer)) "partial" else if (mismatch) "wrong" else "correct"
  text <- paste0("answer result=", result, " known=", known, " rows=", number_list(rows), " columns=", number_list(columns), " givens=", number_list(givens))
  if (result == "partial") {
    extendable <- FALSE
    if (!mismatch) {
      extra <- block$givens
      taken <- matrix(FALSE, block$height, block$width)
      for (given in block$givens) taken[given[1L], given[2L]] <- TRUE
      for (row in seq_len(block$height)) for (column in seq_len(block$width)) if (answer[row, column] != UNKNOWN && !taken[row, column]) extra[[length(extra) + 1L]] <- c(row, column, answer[row, column])
      extendable <- analyze(block$row_clues, block$column_clues, extra)$status %in% c("unique", "multiple")
    }
    text <- paste0(text, " extendable=", if (extendable) "yes" else "no")
  }
  if (analysis$status == "unique") text <- paste0(text, " differs=", sum(answer != UNKNOWN & answer != analysis$solutions[[1L]]))
  lines <- text
  for (is_row in c(TRUE, FALSE)) for (index in if (is_row) rows else columns) {
    clue <- if (is_row) block$row_clues[[index]] else block$column_clues[[index]]
    cells <- line_cells(answer, is_row, index)
    detail <- if (result == "partial") paste0("cells=", state_string(cells)) else paste0("got=", clue_text(run_clue(cells), ","))
    lines <- c(lines, paste0("mismatch ", line_label(is_row, index), " expected=", clue_text(clue, ","), " ", detail))
  }
  list(result = result, lines = lines)
}
puzzle_report <- function(block) {
  a <- analyze(block$row_clues, block$column_clues, block$givens)
  grading <- if (!is.null(block$answer)) grade_answer(block, a) else NULL
  lines <- c(paste("PUZZLE", block$name), paste0("size=", block$width, "x", block$height, " givens=", length(block$givens), " status=", a$status, " difficulty=", a$difficulty),
    paste("clues", clue_statistics(block$row_clues, block$column_clues)),
    paste0("simple known=", determined_count(a$simple$grid), " line_solves=", length(a$simple$steps), " result=", a$simple_result),
    paste0("logic known=", determined_count(a$logic$grid), " line_solves=", length(a$logic$steps), " result=", a$logic_result), paste("steps", step_statistics(a$logic)))
  if (block$width * block$height <= 49L) lines <- c(lines, paste("trace", paste(vapply(a$logic$steps, step_text, character(1L)), collapse = " ")))
  if (a$logic_result == "stuck") lines <- c(lines, paste0("stuck rows=", unknown_summary(a$logic$grid, TRUE), " columns=", unknown_summary(a$logic$grid, FALSE)))
  if (a$status == "contradiction") {
    step <- a$logic$conflict
    clue <- if (step$row) block$row_clues[[step$index]] else block$column_clues[[step$index]]
    lines <- c(lines, paste0("conflict line=", line_label(step$row, step$index), " clue=", clue_text(clue, ","), " cells=", state_string(line_cells(a$logic$grid, step$row, step$index))))
  }
  if (!is.null(a$search)) {
    search <- a$search
    lines <- c(lines, paste0("search guesses=", length(search$guesses), " max_depth=", search$max_depth, " backtracks=", search$backtracks, " solutions=", length(search$solutions), " line_solves=", search$line_solves))
    for (guess in search$guesses) lines <- c(lines, paste0("guess ", guess$number, " depth=", guess$depth, " cell=", cell_text(c(guess$row, guess$column)), " value=", state_char(guess$value), " solves=", guess$solves, " known=", guess$known, " result=", guess$result))
  }
  if (a$status == "multiple") {
    cells <- differing_cells(a$solutions[[1L]], a$solutions[[2L]])
    lines <- c(lines, paste0("differ count=", nrow(cells), " cells=", paste(apply(cells, 1L, cell_text), collapse = " ")))
  }
  names <- character()
  grids <- list()
  if (a$status == "contradiction") {
    names <- "partial"
    grids <- list(a$logic$grid)
  } else {
    if (a$simple_result == "stuck") {
      names <- c(names, "simple")
      grids[[length(grids) + 1L]] <- a$simple$grid
    }
    if (a$logic_result == "stuck") {
      names <- c(names, "logic")
      grids[[length(grids) + 1L]] <- a$logic$grid
    }
    if (a$status == "multiple") {
      names <- c(names, "first", "second")
      grids <- c(grids, a$solutions)
    }
  }
  if (length(names)) lines <- c(lines, grid_display(names, grids))
  if (a$status == "unique") lines <- c(lines, "sheet", answer_sheet(block$row_clues, block$column_clues, a$solutions[[1L]]), paste("picture", features_text(a$solutions[[1L]])))
  lines <- c(lines, evaluate_givens(block, a), if (!is.null(grading)) grading$lines)
  fields <- c(block$name, a$status, a$difficulty, block$width, block$height, length(block$givens), determined_count(a$simple$grid), determined_count(a$logic$grid), a$line_solves, a$guesses, a$max_depth, length(a$solutions), if (is.null(grading)) "-" else grading$result)
  list(block = block, analysis = a, lines = lines, stats = paste(fields, collapse = ","), score = a$line_solves + 25L * a$guesses)
}
process_puzzles <- function(blocks) {
  names <- character()
  paragraphs <- reports <- list()
  stats <- "puzzle,status,difficulty,width,height,givens,simple_known,logic_known,line_solves,guesses,max_depth,solutions,answer"
  for (lines in blocks) {
    block <- validate_puzzle(parse_puzzle(lines), names)
    names <- c(names, block$name)
    if (!is.null(block$error)) {
      paragraphs[[length(paragraphs) + 1L]] <- c(paste("PUZZLE", block$name), paste("error", block$error))
      stats <- c(stats, paste0(block$name, ",invalid", strrep(",-", 11L)))
      next
    }
    report <- puzzle_report(block)
    reports[[length(reports) + 1L]] <- report
    paragraphs[[length(paragraphs) + 1L]] <- report$lines
    stats <- c(stats, report$stats)
  }
  ranked <- Filter(function(report) report$analysis$status == "unique", reports)
  if (length(ranked)) ranked <- ranked[order(vapply(ranked, function(report) match(report$analysis$difficulty, c("easy", "medium", "hard")), integer(1L)), vapply(ranked, function(report) report$score, integer(1L)), vapply(ranked, function(report) report$block$name, character(1L)), method = "radix")]
  ranking <- "RANKING"
  for (index in seq_along(ranked)) {
    report <- ranked[[index]]
    ranking <- c(ranking, paste0("rank ", index, " ", report$block$name, " ", report$analysis$difficulty, " score=", report$score, " size=", report$block$width, "x", report$block$height))
  }
  statuses <- vapply(reports, function(report) report$analysis$status, character(1L))
  difficulties <- vapply(reports, function(report) report$analysis$difficulty, character(1L))
  summary <- paste0("SUMMARY puzzles=", length(blocks), " invalid=", length(blocks) - length(reports), " contradiction=", sum(statuses == "contradiction"), " none=", sum(statuses == "none"), " unique=", sum(statuses == "unique"), " multiple=", sum(statuses == "multiple"), " easy=", sum(difficulties == "easy"), " medium=", sum(difficulties == "medium"), " hard=", sum(difficulties == "hard"), " line_solves=", sum(vapply(reports, function(report) report$analysis$line_solves, integer(1L))), " guesses=", sum(vapply(reports, function(report) report$analysis$guesses, integer(1L))))
  paragraphs <- c(paragraphs, list(ranking), list(summary))
  writeLines(join_paragraphs(paragraphs), "output/solutions.txt", useBytes = TRUE)
  writeLines(stats, "output/stats.csv", useBytes = TRUE)
  reports
}
validate_picture <- function(name, rows, names) {
  if (!valid_name(name)) return("bad name")
  if (name %in% names) return("duplicate name")
  if (length(rows) < 1L || length(rows) > 30L) return("bad height")
  for (index in seq_along(rows)) if (nchar(rows[index]) < 1L || nchar(rows[index]) > 30L || nchar(rows[index]) != nchar(rows[1L]) || !grepl("^[#.]+$", rows[index])) return(paste("bad row", index))
  NULL
}
generate_puzzle <- function(grid) {
  rows <- lapply(seq_len(nrow(grid)), function(row) run_clue(grid[row, ]))
  columns <- lapply(seq_len(ncol(grid)), function(column) run_clue(grid[, column]))
  givens <- list()
  log <- character()
  initial <- latest <- analyze(rows, columns, givens)
  while (latest$status == "multiple") {
    cell <- differing_cells(latest$solutions[[1L]], latest$solutions[[2L]])[1L, ]
    given <- c(cell, grid[cell[1L], cell[2L]])
    givens[[length(givens) + 1L]] <- given
    latest <- analyze(rows, columns, givens)
    log <- c(log, paste0("# hint ", length(givens), " cell=", cell_text(cell), " value=", state_char(given[3L]), " status=", latest$status))
  }
  original <- givens
  for (given in original) {
    others <- Filter(function(other) !identical(other, given), givens)
    if (analyze(rows, columns, others)$status == "unique") {
      givens <- others
      log <- c(log, paste0("# drop cell=", cell_text(given[1:2])))
    }
  }
  final <- analyze(rows, columns, givens)
  count <- 0L
  while (final$difficulty == "hard") {
    cell <- guess_cell(final$logic$grid)
    given <- c(cell, grid[cell[1L], cell[2L]])
    givens[[length(givens) + 1L]] <- given
    final <- analyze(rows, columns, givens)
    count <- count + 1L
    log <- c(log, paste0("# logic hint ", count, " cell=", cell_text(cell), " value=", state_char(given[3L]), " difficulty=", final$difficulty))
  }
  list(grid = grid, rows = rows, columns = columns, givens = givens, initial = initial, final = final, log = log)
}
picture_paragraph <- function(name, generation, reports) {
  g <- generation
  duplicate <- "-"
  for (report in reports) if (identical(report$block$row_clues, g$rows) && identical(report$block$column_clues, g$columns)) {
    duplicate <- report$block$name
    break
  }
  lines <- c(paste0("# picture ", name, " size=", ncol(g$grid), "x", nrow(g$grid), " ", features_text(g$grid)), paste0("# clues ", clue_statistics(g$rows, g$columns), " duplicate_of=", duplicate),
    paste0("# plain status=", g$initial$status, " difficulty=", g$initial$difficulty, " line_solves=", g$initial$line_solves, " guesses=", g$initial$guesses), g$log,
    paste0("# final status=", g$final$status, " difficulty=", g$final$difficulty, " hints=", length(g$givens), " line_solves=", g$final$line_solves, " guesses=", g$final$guesses),
    paste("PUZZLE", name), paste("SIZE", ncol(g$grid), nrow(g$grid)), "ROWS", vapply(g$rows, clue_text, character(1L)), "COLUMNS", vapply(g$columns, clue_text, character(1L)))
  givens <- g$givens
  if (length(givens)) givens <- givens[order(vapply(givens, function(given) given[1L], integer(1L)), vapply(givens, function(given) given[2L], integer(1L)))]
  for (given in givens) lines <- c(lines, paste("GIVEN", given[1L], given[2L], state_char(given[3L])))
  c(lines, "END")
}
process_pictures <- function(blocks, reports) {
  names <- character()
  generations <- paragraphs <- list()
  for (block in blocks) {
    name <- substring(block[1L], 9L)
    rows <- block[-1L]
    error <- validate_picture(name, rows, names)
    names <- c(names, name)
    if (!is.null(error)) paragraphs[[length(paragraphs) + 1L]] <- paste("# picture", name, "error", error)
    else {
      generation <- generate_puzzle(state_grid(rows))
      generations[[length(generations) + 1L]] <- generation
      paragraphs[[length(paragraphs) + 1L]] <- picture_paragraph(name, generation, reports)
    }
  }
  summary <- paste0("# SUMMARY pictures=", length(blocks), " invalid=", length(blocks) - length(generations), " unique=", sum(vapply(generations, function(g) g$initial$status == "unique", logical(1L))), " line_logic=", sum(vapply(generations, function(g) g$initial$difficulty %in% c("easy", "medium"), logical(1L))), " hinted=", sum(vapply(generations, function(g) length(g$givens) > 0L, logical(1L))), " hints=", sum(vapply(generations, function(g) length(g$givens), integer(1L))))
  writeLines(join_paragraphs(c(paragraphs, list(summary))), "output/generated.txt", useBytes = TRUE)
  invisible(NULL)
}

dir.create("output", showWarnings = FALSE)
reports <- process_puzzles(read_blocks("puzzles.txt"))
process_pictures(read_blocks("pictures.txt"), reports)
