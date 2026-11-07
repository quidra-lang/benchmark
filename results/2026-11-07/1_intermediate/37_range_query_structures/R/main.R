kinds <- c("SEG", "LAZY", "FEN", "RFEN", "SPARSE", "SQRT", "PERSIST")
operations <- c("SUM", "MIN", "MAX", "GCD")
number <- function(x) if (x == 0) "0" else format(x, scientific = FALSE, trim = TRUE, digits = 22L)
numbers <- function(x) paste(vapply(x, number, character(1L)), collapse = " ")
fail <- function(message) stop(structure(list(message = message), class = c("command_error", "error", "condition")))
record <- function(...) list2env(list(...), parent = emptyenv())
indices <- function(left, right) if (left > right) integer() else seq.int(left, right)
lowbit <- function(x) bitwAnd(x, -x)
gcd <- function(a, b) {
  a <- abs(a)
  b <- abs(b)
  while (b != 0) {
    rest <- a %% b
    a <- b
    b <- rest
  }
  a
}
aggregate <- function(values) c(sum(values), min(values), max(values))
aggregate_text <- function(value) paste0("sum=", number(value[1L]), " min=", number(value[2L]), " max=", number(value[3L]))
combine <- function(a, b) c(a[1L] + b[1L], min(a[2L], b[2L]), max(a[3L], b[3L]))
operate <- function(op, values) switch(op, SUM = sum(values), MIN = min(values), MAX = max(values), GCD = Reduce(gcd, values, init = 0))
counts <- function() record(visited = 0L, covered = 0L, pushes = 0L)
check_index <- function(n, index) {
  if (index < 0 || index >= n) fail(paste("BAD INDEX", number(index)))
}
check_range <- function(n, left, right) {
  check_index(n, left)
  check_index(n, right)
  if (left > right) fail(paste("BAD RANGE", numbers(c(left, right))))
}
check_version <- function(tree, version) {
  if (version < 0 || version >= length(tree$roots)) fail(paste("BAD VERSION", number(version)))
}
check_cell <- function(grid, row, column) {
  if (row < 0 || row >= grid$height || column < 0 || column >= grid$width) {
    fail(paste("BAD CELL", numbers(c(row, column))))
  }
}

tree_shape <- function(n) {
  tree <- record(n = n, left = rep.int(NA_integer_, 4L * n), right = integer(4L * n))
  visit <- function(node, left, right) {
    tree$left[node] <- left
    tree$right[node] <- right
    if (left < right) {
      middle <- (left + right) %/% 2L
      visit(2L * node, left, middle)
      visit(2L * node + 1L, middle + 1L, right)
    }
  }
  visit(1L, 0L, n - 1L)
  tree$nodes <- which(!is.na(tree$left))
  tree
}
new_segment <- function(values, op) {
  tree <- tree_shape(length(values))
  tree$op <- op
  tree$value <- numeric(4L * tree$n)
  build <- function(node) {
    left <- tree$left[node]
    right <- tree$right[node]
    if (left == right) {
      value <- values[left + 1L]
      tree$value[node] <- if (op == "GCD") abs(value) else value
    } else {
      build(2L * node)
      build(2L * node + 1L)
      tree$value[node] <- operate(op, tree$value[c(2L * node, 2L * node + 1L)])
    }
  }
  build(1L)
  tree
}
segment_query <- function(tree, node, left, right, count) {
  count$visited <- count$visited + 1L
  nl <- tree$left[node]
  nr <- tree$right[node]
  if (left <= nl && nr <= right) return(tree$value[node])
  middle <- (nl + nr) %/% 2L
  if (right <= middle) return(segment_query(tree, 2L * node, left, right, count))
  if (left > middle) return(segment_query(tree, 2L * node + 1L, left, right, count))
  first <- segment_query(tree, 2L * node, left, right, count)
  second <- segment_query(tree, 2L * node + 1L, left, right, count)
  operate(tree$op, c(first, second))
}
segment_update <- function(tree, node, index, value) {
  left <- tree$left[node]
  right <- tree$right[node]
  if (left == right) {
    tree$value[node] <- if (tree$op == "GCD") abs(value) else value
    return(1L)
  }
  child <- 2L * node + as.integer(index > (left + right) %/% 2L)
  visited <- segment_update(tree, child, index, value) + 1L
  tree$value[node] <- operate(tree$op, tree$value[c(2L * node, 2L * node + 1L)])
  visited
}
lazy_pull <- function(tree, node) {
  tree$value[node, ] <- combine(tree$value[2L * node, ], tree$value[2L * node + 1L, ])
}
new_lazy <- function(values) {
  tree <- tree_shape(length(values))
  tree$value <- matrix(0, 4L * tree$n, 3L)
  tree$assign <- rep.int(NA_real_, 4L * tree$n)
  tree$add <- numeric(4L * tree$n)
  build <- function(node) {
    if (tree$left[node] == tree$right[node]) {
      tree$value[node, ] <- values[tree$left[node] + 1L]
    } else {
      build(2L * node)
      build(2L * node + 1L)
      lazy_pull(tree, node)
    }
  }
  build(1L)
  tree
}
lazy_apply <- function(tree, node, value, assignment) {
  change <- c(value * (tree$right[node] - tree$left[node] + 1L), value, value)
  tree$value[node, ] <- if (assignment) change else tree$value[node, ] + change
  if (tree$left[node] < tree$right[node]) {
    if (assignment) {
      tree$assign[node] <- value
      tree$add[node] <- 0
    } else tree$add[node] <- tree$add[node] + value
  }
}
lazy_push <- function(tree, node, count) {
  assignment <- tree$assign[node]
  addition <- tree$add[node]
  if (is.na(assignment) && addition == 0) return(invisible(NULL))
  count$pushes <- count$pushes + 1L
  for (child in c(2L * node, 2L * node + 1L)) {
    if (!is.na(assignment)) lazy_apply(tree, child, assignment, TRUE)
    if (addition != 0) lazy_apply(tree, child, addition, FALSE)
  }
  tree$assign[node] <- NA_real_
  tree$add[node] <- 0
}
lazy_update <- function(tree, node, left, right, value, assignment, count) {
  count$visited <- count$visited + 1L
  nl <- tree$left[node]
  nr <- tree$right[node]
  if (left <= nl && nr <= right) {
    count$covered <- count$covered + 1L
    lazy_apply(tree, node, value, assignment)
    return(invisible(NULL))
  }
  lazy_push(tree, node, count)
  middle <- (nl + nr) %/% 2L
  if (left <= middle) lazy_update(tree, 2L * node, left, right, value, assignment, count)
  if (right > middle) lazy_update(tree, 2L * node + 1L, left, right, value, assignment, count)
  lazy_pull(tree, node)
}
lazy_query <- function(tree, node, left, right, count) {
  count$visited <- count$visited + 1L
  nl <- tree$left[node]
  nr <- tree$right[node]
  if (left <= nl && nr <= right) return(tree$value[node, ])
  lazy_push(tree, node, count)
  middle <- (nl + nr) %/% 2L
  if (right <= middle) return(lazy_query(tree, 2L * node, left, right, count))
  if (left > middle) return(lazy_query(tree, 2L * node + 1L, left, right, count))
  first <- lazy_query(tree, 2L * node, left, right, count)
  second <- lazy_query(tree, 2L * node + 1L, left, right, count)
  combine(first, second)
}

bit_add <- function(tree, position, value, count = NULL) {
  while (position <= length(tree)) {
    tree[position] <- tree[position] + value
    if (!is.null(count)) count$visited <- count$visited + 1L
    position <- position + lowbit(position)
  }
  tree
}
new_bit <- function(values) {
  tree <- numeric(length(values))
  for (i in seq_along(values)) tree <- bit_add(tree, i, values[i])
  tree
}
bit_prefix <- function(tree, position, count) {
  value <- 0
  while (position > 0) {
    value <- value + tree[position]
    count$visited <- count$visited + 1L
    position <- position - lowbit(position)
  }
  value
}
bit_lower <- function(tree, remaining, count) {
  n <- length(tree)
  step <- 1L
  while (2L * step <= n) step <- 2L * step
  position <- 0L
  while (step > 0L) {
    if (position + step <= n) {
      count$visited <- count$visited + 1L
      if (tree[position + step] < remaining) {
        remaining <- remaining - tree[position + step]
        position <- position + step
      }
    }
    step <- step %/% 2L
  }
  if (position == n) "none" else number(position)
}
rfen_prefix <- function(tree, position, count) {
  first <- bit_prefix(tree$first, position, count)
  second <- bit_prefix(tree$second, position, count)
  position * first - second
}
new_sparse <- function(values) {
  n <- length(values)
  tree <- record(values = values, minima = list(seq_len(n) - 1L), maxima = list(seq_len(n) - 1L))
  width <- 2L
  while (width <= n) {
    level <- length(tree$minima)
    positions <- seq_len(n - width + 1L)
    a <- tree$minima[[level]][positions]
    b <- tree$minima[[level]][positions + width %/% 2L]
    tree$minima[[level + 1L]] <- ifelse(values[a + 1L] <= values[b + 1L], a, b)
    a <- tree$maxima[[level]][positions]
    b <- tree$maxima[[level]][positions + width %/% 2L]
    tree$maxima[[level + 1L]] <- ifelse(values[a + 1L] >= values[b + 1L], a, b)
    width <- 2L * width
  }
  tree
}
sparse_query <- function(tree, left, right) {
  level <- 0L
  width <- 1L
  while (2L * width <= right - left + 1L) {
    width <- 2L * width
    level <- level + 1L
  }
  end <- right - width + 1L
  pair <- tree$minima[[level + 1L]][c(left, end) + 1L]
  low <- if (tree$values[pair[1L] + 1L] <= tree$values[pair[2L] + 1L]) pair[1L] else pair[2L]
  pair <- tree$maxima[[level + 1L]][c(left, end) + 1L]
  high <- if (tree$values[pair[1L] + 1L] >= tree$values[pair[2L] + 1L]) pair[1L] else pair[2L]
  values <- tree$values[c(low, high) + 1L]
  list(text = paste0("min=", number(values[1L]), " minpos=", number(low), " max=", number(values[2L]),
                     " maxpos=", number(high), " level=", level), values = values)
}
new_sqrt <- function(values, block) {
  groups <- (seq_along(values) - 1L) %/% block
  sums <- as.numeric(rowsum(values, groups, reorder = FALSE))
  record(values = values, block = block, sums = sums, tags = numeric(length(sums)))
}
split_blocks <- function(tree, left, right) {
  first <- left %/% tree$block
  last <- right %/% tree$block
  if (first == last) cells <- indices(left, right) else {
    cells <- c(indices(left, (first + 1L) * tree$block - 1L), indices(last * tree$block, right))
  }
  list(cells = cells, blocks = indices(first + 1L, last - 1L))
}
sqrt_update <- function(tree, left, right, value) {
  split <- split_blocks(tree, left, right)
  for (index in split$cells) {
    block <- index %/% tree$block + 1L
    tree$values[index + 1L] <- tree$values[index + 1L] + value
    tree$sums[block] <- tree$sums[block] + value
  }
  blocks <- split$blocks + 1L
  tree$tags[blocks] <- tree$tags[blocks] + value
  tree$sums[blocks] <- tree$sums[blocks] + value * tree$block
  split
}
sqrt_query <- function(tree, left, right) {
  split <- split_blocks(tree, left, right)
  value <- sum(tree$values[split$cells + 1L] + tree$tags[split$cells %/% tree$block + 1L])
  value <- value + sum(tree$sums[split$blocks + 1L])
  list(text = paste0("sum=", number(value), " whole=", length(split$blocks), " cells=", length(split$cells)), values = value)
}

new_pool <- function() record(left = integer(), right = integer(), values = numeric(), size = 0L)
pool_append <- function(pool, left, right, value) {
  pool$size <- pool$size + 1L
  node <- pool$size
  pool$left[node] <- left
  pool$right[node] <- right
  pool$values[node] <- value
  node
}
pool_build <- function(pool, values, left, right) {
  if (left == right) return(pool_append(pool, 0L, 0L, values[left + 1L]))
  middle <- (left + right) %/% 2L
  a <- pool_build(pool, values, left, middle)
  b <- pool_build(pool, values, middle + 1L, right)
  pool_append(pool, a, b, pool$values[a] + pool$values[b])
}
pool_fork <- function(pool, source, left, right, index, value, increment) {
  a <- pool$left[source]
  b <- pool$right[source]
  if (left == right) {
    if (increment) value <- pool$values[source] + value
    return(pool_append(pool, 0L, 0L, value))
  }
  middle <- (left + right) %/% 2L
  if (index <= middle) {
    a <- pool_fork(pool, a, left, middle, index, value, increment)
  } else b <- pool_fork(pool, b, middle + 1L, right, index, value, increment)
  pool_append(pool, a, b, pool$values[a] + pool$values[b])
}
pool_query <- function(pool, root, nl, nr, left, right, count) {
  count$visited <- count$visited + 1L
  if (left <= nl && nr <= right) return(pool$values[root])
  middle <- (nl + nr) %/% 2L
  if (right <= middle) return(pool_query(pool, pool$left[root], nl, middle, left, right, count))
  if (left > middle) return(pool_query(pool, pool$right[root], middle + 1L, nr, left, right, count))
  a <- pool_query(pool, pool$left[root], nl, middle, left, right, count)
  b <- pool_query(pool, pool$right[root], middle + 1L, nr, left, right, count)
  a + b
}
new_persistent <- function(values) {
  tree <- record(n = length(values), position = new_pool(), value = new_pool(), domain = sort(unique(values)))
  tree$roots <- pool_build(tree$position, values, 0L, tree$n - 1L)
  m <- length(tree$domain)
  tree$prefixes <- pool_build(tree$value, numeric(m), 0L, m - 1L)
  for (i in seq_along(values)) {
    rank <- match(values[i], tree$domain) - 1L
    tree$prefixes[i + 1L] <- pool_fork(tree$value, tree$prefixes[i], 0L, m - 1L, rank, 1, TRUE)
  }
  tree
}
persistent_kth <- function(tree, left, right, k, count) {
  upper <- tree$prefixes[right + 2L]
  lower <- tree$prefixes[left + 1L]
  left <- 0L
  right <- length(tree$domain) - 1L
  count$visited <- 1L
  pool <- tree$value
  while (left < right) {
    middle <- (left + right) %/% 2L
    a <- pool$left[upper]
    b <- pool$left[lower]
    size <- pool$values[a] - pool$values[b]
    if (k <= size) {
      upper <- a
      lower <- b
      right <- middle
    } else {
      k <- k - size
      upper <- pool$right[upper]
      lower <- pool$right[lower]
      left <- middle + 1L
    }
    count$visited <- count$visited + 1L
  }
  tree$domain[left + 1L]
}
grid_add <- function(grid, row, column, value, count = NULL) {
  y <- row + 1L
  while (y <= grid$height) {
    x <- column + 1L
    while (x <= grid$width) {
      grid$tree[y, x] <- grid$tree[y, x] + value
      if (!is.null(count)) count$visited <- count$visited + 1L
      x <- x + lowbit(x)
    }
    y <- y + lowbit(y)
  }
}
new_grid <- function(height, width, values) {
  grid <- record(height = height, width = width, tree = matrix(0, height, width))
  for (index in seq_along(values)) grid_add(grid, (index - 1L) %/% width, (index - 1L) %% width, values[index])
  grid
}
grid_prefix <- function(grid, row, column, count) {
  value <- 0
  while (row > 0L) {
    x <- column
    while (x > 0L) {
      value <- value + grid$tree[row, x]
      count$visited <- count$visited + 1L
      x <- x - lowbit(x)
    }
    row <- row - lowbit(row)
  }
  value
}

new_lab <- function(values) record(values = values, original = values,
                                  structures = setNames(vector("list", length(kinds)), kinds), grid = NULL)
build_array <- function(lab, kind, parameter = NULL) {
  values <- lab$values
  n <- length(values)
  tree <- switch(kind,
    SEG = new_segment(values, parameter), LAZY = new_lazy(values),
    FEN = record(values = values, tree = new_bit(values)),
    RFEN = {
      differences <- values - c(0, head(values, -1L))
      record(first = new_bit(differences), second = new_bit((seq_along(values) - 1L) * differences))
    },
    SPARSE = new_sparse(values), SQRT = new_sqrt(values, parameter), PERSIST = new_persistent(values))
  lab$structures[[kind]] <- tree
  switch(kind,
    SEG = paste0("SEG BUILD ", parameter, " nodes=", length(tree$nodes), " maxnode=", max(tree$nodes), " root=", number(tree$value[1L])),
    LAZY = paste0("LAZY BUILD nodes=", length(tree$nodes), " ", aggregate_text(tree$value[1L, ])),
    FEN = paste0("FEN BUILD n=", n, " total=", number(sum(values))),
    RFEN = paste0("RFEN BUILD n=", n, " total=", number(sum(values))),
    SPARSE = paste0("SPARSE BUILD levels=", length(tree$minima), " entries=", sum(lengths(tree$minima))),
    SQRT = paste0("SQRT BUILD block=", number(tree$block), " blocks=", length(tree$tags)),
    PERSIST = paste0("PERSIST BUILD nodes=", tree$position$size, " distinct=", length(tree$domain), " valuenodes=", tree$value$size))
}
query_array <- function(lab, kind, left, right, version = 0L) {
  tree <- lab$structures[[kind]]
  count <- counts()
  if (kind == "SPARSE") return(sparse_query(tree, left, right))
  if (kind == "SQRT") return(sqrt_query(tree, left, right))
  if (kind == "SEG") {
    value <- segment_query(tree, 1L, left, right, count)
    return(list(text = paste0(tolower(tree$op), "=", number(value), " visited=", count$visited), values = value))
  }
  if (kind == "LAZY") {
    value <- lazy_query(tree, 1L, left, right, count)
    return(list(text = paste0(aggregate_text(value), " visited=", count$visited, " pushes=", count$pushes), values = value))
  }
  if (kind == "FEN") {
    first <- bit_prefix(tree$tree, right + 1L, count)
    second <- bit_prefix(tree$tree, left, count)
    value <- first - second
  } else if (kind == "RFEN") {
    first <- rfen_prefix(tree, right + 1L, count)
    second <- rfen_prefix(tree, left, count)
    value <- first - second
  } else value <- pool_query(tree$position, tree$roots[version + 1L], 0L, tree$n - 1L, left, right, count)
  list(text = paste0("sum=", number(value), " visited=", count$visited), values = value)
}
dump_structure <- function(lab, kind) {
  tree <- if (kind == "GRID") lab$grid else lab$structures[[kind]]
  n <- length(lab$values)
  if (kind %in% c("SEG", "LAZY")) {
    heading <- if (kind == "SEG") paste("SEG DUMP", tree$op) else "LAZY DUMP"
    rows <- paste0(heading, " nodes=", length(tree$nodes))
    for (node in tree$nodes) {
      prefix <- paste("NODE", numbers(c(node, tree$left[node], tree$right[node])))
      details <- if (kind == "SEG") number(tree$value[node]) else {
        assignment <- if (is.na(tree$assign[node])) "-" else number(tree$assign[node])
        paste0(aggregate_text(tree$value[node, ]), " assign=", assignment, " add=", number(tree$add[node]))
      }
      rows <- c(rows, paste(prefix, details))
    }
    return(rows)
  }
  if (kind == "FEN") return(c(paste0("FEN DUMP n=", n), paste("T", numbers(tree$tree))))
  if (kind == "RFEN") return(c(paste0("RFEN DUMP n=", n), paste("B1", numbers(tree$first)), paste("B2", numbers(tree$second))))
  if (kind == "SPARSE") {
    rows <- paste0("SPARSE DUMP levels=", length(tree$minima))
    for (level in seq_along(tree$minima)) rows <- c(rows,
      paste("MIN", level - 1L, numbers(tree$minima[[level]])), paste("MAX", level - 1L, numbers(tree$maxima[[level]])))
    return(rows)
  }
  if (kind == "SQRT") {
    rows <- paste0("SQRT DUMP block=", number(tree$block), " blocks=", length(tree$tags))
    for (block in seq_along(tree$tags)) {
      first <- (block - 1L) * tree$block
      end <- min(n, block * tree$block)
      rows <- c(rows, paste0("BLOCK ", numbers(c(block - 1L, first, end - 1L)), " add=", number(tree$tags[block]),
                            " sum=", number(tree$sums[block]), " ", numbers(tree$values[indices(first + 1L, end)])))
    }
    return(rows)
  }
  rows <- paste0("GRID DUMP rows=", tree$height, " cols=", tree$width)
  for (row in seq_len(tree$height)) rows <- c(rows, paste("ROW", row, numbers(tree$tree[row, ])))
  rows
}
check_all <- function(lab, left, right) {
  values <- lab$values[indices(left, right) + 1L]
  direct <- aggregate(values)
  common <- Reduce(gcd, values, init = 0)
  rows <- paste0("CHECK ", numbers(c(left, right)), " ", aggregate_text(direct), " gcd=", number(common))
  ok <- different <- 0L
  for (kind in kinds) {
    tree <- lab$structures[[kind]]
    if (is.null(tree)) next
    expected <- direct[1L]
    if (kind == "SEG") {
      expected <- c(direct, common)[match(tree$op, operations)]
    } else if (kind == "LAZY") expected <- direct else if (kind == "SPARSE") expected <- direct[2:3]
    version <- if (kind == "PERSIST") length(tree$roots) - 1L else 0L
    answer <- query_array(lab, kind, left, right, version)
    same <- all(answer$values == expected)
    if (same) ok <- ok + 1L else different <- different + 1L
    prefix <- if (kind == "PERSIST") paste0("version=", version, " ") else ""
    rows <- c(rows, paste(kind, if (same) "OK" else "DIFF", paste0(prefix, answer$text)))
  }
  c(rows, paste0("RESULT ok=", ok, " diff=", different))
}
mo <- function(values, queries) {
  block <- floor(sqrt(length(values)))
  groups <- queries[, 1L] %/% block
  direction <- ifelse(groups %% 2L == 0L, queries[, 2L], -queries[, 2L])
  order <- order(groups, direction, seq_len(nrow(queries)), method = "radix")
  ranks <- match(values, unique(values))
  frequency <- integer(max(ranks))
  answers <- integer(nrow(queries))
  left <- 0L
  right <- -1L
  moves <- 0L
  for (index in order) {
    target <- queries[index, ]
    moves <- moves + abs(target[1L] - left) + abs(target[2L] - right)
    while (left > target[1L]) {
      left <- left - 1L
      rank <- ranks[left + 1L]
      frequency[rank] <- frequency[rank] + 1L
    }
    while (right < target[2L]) {
      right <- right + 1L
      rank <- ranks[right + 1L]
      frequency[rank] <- frequency[rank] + 1L
    }
    while (left < target[1L]) {
      rank <- ranks[left + 1L]
      frequency[rank] <- frequency[rank] - 1L
      left <- left + 1L
    }
    while (right > target[2L]) {
      rank <- ranks[right + 1L]
      frequency[rank] <- frequency[rank] - 1L
      right <- right - 1L
    }
    answers[index] <- sum(frequency > 0L)
  }
  rows <- c(paste0("MO queries=", nrow(queries), " block=", number(block), " moves=", number(moves)), paste("ORDER", numbers(order)))
  for (index in seq_len(nrow(queries))) rows <- c(rows, paste0("ANSWER ", index, " ", numbers(queries[index, ]), " distinct=", answers[index]))
  rows
}
execute <- function(lab, line) {
  words <- strsplit(line, " ", fixed = TRUE)[[1L]]
  command <- words[1L]
  n <- length(lab$values)
  if (command == "LOAD") {
    removed <- sum(!vapply(lab$structures, is.null, logical(1L)))
    lab$values <- lab$original <- as.numeric(words[-1L])
    lab$structures <- setNames(vector("list", length(kinds)), kinds)
    return(paste0("LOAD n=", length(lab$values), " removed=", removed))
  }
  if (command == "RESET") {
    lab$values <- lab$original
    rebuilt <- 0L
    for (kind in kinds) {
      tree <- lab$structures[[kind]]
      if (is.null(tree)) next
      parameter <- if (kind == "SEG") tree$op else if (kind == "SQRT") tree$block else NULL
      build_array(lab, kind, parameter)
      rebuilt <- rebuilt + 1L
    }
    return(paste0("RESET rebuilt=", rebuilt))
  }
  if (command %in% c("ARRAY", "CHECK")) {
    args <- as.numeric(words[-1L])
    check_range(n, args[1L], args[2L])
    if (command == "CHECK") return(check_all(lab, args[1L], args[2L]))
    return(paste(line, numbers(lab$values[indices(args[1L], args[2L]) + 1L])))
  }
  if (command == "MO") {
    queries <- matrix(as.numeric(words[-1L]), ncol = 2L, byrow = TRUE)
    for (index in seq_len(nrow(queries))) check_range(n, queries[index, 1L], queries[index, 2L])
    return(mo(lab$values, queries))
  }
  kind <- command
  action <- words[2L]
  if (action == "BUILD") {
    parameter <- NULL
    if (kind == "SEG") {
      parameter <- words[3L]
      if (!parameter %in% operations) fail(paste("BAD OP", parameter))
    } else if (kind == "SQRT") {
      parameter <- if (length(words) == 3L) as.numeric(words[3L]) else floor(sqrt(n))
      if (parameter > n) fail(paste("BAD BLOCK", number(parameter)))
    } else if (kind == "GRID") {
      height <- as.numeric(words[3L])
      width <- as.numeric(words[4L])
      actual <- length(words) - 4L
      if (actual != height * width) fail(paste("BAD COUNT", actual, number(height * width)))
      values <- as.numeric(words[-seq_len(4L)])
      lab$grid <- new_grid(height, width, values)
      return(paste0("GRID BUILD rows=", number(height), " cols=", number(width), " total=", number(sum(values))))
    }
    return(build_array(lab, kind, parameter))
  }
  tree <- if (kind == "GRID") lab$grid else lab$structures[[kind]]
  if (is.null(tree)) fail(paste("NOT BUILT", kind))
  if (action == "DUMP") return(dump_structure(lab, kind))
  args <- as.numeric(words[-c(1L, 2L)])
  count <- counts()
  if (kind == "GRID") {
    check_cell(tree, args[1L], args[2L])
    if (action == "ADD") {
      grid_add(tree, args[1L], args[2L], args[3L], count)
      return(paste0(line, " visited=", count$visited))
    }
    check_cell(tree, args[3L], args[4L])
    if (args[1L] > args[3L] || args[2L] > args[4L]) fail(paste("BAD RECT", numbers(args)))
    first <- grid_prefix(tree, args[3L] + 1L, args[4L] + 1L, count)
    second <- grid_prefix(tree, args[1L], args[4L] + 1L, count)
    third <- grid_prefix(tree, args[3L] + 1L, args[2L], count)
    fourth <- grid_prefix(tree, args[1L], args[2L], count)
    return(paste0(line, " sum=", number(first - second - third + fourth), " visited=", count$visited))
  }
  if (kind == "PERSIST") {
    if (action == "NODES") return(paste0(line, " versions=", length(tree$roots), " position=", tree$position$size, " value=", tree$value$size))
    if (action == "KTH") {
      check_range(n, args[1L], args[2L])
      if (args[3L] < 1 || args[3L] > args[2L] - args[1L] + 1L) fail(paste("BAD K", number(args[3L])))
      value <- persistent_kth(tree, args[1L], args[2L], args[3L], count)
      return(paste0(line, " value=", number(value), " visited=", count$visited))
    }
    version <- args[1L]
    check_version(tree, version)
    if (action == "SET") {
      check_index(n, args[2L])
      before <- tree$position$size
      new_version <- length(tree$roots)
      root <- pool_fork(tree$position, tree$roots[version + 1L], 0L, n - 1L, args[2L], args[3L], FALSE)
      tree$roots <- c(tree$roots, root)
      return(paste0(line, " version=", new_version, " created=", tree$position$size - before))
    }
    check_range(n, args[2L], args[3L])
    return(paste(line, query_array(lab, kind, args[2L], args[3L], version)$text))
  }
  if (kind == "FEN" && action == "LOWER") {
    negative <- which(tree$values < 0)
    if (length(negative)) fail(paste("NEGATIVE", negative[1L] - 1L))
    index <- bit_lower(tree$tree, args[1L], count)
    return(paste0(line, " index=", index, " visited=", count$visited))
  }
  if (kind == "SEG" && action == "UPDATE") {
    check_index(n, args[1L])
    visited <- segment_update(tree, 1L, args[1L], args[2L])
    lab$values[args[1L] + 1L] <- args[2L]
    return(paste0(line, " root=", number(tree$value[1L]), " visited=", visited))
  }
  if (kind == "FEN" && action %in% c("ADD", "PREFIX")) {
    check_index(n, args[1L])
    index <- args[1L] + 1L
    if (action == "ADD") {
      tree$tree <- bit_add(tree$tree, index, args[2L], count)
      tree$values[index] <- tree$values[index] + args[2L]
      lab$values[index] <- lab$values[index] + args[2L]
      return(paste0(line, " visited=", count$visited))
    }
    value <- bit_prefix(tree$tree, index, count)
    return(paste0(line, " sum=", number(value), " visited=", count$visited))
  }
  left <- args[1L]
  right <- args[2L]
  check_range(n, left, right)
  if (action %in% c("ADD", "ASSIGN")) {
    value <- args[3L]
    assignment <- action == "ASSIGN"
    if (kind == "LAZY") {
      lazy_update(tree, 1L, left, right, value, assignment, count)
      details <- paste0("visited=", count$visited, " covered=", count$covered, " pushes=", count$pushes)
    } else if (kind == "RFEN") {
      tree$first <- bit_add(tree$first, left + 1L, value, count)
      tree$first <- bit_add(tree$first, right + 2L, -value, count)
      tree$second <- bit_add(tree$second, left + 1L, value * left, count)
      tree$second <- bit_add(tree$second, right + 2L, -value * (right + 1L), count)
      details <- paste0("visited=", count$visited)
    } else {
      split <- sqrt_update(tree, left, right, value)
      details <- paste0("whole=", length(split$blocks), " cells=", length(split$cells))
    }
    selected <- indices(left, right) + 1L
    lab$values[selected] <- if (assignment) value else lab$values[selected] + value
    return(paste(line, details))
  }
  paste(line, query_array(lab, kind, left, right)$text)
}

input <- file("stdin", open = "r")
initial_size <- as.integer(readLines(input, n = 1L, warn = FALSE))
initial_values <- as.numeric(strsplit(readLines(input, n = 1L, warn = FALSE), " ", fixed = TRUE)[[1L]])
lab <- new_lab(initial_values)
command_count <- as.integer(readLines(input, n = 1L, warn = FALSE))
for (command_index in seq_len(command_count)) {
  line <- readLines(input, n = 1L, warn = FALSE)
  rows <- tryCatch(execute(lab, line), command_error = function(problem) paste("ERROR", problem$message))
  cat(paste0(rows, "\n"), sep = "")
}
close(input)
