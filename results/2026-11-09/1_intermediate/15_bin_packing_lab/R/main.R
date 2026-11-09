options(scipen = 999)

methods <- c(
  "NEXTFIT", "FIRSTFIT", "BESTFIT", "WORSTFIT", "ALMOSTWORST",
  "HARMONIC", "KBOUNDED", "FFD", "BFD", "WFD"
)
parameterized <- c("HARMONIC", "KBOUNDED")

fail <- function(reason) {
  stop(structure(list(message = reason, call = NULL),
                 class = c("BenchmarkError", "error", "condition")))
}
conditionMessage.BenchmarkError <- function(c) c$message

ceiling <- function(a, b) floor((a + b - 1) / b)
item_text <- function(item) paste0(item[1], ":", item[2])
sizes_of <- function(items) vapply(items, function(item) item[2], numeric(1))
identifiers_of <- function(items) vapply(items, function(item) item[1], numeric(1))
descending <- function(items) {
  items[order(-sizes_of(items), identifiers_of(items))]
}
new_bin <- function(category = NULL) {
  list(items = list(), load = 0, category = category)
}
put <- function(bin, item) {
  bin$items[[length(bin$items) + 1]] <- item
  bin$load <- bin$load + item[2]
  bin
}
packing_name <- function(packing) {
  paste0(packing$method,
         if (packing$method %in% parameterized)
           paste0(" k=", packing$parameter) else "")
}
packing_header <- function(packing, capacity, total) {
  text <- paste0(packing_name(packing), " bins=", length(packing$bins),
                 " inspections=", packing$inspections,
                 " waste=", length(packing$bins) * capacity - total)
  if (packing$method == "KBOUNDED") {
    text <- paste0(text, " closes=", packing$closes)
  }
  text
}

pack <- function(items, capacity, method, parameter = 0) {
  result <- list(method = method, parameter = parameter, bins = list(),
                 steps = list(), inspections = 0, closes = 0)
  order_items <- if (method %in% c("FFD", "BFD", "WFD"))
    descending(items) else items
  active <- integer()
  current <- list()
  for (item in order_items) {
    size <- item[2]
    inspected_before <- result$inspections
    chosen <- NA_integer_
    closed <- NA_integer_
    category <- NA_integer_
    count <- length(result$bins)
    if (method == "NEXTFIT") {
      if (count != 0) {
        result$inspections <- result$inspections + 1
        if (result$bins[[count]]$load + size <= capacity) chosen <- count
      }
    } else if (method %in% c("FIRSTFIT", "FFD", "KBOUNDED")) {
      candidates <- if (method == "KBOUNDED") active else seq_len(count)
      for (index in candidates) {
        result$inspections <- result$inspections + 1
        if (result$bins[[index]]$load + size <= capacity) {
          chosen <- index
          break
        }
      }
    } else if (method == "HARMONIC") {
      category <- min(floor(capacity / size), parameter)
      old <- current[[as.character(category)]]
      if (!is.null(old)) {
        result$inspections <- result$inspections + 1
        if (result$bins[[old]]$load + size <= capacity) chosen <- old
      }
    } else {
      result$inspections <- result$inspections + count
      fitting <- which(vapply(result$bins, function(bin)
        bin$load + size <= capacity, logical(1)))
      if (length(fitting)) {
        loads <- vapply(result$bins[fitting], function(bin) bin$load, numeric(1))
        if (method %in% c("BESTFIT", "BFD")) {
          chosen <- fitting[which.max(loads)]
        } else {
          sorted <- fitting[order(loads, fitting)]
          chosen <- if (method == "ALMOSTWORST" && length(sorted) >= 2)
            sorted[2] else sorted[1]
        }
      }
    }
    opened <- is.na(chosen)
    if (opened) {
      if (method == "KBOUNDED" && length(active) == parameter) {
        loads <- vapply(result$bins[active], function(bin) bin$load, numeric(1))
        closed <- active[which.max(loads)]
        active <- active[active != closed]
        result$closes <- result$closes + 1
      }
      chosen <- length(result$bins) + 1
      result$bins[[chosen]] <- new_bin(if (!is.na(category)) category else NULL)
      if (method == "KBOUNDED") active <- c(active, chosen)
      if (method == "HARMONIC") current[[as.character(category)]] <- chosen
    }
    result$bins[[chosen]] <- put(result$bins[[chosen]], item)
    result$steps[[length(result$steps) + 1]] <- list(
      item = item, bin = chosen, inspected = result$inspections - inspected_before,
      opened = opened, closed = closed, category = category
    )
  }
  result
}

bounds <- function(items, capacity) {
  sizes <- sizes_of(items)
  thresholds <- sort(unique(c(0, sizes[2 * sizes <= capacity])))
  rows <- lapply(thresholds, function(alpha) {
    first <- sizes[sizes > capacity - alpha]
    second <- sizes[2 * sizes > capacity & sizes <= capacity - alpha]
    third <- sizes[2 * sizes <= capacity & sizes >= alpha]
    excess <- sum(third) - (length(second) * capacity - sum(second))
    bound <- length(first) + length(second) +
      if (excess > 0) ceiling(excess, capacity) else 0
    c(alpha, length(first), length(second), length(third), bound)
  })
  list(l1 = ceiling(sum(sizes), capacity),
       l2 = max(vapply(rows, function(row) row[5], numeric(1))), rows = rows)
}

exact_search <- function(items, capacity, limit, lower, incumbent, emit) {
  search <- new.env(parent = emptyenv())
  search$items <- descending(items)
  search$capacity <- capacity
  search$limit <- limit
  search$lower <- lower
  search$best <- incumbent
  search$live <- list()
  search$nodes <- 0
  search$status <- ""
  k <- length(items)
  remaining <- numeric(k + 1)
  remaining[k + 1] <- 0
  for (i in k:1) {
    remaining[i] <- remaining[i + 1] + search$items[[i]][2]
  }
  search$remaining <- remaining
  visit <- function(index) {
    if (search$nodes == search$limit) {
      search$status <- "limit"
      return(invisible(NULL))
    }
    search$nodes <- search$nodes + 1
    count <- length(search$live)
    used <- remaining[1] - remaining[index]
    free <- count * capacity - used
    excess <- remaining[index] - free
    minimum <- count + if (excess > 0) ceiling(excess, capacity) else 0
    if (minimum >= length(search$best)) return(invisible(NULL))
    if (index == k + 1) {
      search$best <- search$live
      emit(paste0("IMPROVE bins=", count, " nodes=", search$nodes))
      if (count == lower) search$status <- "bound"
      return(invisible(NULL))
    }
    item <- search$items[[index]]
    seen_loads <- numeric()
    for (i in seq_len(count)) {
      old <- search$live[[i]]
      if (old$load %in% seen_loads) next
      seen_loads <- c(seen_loads, old$load)
      if (old$load + item[2] > capacity) next
      search$live[[i]] <- put(old, item)
      visit(index + 1)
      search$live[[i]] <- old
      if (search$status != "") return(invisible(NULL))
    }
    if (count + 1 < length(search$best)) {
      search$live[[count + 1]] <- put(new_bin(), item)
      visit(index + 1)
      search$live <- search$live[seq_len(count)]
    }
    invisible(NULL)
  }
  if (length(incumbent) == lower) {
    search$status <- "bound"
  } else {
    visit(1)
  }
  search
}

new_shelf <- function(bottom, height) {
  list(bottom = bottom, height = height, used = 0, items = list())
}
new_sheet <- function(width, height) {
  list(free = list(c(0, 0, width, height)),
       placements = list(), area = 0)
}
rectangle_text <- function(number) intToUtf8(64 + number)

lab <- new.env(parent = emptyenv())
lab$items <- NULL
lab$capacity <- NULL
lab$output <- character()
emit <- function(...) {
  lab$output <- c(lab$output, paste0(..., collapse = ""))
}
total_size <- function() sum(sizes_of(lab$items))

bin_line <- function(number, bin, capacity, classes = FALSE, over = FALSE) {
  text <- paste0("BIN ", number, " load=", bin$load, "/", capacity,
                 " items=", paste(vapply(bin$items, item_text, character(1)),
                                 collapse = " "))
  if (classes) text <- paste0(text, " class=", bin$category)
  if (over) text <- paste0(text, " OVER")
  emit(text)
}
bin_lines <- function(bins, classes = FALSE) {
  for (index in seq_along(bins)) {
    bin_line(index, bins[[index]], lab$capacity, classes)
  }
}
method_result <- function(method, arguments) {
  parameter <- if (method %in% parameterized) as.numeric(arguments[1]) else 0
  if (method %in% parameterized && parameter == 0) fail("BAD PARAMETER")
  pack(lab$items, lab$capacity, method, parameter)
}
cmd_items <- function(arguments) {
  capacity <- as.numeric(arguments[1])
  if (capacity == 0) fail("BAD CAPACITY")
  sizes <- as.numeric(arguments[-1])
  for (i in seq_along(sizes)) {
    if (sizes[i] == 0 || sizes[i] > capacity) fail(paste("BAD ITEM", i))
  }
  lab$capacity <- capacity
  lab$items <- lapply(seq_along(sizes), function(i) c(i, sizes[i]))
  emit(paste0("ITEMS count=", length(sizes), " capacity=", capacity,
              " total=", total_size()))
}
cmd_random <- function(arguments) {
  count <- as.numeric(arguments[1])
  capacity <- as.numeric(arguments[2])
  seed <- as.numeric(arguments[3])
  if (count == 0 || count > 40) fail("BAD COUNT")
  if (capacity == 0) fail("BAD CAPACITY")
  if (seed == 0 || seed >= 2147483647) fail("BAD SEED")
  sizes <- numeric(count)
  value <- seed
  for (i in seq_len(count)) {
    value <- (48271 * value) %% 2147483647
    sizes[i] <- value %% capacity + 1
  }
  lab$capacity <- capacity
  lab$items <- lapply(seq_along(sizes), function(i) c(i, sizes[i]))
  emit(paste0("RANDOM count=", count, " capacity=", capacity,
              " total=", total_size()))
  emit(paste("SIZES", paste(sizes, collapse = " ")))
}
run_method <- function(method, arguments) {
  result <- method_result(method, arguments)
  emit(packing_header(result, lab$capacity, total_size()))
  bin_lines(result$bins, method == "HARMONIC")
}
cmd_trace <- function(arguments) {
  method <- arguments[1]
  result <- method_result(method, arguments[-1])
  emit(paste0("TRACE ", packing_header(result, lab$capacity, total_size())))
  for (i in seq_along(result$steps)) {
    step <- result$steps[[i]]
    text <- paste0("STEP ", i, " item=", item_text(step$item),
                   " bin=", step$bin, " inspected=", step$inspected)
    if (step$opened) text <- paste0(text, " new")
    if (!is.na(step$closed)) text <- paste0(text, " closed=", step$closed)
    if (!is.na(step$category)) text <- paste0(text, " class=", step$category)
    emit(text)
  }
}
cmd_reduce <- function(arguments) {
  method <- arguments[1]
  result <- method_result(method, arguments[-1])
  bins <- result$bins
  before <- length(bins)
  events <- character()
  repeat {
    eliminated <- FALSE
    loads <- vapply(bins, function(bin) bin$load, numeric(1))
    for (source in order(loads, seq_along(bins))) {
      virtual <- loads
      moves <- list()
      source_items <- descending(bins[[source]]$items)
      success <- TRUE
      for (item in source_items) {
        fitting <- which(seq_along(bins) != source & virtual + item[2] <= lab$capacity)
        if (!length(fitting)) {
          success <- FALSE
          break
        }
        destination <- fitting[which.max(virtual[fitting])]
        virtual[destination] <- virtual[destination] + item[2]
        moves[[length(moves) + 1]] <- list(item = item, destination = destination)
      }
      if (!success) next
      descriptions <- vapply(moves, function(move)
        paste0(item_text(move$item), "->", move$destination), character(1))
      events <- c(events, paste0("ELIMINATE bin=", source,
                                 " load=", bins[[source]]$load,
                                 " moves=", paste(descriptions, collapse = " ")))
      for (move in moves) {
        destination <- move$destination
        bins[[destination]] <- put(bins[[destination]], move$item)
      }
      bins <- bins[-source]
      eliminated <- TRUE
      break
    }
    if (!eliminated) break
  }
  emit(paste0("REDUCE ", packing_name(result), " before=", before,
              " after=", length(bins), " eliminated=", before - length(bins)))
  for (event in events) emit(event)
  bin_lines(bins, method == "HARMONIC")
}
cmd_bounds <- function() {
  result <- bounds(lab$items, lab$capacity)
  emit(paste0("BOUNDS total=", total_size(), " L1=", result$l1,
              " L2=", result$l2))
  for (row in result$rows) {
    emit(paste0("ALPHA ", row[1], " j1=", row[2], " j2=", row[3],
                " j3=", row[4], " bound=", row[5]))
  }
}
cmd_compare <- function(arguments) {
  parameter <- as.numeric(arguments[1])
  if (parameter == 0) fail("BAD PARAMETER")
  lower <- bounds(lab$items, lab$capacity)
  results <- lapply(methods, function(method)
    pack(lab$items, lab$capacity, method, parameter))
  results <- results[order(vapply(results, function(x) length(x$bins), numeric(1)),
                           vapply(results, function(x) x$method, character(1)))]
  emit(paste0("COMPARE k=", parameter, " L1=", lower$l1, " L2=", lower$l2))
  for (result in results) {
    count <- length(result$bins)
    emit(paste0(result$method, " bins=", count, " gap=", count - lower$l2,
                " waste=", count * lab$capacity - total_size(),
                " inspections=", result$inspections))
  }
}
cmd_exact <- function(arguments) {
  limit <- as.numeric(arguments[1])
  if (limit == 0) fail("BAD PARAMETER")
  if (length(lab$items) >= 21) fail("TOO MANY ITEMS")
  incumbent <- pack(lab$items, lab$capacity, "FFD")$bins
  lower <- bounds(lab$items, lab$capacity)$l2
  emit(paste0("EXACT ffd=", length(incumbent), " L2=", lower))
  search <- exact_search(lab$items, lab$capacity, limit, lower, incumbent, emit)
  status <- if (search$status == "") "complete" else search$status
  emit(paste0("RESULT bins=", length(search$best),
              " nodes=", search$nodes, " status=", status))
  bin_lines(search$best)
}
cmd_check <- function(arguments) {
  labels <- as.numeric(arguments)
  if (length(labels) != length(lab$items) || any(labels == 0)) {
    fail("BAD ASSIGNMENT")
  }
  bins <- list()
  for (i in seq_along(labels)) {
    label <- as.character(labels[i])
    if (is.null(bins[[label]])) bins[[label]] <- new_bin()
    bins[[label]] <- put(bins[[label]], lab$items[[i]])
  }
  overfull <- sum(vapply(bins, function(bin) bin$load > lab$capacity, logical(1)))
  lower <- bounds(lab$items, lab$capacity)$l2
  emit(paste0("CHECK bins=", length(bins), " over=", overfull,
              " L2=", lower, " status=", if (overfull) "invalid" else "valid"))
  for (label in sort(as.numeric(names(bins)))) {
    bin <- bins[[as.character(label)]]
    bin_line(label, bin, lab$capacity, over = bin$load > lab$capacity)
  }
}
cover_lines <- function(method, bins) {
  covered <- Filter(function(bin) bin$load >= lab$capacity, bins)
  rest <- Filter(function(bin) bin$load < lab$capacity, bins)
  emit(paste0(method, " covered=", length(covered),
              " rest=", if (length(rest)) rest[[1]]$load else 0))
  bin_lines(covered)
  if (length(rest)) {
    emit(paste0("REST items=",
                paste(vapply(rest[[1]]$items, item_text, character(1)), collapse = " ")))
  }
}
cmd_cover <- function() {
  emit(paste0("COVER total=", total_size(),
              " upper=", floor(total_size() / lab$capacity)))
  sequential <- list()
  for (item in lab$items) {
    if (!length(sequential) || sequential[[length(sequential)]]$load >= lab$capacity)
      sequential[[length(sequential) + 1]] <- new_bin()
    last <- length(sequential)
    sequential[[last]] <- put(sequential[[last]], item)
  }
  cover_lines("DNF", sequential)
  available <- descending(lab$items)
  paired <- list()
  while (length(available)) {
    bin <- put(new_bin(), available[[1]])
    available <- available[-1]
    while (bin$load < lab$capacity && length(available)) {
      bin <- put(bin, available[[length(available)]])
      available <- available[-length(available)]
    }
    paired[[length(paired) + 1]] <- bin
  }
  cover_lines("BIGSMALL", paired)
}
machine_lines <- function(machines) {
  for (i in seq_along(machines)) {
    bin <- machines[[i]]
    items <- if (length(bin$items))
      paste(vapply(bin$items, item_text, character(1)), collapse = " ") else "-"
    emit(paste0("MACHINE ", i, " load=", bin$load, " items=", items))
  }
}
cmd_multifit <- function(arguments) {
  count <- as.numeric(arguments[1])
  if (count == 0) fail("BAD PARAMETER")
  total <- total_size()
  largest <- max(sizes_of(lab$items))
  lower <- max(ceiling(total, count), largest)
  upper <- max(ceiling(2 * total, count), largest)
  emit(paste0("MULTIFIT m=", count, " lower=", lower, " upper=", upper))
  while (lower < upper) {
    middle <- floor((lower + upper) / 2)
    n <- length(pack(lab$items, middle, "FFD")$bins)
    success <- n <= count
    emit(paste0("TRY cap=", middle, " bins=", n,
                " ", if (success) "ok" else "fail"))
    if (success) upper <- middle else lower <- middle + 1
  }
  machines <- pack(lab$items, upper, "FFD")$bins
  while (length(machines) < count) machines[[length(machines) + 1]] <- new_bin()
  emit(paste0("RESULT cap=", upper, " makespan=",
              max(vapply(machines, function(bin) bin$load, numeric(1)))))
  machine_lines(machines)
  lpt <- replicate(count, new_bin(), simplify = FALSE)
  for (item in descending(lab$items)) {
    loads <- vapply(lpt, function(bin) bin$load, numeric(1))
    index <- which.min(loads)
    lpt[[index]] <- put(lpt[[index]], item)
  }
  emit(paste0("LPT makespan=",
              max(vapply(lpt, function(bin) bin$load, numeric(1)))))
  machine_lines(lpt)
}
maximal_patterns <- function(length_bar, pieces) {
  patterns <- list()
  visit <- function(index, remaining, prefix) {
    size <- pieces[[index]][1]
    maximum <- floor(remaining / size)
    if (index == length(pieces)) {
      patterns[[length(patterns) + 1]] <<-
        list(counts = c(prefix, maximum), trim = remaining - maximum * size)
      return(invisible(NULL))
    }
    for (quantity in seq.int(maximum, 0)) {
      visit(index + 1, remaining - quantity * size, c(prefix, quantity))
    }
    invisible(NULL)
  }
  visit(1, length_bar, numeric())
  patterns
}
cmd_cutstock <- function(arguments) {
  length_bar <- as.numeric(arguments[1])
  if (length_bar == 0) fail("BAD CAPACITY")
  tokens <- arguments[-1]
  pieces <- list()
  seen <- numeric()
  for (i in seq_along(tokens)) {
    pair <- as.numeric(strsplit(tokens[i], ":", fixed = TRUE)[[1]])
    size <- pair[1]
    demand <- pair[2]
    if (size == 0 || size > length_bar || demand == 0)
      fail(paste("BAD PIECE", i))
    if (size %in% seen) fail(paste("DUPLICATE PIECE", i))
    seen <- c(seen, size)
    pieces[[length(pieces) + 1]] <- pair
  }
  sizes <- vapply(pieces, function(x) x[1], numeric(1))
  pieces <- pieces[order(-sizes)]
  patterns <- maximal_patterns(length_bar, pieces)
  remaining <- vapply(pieces, function(p) p[2], numeric(1))
  uses <- numeric(length(patterns))
  while (any(remaining > 0)) {
    useful <- vapply(patterns, function(p)
      sum(pmin(p$counts, remaining)), numeric(1))
    chosen <- which.max(useful)
    uses[chosen] <- uses[chosen] + 1
    remaining <- pmax(0, remaining - patterns[[chosen]]$counts)
  }
  cut <- vapply(seq_along(pieces), function(i)
    sum(vapply(seq_along(patterns), function(j)
      uses[j] * patterns[[j]]$counts[i], numeric(1))), numeric(1))
  quantity <- sum(vapply(pieces, function(x) prod(x), numeric(1)))
  bars <- sum(uses)
  emit(paste0("CUTSTOCK L=", length_bar, " pieces=", length(pieces),
              " patterns=", length(patterns)))
  for (i in seq_along(patterns)) {
    pattern <- patterns[[i]]
    breakdown <- character()
    for (j in seq_along(pieces)) {
      count <- pattern$counts[j]
      if (count != 0)
        breakdown <- c(breakdown, paste0(count, "x", pieces[[j]][1]))
    }
    emit(paste0("PATTERN ", i, " ", paste(breakdown, collapse = "+"),
                " rest=", pattern$trim))
  }
  for (i in seq_along(uses)) {
    if (uses[i]) emit(paste0("USE ", i, " bars=", uses[i]))
  }
  for (i in seq_along(pieces)) {
    emit(paste0("PIECE ", pieces[[i]][1], " demand=", pieces[[i]][2],
                " cut=", cut[i]))
  }
  trim <- sum(vapply(seq_along(patterns), function(i)
    uses[i] * patterns[[i]]$trim, numeric(1)))
  surplus <- sum(cut) - sum(vapply(pieces, function(x) x[2], numeric(1)))
  emit(paste0("TOTAL bars=", bars, " trim=", trim, " surplus=", surplus,
              " waste=", bars * length_bar - quantity))
  all_sizes <- unlist(lapply(pieces, function(p) rep(p[1], p[2])))
  comparison <- pack(lapply(seq_along(all_sizes), function(i)
    c(i, all_sizes[i])), length_bar, "FIRSTFIT")
  n <- length(comparison$bins)
  emit(paste0("FFD bars=", n, " waste=", n * length_bar - quantity))
  emit(paste0("LOWER bars=", ceiling(quantity, length_bar)))
}
rectangles <- function(tokens) {
  lapply(seq_along(tokens), function(i) {
    dims <- as.numeric(strsplit(tokens[i], "x", fixed = TRUE)[[1]])
    c(i, dims)
  })
}
drawing <- function(width, height, placements) {
  cells <- matrix(".", nrow = height, ncol = width)
  for (p in placements) {
    letter <- rectangle_text(p[1])
    cols <- seq.int(p[2] + 1, p[2] + p[4])
    rows <- seq.int(p[3] + 1, p[3] + p[5])
    cells[rows, cols] <- letter
  }
  for (row in seq.int(height, 1)) emit(paste(cells[row, ], collapse = ""))
}
shelf_method <- function(method, width, rects, area) {
  shelves <- list()
  placements <- list()
  for (rectangle in rects) {
    number <- rectangle[1]
    w <- rectangle[2]
    h <- rectangle[3]
    chosen <- NA_integer_
    if (method == "NFDH") {
      last <- length(shelves)
      if (last && shelves[[last]]$used + w <= width) chosen <- last
    } else {
      fitting <- which(vapply(shelves, function(shelf)
        shelf$used + w <= width, logical(1)))
      if (length(fitting)) {
        chosen <- if (method == "FFDH") fitting[1] else
          fitting[which.max(vapply(shelves[fitting], function(s) s$used, numeric(1)))]
      }
    }
    if (is.na(chosen)) {
      last <- length(shelves)
      bottom <- if (last) shelves[[last]]$bottom + shelves[[last]]$height else 0
      chosen <- last + 1
      shelves[[chosen]] <- new_shelf(bottom, h)
    }
    shelf <- shelves[[chosen]]
    shelf$items[[length(shelf$items) + 1]] <- c(number, shelf$used)
    placements[[length(placements) + 1]] <-
      c(number, shelf$used, shelf$bottom, w, h, 0)
    shelf$used <- shelf$used + w
    shelves[[chosen]] <- shelf
  }
  last <- shelves[[length(shelves)]]
  height <- last$bottom + last$height
  emit(paste0(method, " height=", height, " shelves=", length(shelves),
              " util=", floor(area * 100 / (width * height))))
  for (i in seq_along(shelves)) {
    shelf <- shelves[[i]]
    words <- vapply(shelf$items, function(item)
      paste0(rectangle_text(item[1]), "@", item[2]), character(1))
    emit(paste0("LEVEL ", i, " y=", shelf$bottom, " h=", shelf$height,
                " used=", shelf$used, " items=", paste(words, collapse = " ")))
  }
  drawing(width, height, placements)
}
cmd_shelf <- function(arguments) {
  width <- as.numeric(arguments[1])
  if (width == 0) fail("BAD CAPACITY")
  rects <- rectangles(arguments[-1])
  for (rect in rects) {
    if (rect[2] == 0 || rect[3] == 0 || rect[2] > width)
      fail(paste("BAD RECT", rect[1]))
  }
  rects <- rects[order(
    -vapply(rects, function(r) r[3], numeric(1)),
    -vapply(rects, function(r) r[2], numeric(1)),
    vapply(rects, function(r) r[1], numeric(1))
  )]
  area <- sum(vapply(rects, function(r) r[2] * r[3], numeric(1)))
  emit(paste0("SHELF W=", width, " rects=", length(rects), " area=", area))
  for (method in c("NFDH", "FFDH", "BFDH"))
    shelf_method(method, width, rects, area)
  heights <- numeric(width)
  placements <- list()
  for (rect in rects) {
    number <- rect[1]; w <- rect[2]; h <- rect[3]
    x <- 0
    best <- Inf
    for (column in 0:(width - w)) {
      y <- max(heights[seq.int(column + 1, column + w)])
      if (y < best) {
        best <- y
        x <- column
      }
    }
    heights[seq.int(x + 1, x + w)] <- best + h
    placements[[length(placements) + 1]] <- c(number, x, best, w, h, 0)
  }
  height <- max(heights)
  emit(paste0("SKYLINE height=", height,
              " util=", floor(area * 100 / (width * height))))
  for (p in placements) {
    emit(paste0("PLACE ", rectangle_text(p[1]),
                " x=", p[2], " y=", p[3], " w=", p[4], " h=", p[5]))
  }
  drawing(width, height, placements)
}
free_rectangle <- function(sheets, width, height, rotate, rule) {
  chosen <- NULL
  best <- NULL
  for (sheet_number in seq_along(sheets)) {
    sheet <- sheets[[sheet_number]]
    for (i in seq_along(sheet$free)) {
      rect <- sheet$free[[i]]
      fits <- width <= rect[3] && height <= rect[4]
      fits_rotated <- rotate && height <= rect[3] && width <= rect[4]
      if (!(fits || fits_rotated)) next
      if (rule == "FIRST") return(c(sheet_number, i))
      key <- c(rect[3] * rect[4], sheet_number, i)
      if (is.null(best) ||
          any(key != best) && key[which(key != best)[1]] < best[which(key != best)[1]]) {
        best <- key
        chosen <- c(sheet_number, i)
      }
    }
  }
  chosen
}
cmd_guillotine <- function(arguments) {
  width <- as.numeric(arguments[1])
  height <- as.numeric(arguments[2])
  mode <- arguments[3]
  rule <- arguments[4]
  if (width == 0 || height == 0) fail("BAD CAPACITY")
  rects <- rectangles(arguments[-(1:4)])
  rotate <- mode == "ROTATE"
  for (rect in rects) {
    w <- rect[2]; h <- rect[3]
    fits <- w <= width && h <= height
    fits_rotated <- rotate && h <= width && w <= height
    if (w == 0 || h == 0 || !(fits || fits_rotated))
      fail(paste("BAD RECT", rect[1]))
  }
  rects <- rects[order(
    -vapply(rects, function(r) r[2] * r[3], numeric(1)),
    vapply(rects, function(r) r[1], numeric(1))
  )]
  sheets <- list()
  rotated_count <- 0
  for (rect in rects) {
    number <- rect[1]; w <- rect[2]; h <- rect[3]
    chosen <- free_rectangle(sheets, w, h, rotate, rule)
    if (is.null(chosen)) {
      sheets[[length(sheets) + 1]] <- new_sheet(width, height)
      chosen <- c(length(sheets), 1)
    }
    sheet_number <- chosen[1]
    i <- chosen[2]
    sheet <- sheets[[sheet_number]]
    region <- sheet$free[[i]]
    sheet$free <- sheet$free[-i]
    x <- region[1]; y <- region[2]
    free_width <- region[3]; free_height <- region[4]
    rotated <- !(w <= free_width && h <= free_height)
    pw <- if (rotated) h else w
    ph <- if (rotated) w else h
    rotated_count <- rotated_count + as.integer(rotated)
    sheet$placements[[length(sheet$placements) + 1]] <-
      c(number, x, y, pw, ph, as.integer(rotated))
    sheet$area <- sheet$area + w * h
    right_width <- free_width - pw
    top_height <- free_height - ph
    if (right_width <= top_height) {
      children <- list(c(x, y + ph, free_width, top_height),
                       c(x + pw, y, right_width, ph))
    } else {
      children <- list(c(x, y + ph, pw, top_height),
                       c(x + pw, y, right_width, free_height))
    }
    for (child in children) {
      if (child[3] > 0 && child[4] > 0)
        sheet$free[[length(sheet$free) + 1]] <- child
    }
    sheets[[sheet_number]] <- sheet
  }
  area <- sum(vapply(sheets, function(s) s$area, numeric(1)))
  emit(paste0("GUILLOTINE W=", width, " H=", height, " mode=", mode,
              " rule=", rule, " rects=", length(rects),
              " sheets=", length(sheets), " rotated=", rotated_count,
              " util=", floor(area * 100 / (length(sheets) * width * height))))
  for (i in seq_along(sheets)) {
    sheet <- sheets[[i]]
    emit(paste0("SHEET ", i, " placed=", length(sheet$placements),
                " area=", sheet$area))
    for (p in sheet$placements) {
      text <- paste0("PLACE ", rectangle_text(p[1]),
                     " x=", p[2], " y=", p[3], " w=", p[4], " h=", p[5])
      if (p[6]) text <- paste0(text, " rotated")
      emit(text)
    }
    free <- if (length(sheet$free)) {
      paste(vapply(sheet$free, function(r)
        paste0(r[1], ",", r[2], ",", r[3], "x", r[4]), character(1)), collapse = " ")
    } else "none"
    emit(paste("FREE", free))
    drawing(width, height, sheet$placements)
  }
}
execute <- function(line) {
  words <- strsplit(line, " ", fixed = TRUE)[[1]]
  command <- words[1]
  arguments <- words[-1]
  tryCatch({
    if (!(command %in% c("ITEMS", "RANDOM", "CUTSTOCK", "SHELF", "GUILLOTINE")) &&
        is.null(lab$items)) fail("NO ITEMS")
    if (command %in% methods) {
      run_method(command, arguments)
    } else if (command == "ITEMS") {
      cmd_items(arguments)
    } else if (command == "RANDOM") {
      cmd_random(arguments)
    } else if (command == "TRACE") {
      cmd_trace(arguments)
    } else if (command == "REDUCE") {
      cmd_reduce(arguments)
    } else if (command == "BOUNDS") {
      cmd_bounds()
    } else if (command == "COMPARE") {
      cmd_compare(arguments)
    } else if (command == "EXACT") {
      cmd_exact(arguments)
    } else if (command == "CHECK") {
      cmd_check(arguments)
    } else if (command == "COVER") {
      cmd_cover()
    } else if (command == "MULTIFIT") {
      cmd_multifit(arguments)
    } else if (command == "CUTSTOCK") {
      cmd_cutstock(arguments)
    } else if (command == "SHELF") {
      cmd_shelf(arguments)
    } else if (command == "GUILLOTINE") {
      cmd_guillotine(arguments)
    }
  }, BenchmarkError = function(error) {
    emit(paste("ERROR", conditionMessage(error)))
  })
}

input <- file("stdin", "r")
count <- as.integer(readLines(input, n = 1))
for (i in seq_len(count)) {
  execute(readLines(input, n = 1))
}
close(input)
if (length(lab$output)) cat(paste(lab$output, collapse = "\n"), "\n", sep = "")
