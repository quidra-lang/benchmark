options(scipen = 999)
emit <- function(...) cat(paste0(...), "\n", sep = "")
sides <- c("top", "right", "bottom", "left")
defaults <- list(
    display = "block", position = "static", "box-sizing" = "content-box",
    width = "auto", height = "auto", "min-width" = "0", "min-height" = "0",
    "max-width" = "none", "max-height" = "none", top = "auto", right = "auto",
    bottom = "auto", left = "auto", "flex-direction" = "row", "flex-wrap" = "nowrap",
    "justify-content" = "start", "align-items" = "stretch", "align-self" = "auto",
    "row-gap" = "0", "column-gap" = "0", order = "0", "flex-grow" = "0",
    "flex-shrink" = "1", "flex-basis" = "auto", "grid-template-columns" = "none",
    "grid-template-rows" = "none", "grid-column" = "auto", "grid-row" = "auto"
)
for (prefix in c("margin", "padding", "border")) {
    for (side in sides) defaults[[paste0(prefix, "-", side)]] <- "0"
}
choices <- list(
    display = c("block", "flex", "grid", "none"), position = c("static", "relative", "absolute"),
    "box-sizing" = c("content-box", "border-box"), "flex-direction" = c("row", "row-reverse", "column", "column-reverse"),
    "flex-wrap" = c("nowrap", "wrap"), "justify-content" = c("start", "end", "center", "space-between", "space-around", "space-evenly"),
    "align-items" = c("stretch", "start", "end", "center"), "align-self" = c("auto", "stretch", "start", "end", "center")
)
integer_token <- function(text) grepl("\\A[0-9]{1,3}\\z", text, perl = TRUE)
positive <- function(text) integer_token(text) && as.numeric(text) > 0
signed <- function(text) integer_token(text) || (startsWith(text, "-") && integer_token(substring(text, 2)))
percentage <- function(text) endsWith(text, "%") && integer_token(substr(text, 1, nchar(text) - 1L))
fraction <- function(text) endsWith(text, "fr") && positive(substr(text, 1, nchar(text) - 2L))
known <- function(property) property %in% c(names(defaults), "margin", "padding", "border", "gap")
declaration <- function(property, value) {
    if (!known(property)) return(NULL)
    tokens <- strsplit(value, " ", fixed = TRUE)[[1]]
    count <- length(tokens)
    if (property %in% c("margin", "padding", "border")) {
        valid_tokens <- if (property == "border") tokens %in% c("0", "1") else vapply(tokens, integer_token, logical(1))
        if (count < 1 || count > 4 || !all(valid_tokens)) return(NULL)
        expanded <- c(tokens[1], if (count >= 2) tokens[2] else tokens[1], if (count >= 3) tokens[3] else tokens[1], if (count == 4) tokens[4] else if (count >= 2) tokens[2] else tokens[1])
        return(Map(function(side, v) c(paste0(property, "-", side), v), sides, expanded))
    }
    if (property == "gap") {
        if (count < 1 || count > 2 || !all(vapply(tokens, integer_token, logical(1)))) return(NULL)
        return(list(c("row-gap", tokens[1]), c("column-gap", tail(tokens, 1))))
    }
    valid <- FALSE
    if (property %in% c("grid-template-columns", "grid-template-rows")) {
        valid <- value == "none" || all(vapply(tokens, function(t) t == "auto" || integer_token(t) || fraction(t), logical(1)))
    } else if (property %in% c("grid-column", "grid-row")) {
        valid <- value == "auto" || (count == 1 && positive(tokens[1])) ||
            (count == 2 && tokens[1] == "span" && positive(tokens[2])) ||
            (count == 3 && positive(tokens[1]) && tokens[2] == "/" && positive(tokens[3]) && as.numeric(tokens[1]) < as.numeric(tokens[3])) ||
            (count == 4 && positive(tokens[1]) && tokens[2] == "/" && tokens[3] == "span" && positive(tokens[4]))
    } else if (count == 1) {
        if (property %in% names(choices)) {
            valid <- value %in% choices[[property]]
        } else if (property %in% c("width", "height", "flex-basis")) {
            valid <- value == "auto" || integer_token(value) || percentage(value)
        } else if (property %in% c("min-width", "min-height")) {
            valid <- integer_token(value) || percentage(value)
        } else if (property %in% c("max-width", "max-height")) {
            valid <- value == "none" || integer_token(value) || percentage(value)
        } else if (property %in% c("top", "right", "bottom", "left")) {
            valid <- value == "auto" || signed(value)
        } else if (property == "order") {
            valid <- signed(value)
        } else if (startsWith(property, "border-")) {
            valid <- value %in% c("0", "1")
        } else {
            valid <- integer_token(value)
        }
    }
    if (valid) list(c(property, value)) else NULL
}
new_element <- function(type, id, classes, text, parent, depth, index) {
    element <- new.env(parent = emptyenv())
    element$type <- type
    element$id <- id
    element$classes <- classes
    element$text <- text
    element$parent <- parent
    element$depth <- depth
    element$index <- index
    element$children <- list()
    element$overrides <- list()
    element
}
frame <- function(element, horizontal) {
    indices <- if (horizontal) c(2, 4) else c(1, 3)
    sum(element$padding[indices]) + sum(element$border[indices])
}
margins <- function(element, horizontal) sum(element$margin[if (horizontal) c(2, 4) else c(1, 3)])
border_width <- function(element) element$cw + frame(element, TRUE)
border_height <- function(element) element$ch + frame(element, FALSE)

make_layout <- function(width, height, rules, elements) {
    state <- new.env(parent = emptyenv())
    state$width <- width
    state$height <- height
    ids <- setNames(elements, vapply(elements, function(e) e$id, character(1)))
    children <- function(element, ordered = FALSE) {
        result <- Filter(function(e) e$displayed && e$style$position != "absolute", element$children)
        if (ordered && length(result) > 0) {
            result <- result[order(vapply(result, function(e) as.numeric(e$style$order), numeric(1)), vapply(result, function(e) e$index, numeric(1)))]
        }
        result
    }
    align <- function(parent, child) if (child$style[["align-self"]] == "auto") parent$style[["align-items"]] else child$style[["align-self"]]
    resolve <- function(element, property, reference, horizontal) {
        value <- element$style[[property]]
        if (value %in% c("auto", "none") || (endsWith(value, "%") && is.null(reference))) return(NULL)
        result <- if (endsWith(value, "%")) floor(reference * as.numeric(substr(value, 1, nchar(value) - 1L)) / 100) else as.numeric(value)
        if (element$style[["box-sizing"]] == "border-box") max(0, result - frame(element, horizontal)) else result
    }
    clamp <- function(element, value, reference, horizontal) {
        axis <- if (horizontal) "width" else "height"
        lower <- resolve(element, paste0("min-", axis), reference, horizontal)
        upper <- resolve(element, paste0("max-", axis), reference, horizontal)
        if (is.null(lower)) lower <- 0
        if (!is.null(upper)) value <- min(value, upper)
        max(value, lower)
    }
    distribute <- function(total, weights) {
        sum_weights <- sum(weights)
        if (sum_weights == 0) return(rep(0, length(weights)))
        result <- floor(total * weights / sum_weights)
        remainder <- total - sum(result)
        for (i in seq_along(weights)) {
            if (remainder == 0) break
            if (weights[i] > 0) {
                result[i] <- result[i] + 1
                remainder <- remainder - 1
            }
        }
        result
    }
    grid_position <- function(value) {
        tokens <- strsplit(value, " ", fixed = TRUE)[[1]]
        if (value == "auto") return(c(0, 1))
        if (tokens[1] == "span") return(c(0, as.numeric(tokens[2])))
        start <- as.numeric(tokens[1])
        span <- if (length(tokens) == 1) 1 else if (tokens[3] == "span") as.numeric(tokens[4]) else as.numeric(tokens[3]) - start
        c(start, span)
    }
    placement <- function(element) {
        columns <- if (element$style[["grid-template-columns"]] == "none") "auto" else strsplit(element$style[["grid-template-columns"]], " ", fixed = TRUE)[[1]]
        rows <- if (element$style[["grid-template-rows"]] == "none") character() else strsplit(element$style[["grid-template-rows"]], " ", fixed = TRUE)[[1]]
        nc <- length(columns)
        items <- lapply(children(element, TRUE), function(child) {
            column <- grid_position(child$style[["grid-column"]])
            row <- grid_position(child$style[["grid-row"]])
            item <- new.env(parent = emptyenv())
            item$element <- child
            item$column <- column[1]
            item$cs <- column[2]
            item$row <- row[1]
            item$rs <- row[2]
            item
        })
        for (item in items) nc <- max(nc, if (item$column == 0) item$cs else item$column + item$cs - 1)
        occupied <- new.env(hash = TRUE, parent = emptyenv())
        overlaps <- function(item, row, column) {
            for (r in seq.int(row, row + item$rs - 1)) {
                for (c in seq.int(column, column + item$cs - 1)) {
                    if (exists(paste(r, c, sep = ","), envir = occupied, inherits = FALSE)) return(TRUE)
                }
            }
            FALSE
        }
        occupy <- function(item) {
            for (r in seq.int(item$row, item$row + item$rs - 1)) {
                for (c in seq.int(item$column, item$column + item$cs - 1)) assign(paste(r, c, sep = ","), TRUE, envir = occupied)
            }
        }
        for (item in items) if (item$row > 0 && item$column > 0) occupy(item)
        cr <- cc <- 1
        for (item in items) {
            if (item$row > 0 && item$column > 0) next
            if (item$row > 0) {
                column <- 1
                while (column + item$cs - 1 <= nc && overlaps(item, item$row, column)) column <- column + 1
                item$column <- if (column + item$cs - 1 <= nc) column else 1
            } else if (item$column > 0) {
                if (item$column < cc) cr <- cr + 1
                row <- cr
                while (overlaps(item, row, item$column)) row <- row + 1
                item$row <- cr <- row
                cc <- item$column + item$cs
            } else {
                row <- cr
                column <- cc
                repeat {
                    if (column + item$cs - 1 > nc) {
                        row <- row + 1
                        column <- 1
                    } else if (overlaps(item, row, column)) {
                        column <- column + 1
                    } else {
                        break
                    }
                }
                item$row <- cr <- row
                item$column <- column
                cc <- column + item$cs
            }
            occupy(item)
        }
        nr <- length(rows)
        for (item in items) nr <- max(nr, item$row + item$rs - 1)
        list(items = items, columns = c(columns, rep("auto", nc - length(columns))), rows = c(rows, rep("auto", nr - length(rows))))
    }
    track_sizes <- function(grid, horizontal, available, gap, contributions) {
        specifications <- if (horizontal) grid$columns else grid$rows
        fractional <- any(vapply(specifications, fraction, logical(1)))
        sizes <- weights <- rep(0, length(specifications))
        for (i in seq_along(specifications)) {
            specification <- specifications[i]
            weights[i] <- if (fractional) {
                if (fraction(specification)) as.numeric(substr(specification, 1, nchar(specification) - 2L)) else 0
            } else if (specification == "auto") 1 else 0
            if (integer_token(specification)) {
                sizes[i] <- as.numeric(specification)
            } else if (specification == "auto" || is.null(available)) {
                for (j in seq_along(grid$items)) {
                    item <- grid$items[[j]]
                    start <- if (horizontal) item$column else item$row
                    span <- if (horizontal) item$cs else item$rs
                    if (start == i && span == 1) sizes[i] <- max(sizes[i], contributions[j])
                }
            }
        }
        if (!is.null(available)) {
            leftover <- available - sum(sizes) - gap * (length(sizes) - 1)
            sizes <- sizes + distribute(max(leftover, 0), weights)
        }
        sizes
    }
    max_content <- function(element) {
        if (!is.null(element$maximum)) return(element$maximum)
        items <- children(element)
        if (!is.null(element$text)) {
            value <- nchar(element$text, type = "bytes")
        } else if (element$style$display == "flex" && startsWith(element$style[["flex-direction"]], "row")) {
            value <- sum(vapply(items, contribution, numeric(1))) + as.numeric(element$style[["column-gap"]]) * max(0, length(items) - 1)
        } else if (element$style$display == "grid") {
            grid <- placement(element)
            values <- vapply(grid$items, function(item) contribution(item$element), numeric(1))
            value <- sum(track_sizes(grid, TRUE, NULL, as.numeric(element$style[["column-gap"]]), values)) + as.numeric(element$style[["column-gap"]]) * (length(grid$columns) - 1)
        } else {
            value <- if (length(items) == 0) 0 else max(vapply(items, contribution, numeric(1)))
        }
        element$maximum <- value
        value
    }
    contribution <- function(element) {
        if (!is.null(element$contribution)) return(element$contribution)
        value <- resolve(element, "width", NULL, TRUE)
        if (is.null(value)) value <- max_content(element)
        element$contribution <- clamp(element, value, NULL, TRUE) + frame(element, TRUE) + margins(element, TRUE)
        element$contribution
    }
    position_child <- function(parent, child, x, y) {
        child$rx <- parent$border[4] + parent$padding[4] + x
        child$ry <- parent$border[1] + parent$padding[1] + y
    }
    layout <- function(element, cw_reference, ch_reference, fw = NULL, fh = NULL) {
        if (is.null(fw)) {
            value <- resolve(element, "width", cw_reference, TRUE)
            if (is.null(value)) value <- max(0, cw_reference - frame(element, TRUE) - margins(element, TRUE))
            fw <- clamp(element, value, cw_reference, TRUE)
        }
        element$cw <- fw
        if (is.null(fh)) {
            value <- resolve(element, "height", ch_reference, FALSE)
            if (!is.null(value)) fh <- clamp(element, value, ch_reference, FALSE)
        }
        if (!is.null(element$text)) {
            lines <- character()
            for (word in strsplit(element$text, " ", fixed = TRUE)[[1]]) {
                last <- length(lines)
                if (last > 0 && nchar(lines[last]) + 1 + nchar(word) <= element$cw) {
                    lines[last] <- paste(lines[last], word)
                } else {
                    lines <- c(lines, word)
                }
            }
            element$lines <- lines
            natural <- length(lines)
        } else if (element$style$display == "flex") {
            natural <- flex(element, fh, ch_reference)
        } else if (element$style$display == "grid") {
            natural <- grid_layout(element, fh)
        } else {
            natural <- block(element, fh)
        }
        element$natural <- natural
        element$ch <- if (is.null(fh)) clamp(element, natural, ch_reference, FALSE) else fh
        natural
    }
    block <- function(element, reference) {
        bottom <- 0
        previous <- NULL
        for (child in children(element)) {
            layout(child, element$cw, reference)
            y <- bottom + if (is.null(previous)) child$margin[1] else max(previous$margin[3], child$margin[1])
            position_child(element, child, child$margin[4], y)
            bottom <- y + border_height(child)
            previous <- child
        }
        if (is.null(previous)) 0 else bottom + previous$margin[3]
    }
    flex <- function(element, reference, height_reference) {
        horizontal <- startsWith(element$style[["flex-direction"]], "row")
        reverse <- endsWith(element$style[["flex-direction"]], "reverse")
        main_reference <- if (horizontal) element$cw else reference
        gap <- as.numeric(element$style[[if (horizontal) "column-gap" else "row-gap"]])
        line_gap <- as.numeric(element$style[["row-gap"]])
        items <- lapply(children(element, TRUE), function(child) {
            item <- new.env(parent = emptyenv())
            item$element <- child
            item$align <- align(element, child)
            item$cross <- NULL
            if (!horizontal) {
                room <- max(0, element$cw - frame(child, TRUE) - margins(child, TRUE))
                cross <- resolve(child, "width", element$cw, TRUE)
                if (is.null(cross)) cross <- if (item$align == "stretch") room else min(max_content(child), room)
                item$cross <- clamp(child, cross, element$cw, TRUE)
            }
            base <- resolve(child, "flex-basis", main_reference, horizontal)
            if (is.null(base)) base <- resolve(child, if (horizontal) "width" else "height", main_reference, horizontal)
            if (is.null(base)) base <- if (horizontal) max_content(child) else layout(child, element$cw, reference, item$cross)
            item$base <- base
            item$hypothetical <- clamp(child, base, main_reference, horizontal)
            item$outer <- frame(child, horizontal) + margins(child, horizontal)
            item
        })
        main_length <- if (horizontal) element$cw else reference
        if (is.null(main_length)) {
            natural <- sum(vapply(items, function(i) i$hypothetical + i$outer, numeric(1))) + gap * max(0, length(items) - 1)
            main_length <- clamp(element, natural, height_reference, FALSE)
        }
        lines <- list()
        for (item in items) {
            last <- length(lines)
            current <- if (last == 0) list() else lines[[last]]
            current_length <- sum(vapply(current, function(i) i$hypothetical + i$outer, numeric(1))) + gap * length(current)
            if (last == 0 || (horizontal && element$style[["flex-wrap"]] == "wrap" && current_length + item$hypothetical + item$outer > main_length)) {
                lines[[last + 1L]] <- list()
                last <- last + 1L
            }
            lines[[last]][[length(lines[[last]]) + 1L]] <- item
        }
        cross_start <- 0
        for (line in lines) {
            total_gap <- gap * (length(line) - 1)
            growing <- sum(vapply(line, function(i) i$hypothetical + i$outer, numeric(1))) + total_gap < main_length
            for (item in line) {
                child <- item$element
                item$weight <- if (growing) as.numeric(child$style[["flex-grow"]]) else as.numeric(child$style[["flex-shrink"]]) * item$base
                item$size <- item$hypothetical
                item$frozen <- item$weight == 0 || if (growing) item$base > item$hypothetical else item$base < item$hypothetical
            }
            repeat {
                active <- Filter(function(i) !i$frozen, line)
                if (length(active) == 0) break
                free <- main_length - total_gap - sum(vapply(line, function(i) (if (i$frozen) i$size else i$base) + i$outer, numeric(1)))
                assigned <- distribute(max(0, if (growing) free else -free), vapply(active, function(i) i$weight, numeric(1)))
                for (i in seq_along(active)) {
                    item <- active[[i]]
                    tentative <- item$base + if (growing) assigned[i] else -assigned[i]
                    item$size <- clamp(item$element, tentative, main_reference, horizontal)
                    item$violation <- item$size - tentative
                }
                violation <- sum(vapply(active, function(i) i$violation, numeric(1)))
                for (item in active) {
                    if (violation == 0 || if (violation > 0) item$violation > 0 else item$violation < 0) item$frozen <- TRUE
                }
            }
            if (horizontal) {
                for (item in line) {
                    layout(item$element, element$cw, reference, item$size)
                    item$cross <- item$element$ch
                }
            }
            outer_cross <- max(vapply(line, function(i) i$cross + frame(i$element, !horizontal) + margins(i$element, !horizontal), numeric(1)))
            line_cross <- if (!horizontal) element$cw else if (length(lines) == 1) {
                if (is.null(reference)) clamp(element, outer_cross, height_reference, FALSE) else reference
            } else outer_cross
            remaining <- main_length - total_gap - sum(vapply(line, function(i) i$size + i$outer, numeric(1)))
            spaces <- rep(0, length(line))
            if (remaining > 0) {
                kind <- element$style[["justify-content"]]
                if (kind == "end") {
                    spaces[1] <- remaining
                } else if (kind == "center") {
                    spaces[1] <- remaining %/% 2
                } else if (kind %in% c("space-between", "space-around", "space-evenly")) {
                    weights <- vapply(0:length(line), function(i) {
                        if (kind == "space-evenly") 1 else if (i == 0 || i == length(line)) {
                            if (kind == "space-between") 0 else 1
                        } else if (kind == "space-between") 1 else 2
                    }, numeric(1))
                    spaces <- head(distribute(remaining, weights), length(line))
                }
            }
            cursor <- 0
            for (i in seq_along(line)) {
                item <- line[[i]]
                child <- item$element
                cross <- item$cross
                if (horizontal) {
                    if (item$align == "stretch" && child$style$height == "auto") {
                        cross <- clamp(child, max(0, line_cross - frame(child, FALSE) - margins(child, FALSE)), reference, FALSE)
                        layout(child, element$cw, reference, item$size, cross)
                    } else {
                        layout(child, element$cw, reference, item$size)
                    }
                } else {
                    layout(child, element$cw, reference, cross, item$size)
                }
                room <- line_cross - cross - frame(child, !horizontal) - margins(child, !horizontal)
                offset <- if (room <= 0) 0 else if (item$align == "end") room else if (item$align == "center") room %/% 2 else 0
                cursor <- cursor + spaces[i]
                size <- item$size + item$outer
                main <- (if (reverse) main_length - cursor - size else cursor) + child$margin[if (horizontal) 4 else 1]
                cross_position <- cross_start + offset + child$margin[if (horizontal) 1 else 4]
                position_child(element, child, if (horizontal) main else cross_position, if (horizontal) cross_position else main)
                cursor <- cursor + size + gap
            }
            cross_start <- cross_start + line_cross + line_gap
        }
        if (horizontal) {
            if (length(lines) == 0) 0 else cross_start - line_gap
        } else main_length
    }
    grid_layout <- function(element, reference) {
        grid <- placement(element)
        column_gap <- as.numeric(element$style[["column-gap"]])
        row_gap <- as.numeric(element$style[["row-gap"]])
        columns <- track_sizes(grid, TRUE, element$cw, column_gap, vapply(grid$items, function(i) contribution(i$element), numeric(1)))
        for (item in grid$items) {
            child <- item$element
            item$aw <- sum(columns[seq.int(item$column, item$column + item$cs - 1)]) + column_gap * (item$cs - 1)
            item$ax <- sum(head(columns, item$column - 1)) + column_gap * (item$column - 1)
            value <- resolve(child, "width", item$aw, TRUE)
            if (is.null(value)) value <- max(0, item$aw - frame(child, TRUE) - margins(child, TRUE))
            item$gw <- clamp(child, value, item$aw, TRUE)
            layout(child, item$aw, NULL, item$gw)
            item$row_contribution <- border_height(child) + margins(child, FALSE)
        }
        rows <- track_sizes(grid, FALSE, reference, row_gap, vapply(grid$items, function(i) i$row_contribution, numeric(1)))
        for (item in grid$items) {
            child <- item$element
            area_height <- sum(rows[seq.int(item$row, item$row + item$rs - 1)]) + row_gap * (item$rs - 1)
            area_y <- sum(head(rows, item$row - 1)) + row_gap * (item$row - 1)
            alignment <- align(element, child)
            height <- if (alignment == "stretch" && child$style$height == "auto") clamp(child, max(0, area_height - frame(child, FALSE) - margins(child, FALSE)), area_height, FALSE) else NULL
            layout(child, item$aw, area_height, item$gw, height)
            room <- area_height - border_height(child) - margins(child, FALSE)
            offset <- if (room <= 0) 0 else if (alignment == "end") room else if (alignment == "center") room %/% 2 else 0
            position_child(element, child, item$ax + child$margin[4], area_y + offset + child$margin[1])
        }
        if (length(rows) == 0) 0 else sum(rows) + row_gap * (length(rows) - 1)
    }
    offset_values <- function(element) lapply(c("left", "right", "top", "bottom"), function(p) if (element$style[[p]] == "auto") NULL else as.numeric(element$style[[p]]))
    relayout <- function() {
        for (element in elements) {
            element$style <- defaults
            priorities <- list()
            for (rule in rules) {
                specificity <- -1
                for (selector in rule$selectors) {
                    if (startsWith(selector, "#")) {
                        match <- if (substring(selector, 2) == element$id) 2 else -1
                    } else if (startsWith(selector, ".")) {
                        match <- if (substring(selector, 2) %in% element$classes) 1 else -1
                    } else {
                        match <- if (selector == element$type) 0 else -1
                    }
                    specificity <- max(specificity, match)
                }
                if (specificity < 0) next
                for (decl in rule$declarations) {
                    property <- decl[1]
                    if (is.null(priorities[[property]]) || specificity >= priorities[[property]]) {
                        element$style[[property]] <- decl[2]
                        priorities[[property]] <- specificity
                    }
                }
            }
            for (property in names(element$overrides)) element$style[[property]] <- element$overrides[[property]]
            element$margin <- vapply(sides, function(side) as.numeric(element$style[[paste0("margin-", side)]]), numeric(1))
            element$padding <- vapply(sides, function(side) as.numeric(element$style[[paste0("padding-", side)]]), numeric(1))
            element$border <- vapply(sides, function(side) as.numeric(element$style[[paste0("border-", side)]]), numeric(1))
            element$displayed <- element$style$display != "none" && (is.null(element$parent) || element$parent$displayed)
            element$maximum <- element$contribution <- NULL
            element$lines <- character()
            element$containing <- NULL
        }
        root <- elements[[1]]
        if (root$displayed && root$style$position != "absolute") {
            layout(root, state$width, state$height)
            root$rx <- root$margin[4]
            root$ry <- root$margin[1]
        }
        for (element in elements) {
            if (!element$displayed || element$style$position != "absolute") next
            ancestor <- element$parent
            while (!is.null(ancestor) && ancestor$style$position == "static") ancestor <- ancestor$parent
            element$containing <- ancestor
            cbw <- if (is.null(ancestor)) state$width else ancestor$cw + sum(ancestor$padding[c(2, 4)])
            cbh <- if (is.null(ancestor)) state$height else ancestor$ch + sum(ancestor$padding[c(1, 3)])
            offsets <- offset_values(element)
            left <- offsets[[1]]
            right <- offsets[[2]]
            top <- offsets[[3]]
            bottom <- offsets[[4]]
            width <- resolve(element, "width", cbw, TRUE)
            if (is.null(width)) {
                room <- max(0, cbw - (if (is.null(left)) 0 else left) - (if (is.null(right)) 0 else right) - margins(element, TRUE) - frame(element, TRUE))
                width <- if (!is.null(left) && !is.null(right)) room else min(max_content(element), room)
            }
            fw <- clamp(element, width, cbw, TRUE)
            fh <- if (element$style$height == "auto" && !is.null(top) && !is.null(bottom)) clamp(element, max(0, cbh - top - bottom - margins(element, FALSE) - frame(element, FALSE)), cbh, FALSE) else NULL
            layout(element, cbw, cbh, fw, fh)
            element$rx <- if (!is.null(left)) left + element$margin[4] else if (!is.null(right)) cbw - right - element$margin[2] - border_width(element) else element$margin[4]
            element$ry <- if (!is.null(top)) top + element$margin[1] else if (!is.null(bottom)) cbh - bottom - element$margin[3] - border_height(element) else element$margin[1]
        }
        for (element in elements) {
            if (!element$displayed) next
            reference <- if (element$style$position == "absolute") element$containing else element$parent
            x <- if (is.null(reference)) 0 else reference$x
            y <- if (is.null(reference)) 0 else reference$y
            if (element$style$position == "absolute" && !is.null(reference)) {
                x <- x + reference$border[4]
                y <- y + reference$border[1]
            }
            element$x <- x + element$rx
            element$y <- y + element$ry
            if (element$style$position == "relative") {
                offsets <- offset_values(element)
                element$x <- element$x + if (!is.null(offsets[[1]])) offsets[[1]] else if (!is.null(offsets[[2]])) -offsets[[2]] else 0
                element$y <- element$y + if (!is.null(offsets[[3]])) offsets[[3]] else if (!is.null(offsets[[4]])) -offsets[[4]] else 0
            }
        }
    }
    boxes <- function(element) {
        x <- element$x
        y <- element$y
        w <- border_width(element)
        h <- border_height(element)
        m <- element$margin
        b <- element$border
        p <- element$padding
        list(c(x - m[4], y - m[1], w + m[2] + m[4], h + m[1] + m[3]), c(x, y, w, h),
            c(x + b[4], y + b[1], w - b[2] - b[4], h - b[1] - b[3]),
            c(x + b[4] + p[4], y + b[1] + p[1], element$cw, element$ch))
    }
    snapshot <- function() lapply(elements, function(e) if (e$displayed) c(e$x, e$y, border_width(e), border_height(e)) else NULL)
    changes <- function(before) {
        after <- snapshot()
        changed <- character()
        for (i in seq_along(elements)) {
            a <- before[[i]]
            b <- after[[i]]
            if (is.null(a) != is.null(b) || (!is.null(a) && !is.null(b) && any(a != b))) changed <- c(changed, elements[[i]]$id)
        }
        if (length(changed) == 0) "no change" else paste(changed, collapse = " ")
    }
    render <- function() {
        screen <- matrix(".", nrow = state$height, ncol = state$width)
        for (element in elements) {
            if (!element$displayed) next
            rect <- boxes(element)[[2]]
            x <- rect[1]
            y <- rect[2]
            w <- rect[3]
            h <- rect[4]
            y0 <- max(y, 0)
            y1 <- min(y + h, state$height)
            x0 <- max(x, 0)
            x1 <- min(x + w, state$width)
            if (y0 < y1 && x0 < x1) {
                for (row in seq.int(y0, y1 - 1)) {
                    for (column in seq.int(x0, x1 - 1)) {
                        horizontal <- (element$border[1] == 1 && row == y) || (element$border[3] == 1 && row == y + h - 1)
                        vertical <- (element$border[4] == 1 && column == x) || (element$border[2] == 1 && column == x + w - 1)
                        screen[row + 1, column + 1] <- if (horizontal && vertical) "+" else if (horizontal) "-" else if (vertical) "|" else " "
                    }
                }
            }
            if (!is.null(element$text)) {
                content <- boxes(element)[[4]]
                for (i in seq_along(element$lines)) {
                    row <- content[2] + i - 1L
                    if (row < 0 || row >= state$height) next
                    chars <- strsplit(element$lines[i], "", fixed = TRUE)[[1]]
                    for (j in seq_along(chars)) {
                        column <- content[1] + j - 1L
                        if (column >= 0 && column < state$width) screen[row + 1, column + 1] <- chars[j]
                    }
                }
            }
        }
        edge <- paste(rep("#", state$width + 2), collapse = "")
        emit("render ", state$width, "x", state$height)
        emit(edge)
        for (row in seq_len(state$height)) emit("#", paste(screen[row, ], collapse = ""), "#")
        emit(edge)
    }
    execute <- function(line) {
        words <- strsplit(line, " ", fixed = TRUE)[[1]]
        command <- words[1]
        args <- words[-1]
        if (command == "LAYOUT") {
            emit("layout ", state$width, "x", state$height)
            for (e in elements) {
                suffix <- if (e$displayed) paste(e$x, e$y, border_width(e), border_height(e)) else "none"
                emit(paste(rep("  ", e$depth), collapse = ""), e$id, " ", suffix)
            }
        } else if (command == "BOX") {
            element <- ids[[args[1]]]
            if (is.null(element)) {
                emit("error: unknown element ", args[1])
            } else if (!element$displayed) {
                emit("box ", element$id, ": none")
            } else {
                emit("box ", element$id)
                rects <- boxes(element)
                for (i in 1:4) emit(c("margin", "border", "padding", "content")[i], " ", paste(rects[[i]], collapse = " "))
            }
        } else if (command == "RENDER") {
            render()
        } else if (command == "HIT") {
            x <- as.numeric(args[1])
            y <- as.numeric(args[2])
            if (x >= state$width || y >= state$height) {
                emit("error: point ", x, " ", y, " outside viewport")
            } else {
                found <- NULL
                for (e in elements) {
                    if (e$displayed && e$x <= x && x < e$x + border_width(e) && e$y <= y && y < e$y + border_height(e)) found <- e
                }
                path <- character()
                while (!is.null(found)) {
                    path <- c(found$id, path)
                    found <- found$parent
                }
                emit("hit ", x, " ", y, ": ", if (length(path) == 0) "none" else paste(path, collapse = " > "))
            }
        } else if (command == "SET") {
            id <- args[1]
            property <- args[2]
            value <- paste(args[-c(1, 2)], collapse = " ")
            if (is.null(ids[[id]])) {
                emit("error: unknown element ", id)
            } else if (!known(property)) {
                emit("error: unknown property ", property)
            } else {
                declarations <- declaration(property, value)
                if (is.null(declarations)) {
                    emit("error: invalid value for ", property, ": ", value)
                } else {
                    before <- snapshot()
                    for (decl in declarations) ids[[id]]$overrides[[decl[1]]] <- decl[2]
                    relayout()
                    emit("set ", id, " ", property, " ", value, ": ", changes(before))
                }
            }
        } else if (command == "VIEWPORT") {
            width <- as.numeric(args[1])
            height <- as.numeric(args[2])
            if (width < 1 || width > 80 || height < 1 || height > 40) {
                emit("error: invalid viewport ", width, " ", height)
            } else {
                before <- snapshot()
                state$width <- width
                state$height <- height
                relayout()
                emit("viewport ", width, " ", height, ": ", changes(before))
            }
        } else if (command == "OVERFLOW") {
            overflow <- character()
            for (e in elements) {
                if (!e$displayed) next
                if (!is.null(e$text)) {
                    over <- max(nchar(e$lines)) > e$cw || length(e$lines) > e$ch
                } else {
                    content <- boxes(e)[[4]]
                    over <- FALSE
                    for (child in children(e)) {
                        rect <- boxes(child)[[1]]
                        if (rect[1] < content[1] || rect[2] < content[2] || rect[1] + rect[3] > content[1] + content[3] || rect[2] + rect[4] > content[2] + content[4]) over <- TRUE
                    }
                }
                if (over) overflow <- c(overflow, e$id)
            }
            emit("overflow: ", if (length(overflow) == 0) "none" else paste(overflow, collapse = " "))
        } else {
            emit("error: unknown command ", command)
        }
        invisible(NULL)
    }
    relayout()
    execute
}

input <- readLines(file("stdin"), warn = FALSE)
viewport <- as.numeric(strsplit(input[1], " ", fixed = TRUE)[[1]])
i <- 2L
rules <- list()
while (input[i] != "---") {
    parts <- strsplit(input[i], " { ", fixed = TRUE)[[1]]
    body <- substr(parts[2], 1, nchar(parts[2]) - 2L)
    declarations <- list()
    for (text in strsplit(body, "; ", fixed = TRUE)[[1]]) {
        colon <- regexpr(": ", text, fixed = TRUE)[1]
        property <- substr(text, 1, colon - 1L)
        value <- substring(text, colon + 2L)
        declarations <- c(declarations, declaration(property, value))
    }
    rules[[length(rules) + 1L]] <- list(selectors = strsplit(parts[1], ", ", fixed = TRUE)[[1]], declarations = declarations)
    i <- i + 1L
}
i <- i + 1L
elements <- stack <- list()
while (input[i] != "===") {
    line <- input[i]
    indent <- attr(regexpr("^ *", line), "match.length")
    depth <- indent / 2
    content <- substring(line, indent + 1L)
    space <- regexpr(" ", content, fixed = TRUE)[1]
    head <- if (space < 0) content else substr(content, 1, space - 1L)
    text <- if (space < 0) NULL else substr(content, space + 2L, nchar(content) - 1L)
    hash <- regexpr("#", head, fixed = TRUE)[1]
    type <- substr(head, 1, hash - 1L)
    names <- strsplit(substring(head, hash + 1L), ".", fixed = TRUE)[[1]]
    parent <- if (depth == 0) NULL else stack[[depth]]
    element <- new_element(type, names[1], names[-1], text, parent, depth, length(elements) + 1L)
    if (!is.null(parent)) parent$children[[length(parent$children) + 1L]] <- element
    elements[[length(elements) + 1L]] <- element
    stack[[depth + 1L]] <- element
    i <- i + 1L
}
i <- i + 1L
layout <- make_layout(viewport[1], viewport[2], rules, elements)
while (input[i] != "END") {
    layout(input[i])
    i <- i + 1L
}
