fail <- function(message) {
    stop(structure(list(message = message, call = NULL), class = c("command_error", "error", "condition")))
}
node <- function(keys = integer(), values = character(), kids = integer()) list(keys = keys, values = values, kids = kids)
new_tree <- function(degree) {
    tree <- new.env(parent = emptyenv())
    tree$degree <- degree
    tree$root <- 0L
    tree$pages <- list(node())
    tree$counters <- c(splits = 0L, merges = 0L, borrows = 0L)
    tree
}
copy_tree <- function(source) {
    tree <- new_tree(source$degree)
    tree$root <- source$root
    tree$pages <- source$pages
    tree$counters <- source$counters
    tree
}
get_node <- function(tree, page) tree$pages[[page + 1L]]
set_node <- function(tree, page, value) tree$pages[page + 1L] <- list(value)
live_pages <- function(pages) which(!vapply(pages, is.null, logical(1L))) - 1L
allocate_node <- function(tree, value = node()) {
    force(value)
    holes <- which(vapply(tree$pages, is.null, logical(1L)))
    page <- if (length(holes)) holes[1L] - 1L else length(tree$pages)
    set_node(tree, page, value)
    page
}
release_node <- function(tree, page) tree$pages[page + 1L] <- list(NULL)
notation <- function(value) paste0("[", paste(value$keys, collapse = " "), "]")
entry_text <- function(keys, values) paste0(keys, "=", values)
position <- function(value, key) {
    found <- which(value$keys >= key)
    if (length(found)) found[1L] else length(value$keys) + 1L
}
search_tree <- function(tree, key) {
    page <- tree$root
    path <- integer()
    repeat {
        path <- c(path, page)
        value <- get_node(tree, page)
        at <- position(value, key)
        found <- at <= length(value$keys) && value$keys[at] == key
        if (found || !length(value$kids)) return(list(page = page, at = at, found = found, path = path))
        page <- value$kids[at]
    }
}
inorder <- function(tree) {
    keys <- integer()
    values <- character()
    visit <- function(page) {
        value <- get_node(tree, page)
        for (j in seq_len(length(value$keys) + 1L)) {
            if (length(value$kids)) visit(value$kids[j])
            if (j <= length(value$keys)) {
                keys <<- c(keys, value$keys[j])
                values <<- c(values, value$values[j])
            }
        }
    }
    visit(tree$root)
    list(keys = keys, values = values)
}
height <- function(tree) {
    result <- 0L
    value <- get_node(tree, tree$root)
    while (length(value$kids)) {
        result <- result + 1L
        value <- get_node(tree, value$kids[1L])
    }
    result
}
key_count <- function(tree) sum(vapply(tree$pages, function(value) length(value$keys), integer(1L)))
check_tree <- function(tree) {
    reference <- NULL
    bound_text <- function(value, lower) if (is.null(value)) if (lower) "-inf" else "+inf" else as.character(value)
    visit <- function(page, location, depth, lower, upper) {
        value <- get_node(tree, page)
        count <- length(value$keys)
        minimum <- if (page == tree$root) as.integer(length(value$kids) > 0L) else tree$degree - 1L
        maximum <- 2L * tree$degree - 1L
        where <- paste0(" at=", location, " node=", notation(value))
        if (count < minimum || count > maximum)
            return(paste0("FAIL COUNT", where, " keys=", count, " allowed=", minimum, "..", maximum))
        if (count > 1L) {
            bad <- which(value$keys[-count] >= value$keys[-1L])
            if (length(bad)) return(paste0("FAIL ORDER", where, " ", value$keys[bad[1L]], ">=", value$keys[bad[1L] + 1L]))
        }
        for (key in value$keys) {
            if ((!is.null(lower) && key <= lower) || (!is.null(upper) && key >= upper))
                return(paste0("FAIL RANGE", where, " key=", key, " low=", bound_text(lower, TRUE), " high=", bound_text(upper, FALSE)))
        }
        if (!length(value$kids)) {
            if (is.null(reference)) reference <<- depth else if (depth != reference)
                return(paste0("FAIL DEPTH", where, " depth=", depth, " expected=", reference))
        } else {
            for (j in seq_along(value$kids)) {
                problem <- visit(value$kids[j], paste0(location, ".", j - 1L), depth + 1L,
                                 if (j == 1L) lower else value$keys[j - 1L],
                                 if (j > count) upper else value$keys[j])
                if (!is.null(problem)) return(problem)
            }
        }
        NULL
    }
    visit(tree$root, "root", 0L, NULL, NULL)
}
tree_status <- function(tree) if (is.null(check_tree(tree))) "OK" else "DAMAGED"
changes <- function(tree, before) {
    old <- live_pages(before)
    current <- live_pages(tree$pages)
    writes <- sum(vapply(current, function(page) page >= length(before) || !identical(before[[page + 1L]], get_node(tree, page)), logical(1L)))
    c(writes = writes, frees = length(setdiff(old, current)))
}
trace_context <- function(enabled) {
    context <- new.env(parent = emptyenv())
    context$enabled <- enabled
    context$lines <- character()
    context$cases <- character()
    context
}
step <- function(context, text) {
    if (!is.null(context) && context$enabled) context$lines <- c(context$lines, text)
}
add_case <- function(context, name) {
    if (!is.null(context)) context$cases <- c(context$cases, name)
}
split_child <- function(tree, page, at, context) {
    parent <- get_node(tree, page)
    left_page <- parent$kids[at]
    left <- get_node(tree, left_page)
    degree <- tree$degree
    middle_key <- left$keys[degree]
    middle_value <- left$values[degree]
    right_indices <- seq.int(degree + 1L, length(left$keys))
    right <- node(left$keys[right_indices], left$values[right_indices],
                  if (length(left$kids)) left$kids[seq.int(degree + 1L, 2L * degree)] else integer())
    right_page <- allocate_node(tree, right)
    step(context, paste0("STEP split page=", left_page, " keys=", notation(left), " up=", middle_key, " new=", right_page))
    left$keys <- left$keys[seq_len(degree - 1L)]
    left$values <- left$values[seq_len(degree - 1L)]
    if (length(left$kids)) left$kids <- left$kids[seq_len(degree)]
    parent$keys <- append(parent$keys, middle_key, after = at - 1L)
    parent$values <- append(parent$values, middle_value, after = at - 1L)
    parent$kids <- append(parent$kids, right_page, after = at)
    set_node(tree, left_page, left)
    set_node(tree, page, parent)
    tree$counters["splits"] <- tree$counters["splits"] + 1L
}
insert_entry <- function(tree, key, text, context = NULL) {
    found <- search_tree(tree, key)
    if (found$found) {
        value <- get_node(tree, found$page)
        old <- value$values[found$at]
        value$values[found$at] <- text
        set_node(tree, found$page, value)
        return(list(added = FALSE, old = old))
    }
    if (length(get_node(tree, tree$root)$keys) == 2L * tree$degree - 1L) {
        tree$root <- allocate_node(tree, node(kids = tree$root))
        step(context, paste0("STEP grow page=", tree$root))
        split_child(tree, tree$root, 1L, context)
    }
    page <- tree$root
    repeat {
        value <- get_node(tree, page)
        at <- position(value, key)
        if (!length(value$kids)) break
        if (length(get_node(tree, value$kids[at])$keys) == 2L * tree$degree - 1L) {
            split_child(tree, page, at, context)
            value <- get_node(tree, page)
            if (key > value$keys[at]) at <- at + 1L
        }
        page <- value$kids[at]
    }
    value$keys <- append(value$keys, key, after = at - 1L)
    value$values <- append(value$values, text, after = at - 1L)
    set_node(tree, page, value)
    step(context, paste0("STEP place page=", page, " keys=", notation(value)))
    list(added = TRUE, old = NULL)
}
merge_children <- function(tree, page, at, name, context) {
    parent <- get_node(tree, page)
    left_page <- parent$kids[at]
    right_page <- parent$kids[at + 1L]
    left <- get_node(tree, left_page)
    right <- get_node(tree, right_page)
    left$keys <- c(left$keys, parent$keys[at], right$keys)
    left$values <- c(left$values, parent$values[at], right$values)
    left$kids <- c(left$kids, right$kids)
    parent$keys <- parent$keys[-at]
    parent$values <- parent$values[-at]
    parent$kids <- parent$kids[-(at + 1L)]
    set_node(tree, left_page, left)
    set_node(tree, page, parent)
    release_node(tree, right_page)
    tree$counters["merges"] <- tree$counters["merges"] + 1L
    step(context, paste0("STEP ", name, " page=", page, " merge=", left_page, "+", right_page, " keys=", notation(left)))
    if (page == tree$root && !length(parent$keys)) {
        tree$root <- left_page
        release_node(tree, page)
        step(context, paste0("STEP shrink page=", left_page))
    }
    left_page
}
borrow_child <- function(tree, page, at, from_left, context) {
    parent <- get_node(tree, page)
    child_page <- parent$kids[at]
    sibling_page <- parent$kids[at + if (from_left) -1L else 1L]
    child <- get_node(tree, child_page)
    sibling <- get_node(tree, sibling_page)
    separator <- at - as.integer(from_left)
    take <- if (from_left) length(sibling$keys) else 1L
    child$keys <- append(child$keys, parent$keys[separator], after = if (from_left) 0L else length(child$keys))
    child$values <- append(child$values, parent$values[separator], after = if (from_left) 0L else length(child$values))
    parent$keys[separator] <- sibling$keys[take]
    parent$values[separator] <- sibling$values[take]
    sibling$keys <- sibling$keys[-take]
    sibling$values <- sibling$values[-take]
    if (length(sibling$kids)) {
        take_child <- if (from_left) length(sibling$kids) else 1L
        child$kids <- append(child$kids, sibling$kids[take_child], after = if (from_left) 0L else length(child$kids))
        sibling$kids <- sibling$kids[-take_child]
    }
    set_node(tree, child_page, child)
    set_node(tree, sibling_page, sibling)
    set_node(tree, page, parent)
    tree$counters["borrows"] <- tree$counters["borrows"] + 1L
    step(context, paste0("STEP 3a-", if (from_left) "left" else "right", " page=", page, " child=", child_page,
                        " from=", sibling_page, " keys=", notation(child)))
}
delete_entry <- function(tree, page, key, context = NULL) {
    value <- get_node(tree, page)
    at <- position(value, key)
    if (at <= length(value$keys) && value$keys[at] == key) {
        if (!length(value$kids)) {
            add_case(context, "1")
            value$keys <- value$keys[-at]
            value$values <- value$values[-at]
            set_node(tree, page, value)
            step(context, paste0("STEP 1 page=", page, " keys=", notation(value)))
        } else {
            left <- value$kids[at]
            right <- value$kids[at + 1L]
            if (length(get_node(tree, left)$keys) >= tree$degree || length(get_node(tree, right)$keys) >= tree$degree) {
                predecessor <- length(get_node(tree, left)$keys) >= tree$degree
                child <- if (predecessor) left else right
                extreme <- get_node(tree, child)
                while (length(extreme$kids)) extreme <- get_node(tree, extreme$kids[if (predecessor) length(extreme$kids) else 1L])
                pick <- if (predecessor) length(extreme$keys) else 1L
                replacement_key <- extreme$keys[pick]
                replacement_value <- extreme$values[pick]
                name <- if (predecessor) "2a" else "2b"
                add_case(context, name)
                step(context, paste0("STEP ", name, " page=", page, if (predecessor) " pred=" else " succ=", replacement_key))
                delete_entry(tree, child, replacement_key, context)
                value <- get_node(tree, page)
                value$keys[at] <- replacement_key
                value$values[at] <- replacement_value
                set_node(tree, page, value)
            } else {
                add_case(context, "2c")
                child <- merge_children(tree, page, at, "2c", context)
                delete_entry(tree, child, key, context)
            }
        }
    } else {
        child <- value$kids[at]
        if (length(get_node(tree, child)$keys) == tree$degree - 1L) {
            if (at > 1L && length(get_node(tree, value$kids[at - 1L])$keys) >= tree$degree) {
                add_case(context, "3a-left")
                borrow_child(tree, page, at, TRUE, context)
            } else if (at < length(value$kids) && length(get_node(tree, value$kids[at + 1L])$keys) >= tree$degree) {
                add_case(context, "3a-right")
                borrow_child(tree, page, at, FALSE, context)
            } else {
                name <- if (at > 1L) "3b-left" else "3b-right"
                add_case(context, name)
                child <- merge_children(tree, page, if (at > 1L) at - 1L else at, name, context)
            }
        }
        delete_entry(tree, child, key, context)
    }
    invisible(NULL)
}
scan_tree <- function(tree, lower, upper) {
    visited <- 0L
    result <- list(keys = integer(), values = character())
    visit <- function(page) {
        visited <<- visited + 1L
        value <- get_node(tree, page)
        count <- length(value$keys)
        for (j in seq_len(count + 1L)) {
            if (length(value$kids) && (j == 1L || value$keys[j - 1L] < upper) && (j > count || value$keys[j] > lower)) visit(value$kids[j])
            if (j <= count && value$keys[j] >= lower && value$keys[j] <= upper) {
                result$keys <<- c(result$keys, value$keys[j])
                result$values <<- c(result$values, value$values[j])
            }
        }
    }
    visit(tree$root)
    result$visited <- visited
    result
}
dump_tree <- function(tree, page = tree$root) {
    value <- get_node(tree, page)
    tokens <- "("
    for (j in seq_len(length(value$keys) + 1L)) {
        if (length(value$kids)) tokens <- c(tokens, dump_tree(tree, value$kids[j]))
        if (j <= length(value$keys)) tokens <- c(tokens, entry_text(value$keys[j], value$values[j]))
    }
    c(tokens, ")")
}
load_tree <- function(degree, tokens) {
    tree <- new_tree(degree)
    tree$pages <- list()
    at <- 1L
    peek <- function() if (at <= length(tokens)) tokens[at] else ""
    syntax <- function() fail(paste("ERROR SYNTAX", at))
    expect <- function(text) {
        if (peek() != text) syntax()
        at <<- at + 1L
    }
    read_entry <- function() {
        text <- peek()
        if (text %in% c("", "(", ")")) syntax()
        fields <- strsplit(text, "=", fixed = TRUE)[[1L]]
        at <<- at + 1L
        list(key = as.integer(fields[1L]), value = fields[2L])
    }
    read_node <- function() {
        expect("(")
        page <- allocate_node(tree)
        value <- node()
        internal <- peek() == "("
        if (internal) value$kids <- read_node()
        while (peek() != ")") {
            entry <- read_entry()
            value$keys <- c(value$keys, entry$key)
            value$values <- c(value$values, entry$value)
            if (internal) value$kids <- c(value$kids, read_node())
        }
        expect(")")
        set_node(tree, page, value)
        page
    }
    tree$root <- read_node()
    if (at <= length(tokens)) syntax()
    tree
}
compact_tree <- function(source) {
    entries <- inorder(source)
    candidates <- list()
    degree <- source$degree
    repeat {
        count <- length(entries$keys)
        groups <- (count + 2L * degree) %/% (2L * degree)
        kept <- count - groups + 1L
        sizes <- rep.int(kept %/% groups, groups) + as.integer(seq_len(groups) <= kept %% groups)
        level <- vector("list", groups)
        separators <- list(keys = integer(), values = character())
        at <- 1L
        child_at <- 1L
        for (i in seq_len(groups)) {
            chosen <- at - 1L + seq_len(sizes[i])
            kids <- if (length(candidates)) candidates[child_at - 1L + seq_len(sizes[i] + 1L)] else list()
            level[[i]] <- list(keys = entries$keys[chosen], values = entries$values[chosen], kids = kids)
            at <- at + sizes[i]
            child_at <- child_at + sizes[i] + 1L
            if (i < groups) {
                separators$keys <- c(separators$keys, entries$keys[at])
                separators$values <- c(separators$values, entries$values[at])
                at <- at + 1L
            }
        }
        if (groups == 1L) break
        entries <- separators
        candidates <- level
    }
    tree <- new_tree(degree)
    tree$pages <- list()
    assign_pages <- function(value) {
        page <- allocate_node(tree)
        kids <- vapply(value$kids, assign_pages, integer(1L))
        set_node(tree, page, node(value$keys, value$values, kids))
        page
    }
    tree$root <- assign_pages(level[[1L]])
    tree
}

execute <- function(state, words) {
    command <- words[1L]
    args <- words[-1L]
    if (command == "TRACE") {
        state$trace <- args[1L] == "ON"
        return(paste("TRACE", args[1L]))
    }
    if (command %in% c("CREATE", "LOAD")) {
        degree <- as.integer(args[1L])
        if (degree < 2L || degree > 5L) fail(paste("ERROR BAD DEGREE", degree))
        tree <- if (command == "CREATE") new_tree(degree) else load_tree(degree, args[-1L])
        state$index <- tree
        state$cursor <- list(kind = "UNSET", key = 0L)
        if (command == "CREATE") return(paste0("CREATE t=", degree))
        return(paste0("LOAD t=", degree, " nodes=", length(live_pages(tree$pages)), " keys=", key_count(tree), " ", tree_status(tree)))
    }
    tree <- state$index
    if (is.null(tree)) fail("ERROR NO INDEX")
    needs_valid <- c("INSERT", "BULKLOAD", "DELETE", "DELRANGE", "RANGE", "COUNT", "MIN", "MAX", "FLOOR", "CEIL", "RANK", "SELECT", "SEEK", "NEXT", "PREV", "HEIGHT", "COMPACT")
    if (command %in% needs_valid && !is.null(check_tree(tree))) fail("ERROR DAMAGED")
    if (command %in% c("DELRANGE", "RANGE", "COUNT") && as.integer(args[1L]) > as.integer(args[2L]))
        fail(paste("ERROR BAD RANGE", args[1L], args[2L]))
    if (command == "SELECT" && (as.integer(args[1L]) < 1L || as.integer(args[1L]) > key_count(tree)))
        fail(paste("ERROR BAD POSITION", args[1L]))
    if (command %in% c("NEXT", "PREV") && state$cursor$kind == "UNSET") fail("ERROR NO CURSOR")
    if (command == "RESTORE" && is.null(state$saved)) fail("ERROR NO SAVE")
    switch(command,
        INSERT = {
            key <- as.integer(args[1L])
            before <- tree$pages
            splits <- tree$counters["splits"]
            context <- trace_context(state$trace)
            result <- insert_entry(tree, key, args[2L], context)
            delta <- changes(tree, before)
            text <- if (result$added) paste0("INSERT ", key, " NEW splits=", tree$counters["splits"] - splits, " height=", height(tree), " writes=", delta["writes"]) else
                paste0("INSERT ", key, " UPDATED old=", result$old, " writes=", delta["writes"])
            c(context$lines, text)
        },
        BULKLOAD = {
            before <- tree$pages
            splits <- tree$counters["splits"]
            added <- 0L
            for (i in seq.int(1L, length(args), by = 2L)) added <- added + as.integer(insert_entry(tree, as.integer(args[i]), args[i + 1L])$added)
            pairs <- length(args) %/% 2L
            paste0("BULKLOAD pairs=", pairs, " new=", added, " updated=", pairs - added, " splits=", tree$counters["splits"] - splits,
                   " height=", height(tree), " writes=", changes(tree, before)["writes"])
        },
        DELETE = {
            key <- as.integer(args[1L])
            found <- search_tree(tree, key)
            if (!found$found) return(paste("DELETE", key, "NOT FOUND"))
            old <- get_node(tree, found$page)$values[found$at]
            before <- tree$pages
            context <- trace_context(state$trace)
            delete_entry(tree, tree$root, key, context)
            delta <- changes(tree, before)
            c(context$lines, paste0("DELETE ", key, " REMOVED value=", old, " cases=", paste(context$cases, collapse = ","),
                                   " height=", height(tree), " writes=", delta["writes"], " frees=", delta["frees"]))
        },
        DELRANGE = {
            lower <- as.integer(args[1L])
            upper <- as.integer(args[2L])
            before <- tree$pages
            counts <- tree$counters
            keys <- inorder(tree)$keys
            keys <- keys[keys >= lower & keys <= upper]
            for (key in keys) delete_entry(tree, tree$root, key)
            delta <- changes(tree, before)
            paste0("DELRANGE ", lower, " ", upper, " removed=", length(keys), " merges=", tree$counters["merges"] - counts["merges"],
                   " borrows=", tree$counters["borrows"] - counts["borrows"], " height=", height(tree), " writes=", delta["writes"], " frees=", delta["frees"])
        },
        GET = {
            key <- as.integer(args[1L])
            result <- search_tree(tree, key)
            outcome <- if (result$found) paste0("FOUND value=", get_node(tree, result$page)$values[result$at]) else "NOT FOUND"
            path <- vapply(result$path, function(page) notation(get_node(tree, page)), character(1L))
            paste0("GET ", key, " ", outcome, " path=", paste(path, collapse = " -> "))
        },
        RANGE =, COUNT = {
            result <- scan_tree(tree, as.integer(args[1L]), as.integer(args[2L]))
            text <- paste0(command, " ", args[1L], " ", args[2L], " count=", length(result$keys), " visited=", result$visited)
            if (command == "RANGE" && length(result$keys)) paste(text, paste(entry_text(result$keys, result$values), collapse = " ")) else text
        },
        MIN =, MAX =, FLOOR =, CEIL =, RANK =, SELECT =, SEEK =, NEXT =, PREV = {
            entries <- inorder(tree)
            keys <- entries$keys
            displays <- if (length(keys)) entry_text(keys, entries$values) else character()
            if (command %in% c("MIN", "MAX")) {
                if (!length(keys)) return(paste(command, "EMPTY"))
                return(paste(command, displays[if (command == "MIN") 1L else length(keys)]))
            }
            if (command == "SELECT") return(paste("SELECT", args[1L], displays[as.integer(args[1L])]))
            if (command == "RANK") return(paste("RANK", args[1L], sum(keys < as.integer(args[1L]))))
            if (command %in% c("FLOOR", "CEIL", "SEEK")) {
                key <- as.integer(args[1L])
                indices <- if (command == "FLOOR") which(keys <= key) else which(keys >= key)
                chosen <- if (length(indices)) indices[if (command == "FLOOR") length(indices) else 1L] else NA_integer_
                if (command == "SEEK") state$cursor <- if (is.na(chosen)) list(kind = "END", key = 0L) else list(kind = "KEY", key = keys[chosen])
                return(paste(command, key, if (!is.na(chosen)) displays[chosen] else if (command == "SEEK") "END" else "NONE"))
            }
            cursor <- state$cursor
            if (command == "NEXT") {
                indices <- if (cursor$kind == "END") integer() else if (cursor$kind == "BEGIN") seq_along(keys) else which(keys > cursor$key)
                chosen <- if (length(indices)) indices[1L] else NA_integer_
            } else {
                indices <- if (cursor$kind == "BEGIN") integer() else if (cursor$kind == "END") seq_along(keys) else which(keys < cursor$key)
                chosen <- if (length(indices)) indices[length(indices)] else NA_integer_
            }
            if (is.na(chosen)) {
                state$cursor <- list(kind = if (command == "NEXT") "END" else "BEGIN", key = 0L)
                paste(command, state$cursor$kind)
            } else {
                state$cursor <- list(kind = "KEY", key = keys[chosen])
                paste(command, displays[chosen])
            }
        },
        PRINT = {
            level <- tree$root
            depth <- 0L
            result <- character()
            while (length(level)) {
                result <- c(result, paste("LEVEL", depth, paste(vapply(level, function(page) notation(get_node(tree, page)), character(1L)), collapse = " ")))
                level <- as.integer(unlist(lapply(level, function(page) get_node(tree, page)$kids), use.names = FALSE))
                depth <- depth + 1L
            }
            result
        },
        PAGES = vapply(live_pages(tree$pages), function(page) {
            value <- get_node(tree, page)
            paste0("PAGE ", page, " ", notation(value), " kids=", if (length(value$kids)) paste(value$kids, collapse = ",") else "-")
        }, character(1L)),
        DUMP = paste("DUMP", tree$degree, paste(dump_tree(tree), collapse = " ")),
        HEIGHT = paste("HEIGHT", height(tree)),
        STATS = {
            pages <- live_pages(tree$pages)
            leaves <- sum(vapply(pages, function(page) !length(get_node(tree, page)$kids), logical(1L)))
            keys <- key_count(tree)
            paste0("STATS t=", tree$degree, " nodes=", length(pages), " leaves=", leaves, " keys=", keys,
                   " fill=", (100L * keys) %/% ((2L * tree$degree - 1L) * length(pages)), "% splits=", tree$counters["splits"],
                   " merges=", tree$counters["merges"], " borrows=", tree$counters["borrows"])
        },
        VERIFY = {
            problem <- check_tree(tree)
            paste("VERIFY", if (is.null(problem)) "OK" else problem)
        },
        REBUILD = {
            entries <- inorder(tree)
            rebuilt <- new_tree(tree$degree)
            for (i in seq_along(entries$keys)) insert_entry(rebuilt, entries$keys[i], entries$values[i])
            state$index <- rebuilt
            paste0("REBUILD entries=", length(entries$keys), " keys=", key_count(rebuilt), " nodes=", length(live_pages(rebuilt$pages)),
                   " splits=", rebuilt$counters["splits"], " height=", height(rebuilt))
        },
        COMPACT = {
            compacted <- compact_tree(tree)
            state$index <- compacted
            paste0("COMPACT nodes=", length(live_pages(tree$pages)), "->", length(live_pages(compacted$pages)), " height=", height(compacted))
        },
        SAVE =, RESTORE = {
            if (command == "SAVE") state$saved <- copy_tree(tree) else state$index <- copy_tree(state$saved)
            result <- state$index
            paste0(command, " nodes=", length(live_pages(result$pages)), " keys=", key_count(result), " ", tree_status(result))
        }
    )
}

state <- new.env(parent = emptyenv())
state$index <- NULL
state$saved <- NULL
state$cursor <- list(kind = "UNSET", key = 0L)
state$trace <- FALSE
input <- readLines(file("stdin"), warn = FALSE)
if (length(input)) for (line in input[1L + seq_len(as.integer(input[1L]))]) {
    reply <- tryCatch(execute(state, strsplit(line, " ", fixed = TRUE)[[1L]]), command_error = function(error) conditionMessage(error))
    cat(paste(reply, collapse = "\n"), "\n", sep = "")
}
