queens <- function(n) {
  variables <- n * n
  clauses <- lapply(seq_len(n), function(r) (r - 1L) * n + seq_len(n))
  for (a in seq_len(variables)) {
    if (a == variables) next
    row_a <- (a - 1L) %/% n
    col_a <- (a - 1L) %% n
    for (b in seq.int(a + 1L, variables)) {
      row_b <- (b - 1L) %/% n
      col_b <- (b - 1L) %% n
      if (row_a == row_b || col_a == col_b || abs(row_a - row_b) == abs(col_a - col_b)) clauses[[length(clauses) + 1L]] <- c(
          -a,
          -b
      )
    }
  }
  list(variables = variables, clauses = clauses)
}
pigeon <- function(pigeons, holes) {
  clauses <- lapply(seq_len(pigeons), function(p) (p - 1L) * holes + seq_len(holes))
  for (p in seq_len(pigeons)) for (first in seq_len(holes - 1L)) for (second in seq.int(first + 1L, holes)) clauses[[length(clauses) + 1L]] <- c(
      -((p - 1L) * holes + first),
      -((p - 1L) * holes + second)
  )
  for (hole in seq_len(holes)) for (first in seq_len(pigeons - 1L)) for (second in seq.int(first + 1L, pigeons)) clauses[[length(clauses) + 1L]] <- c(
      -((first - 1L) * holes + hole),
      -((second - 1L) * holes + hole)
  )
  list(variables = pigeons * holes, clauses = clauses)
}
coloring <- function(graph, colors) {
  vertices <- graph$vertices
  clauses <- lapply(seq_len(vertices), function(v) (v - 1L) * colors + seq_len(colors))
  for (v in seq_len(vertices)) for (first in seq_len(colors - 1L)) for (second in seq.int(first + 1L, colors)) clauses[[length(clauses) + 1L]] <- c(
      -((v - 1L) * colors + first),
      -((v - 1L) * colors + second)
  )
  for (edge in graph$edges) for (color in seq_len(colors)) clauses[[length(clauses) + 1L]] <- c(
      -((edge[[1L]] - 1L) * colors + color),
      -((edge[[2L]] - 1L) * colors + color)
  )
  list(variables = vertices * colors, clauses = clauses)
}
positions <- function(model, rows, width) vapply(
    seq_len(rows),
    function(row) which(model[(row - 1L) * width + seq_len(width)])[[1L]],
    0L
)
queens_symmetries <- function(columns) {
  n <- length(columns)
  transforms <- list(function(r, c) c(r, c), function(r, c) c(c, n + 1L - r), function(r, c) c(n + 1L - r, n + 1L - c),
                     function(r, c) c(n + 1L - c, r), function(r, c) c(r, n + 1L - c), function(r, c) c(
                         n + 1L - r,
                         c
                     ),
                     function(r, c) c(c, r), function(r, c) c(n + 1L - c, n + 1L - r))
  lapply(transforms, function(transform) {
    current <- integer(n)
    for (row in seq_len(n)) {
      point <- transform(row, columns[[row]])
      current[[point[[1L]]]] <- point[[2L]]
    }
    current
  })
}
canonical_coloring <- function(colors) match(colors, unique(colors))
