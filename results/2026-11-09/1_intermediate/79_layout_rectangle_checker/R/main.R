options(scipen = 999)
emit <- function(...) cat(paste0(...), "\n", sep = "")
fail <- function(message) stop(structure(list(message = message, call = NULL), class = c("layout_error", "error", "condition")))
ascii_sort <- function(values) sort(values, method = "radix")
lex_less <- function(a, b) {
    if (is.null(b)) return(TRUE)
    different <- which(a != b)
    length(different) > 0 && a[different[1]] < b[different[1]]
}
notation <- function(box) paste0("(", box[1], ",", box[2], ")-(", box[3], ",", box[4], ")")
point <- function(x, y) paste0("(", x, ",", y, ")")
width <- function(rectangle) rectangle$box[3] - rectangle$box[1]
height <- function(rectangle) rectangle$box[4] - rectangle$box[2]
percent <- function(area, denominator) {
    value <- floor(10000 * area / denominator)
    sprintf("%d.%02d", as.integer(value %/% 100), as.integer(value %% 100))
}

coverage_grid <- function(rectangles) {
    xs <- sort(unique(unlist(lapply(rectangles, function(r) r$box[c(1, 3)]))))
    ys <- sort(unique(unlist(lapply(rectangles, function(r) r$box[c(2, 4)]))))
    nx <- length(xs) - 1L
    ny <- length(ys) - 1L
    cells <- matrix(0, nrow = ny, ncol = nx)
    for (r in rectangles) {
        columns <- seq.int(match(r$box[1], xs), match(r$box[3], xs) - 1L)
        rows <- seq.int(match(r$box[2], ys), match(r$box[4], ys) - 1L)
        cells[rows, columns] <- cells[rows, columns, drop = FALSE] + 1
    }
    area <- function(k = 1, window = NULL) {
        result <- 0
        for (j in seq_len(ny)) {
            for (i in seq_len(nx)) {
                if (cells[j, i] < k) next
                dx <- if (is.null(window)) xs[i + 1L] - xs[i] else max(0, min(xs[i + 1L], window[3]) - max(xs[i], window[1]))
                dy <- if (is.null(window)) ys[j + 1L] - ys[j] else max(0, min(ys[j + 1L], window[4]) - max(ys[j], window[2]))
                result <- result + dx * dy
            }
        }
        result
    }
    perimeter <- function() {
        result <- 0
        for (j in seq_len(ny)) {
            for (i in seq_len(nx)) {
                if (cells[j, i] == 0) next
                dy <- ys[j + 1L] - ys[j]
                dx <- xs[i + 1L] - xs[i]
                if (i == 1 || cells[j, i - 1L] == 0) result <- result + dy
                if (i == nx || cells[j, i + 1L] == 0) result <- result + dy
                if (j == 1 || cells[j - 1L, i] == 0) result <- result + dx
                if (j == ny || cells[j + 1L, i] == 0) result <- result + dx
            }
        }
        result
    }
    largest_empty <- function() {
        best <- NULL
        for (left in seq_len(nx)) {
            blocked <- rep(FALSE, ny)
            for (right in seq.int(left, nx)) {
                blocked <- blocked | cells[, right] > 0
                j <- 1L
                while (j <= ny) {
                    if (blocked[j]) {
                        j <- j + 1L
                        next
                    }
                    start <- j
                    while (j <= ny && !blocked[j]) j <- j + 1L
                    width <- xs[right + 1L] - xs[left]
                    value <- width * (ys[j] - ys[start])
                    choice <- c(-value, xs[left], ys[start], width, xs[right + 1L], ys[j])
                    if (lex_less(choice, best)) best <- choice
                }
            }
        }
        if (is.null(best)) NULL else list(box = best[c(2, 3, 5, 6)], area = -best[1])
    }
    holes <- function() {
        visited <- matrix(FALSE, nrow = ny, ncol = nx)
        result <- list()
        for (j in seq_len(ny)) {
            for (i in seq_len(nx)) {
                if (cells[j, i] > 0 || visited[j, i]) next
                queue <- list(c(i, j))
                visited[j, i] <- TRUE
                head <- 1L
                area <- 0
                boundary <- FALSE
                x1 <- x2 <- xs[i]
                y1 <- y2 <- ys[j]
                anchor <- c(ys[j], xs[i])
                while (head <= length(queue)) {
                    cell <- queue[[head]]
                    x <- cell[1]
                    y <- cell[2]
                    head <- head + 1L
                    area <- area + (xs[x + 1L] - xs[x]) * (ys[y + 1L] - ys[y])
                    x1 <- min(x1, xs[x])
                    x2 <- max(x2, xs[x + 1L])
                    y1 <- min(y1, ys[y])
                    y2 <- max(y2, ys[y + 1L])
                    candidate <- c(ys[y], xs[x])
                    if (lex_less(candidate, anchor)) anchor <- candidate
                    boundary <- boundary || x == 1 || y == 1 || x == nx || y == ny
                    for (neighbor in list(c(x - 1L, y), c(x + 1L, y), c(x, y - 1L), c(x, y + 1L))) {
                        a <- neighbor[1]
                        b <- neighbor[2]
                        if (a < 1 || b < 1 || a > nx || b > ny || cells[b, a] > 0 || visited[b, a]) next
                        visited[b, a] <- TRUE
                        queue[[length(queue) + 1L]] <- neighbor
                    }
                }
                if (!boundary) result[[length(result) + 1L]] <- list(anchor = anchor, area = area, box = c(x1, y1, x2, y2))
            }
        }
        if (length(result) > 0) result <- result[order(vapply(result, function(h) h$anchor[1], numeric(1)), vapply(result, function(h) h$anchor[2], numeric(1)))]
        result
    }
    pieces <- function() {
        active <- result <- list()
        for (j in seq_len(ny)) {
            current <- list()
            i <- 1L
            while (i <= nx) {
                if (cells[j, i] == 0) {
                    i <- i + 1L
                    next
                }
                start <- i
                while (i <= nx && cells[j, i] > 0) i <- i + 1L
                left <- xs[start]
                right <- xs[i]
                key <- paste(left, right, sep = ",")
                bottom <- if (is.null(active[[key]])) ys[j] else active[[key]][2]
                current[[key]] <- c(left, bottom, right)
                active[[key]] <- NULL
            }
            for (run in active) result[[length(result) + 1L]] <- c(run, ys[j])
            active <- current
        }
        for (run in active) result[[length(result) + 1L]] <- c(run, tail(ys, 1))
        if (length(result) > 0) result <- result[order(vapply(result, function(r) r[2], numeric(1)), vapply(result, function(r) r[1], numeric(1)))]
        result
    }
    list(area = area, perimeter = perimeter, largest_empty = largest_empty, holes = holes, pieces = pieces)
}

make_workbench <- function() {
    state <- new.env(parent = emptyenv())
    state$rectangles <- list()
    state$rules <- list()
    state$history <- list()
    sorted <- function() state$rectangles[ascii_sort(names(state$rectangles))]
    on_layer <- function(layer) Filter(function(r) r$layer == layer, sorted())
    require_layer <- function(layer) {
        rectangles <- on_layer(layer)
        if (length(rectangles) == 0) fail(paste0("no rectangles on ", layer))
        rectangles
    }
    rectangle <- function(name) {
        r <- state$rectangles[[name]]
        if (is.null(r)) fail(paste0("unknown rectangle ", name))
        r
    }
    bounds <- function(box) if (any(abs(box) > 10000)) fail("out of bounds")
    remember <- function(line) state$history[[length(state$history) + 1L]] <- list(rectangles = state$rectangles, line = line)
    relation <- function(a, b) {
        box <- c(max(a$box[1], b$box[1]), max(a$box[2], b$box[2]), min(a$box[3], b$box[3]), min(a$box[4], b$box[4]))
        ox <- box[3] - box[1]
        oy <- box[4] - box[2]
        kind <- if (ox < 0 || oy < 0) "separated" else if (ox == 0 && oy == 0) "corner" else if (ox == 0 || oy == 0) "edge" else "overlap"
        direction <- if (ox < 0 && oy < 0) "diagonal" else if (ox < 0) "x" else "y"
        list(kind = kind, box = box, ox = ox, oy = oy, gap = max(0, -ox, -oy), direction = direction)
    }
    contains <- function(a, b) all(c(a$box[1:2] <= b$box[1:2], a$box[3:4] >= b$box[3:4]))
    connected <- function(a, b) relation(a, b)$kind %in% c("overlap", "edge")
    nets <- function(rectangles) {
        remaining <- rectangles
        result <- list()
        while (length(remaining) > 0) {
            group <- remaining[1]
            remaining <- remaining[-1]
            i <- 1L
            while (i <= length(group)) {
                selected <- vapply(remaining, function(r) connected(group[[i]], r), logical(1))
                group <- c(group, remaining[selected])
                remaining <- remaining[!selected]
                i <- i + 1L
            }
            names <- vapply(group, function(r) r$name, character(1))
            result[[length(result) + 1L]] <- group[order(names, method = "radix")]
        }
        result
    }
    spacing <- function(rectangles, minimum) {
        result <- list()
        n <- length(rectangles)
        if (n >= 2) {
            for (i in seq_len(n - 1L)) {
                for (j in seq.int(i + 1L, n)) {
                    a <- rectangles[[i]]
                    b <- rectangles[[j]]
                    rel <- relation(a, b)
                    if (rel$kind == "corner" || (rel$kind == "separated" && rel$gap < minimum)) {
                        result[[length(result) + 1L]] <- list(gap = rel$gap, a = a$name, b = b$name, direction = if (rel$kind == "corner") "corner" else rel$direction)
                    }
                }
            }
        }
        if (length(result) > 0) {
            result <- result[order(vapply(result, function(v) v$gap, numeric(1)), vapply(result, function(v) v$a, character(1)), vapply(result, function(v) v$b, character(1)), method = "radix")]
        }
        result
    }
    spacing_lines <- function(violations) for (v in violations) emit(v$a, " ", v$b, " gap ", v$gap, " ", v$direction)
    bounding <- function(rectangles) c(min(vapply(rectangles, function(r) r$box[1], numeric(1))), min(vapply(rectangles, function(r) r$box[2], numeric(1))), max(vapply(rectangles, function(r) r$box[3], numeric(1))), max(vapply(rectangles, function(r) r$box[4], numeric(1))))
    names_text <- function(rectangles) {
        if (length(rectangles) == 0) "none" else paste(vapply(rectangles, function(r) r$name, character(1)), collapse = " ")
    }
    execute <- function(line) {
        words <- strsplit(line, " ", fixed = TRUE)[[1]]
        command <- words[1]
        args <- words[-1]
        if (command == "ADD") {
            name <- args[1]
            layer <- args[2]
            if (!is.null(state$rectangles[[name]])) fail(paste0("duplicate rectangle ", name))
            box <- as.numeric(args[3:6])
            if (box[1] >= box[3] || box[2] >= box[4]) fail("invalid rectangle")
            bounds(box)
            remember(line)
            state$rectangles[[name]] <- list(name = name, layer = layer, box = box)
            emit("added ", name, " ", layer, " ", notation(box))
        } else if (command %in% c("COPY", "MOVE", "RESIZE", "SPLIT", "LAYER", "DELETE")) {
            name <- args[1]
            original <- rectangle(name)
            changed <- original
            if (command %in% c("COPY", "MOVE")) {
                new_name <- if (command == "COPY") args[2] else name
                if (command == "COPY" && !is.null(state$rectangles[[new_name]])) fail(paste0("duplicate rectangle ", new_name))
                offset <- as.numeric(if (command == "COPY") args[3:4] else args[2:3])
                changed$name <- new_name
                changed$box <- changed$box + rep(offset, 2)
                bounds(changed$box)
                message <- if (command == "COPY") paste0("copied ", name, " to ", new_name, " ", notation(changed$box)) else paste0("moved ", name, " to ", notation(changed$box))
            } else if (command == "RESIZE") {
                size <- as.numeric(args[2:3])
                if (any(size <= 0)) fail("invalid size")
                changed$box[3:4] <- changed$box[1:2] + size
                bounds(changed$box)
                message <- paste0("resized ", name, " to ", notation(changed$box))
            } else if (command == "SPLIT") {
                axis <- args[2]
                position <- as.numeric(args[3])
                new_name <- args[4]
                if (!is.null(state$rectangles[[new_name]])) fail(paste0("duplicate rectangle ", new_name))
                index <- if (axis == "x") 1L else 2L
                if (!(original$box[index] < position && position < original$box[index + 2L])) fail(paste0("cut outside ", name))
                added <- original
                added$name <- new_name
                changed$box[index + 2L] <- position
                added$box[index] <- position
                message <- paste0("split ", name, " at ", axis, "=", position, ": ", name, " ", notation(changed$box), ", ", new_name, " ", notation(added$box))
            } else if (command == "LAYER") {
                if (original$layer == args[2]) fail(paste0("already on ", args[2]))
                changed$layer <- args[2]
                message <- paste0("layer ", name, " ", original$layer, " -> ", changed$layer)
            } else {
                message <- paste0("deleted ", name)
            }
            remember(line)
            if (command == "DELETE") {
                state$rectangles[[name]] <- NULL
            } else {
                state$rectangles[[changed$name]] <- changed
                if (command == "SPLIT") state$rectangles[[added$name]] <- added
            }
            emit(message)
        } else if (command == "UNDO") {
            if (length(state$history) == 0) fail("nothing to undo")
            previous <- tail(state$history, 1)[[1]]
            state$history <- head(state$history, -1L)
            state$rectangles <- previous$rectangles
            emit("undo: ", previous$line)
        } else if (command == "LIST") {
            emit("rectangles: ", length(state$rectangles))
            for (r in sorted()) emit(r$name, " ", r$layer, " ", notation(r$box), " ", width(r), "x", height(r))
        } else if (command == "INFO") {
            a <- rectangle(args[1])
            emit(a$name, " ", a$layer, " ", notation(a$box), " ", width(a), "x", height(a), " area ", width(a) * height(a))
            others <- Filter(function(r) r$name != a$name, sorted())
            labels <- c("overlaps", "touches", "corners", "encloses", "enclosed by")
            for (i in seq_along(labels)) {
                matches <- Filter(function(b) {
                    if (i <= 3) b$layer == a$layer && relation(a, b)$kind == c("overlap", "edge", "corner")[i] else if (i == 4) contains(a, b) else contains(b, a)
                }, others)
                emit(labels[i], ": ", names_text(matches))
            }
        } else if (command == "LAYERS") {
            layers <- ascii_sort(unique(vapply(sorted(), function(r) r$layer, character(1))))
            emit("layers: ", length(layers))
            for (layer in layers) {
                rectangles <- on_layer(layer)
                emit(layer, ": ", length(rectangles), " rectangles, area ", coverage_grid(rectangles)$area(), ", nets ", length(nets(rectangles)))
            }
        } else if (command == "OVERLAPS") {
            rectangles <- if (length(args) == 0) sorted() else require_layer(args[1])
            pairs <- list()
            n <- length(rectangles)
            if (n >= 2) {
                for (i in seq_len(n - 1L)) {
                    for (j in seq.int(i + 1L, n)) {
                        a <- rectangles[[i]]
                        b <- rectangles[[j]]
                        rel <- relation(a, b)
                        if (a$layer == b$layer && rel$kind == "overlap") pairs[[length(pairs) + 1L]] <- list(layer = a$layer, a = a$name, b = b$name, box = rel$box, area = rel$ox * rel$oy)
                    }
                }
            }
            if (length(pairs) > 0) pairs <- pairs[order(vapply(pairs, function(p) p$layer, character(1)), vapply(pairs, function(p) p$a, character(1)), vapply(pairs, function(p) p$b, character(1)), method = "radix")]
            emit("overlaps ", if (length(args) == 0) "all layers" else args[1], ": ", length(pairs))
            for (p in pairs) emit(if (length(args) == 0) paste0(p$layer, " ") else "", p$a, " ", p$b, " ", notation(p$box), " area ", p$area)
        } else if (command %in% c("AREA", "COVER", "PERIMETER", "BBOX", "DENSITY", "RENDER", "EMPTY", "HOLES", "MERGE", "NETS", "DRC")) {
            layer <- if (command == "COVER") args[2] else args[1]
            rectangles <- require_layer(layer)
            grid <- coverage_grid(rectangles)
            box <- bounding(rectangles)
            if (command == "AREA") {
                emit("area ", layer, ": ", grid$area())
            } else if (command == "COVER") {
                emit("cover ", layer, " >= ", args[1], ": ", grid$area(as.numeric(args[1])))
            } else if (command == "PERIMETER") {
                emit("perimeter ", layer, ": ", grid$perimeter())
            } else if (command == "BBOX") {
                w <- box[3] - box[1]
                h <- box[4] - box[2]
                emit("bbox ", layer, ": ", notation(box), " ", w, "x", h, ", ", length(rectangles), " rectangles, density ", percent(grid$area(), w * h), "%")
            } else if (command == "DENSITY") {
                w <- as.numeric(args[2])
                columns <- ceiling((box[3] - box[1]) / w)
                rows <- ceiling((box[4] - box[2]) / w)
                if (columns > 20 || rows > 20) fail("too many windows")
                values <- matrix(0, nrow = rows, ncol = columns)
                for (j in seq_len(rows)) {
                    for (i in seq_len(columns)) values[j, i] <- grid$area(1, c(box[1] + (i - 1) * w, box[2] + (j - 1) * w, box[1] + i * w, box[2] + j * w))
                }
                emit("density ", layer, " window ", w, ": ", columns, "x", rows)
                for (j in rev(seq_len(rows))) emit(paste(floor(100 * values[j, ] / (w * w)), collapse = " "))
                flat <- as.vector(t(values))
                for (label in c("min", "max")) {
                    value <- if (label == "min") min(flat) else max(flat)
                    index <- match(value, flat) - 1L
                    emit(label, " ", percent(value, w * w), "% at ", point(box[1] + index %% columns * w, box[2] + index %/% columns * w))
                }
            } else if (command == "RENDER") {
                window <- as.numeric(args[2:5])
                if (window[1] >= window[3] || window[2] >= window[4]) fail("invalid window")
                if (window[3] - window[1] > 60 || window[4] - window[2] > 40) fail("window too large")
                emit("render ", layer, " ", notation(window))
                for (y in seq.int(window[4] - 1, window[2])) {
                    row <- vapply(seq.int(window[1], window[3] - 1), function(x) {
                        count <- sum(vapply(rectangles, function(r) r$box[1] <= x && x < r$box[3] && r$box[2] <= y && y < r$box[4], logical(1)))
                        if (count == 0) "." else if (count >= 10) "*" else as.character(count)
                    }, character(1))
                    emit(paste(row, collapse = ""))
                }
            } else if (command == "EMPTY") {
                empty <- grid$largest_empty()
                emit("empty ", layer, ": ", if (is.null(empty)) "none" else paste0(notation(empty$box), " area ", empty$area))
            } else if (command == "HOLES") {
                holes <- grid$holes()
                emit("holes ", layer, ": ", length(holes))
                for (i in seq_along(holes)) emit("hole ", i, ": area ", holes[[i]]$area, ", bbox ", notation(holes[[i]]$box))
            } else if (command == "MERGE") {
                pieces <- grid$pieces()
                emit("merge ", layer, ": ", length(pieces), " pieces")
                for (piece in pieces) emit(notation(piece))
            } else if (command == "NETS") {
                groups <- nets(rectangles)
                emit("nets ", layer, ": ", length(groups))
                for (i in seq_along(groups)) emit("net ", i, ": ", names_text(groups[[i]]), " area ", coverage_grid(groups[[i]])$area())
            } else {
                violations <- spacing(rectangles, as.numeric(args[2]))
                emit("drc ", layer, " spacing ", args[2], ": ", length(violations), " violations")
                spacing_lines(violations)
            }
        } else if (command %in% c("INTERSECT", "ADJACENT", "ENCLOSE", "PATH")) {
            a <- rectangle(args[1])
            b <- rectangle(args[2])
            if (a$name == b$name) fail(paste0("same rectangle ", a$name))
            rel <- relation(a, b)
            prefix <- paste0(tolower(command), " ", a$name, " ", b$name, ": ")
            if (command == "ENCLOSE") {
                margins <- c(b$box[1:2] - a$box[1:2], a$box[3:4] - b$box[3:4])
                emit(prefix, if (min(margins) >= 0) "yes, " else "no, ", "margins left ", margins[1], " bottom ", margins[2], " right ", margins[3], " top ", margins[4], if (min(margins) >= 0) paste0(", min ", min(margins)) else "")
            } else if (command == "PATH") {
                if (a$layer != b$layer) fail("different layers")
                queue <- list(a$name)
                seen <- a$name
                head <- 1L
                path <- NULL
                while (head <= length(queue)) {
                    route <- queue[[head]]
                    head <- head + 1L
                    last <- tail(route, 1)
                    if (last == b$name) {
                        path <- route
                        break
                    }
                    for (r in on_layer(a$layer)) {
                        if (!(r$name %in% seen) && connected(state$rectangles[[last]], r)) {
                            seen <- c(seen, r$name)
                            queue[[length(queue) + 1L]] <- c(route, r$name)
                        }
                    }
                }
                emit(prefix, if (is.null(path)) "none" else paste0(paste(path, collapse = " -> "), " (", length(path) - 1L, " steps)"))
            } else if (command == "INTERSECT") {
                result <- if (rel$kind == "overlap") paste0(notation(rel$box), " area ", rel$ox * rel$oy) else if (rel$kind == "edge") paste0("segment ", notation(rel$box), " length ", rel$ox + rel$oy) else if (rel$kind == "corner") paste0("point ", point(rel$box[1], rel$box[2])) else paste0("none, gap ", rel$gap)
                emit(prefix, result)
            } else {
                if (rel$kind == "edge") {
                    direction <- if (rel$ox == 0) {
                        if (a$box[3] == rel$box[1]) "west" else "east"
                    } else if (a$box[4] == rel$box[2]) "south" else "north"
                    result <- paste0(a$name, " is ", direction, " of ", b$name, ", edge ", notation(rel$box), ", length ", rel$ox + rel$oy)
                } else {
                    result <- if (rel$kind == "overlap") "overlapping" else if (rel$kind == "corner") paste0("corner only at ", point(rel$box[1], rel$box[2])) else "not adjacent"
                }
                emit(prefix, result)
            }
        } else if (command == "AT") {
            x <- as.numeric(args[1])
            y <- as.numeric(args[2])
            found <- character()
            for (r in sorted()) {
                if (r$box[1] <= x && x <= r$box[3] && r$box[2] <= y && y <= r$box[4]) {
                    horizontal <- x %in% r$box[c(1, 3)]
                    vertical <- y %in% r$box[c(2, 4)]
                    found <- c(found, paste(r$name, r$layer, if (horizontal && vertical) "corner" else if (horizontal || vertical) "edge" else "inside"))
                }
            }
            emit("at ", point(x, y), ": ", if (length(found) == 0) "none" else paste(found, collapse = ", "))
        } else if (command == "NEAREST") {
            a <- rectangle(args[1])
            nearest <- NULL
            gap <- NULL
            for (r in on_layer(a$layer)) {
                if (r$name == a$name) next
                value <- relation(a, r)$gap
                if (is.null(gap) || value < gap) {
                    gap <- value
                    nearest <- r$name
                }
            }
            emit("nearest ", a$name, ": ", if (is.null(nearest)) "none" else paste0(nearest, " gap ", gap))
        } else if (command == "RULE") {
            kind <- tolower(args[1])
            if (kind == "enclose" && args[2] == args[3]) fail(paste0("same layer ", args[2]))
            key <- paste(c(kind, if (kind == "enclose") args[2:3] else args[2]), collapse = " ")
            state$rules[[key]] <- list(kind = kind, layer = args[2], outer = if (kind == "enclose") args[3] else NULL, value = as.numeric(args[if (kind == "enclose") 4 else 3]))
            emit("rule ", kind, " ", paste(args[-1], collapse = " "))
        } else if (command == "CHECK") {
            if (length(state$rules) == 0) fail("no rules")
            total <- 0
            for (key in ascii_sort(names(state$rules))) {
                rule <- state$rules[[key]]
                rectangles <- on_layer(rule$layer)
                if (rule$kind == "spacing") {
                    violations <- spacing(rectangles, rule$value)
                    emit("spacing ", rule$layer, " ", rule$value, ": ", length(violations), " violations")
                    spacing_lines(violations)
                } else if (rule$kind == "width") {
                    violations <- Filter(function(r) min(width(r), height(r)) < rule$value, rectangles)
                    emit("width ", rule$layer, " ", rule$value, ": ", length(violations), " violations")
                    for (r in violations) emit(r$name, " width ", min(width(r), height(r)))
                } else {
                    enclosures <- on_layer(rule$outer)
                    violations <- list()
                    for (r in rectangles) {
                        best <- if (length(enclosures) == 0) NULL else max(vapply(enclosures, function(u) min(c(r$box[1:2] - u$box[1:2], u$box[3:4] - r$box[3:4])), numeric(1)))
                        if (is.null(best) || best < rule$value) violations[[length(violations) + 1L]] <- list(name = r$name, margin = best)
                    }
                    emit("enclose ", rule$layer, " ", rule$outer, " ", rule$value, ": ", length(violations), " violations")
                    for (v in violations) emit(v$name, " best margin ", if (is.null(v$margin)) "none" else v$margin)
                }
                total <- total + length(violations)
            }
            emit("check: ", total, " violations in ", length(state$rules), " rules")
        }
        invisible(NULL)
    }
    function(line) tryCatch(execute(line), layout_error = function(error) emit("error: ", conditionMessage(error)))
}

input <- readLines(file("stdin"), warn = FALSE)
workbench <- make_workbench()
for (i in seq_len(as.integer(input[1]))) workbench(input[i + 1L])
