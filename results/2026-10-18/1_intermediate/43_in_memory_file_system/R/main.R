number <- function(value) sprintf("%.0f", value)
terminal <- function(lines) if (length(lines)) writeLines(lines, useBytes = TRUE)
new_output <- function(direct) {
  result <- new.env(parent = emptyenv())
  result$direct <- direct
  result$chunks <- vector("list", 32L)
  result$count <- 0L
  result
}
emit <- function(output, lines) {
  if (!length(lines)) return(invisible(NULL))
  if (output$direct) terminal(lines) else {
    output$count <- output$count + 1L
    if (output$count > length(output$chunks)) length(output$chunks) <- 2L * length(output$chunks)
    output$chunks[[output$count]] <- lines
  }
}
output_lines <- function(output) {
  if (!output$count) return(character())
  unlist(output$chunks[seq_len(output$count)], use.names = FALSE)
}
options_of <- function(arguments) {
  flags <- character()
  at <- 0L
  while (at < length(arguments) && startsWith(arguments[at + 1L], "-")) {
    flags <- c(flags, strsplit(substring(arguments[at + 1L], 2L), "", fixed = TRUE)[[1L]])
    at <- at + 1L
  }
  list(flags = unique(flags), paths = if (at) arguments[-seq_len(at)] else arguments)
}
last_component <- function(path) sub("^.*/", "", path)
invalid_source <- function(path) last_component(path) %in% c("", ".", "..")
joined <- function(path, name) paste0(path, if (path == "/") "" else "/", name)
new_node <- function(kind, inode, modified, lines = character(), target = "") {
  node <- new.env(parent = emptyenv())
  node$kind <- kind
  node$inode <- inode
  node$modified <- modified
  node$name <- ""
  node$parent <- NULL
  node$entries <- list()
  node$lines <- lines
  node$target <- target
  node
}
new_shell <- function() {
  shell <- new.env(parent = emptyenv())
  shell$root <- new_node("d", 1L, 0L)
  shell$root$parent <- shell$root
  shell$current <- shell$root
  shell$previous <- NULL
  shell$clock <- 0L
  shell$next_inode <- 2L
  shell
}
children <- function(node) {
  if (!length(node$entries)) return(list())
  node$entries[order(names(node$entries), method = "radix")]
}
node_size <- function(node) switch(node$kind,
  d = as.double(length(node$entries)), l = as.double(nchar(node$target, type = "bytes")),
  f = sum(as.double(nchar(node$lines, type = "bytes")) + 1))
link_count <- function(node) {
  if (node$kind != "d") return(1L)
  2L + sum(vapply(node$entries, function(child) child$kind == "d", logical(1)))
}
absolute <- function(shell, node) {
  parts <- character()
  while (!identical(node, shell$root)) {
    parts <- c(parts, node$name)
    node <- node$parent
  }
  paste0("/", paste(rev(parts), collapse = "/"))
}
descendant <- function(shell, node, ancestor) {
  while (!identical(node, ancestor)) {
    if (identical(node, shell$root)) return(FALSE)
    node <- node$parent
  }
  TRUE
}
attach <- function(shell, parent, name, node) {
  parent$entries[name] <- list(node)
  parent$modified <- shell$clock
  node$parent <- parent
  node$name <- name
}
create_node <- function(shell, parent, name, kind, lines = character(), target = "") {
  node <- new_node(kind, shell$next_inode, shell$clock, lines, target)
  shell$next_inode <- shell$next_inode + 1L
  attach(shell, parent, name, node)
  node
}
detach <- function(shell, node) {
  node$parent$entries[[node$name]] <- NULL
  node$parent$modified <- shell$clock
}
write_file <- function(shell, node, lines, append = FALSE) {
  force(lines)
  node$lines <- if (append) c(node$lines, lines) else lines
  node$modified <- shell$clock
}
resolution <- function(node = NULL, parent = NULL, name = "", problem = "") {
  list(node = node, parent = parent, name = name, problem = problem)
}
resolve <- function(shell, path, follow = TRUE, parents = FALSE) {
  expansions <- 0L
  walk <- function(path, base, follow, original) {
    node <- if (startsWith(path, "/")) shell$root else base
    parts <- strsplit(path, "/", fixed = TRUE)[[1L]]
    parts <- parts[nzchar(parts)]
    for (index in seq_along(parts)) {
      if (node$kind != "d") return(resolution(problem = "Not a directory"))
      name <- parts[index]
      if (name == ".") next
      if (name == "..") { node <- node$parent; next }
      last <- index == length(parts)
      candidate <- node$entries[[name]]
      if (is.null(candidate)) {
        if (original && parents && !last) candidate <- create_node(shell, node, name, "d")
        else return(resolution(parent = if (original && last) node else NULL,
                               name = name, problem = "No such file or directory"))
      }
      if (candidate$kind == "l" && (!last || follow)) {
        expansions <<- expansions + 1L
        if (expansions > 8L) return(resolution(problem = "Too many levels of symbolic links"))
        target <- walk(candidate$target, node, TRUE, FALSE)
        if (is.null(target$node)) return(target)
        candidate <- target$node
      }
      node <- candidate
    }
    resolution(node = node)
  }
  walk(path, shell$current, follow, TRUE)
}
clone_tree <- function(shell, source, parent, name) {
  pending <- list(list(source = source, parent = parent, name = name))
  while (length(pending)) {
    step <- pending[[length(pending)]]
    pending[[length(pending)]] <- NULL
    original <- step$source
    copy <- create_node(shell, step$parent, step$name, original$kind, original$lines, original$target)
    if (original$kind == "d") for (child in rev(children(original))) {
      pending[[length(pending) + 1L]] <- list(source = child, parent = copy, name = child$name)
    }
  }
}
move_one <- function(shell, source_path, destination) {
  problem <- function(path, reason) terminal(sprintf("mv: cannot move '%s' to '%s': %s", source_path, path, reason))
  if (invalid_source(source_path)) { problem(destination, "Invalid argument"); return(invisible(NULL)) }
  result <- resolve(shell, source_path, FALSE)
  source <- result$node
  if (is.null(source)) { terminal(sprintf("mv: cannot stat '%s': %s", source_path, result$problem)); return(invisible(NULL)) }
  directory <- resolve(shell, destination)$node
  if (!is.null(directory) && directory$kind == "d") {
    parent <- directory
    name <- last_component(source_path)
    target <- joined(destination, name)
  } else {
    result <- resolve(shell, destination, FALSE)
    if (!is.null(result$parent)) { parent <- result$parent; name <- result$name }
    else if (!is.null(result$node)) { parent <- result$node$parent; name <- result$node$name }
    else { problem(destination, result$problem); return(invisible(NULL)) }
    target <- destination
  }
  existing <- parent$entries[[name]]
  if (source$kind == "d" && descendant(shell, parent, source)) {
    terminal(sprintf("mv: cannot move '%s' to a subdirectory of itself, '%s'", source_path, target))
  } else if (identical(existing, source)) terminal(sprintf("mv: '%s' and '%s' are the same file", source_path, target))
  else if (!is.null(existing) && source$kind == "d" && existing$kind != "d") {
    terminal(sprintf("mv: cannot overwrite non-directory '%s' with directory '%s'", target, source_path))
  } else if (!is.null(existing) && source$kind != "d" && existing$kind == "d") {
    terminal(sprintf("mv: cannot overwrite directory '%s' with non-directory '%s'", target, source_path))
  } else if (!is.null(existing) && existing$kind == "d" && length(existing$entries)) problem(target, "Directory not empty")
  else if (identical(existing, shell$current)) problem(target, "Device or resource busy")
  else {
    if (!is.null(existing)) detach(shell, existing)
    detach(shell, source)
    attach(shell, parent, name, source)
  }
}
copy_one <- function(shell, source_path, destination, recursive) {
  problem <- function(path, reason) terminal(sprintf("cp: cannot copy '%s' to '%s': %s", source_path, path, reason))
  if (invalid_source(source_path)) { problem(destination, "Invalid argument"); return(invisible(NULL)) }
  result <- resolve(shell, source_path)
  source <- result$node
  if (is.null(source)) { terminal(sprintf("cp: cannot stat '%s': %s", source_path, result$problem)); return(invisible(NULL)) }
  if (source$kind == "d" && !recursive) {
    terminal(sprintf("cp: -r not specified; omitting directory '%s'", source_path)); return(invisible(NULL))
  }
  result <- resolve(shell, destination)
  if (is.null(result$node) && is.null(result$parent)) { problem(destination, result$problem); return(invisible(NULL)) }
  target <- if (!is.null(result$node) && result$node$kind == "d") joined(destination, last_component(source_path)) else destination
  result <- resolve(shell, target, source$kind != "d")
  if (source$kind == "d") {
    if (!is.null(result$node)) problem(target, "File exists")
    else if (descendant(shell, result$parent, source)) {
      terminal(sprintf("cp: cannot copy a directory, '%s', into itself, '%s'", source_path, target))
    } else clone_tree(shell, source, result$parent, result$name)
  } else if (!is.null(result$parent)) create_node(shell, result$parent, result$name, "f", source$lines)
  else if (is.null(result$node)) problem(target, result$problem)
  else if (identical(result$node, source)) terminal(sprintf("cp: '%s' and '%s' are the same file", source_path, target))
  else if (result$node$kind == "d") terminal(sprintf("cp: cannot overwrite directory '%s' with non-directory '%s'", target, source_path))
  else write_file(shell, result$node, source$lines)
}

listing <- function(shell, options, output) {
  flags <- options$flags
  paths <- if (length(options$paths)) options$paths else "."
  for (path in paths) {
    result <- resolve(shell, path, !("l" %in% flags))
    node <- result$node
    if (is.null(node)) { terminal(sprintf("ls: cannot access '%s': %s", path, result$problem)); next }
    if (node$kind != "d") { entries <- list(node); labels <- path }
    else {
      if (length(paths) > 1L) emit(output, paste0(path, ":"))
      entries <- children(node)
      if (length(entries) && !("a" %in% flags)) entries <- entries[!startsWith(names(entries), ".")]
      if ("a" %in% flags) entries <- c(list("." = node, ".." = node$parent), entries)
      labels <- names(entries)
      if ("t" %in% flags) {
        order <- order(-vapply(entries, function(entry) entry$modified, integer(1)), method = "radix")
        entries <- entries[order]
        labels <- labels[order]
      }
    }
    if ("r" %in% flags) { entries <- rev(entries); labels <- rev(labels) }
    if (!length(entries)) next
    if (!("l" %in% flags)) { emit(output, labels); next }
    values <- cbind(vapply(entries, link_count, integer(1)), vapply(entries, node_size, numeric(1)),
                    vapply(entries, function(entry) entry$modified, integer(1)))
    widths <- apply(values, 2L, function(column) max(nchar(number(column), type = "bytes")))
    lines <- vapply(seq_along(entries), function(index) {
      entry <- entries[[index]]
      fields <- vapply(seq_len(3L), function(column) sprintf("%*s", widths[column], number(values[index, column])), character(1))
      paste0(if (entry$kind == "f") "-" else entry$kind, " ", paste(fields, collapse = " "), " ", labels[index],
             if (entry$kind == "l") paste0(" -> ", entry$target) else "")
    }, character(1))
    emit(output, lines)
  }
}
visits <- function(node, path, limit = 1000L) {
  pending <- list(list(node = node, path = path, name = if (path == "/") "/" else last_component(path), depth = 0L))
  result <- vector("list", 1000L)
  count <- 0L
  while (length(pending)) {
    visit <- pending[[length(pending)]]
    pending[[length(pending)]] <- NULL
    count <- count + 1L
    result[[count]] <- visit
    if (visit$node$kind == "d" && visit$depth < limit) for (child in rev(children(visit$node))) {
      pending[[length(pending) + 1L]] <- list(node = child, path = joined(visit$path, child$name), name = child$name, depth = visit$depth + 1L)
    }
  }
  result[seq_len(count)]
}
glob_matches <- function(pattern, text) {
  previous <- c(TRUE, rep(FALSE, nchar(text, type = "bytes")))
  characters <- strsplit(text, "", fixed = TRUE)[[1L]]
  for (character in strsplit(pattern, "", fixed = TRUE)[[1L]]) {
    following <- rep(FALSE, length(previous))
    following[1L] <- character == "*" && previous[1L]
    for (position in seq_along(characters)) following[position + 1L] <- if (character == "*") {
      previous[position + 1L] || following[position]
    } else previous[position] && (character == "?" || character == characters[position])
    previous <- following
  }
  tail(previous, 1L)
}
find_nodes <- function(shell, arguments, output) {
  path <- "."
  if (length(arguments) && !startsWith(arguments[1L], "-")) { path <- arguments[1L]; arguments <- arguments[-1L] }
  pattern <- kind <- ""
  limit <- 1000L
  at <- 1L
  while (at <= length(arguments)) {
    test <- arguments[at]
    value <- arguments[at + 1L]
    if (test == "-name") pattern <- value else if (test == "-type") kind <- value else limit <- as.integer(value)
    at <- at + 2L
  }
  result <- resolve(shell, path)
  if (is.null(result$node)) { terminal(sprintf("find: '%s': %s", path, result$problem)); return(invisible(NULL)) }
  rows <- visits(result$node, path, limit)
  selected <- vapply(rows, function(row) (!nzchar(pattern) || glob_matches(pattern, row$name)) &&
                      (!nzchar(kind) || row$node$kind == kind), logical(1))
  emit(output, vapply(rows[selected], `[[`, character(1), "path"))
}
disk_usage <- function(shell, options, output) {
  paths <- if (length(options$paths)) options$paths else "."
  for (path in paths) {
    result <- resolve(shell, path)
    if (is.null(result$node)) { terminal(sprintf("du: cannot access '%s': %s", path, result$problem)); next }
    pending <- list(list(node = result$node, path = path, show = TRUE, complete = FALSE))
    totals <- new.env(hash = TRUE, parent = emptyenv())
    lines <- character()
    while (length(pending)) {
      step <- pending[[length(pending)]]
      pending[[length(pending)]] <- NULL
      node <- step$node
      if (node$kind == "d" && !step$complete) {
        step$complete <- TRUE
        pending[[length(pending) + 1L]] <- step
        for (child in rev(children(node))) pending[[length(pending) + 1L]] <- list(
          node = child, path = joined(step$path, child$name), complete = FALSE,
          show = step$show && !("s" %in% options$flags) && (child$kind == "d" || "a" %in% options$flags))
        next
      }
      amount <- if (node$kind == "d") sum(vapply(node$entries, function(child) totals[[number(child$inode)]], numeric(1))) else node_size(node)
      totals[[number(node$inode)]] <- amount
      if (step$show) lines <- c(lines, paste(number(amount), step$path))
    }
    emit(output, lines)
  }
}
draw_tree <- function(shell, options, output) {
  path <- if (length(options$paths)) options$paths[1L] else "."
  result <- resolve(shell, path)
  if (is.null(result$node)) { terminal(sprintf("tree: %s: %s", path, result$problem)); return(invisible(NULL)) }
  if (result$node$kind != "d") { terminal(sprintf("tree: %s: Not a directory", path)); return(invisible(NULL)) }
  frames <- function(node, prefix) {
    entries <- children(node)
    if (length(entries) && !("a" %in% options$flags)) entries <- entries[!startsWith(names(entries), ".")]
    lapply(rev(seq_along(entries)), function(index) list(node = entries[[index]], prefix = prefix, last = index == length(entries)))
  }
  pending <- frames(result$node, "")
  lines <- path
  directories <- files <- 0L
  while (length(pending)) {
    step <- pending[[length(pending)]]
    pending[[length(pending)]] <- NULL
    node <- step$node
    lines <- c(lines, paste0(step$prefix, if (step$last) "`-- " else "|-- ", node$name,
                             if (node$kind == "l") paste0(" -> ", node$target) else ""))
    if (node$kind == "d") {
      directories <- directories + 1L
      pending <- c(pending, frames(node, paste0(step$prefix, if (step$last) "    " else "|   ")))
    } else files <- files + 1L
  }
  emit(output, c(lines, paste(number(directories), if (directories == 1L) "directory," else "directories,",
                              number(files), if (files == 1L) "file" else "files")))
}

read_inputs <- function(shell, command, paths, input, consume) {
  if (!length(paths)) { consume(input, NULL); return(invisible(NULL)) }
  for (path in paths) {
    result <- resolve(shell, path)
    if (is.null(result$node)) terminal(sprintf("%s: %s: %s", command, path, result$problem))
    else if (result$node$kind == "d") terminal(sprintf("%s: %s: Is a directory", command, path))
    else consume(result$node$lines, path)
  }
}
word_count <- function(line) sum(nzchar(strsplit(line, " ", fixed = TRUE)[[1L]]))
numeric_prefix <- function(line) {
  match <- regexpr("^-?[0-9]+", line, perl = TRUE)
  if (match[1L] == -1L) return(0L)
  as.integer(substr(line, 1L, attr(match, "match.length")))
}
text_command <- function(shell, command, arguments, input, output) {
  options <- options_of(arguments)
  flags <- options$flags
  paths <- options$paths
  if (command == "grep") {
    pattern <- paths[1L]
    paths <- paths[-1L]
    if ("i" %in% flags) pattern <- chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", pattern)
    named <- "r" %in% flags || length(paths) > 1L
    consume <- function(lines, name) {
      comparison <- if ("i" %in% flags) chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", lines) else lines
      selected <- grepl(pattern, comparison, fixed = TRUE, useBytes = TRUE)
      if ("v" %in% flags) selected <- !selected
      prefix <- if (named) paste0(name, ":") else ""
      if ("c" %in% flags) emit(output, paste0(prefix, number(sum(selected))))
      else if (any(selected)) emit(output, paste0(prefix, if ("n" %in% flags) paste0(which(selected), ":") else "", lines[selected]))
    }
    if (!("r" %in% flags)) read_inputs(shell, command, paths, input, consume)
    else {
      if (!length(paths)) paths <- "."
      for (path in paths) {
        result <- resolve(shell, path)
        if (is.null(result$node)) { terminal(sprintf("grep: %s: %s", path, result$problem)); next }
        for (row in visits(result$node, path)) if (row$node$kind == "f") consume(row$node$lines, row$path)
      }
    }
  } else if (command == "sort") {
    gathered <- new_output(FALSE)
    read_inputs(shell, command, paths, input, function(lines, name) emit(gathered, lines))
    lines <- output_lines(gathered)
    ordering <- if ("n" %in% flags) order(vapply(lines, numeric_prefix, integer(1)), lines, method = "radix") else order(lines, method = "radix")
    if ("r" %in% flags) ordering <- rev(ordering)
    emit(output, lines[ordering])
  } else if (command == "wc") {
    selected <- c("l", "w", "c") %in% flags
    if (!any(selected)) selected[] <- TRUE
    report <- function(counts, name) emit(output, paste0(paste(number(counts[selected]), collapse = " "), if (is.null(name)) "" else paste0(" ", name)))
    totals <- numeric(3L)
    read_inputs(shell, command, paths, input, function(lines, name) {
      counts <- c(as.double(length(lines)), sum(vapply(lines, word_count, integer(1))), sum(as.double(nchar(lines, type = "bytes")) + 1))
      totals <<- totals + counts
      report(counts, name)
    })
    if (length(paths) > 1L) report(totals, "total")
  } else if (command %in% c("head", "tail")) {
    explicit <- length(arguments) > 0L && arguments[1L] == "-n"
    raw <- if (explicit) arguments[2L] else "10"
    paths <- if (explicit) arguments[-seq_len(2L)] else arguments
    special <- startsWith(raw, "-") || startsWith(raw, "+")
    count <- as.integer(if (special) substring(raw, 2L) else raw)
    read_inputs(shell, command, paths, input, function(lines, name) {
      start <- 0L
      stop <- length(lines)
      if (command == "head") stop <- if (special) max(0L, stop - count) else min(stop, count)
      else start <- if (special) min(stop, max(0L, count - 1L)) else max(0L, stop - count)
      if (start < stop) emit(output, lines[seq.int(start + 1L, stop)])
    })
  } else read_inputs(shell, command, paths, input, function(lines, name) {
    if (command == "cat") emit(output, lines)
    else if (length(lines)) {
      groups <- rle(lines)
      emit(output, if ("c" %in% flags) paste(number(groups$lengths), groups$values) else groups$values)
    }
  })
}

execute <- function(shell, text, input, output) {
  words <- strsplit(text, " ", fixed = TRUE)[[1L]]
  command <- words[1L]
  arguments <- words[-1L]
  options <- options_of(arguments)
  flags <- options$flags
  paths <- options$paths
  if (command == "pwd") emit(output, absolute(shell, shell$current))
  else if (command == "echo") emit(output, substring(text, 6L))
  else if (command == "cd") {
    path <- if (length(arguments)) arguments[1L] else "/"
    previous <- path == "-"
    if (previous) {
      if (is.null(shell$previous)) { terminal("cd: OLDPWD not set"); return(invisible(NULL)) }
      path <- shell$previous
    }
    result <- resolve(shell, path)
    if (is.null(result$node)) terminal(sprintf("cd: %s: %s", path, result$problem))
    else if (result$node$kind != "d") terminal(sprintf("cd: %s: Not a directory", path))
    else {
      shell$previous <- absolute(shell, shell$current)
      shell$current <- result$node
      if (previous) emit(output, absolute(shell, shell$current))
    }
  } else if (command == "mkdir") for (path in paths) {
    result <- resolve(shell, path, FALSE, "p" %in% flags)
    if (!is.null(result$parent)) create_node(shell, result$parent, result$name, "d")
    else if (is.null(result$node)) terminal(sprintf("mkdir: cannot create directory '%s': %s", path, result$problem))
    else {
      directory <- NULL
      if ("p" %in% flags) directory <- resolve(shell, path)$node
      if (is.null(directory) || directory$kind != "d") terminal(sprintf("mkdir: cannot create directory '%s': File exists", path))
    }
  } else if (command == "touch") for (path in arguments) {
    result <- resolve(shell, path)
    if (!is.null(result$parent)) create_node(shell, result$parent, result$name, "f")
    else if (is.null(result$node)) terminal(sprintf("touch: cannot touch '%s': %s", path, result$problem))
    else result$node$modified <- shell$clock
  } else if (command == "ls") listing(shell, options, output)
  else if (command == "stat") for (path in arguments) {
    result <- resolve(shell, path, FALSE)
    node <- result$node
    if (is.null(node)) { terminal(sprintf("stat: cannot stat '%s': %s", path, result$problem)); next }
    kind <- switch(node$kind, d = "directory", l = "symbolic link", f = if (length(node$lines)) "regular file" else "regular empty file")
    emit(output, sprintf("%s: %s, size %s, inode %s, links %s, modified %s", path, kind, number(node_size(node)),
                         number(node$inode), number(link_count(node)), number(node$modified)))
  } else if (command %in% c("rm", "rmdir")) for (path in paths) {
    directory_only <- command == "rmdir"
    dot <- last_component(path) %in% c(".", "..")
    if (dot && !directory_only) { terminal(sprintf("rm: refusing to remove '.' or '..' directory: skipping '%s'", path)); next }
    problem <- ""
    if (dot) problem <- "Invalid argument" else {
      result <- resolve(shell, path, FALSE)
      node <- result$node
      if (is.null(node)) {
        if (!directory_only && "f" %in% flags && result$problem == "No such file or directory") next
        problem <- result$problem
      } else if (directory_only && node$kind != "d") problem <- "Not a directory"
      else if (!directory_only && node$kind == "d" && !("r" %in% flags)) problem <- "Is a directory"
      else if (descendant(shell, shell$current, node)) problem <- "Device or resource busy"
      else if (directory_only && length(node$entries)) problem <- "Directory not empty"
      else detach(shell, node)
    }
    if (nzchar(problem)) terminal(sprintf(if (directory_only) "rmdir: failed to remove '%s': %s" else "rm: cannot remove '%s': %s", path, problem))
  } else if (command %in% c("mv", "cp")) {
    destination <- tail(paths, 1L)
    if (length(paths) > 2L) {
      node <- resolve(shell, destination)$node
      if (is.null(node) || node$kind != "d") { terminal(sprintf("%s: target '%s' is not a directory", command, destination)); return(invisible(NULL)) }
    }
    for (path in head(paths, -1L)) {
      if (command == "mv") move_one(shell, path, destination) else copy_one(shell, path, destination, "r" %in% flags)
    }
  } else if (command == "ln") {
    path <- arguments[3L]
    result <- resolve(shell, path, FALSE)
    if (!is.null(result$parent)) create_node(shell, result$parent, result$name, "l", target = arguments[2L])
    else terminal(sprintf("ln: failed to create symbolic link '%s': %s", path, if (is.null(result$node)) result$problem else "File exists"))
  } else if (command %in% c("readlink", "realpath")) {
    path <- arguments[1L]
    result <- resolve(shell, path, command == "realpath")
    if (is.null(result$node)) terminal(sprintf("%s: %s: %s", command, path, result$problem))
    else if (command == "realpath") emit(output, absolute(shell, result$node))
    else if (result$node$kind == "l") emit(output, result$node$target)
    else terminal(sprintf("readlink: %s: Invalid argument", path))
  } else if (command == "find") find_nodes(shell, arguments, output)
  else if (command == "du") disk_usage(shell, options, output)
  else if (command == "tree") draw_tree(shell, options, output)
  else if (command %in% c("cat", "wc", "head", "tail", "grep", "sort", "uniq")) text_command(shell, command, arguments, input, output)
  else terminal(paste0(command, ": command not found"))
  invisible(NULL)
}
process_line <- function(shell, line) {
  shell$clock <- shell$clock + 1L
  terminal(paste0(absolute(shell, shell$current), "$ ", line))
  marker <- regexpr(" >", line, fixed = TRUE)[1L]
  pipeline <- line
  redirect <- NULL
  if (marker != -1L) {
    pipeline <- substr(line, 1L, marker - 1L)
    append <- startsWith(substring(line, marker), " >> ")
    path <- substring(line, marker + if (append) 4L else 3L)
    result <- resolve(shell, path)
    if (!is.null(result$parent)) redirect <- create_node(shell, result$parent, result$name, "f")
    else if (!is.null(result$node) && result$node$kind == "f") {
      redirect <- result$node
      if (!append) write_file(shell, redirect, character())
    } else {
      terminal(sprintf("sh: %s: %s", path, if (is.null(result$node)) result$problem else "Is a directory"))
      return(invisible(NULL))
    }
  }
  commands <- strsplit(pipeline, " | ", fixed = TRUE)[[1L]]
  input <- character()
  for (index in seq_along(commands)) {
    output <- new_output(index == length(commands) && is.null(redirect))
    execute(shell, commands[index], input, output)
    input <- output_lines(output)
  }
  if (!is.null(redirect) && length(input)) write_file(shell, redirect, input, TRUE)
  invisible(NULL)
}
main <- function() {
  shell <- new_shell()
  input <- file("stdin", open = "r")
  on.exit(close(input))
  repeat {
    line <- readLines(input, n = 1L, warn = FALSE)
    if (!length(line) || line == "exit") break
    process_line(shell, line)
  }
}
main()
