say <- function(...) cat(paste0(...), "\n", sep = "")
fail <- function(message) {
  stop(structure(list(message = message, call = NULL), class = c("GraphError", "error", "condition")))
}
vertices <- function(g) seq_len(g$n) - 1L
pairs <- function(n) {
  result <- list()
  if (n >= 2L) {
    for (u in 0:(n - 2L)) {
      for (v in (u + 1L):(n - 1L)) result[[length(result) + 1L]] <- c(u, v)
    }
  }
  result
}
new_graph <- function(n) {
  g <- new.env(parent = emptyenv())
  g$n <- as.integer(n)
  g$adj <- matrix(FALSE, n, n)
  g
}
join <- function(g, u, v) {
  g$adj[u + 1L, v + 1L] <- TRUE
  g$adj[v + 1L, u + 1L] <- TRUE
}
edge_list <- function(g) {
  if (is.null(g$edges)) g$edges <- Filter(function(e) g$adj[e[[1]] + 1L, e[[2]] + 1L], pairs(g$n))
  g$edges
}
neighbors <- function(g, v) which(g$adj[v + 1L, ]) - 1L
degrees <- function(g) as.integer(rowSums(g$adj))
compare_sequences <- function(a, b) {
  for (i in seq_len(min(length(a), length(b)))) {
    if (a[[i]] != b[[i]]) return(if (a[[i]] < b[[i]]) -1L else 1L)
  }
  sign(length(a) - length(b))
}
compare_signature <- function(a, b) {
  if (a$color != b$color) return(sign(a$color - b$color))
  compare_sequences(a$neighbors, b$neighbors)
}
refine <- function(g, colors) {
  rounds <- 0L
  repeat {
    signatures <- lapply(vertices(g), function(v) {
      list(color = colors[[v + 1L]], neighbors = sort(colors[neighbors(g, v) + 1L]))
    })
    ordered <- integer()
    for (i in seq_along(signatures)) {
      at <- length(ordered)
      while (at > 0L && compare_signature(signatures[[i]], signatures[[ordered[[at]]]]) < 0L) at <- at - 1L
      ordered <- append(ordered, i, after = at)
    }
    fresh <- integer(g$n)
    color <- -1L
    previous <- NULL
    for (i in ordered) {
      if (is.null(previous) || compare_signature(signatures[[i]], previous) != 0L) color <- color + 1L
      fresh[[i]] <- color
      previous <- signatures[[i]]
    }
    if (color + 1L == length(unique(colors))) return(list(colors = colors, rounds = rounds))
    colors <- fresh
    rounds <- rounds + 1L
  }
}
stable <- function(g) {
  if (is.null(g$stable)) {
    d <- degrees(g)
    g$stable <- refine(g, match(d, sort(unique(d))) - 1L)
  }
  g$stable
}
individualize <- function(colors, v) {
  x <- colors[[v + 1L]]
  result <- colors
  selected <- which(colors >= x & seq_along(colors) != v + 1L)
  result[selected] <- result[selected] + 1L
  result
}
leaf_string <- function(g, labels) {
  inverse <- order(labels) - 1L
  paste0(vapply(pairs(g$n), function(e) {
    if (g$adj[inverse[[e[[1]] + 1L]] + 1L, inverse[[e[[2]] + 1L]] + 1L]) "1" else "0"
  }, character(1)), collapse = "")
}
canonical <- function(g) {
  if (!is.null(g$canonical)) return(g$canonical)
  nodes <- 0L
  leaves <- 0L
  best <- NULL
  labels <- integer()
  winners <- list()
  visit <- function(colors) {
    nodes <<- nodes + 1L
    if (length(unique(colors)) == g$n) {
      leaves <<- leaves + 1L
      string <- leaf_string(g, colors)
      if (is.null(best) || string > best) {
        best <<- string
        labels <<- colors
        winners <<- list(colors)
      } else if (string == best) {
        winners[[length(winners) + 1L]] <<- colors
      }
      return(invisible(NULL))
    }
    cells <- lapply(0:max(colors), function(c) which(colors == c) - 1L)
    sizes <- lengths(cells)
    sizes[sizes == 1L] <- g$n + 1L
    cell <- cells[[which.min(sizes)]]
    for (v in cell) visit(refine(g, individualize(colors, v))$colors)
  }
  visit(stable(g)$colors)
  g$canonical <- list(nodes = nodes, leaves = leaves, string = best, labels = labels, winners = winners)
  g$canonical
}
invariants <- function(g) {
  if (!is.null(g$invariants)) return(g$invariants)
  components <- integer()
  seen <- rep(FALSE, g$n)
  for (start in vertices(g)) {
    if (seen[[start + 1L]]) next
    queue <- start
    seen[[start + 1L]] <- TRUE
    at <- 1L
    while (at <= length(queue)) {
      u <- queue[[at]]
      at <- at + 1L
      for (v in neighbors(g, u)) {
        if (!seen[[v + 1L]]) {
          seen[[v + 1L]] <- TRUE
          queue <- c(queue, v)
        }
      }
    }
    components <- c(components, length(queue))
  }
  girth <- Inf
  eccentricities <- integer()
  bipartite <- TRUE
  for (start in vertices(g)) {
    distance <- rep(-1L, g$n)
    parent <- rep(-1L, g$n)
    distance[[start + 1L]] <- 0L
    queue <- start
    at <- 1L
    while (at <= length(queue)) {
      u <- queue[[at]]
      at <- at + 1L
      for (v in neighbors(g, u)) {
        if (distance[[v + 1L]] == -1L) {
          distance[[v + 1L]] <- distance[[u + 1L]] + 1L
          parent[[v + 1L]] <- u
          queue <- c(queue, v)
        } else if (parent[[u + 1L]] != v) {
          girth <- min(girth, distance[[u + 1L]] + distance[[v + 1L]] + 1L)
        }
        if (distance[[u + 1L]] %% 2L == distance[[v + 1L]] %% 2L) bipartite <- FALSE
      }
    }
    eccentricities <- c(eccentricities, max(distance))
  }
  triangles <- 0L
  if (g$n >= 3L) {
    for (a in 0:(g$n - 3L)) {
      for (b in (a + 1L):(g$n - 2L)) {
        for (c in (b + 1L):(g$n - 1L)) {
          if (g$adj[a + 1L, b + 1L] && g$adj[a + 1L, c + 1L] && g$adj[b + 1L, c + 1L]) triangles <- triangles + 1L
        }
      }
    }
  }
  g$invariants <- list(degrees = sort(degrees(g), decreasing = TRUE), triangles = triangles,
    sizes = sort(components, decreasing = TRUE), components = length(components),
    girth = if (is.infinite(girth)) "none" else girth,
    diameter = if (length(components) == 1L) max(eccentricities) else "INF",
    radius = if (length(components) == 1L) min(eccentricities) else "INF",
    bipartite = if (bipartite) "yes" else "no")
  g$invariants
}
clique <- function(g) {
  best <- integer()
  for (mask in seq_len(2^g$n - 1L)) {
    set <- vertices(g)[bitwAnd(mask, bitwShiftL(1L, vertices(g))) != 0L]
    valid <- all(vapply(pairs(length(set)), function(e) g$adj[set[[e[[1]] + 1L]] + 1L, set[[e[[2]] + 1L]] + 1L], logical(1)))
    if (valid && (length(set) > length(best) || (length(set) == length(best) && compare_sequences(set, best) < 0L))) best <- set
  }
  best
}
coloring <- function(g) {
  for (limit in seq_len(g$n)) {
    colors <- rep(-1L, g$n)
    search <- function(v, maximum) {
      if (v == g$n) return(TRUE)
      for (color in 0:min(limit - 1L, maximum + 1L)) {
        previous <- seq_len(v)
        if (any(g$adj[v + 1L, previous] & colors[previous] == color)) next
        colors[[v + 1L]] <<- color
        if (search(v + 1L, max(maximum, color))) return(TRUE)
      }
      colors[[v + 1L]] <<- -1L
      FALSE
    }
    if (search(0L, -1L)) return(list(count = limit, colors = colors))
  }
}

schemas <- list(
  GRAPH = list(2L, Inf, c("name", "num"), "edge"), CYCLE = list(2L, 2L, c("name", "num")),
  PATH = list(2L, 2L, c("name", "num")), COMPLETE = list(2L, 2L, c("name", "num")),
  BIPARTITE = list(3L, 3L, c("name", "num", "num")), STAR = list(2L, 2L, c("name", "num")),
  WHEEL = list(2L, 2L, c("name", "num")), PETERSEN = list(1L, 1L, "name"),
  HYPERCUBE = list(2L, 2L, c("name", "num")), CIRCULANT = list(3L, Inf, c("name", "num"), "num"),
  GRID = list(3L, 3L, c("name", "num", "num")), COMPLEMENT = list(2L, 2L, c("name", "graph")),
  LINE = list(2L, 2L, c("name", "graph")), PRODUCT = list(3L, 3L, c("name", "graph", "graph")),
  UNION = list(3L, 3L, c("name", "graph", "graph")), RELABEL = list(2L, Inf, c("name", "graph"), "num"),
  INDUCED = list(3L, Inf, c("name", "graph"), "num"), CANONIZE = list(2L, 2L, c("name", "graph")),
  DELETE = list(1L, 1L, "graph"), LIST = list(0L, 0L, character()), SHOW = list(1L, 1L, "graph"),
  INVARIANTS = list(1L, 1L, "graph"), REFINE = list(1L, Inf, "graph", "num"),
  CANON = list(1L, 1L, "graph"), ISO = list(2L, 2L, c("graph", "graph")),
  AUT = list(1L, 1L, "graph"), SUBISO = list(2L, 2L, c("graph", "graph")), CLASSIFY = list(1L, 1L, "num")
)
registry <- new.env(parent = emptyenv())
class_cache <- new.env(parent = emptyenv())
get_graph <- function(name) registry[[name]]
validate <- function(command, args) {
  schema <- schemas[[command]]
  if (is.null(schema)) fail(paste("unknown command", command))
  if (length(args) < schema[[1]] || length(args) > schema[[2]]) fail("bad arguments")
  types <- schema[[3]]
  for (i in seq_along(args)) {
    type <- if (i <= length(types)) types[[i]] else schema[[4]]
    pattern <- switch(type, num = "\\A(?:0|[1-9][0-9]{0,2})\\z",
      edge = "\\A(?:0|[1-9][0-9]{0,2})-(?:0|[1-9][0-9]{0,2})\\z", "\\A[a-z][a-z0-9]{0,7}\\z")
    if (!grepl(pattern, args[[i]], perl = TRUE)) fail("bad arguments")
  }
  for (i in seq_along(types)) {
    if (types[[i]] == "graph" && is.null(get_graph(args[[i]]))) fail(paste("no graph", args[[i]]))
  }
  schema
}
size_check <- function(n, minimum = 1L, maximum = 16L) {
  if (n < minimum) fail("bad value")
  if (n > maximum) fail("too large")
}
define_graph <- function(command, args) {
  name <- args[[1]]
  number <- if (length(args) >= 2L && grepl("^[0-9]+$", args[[2]])) as.integer(args[[2]]) else 0L
  source <- if (length(args) >= 2L) get_graph(args[[2]]) else NULL
  if (command == "GRAPH") {
    size_check(number)
    g <- new_graph(number)
    for (word in args[-c(1L, 2L)]) {
      e <- as.integer(strsplit(word, "-", fixed = TRUE)[[1]])
      if (e[[1]] >= number || e[[2]] >= number || e[[1]] == e[[2]]) fail(paste("bad edge", word))
      if (g$adj[e[[1]] + 1L, e[[2]] + 1L]) fail(paste("duplicate edge", word))
      join(g, e[[1]], e[[2]])
    }
  } else if (command %in% c("PATH", "CYCLE", "COMPLETE", "STAR", "WHEEL", "CIRCULANT")) {
    minimum <- if (command %in% c("CYCLE", "WHEEL", "CIRCULANT")) 3L else 1L
    maximum <- if (command %in% c("STAR", "WHEEL")) 15L else 16L
    size_check(number, minimum, maximum)
    n <- number + as.integer(command %in% c("STAR", "WHEEL"))
    g <- new_graph(n)
    if (command %in% c("PATH", "CYCLE")) {
      if (n >= 2L) for (v in 0:(n - 2L)) join(g, v, v + 1L)
      if (command == "CYCLE") join(g, n - 1L, 0L)
    } else if (command == "COMPLETE") {
      for (e in pairs(n)) join(g, e[[1]], e[[2]])
    } else if (command %in% c("STAR", "WHEEL")) {
      for (v in seq_len(n - 1L)) join(g, 0L, v)
      if (command == "WHEEL") {
        for (v in seq_len(n - 2L)) join(g, v, v + 1L)
        join(g, n - 1L, 1L)
      }
    } else {
      jumps <- as.integer(args[-c(1L, 2L)])
      if (any(jumps == 0L | 2L * jumps > n) || any(diff(jumps) <= 0L)) fail("bad value")
      for (v in vertices(g)) for (j in jumps) join(g, v, (v + j) %% n)
    }
  } else if (command %in% c("BIPARTITE", "GRID")) {
    a <- as.integer(args[[2]])
    b <- as.integer(args[[3]])
    if (a == 0L || b == 0L) fail("bad value")
    n <- if (command == "GRID") a * b else a + b
    size_check(n)
    g <- new_graph(n)
    for (x in 0:(a - 1L)) {
      for (y in 0:(b - 1L)) {
        if (command == "BIPARTITE") {
          join(g, x, a + y)
        } else {
          if (y + 1L < b) join(g, x * b + y, x * b + y + 1L)
          if (x + 1L < a) join(g, x * b + y, (x + 1L) * b + y)
        }
      }
    }
  } else if (command == "PETERSEN") {
    g <- new_graph(10L)
    for (i in 0:4) {
      join(g, i, (i + 1L) %% 5L)
      join(g, i, i + 5L)
      join(g, i + 5L, 5L + (i + 2L) %% 5L)
    }
  } else if (command == "HYPERCUBE") {
    size_check(number, 1L, 4L)
    g <- new_graph(2^number)
    for (v in vertices(g)) for (bit in 0:(number - 1L)) join(g, v, bitwXor(v, bitwShiftL(1L, bit)))
  } else if (command == "COMPLEMENT") {
    g <- new_graph(source$n)
    for (e in pairs(source$n)) if (!source$adj[e[[1]] + 1L, e[[2]] + 1L]) join(g, e[[1]], e[[2]])
  } else if (command == "LINE") {
    edges <- edge_list(source)
    if (!length(edges)) fail("no edges")
    size_check(length(edges))
    g <- new_graph(length(edges))
    for (e in pairs(length(edges))) {
      if (length(intersect(edges[[e[[1]] + 1L]], edges[[e[[2]] + 1L]]))) join(g, e[[1]], e[[2]])
    }
  } else if (command %in% c("PRODUCT", "UNION")) {
    other <- get_graph(args[[3]])
    n <- if (command == "PRODUCT") source$n * other$n else source$n + other$n
    size_check(n)
    g <- new_graph(n)
    if (command == "PRODUCT") {
      for (x in vertices(source)) for (e in edge_list(other)) join(g, x * other$n + e[[1]], x * other$n + e[[2]])
      for (y in vertices(other)) for (e in edge_list(source)) join(g, e[[1]] * other$n + y, e[[2]] * other$n + y)
    } else {
      for (e in edge_list(source)) join(g, e[[1]], e[[2]])
      for (e in edge_list(other)) join(g, source$n + e[[1]], source$n + e[[2]])
    }
  } else if (command %in% c("RELABEL", "CANONIZE")) {
    labels <- if (command == "CANONIZE") canonical(source)$labels else as.integer(args[-c(1L, 2L)])
    if (!identical(sort(labels), vertices(source))) fail("bad permutation")
    g <- new_graph(source$n)
    for (e in edge_list(source)) join(g, labels[[e[[1]] + 1L]], labels[[e[[2]] + 1L]])
  } else if (command == "INDUCED") {
    selected <- as.integer(args[-c(1L, 2L)])
    if (any(selected >= source$n) || anyDuplicated(selected)) fail("bad vertices")
    g <- new_graph(length(selected))
    for (e in pairs(length(selected))) {
      if (source$adj[selected[[e[[1]] + 1L]] + 1L, selected[[e[[2]] + 1L]] + 1L]) join(g, e[[1]], e[[2]])
    }
  }
  verb <- if (is.null(get_graph(name))) "defined" else "redefined"
  registry[[name]] <- g
  say(verb, " ", name, " n ", g$n, " m ", length(edge_list(g)))
}
show_invariants <- function(name, g) {
  inv <- invariants(g)
  say("invariants ", name)
  say("degrees ", paste(inv$degrees, collapse = " "))
  say("edges ", length(edge_list(g)), " triangles ", inv$triangles)
  say("components ", inv$components, " sizes ", paste(inv$sizes, collapse = " "))
  say("girth ", inv$girth, " diameter ", inv$diameter, " radius ", inv$radius)
  say("bipartite ", inv$bipartite)
  if (g$n > 12L) {
    say("clique -")
    say("chromatic -")
  } else {
    cl <- clique(g)
    coloring_result <- coloring(g)
    say("clique ", length(cl), " ", paste(cl, collapse = " "))
    say("chromatic ", coloring_result$count, " ", paste(coloring_result$colors, collapse = " "))
  }
}
isomorphism <- function(a, b) {
  av <- invariants(a)
  bv <- invariants(b)
  tests <- list(list("vertices", a$n, b$n), list("edges", length(edge_list(a)), length(edge_list(b))),
    list("degrees", av$degrees, bv$degrees), list("triangles", av$triangles, bv$triangles),
    list("components", av$components, bv$components), list("girth", av$girth, bv$girth),
    list("diameter", av$diameter, bv$diameter), list("bipartite", av$bipartite, bv$bipartite))
  for (test in tests) {
    if (!identical(test[[2]], test[[3]])) {
      say("not isomorphic ", test[[1]], if (test[[1]] == "degrees") "" else paste0(" ", test[[2]], " ", test[[3]]))
      return(invisible(NULL))
    }
  }
  profile <- function(g) {
    s <- stable(g)
    list(s$rounds, tabulate(s$colors + 1L))
  }
  if (!identical(profile(a), profile(b))) {
    say("not isomorphic refinement")
  } else if (canonical(a)$string != canonical(b)$string) {
    say("not isomorphic canonical")
  } else {
    inverse <- order(canonical(b)$labels) - 1L
    say("isomorphic")
    say("mapping ", paste(inverse[canonical(a)$labels + 1L], collapse = " "))
  }
}
automorphisms <- function(name, g) {
  canon <- canonical(g)
  inverse <- order(canon$labels) - 1L
  vertex_parent <- seq_len(g$n)
  edges <- edge_list(g)
  edge_parent <- seq_along(edges)
  find <- function(parents, x) {
    while (parents[[x]] != x) x <- parents[[x]]
    x
  }
  edge_keys <- vapply(edges, function(e) paste(e, collapse = "-"), character(1))
  for (labels in canon$winners) {
    mapping <- inverse[labels + 1L]
    for (v in vertices(g)) vertex_parent[[find(vertex_parent, v + 1L)]] <- find(vertex_parent, mapping[[v + 1L]] + 1L)
    for (i in seq_along(edges)) {
      key <- paste(sort(mapping[edges[[i]] + 1L]), collapse = "-")
      edge_parent[[find(edge_parent, i)]] <- find(edge_parent, match(key, edge_keys))
    }
  }
  orbits <- function(parents) {
    result <- list()
    for (i in seq_along(parents)) {
      root <- find(parents, i)
      key <- as.character(root)
      result[[key]] <- c(result[[key]], i)
    }
    result[order(vapply(result, function(x) x[[1]], integer(1)))]
  }
  vertex_orbits <- orbits(vertex_parent)
  edge_orbits <- orbits(edge_parent)
  say("aut ", name, " order ", length(canon$winners))
  say("vertex orbits ", length(vertex_orbits))
  for (orbit in vertex_orbits) say("orbit ", paste(orbit - 1L, collapse = " "))
  say("edge orbits ", length(edge_orbits))
  for (orbit in edge_orbits) say("orbit ", paste(edge_keys[orbit], collapse = " "))
  say("transitive vertex ", if (length(vertex_orbits) == 1L) "yes" else "no",
      " edge ", if (length(edge_orbits) == 1L) "yes" else "no")
}
subiso <- function(pn, tn, pattern, target) {
  count <- 0L
  induced_count <- 0L
  examples <- list()
  search <- function(mapping, induced) {
    depth <- length(mapping)
    if (depth == pattern$n) {
      count <<- count + 1L
      if (induced) induced_count <<- induced_count + 1L
      if (length(examples) < 5L) examples[[length(examples) + 1L]] <<- list(mapping = mapping, induced = induced)
      return(invisible(NULL))
    }
    for (v in vertices(target)) {
      if (v %in% mapping) next
      previous <- seq_len(depth)
      pe <- pattern$adj[depth + 1L, previous]
      te <- target$adj[v + 1L, mapping + 1L]
      if (any(pe & !te)) next
      search(c(mapping, v), induced && all(pe == te))
    }
  }
  if (pattern$n <= target$n) search(integer(), TRUE)
  group_order <- length(canonical(pattern)$winners)
  say("subiso ", pn, " ", tn, " embeddings ", count, " induced ", induced_count)
  say("copies ", count %/% group_order, " induced ", induced_count %/% group_order)
  for (example in examples) say("embedding ", paste(example$mapping, collapse = " "), if (example$induced) " induced" else "")
}
classify <- function(n) {
  size_check(n, 1L, 5L)
  key <- as.character(n)
  levels <- class_cache[[key]]
  if (is.null(levels)) {
    edge_pairs <- pairs(n)
    levels <- list(paste(rep("0", length(edge_pairs)), collapse = ""))
    for (m in seq_along(edge_pairs)) {
      next_level <- character()
      for (string in levels[[m]]) {
        bits <- strsplit(string, "", fixed = TRUE)[[1]]
        for (extra in which(bits == "0")) {
          g <- new_graph(n)
          for (i in seq_along(edge_pairs)) {
            if (bits[[i]] == "1" || i == extra) join(g, edge_pairs[[i]][[1]], edge_pairs[[i]][[2]])
          }
          next_level <- union(next_level, canonical(g)$string)
        }
      }
      levels[[length(levels) + 1L]] <- next_level
    }
    class_cache[[key]] <- levels
  }
  say("classify ", n, " total ", sum(lengths(levels)))
  for (m in seq_along(levels)) {
    strings <- sort(levels[[m]], method = "radix")
    strings[strings == ""] <- "-"
    say("edges ", m - 1L, " count ", length(strings), " ", paste(strings, collapse = " "))
  }
}
execute <- function(line) {
  words <- strsplit(line, " ", fixed = TRUE)[[1]]
  command <- words[[1]]
  args <- words[-1]
  schema <- validate(command, args)
  if (length(schema[[3]]) && schema[[3]][[1]] == "name") {
    define_graph(command, args)
    return(invisible(NULL))
  }
  name <- if (length(args)) args[[1]] else NULL
  g <- if (!is.null(name)) get_graph(name) else NULL
  switch(command,
    DELETE = {
      rm(list = name, envir = registry)
      say("deleted ", name)
    },
    LIST = {
      names <- sort(ls(registry), method = "radix")
      say("graphs ", length(names))
      for (name in names) say(name, " n ", get_graph(name)$n, " m ", length(edge_list(get_graph(name))))
    },
    SHOW = {
      say("graph ", name, " n ", g$n, " m ", length(edge_list(g)))
      for (v in vertices(g)) {
        ns <- neighbors(g, v)
        say(v, ":", if (length(ns)) paste0(" ", paste(ns, collapse = " ")) else "")
      }
    },
    INVARIANTS = show_invariants(name, g),
    REFINE = {
      selected <- as.integer(args[-1])
      if (any(selected >= g$n)) fail("bad vertices")
      result <- stable(g)
      colors <- result$colors
      rounds <- result$rounds
      for (v in selected) {
        if (sum(colors == colors[[v + 1L]]) == 1L) fail(paste("singleton", v))
        result <- refine(g, individualize(colors, v))
        colors <- result$colors
        rounds <- rounds + result$rounds
      }
      say("refine ", name, " rounds ", rounds, " cells ", length(unique(colors)))
      for (c in 0:max(colors)) say(c, ": ", paste(which(colors == c) - 1L, collapse = " "))
    },
    CANON = {
      result <- canonical(g)
      say("canon ", name, " nodes ", result$nodes, " leaves ", result$leaves)
      say("labels ", paste(result$labels, collapse = " "))
      say("string ", if (result$string == "") "-" else result$string)
    },
    ISO = isomorphism(g, get_graph(args[[2]])),
    AUT = automorphisms(name, g),
    SUBISO = subiso(name, args[[2]], g, get_graph(args[[2]])),
    CLASSIFY = classify(as.integer(name))
  )
}

input <- file("stdin", "r")
count <- as.integer(readLines(input, n = 1L, warn = FALSE))
for (i in seq_len(count)) {
  line <- readLines(input, n = 1L, warn = FALSE)
  tryCatch(execute(line), GraphError = function(error) say("error: ", conditionMessage(error)))
}
