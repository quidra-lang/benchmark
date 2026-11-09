state <- new.env(parent = emptyenv())
state$commits <- list()
state$sequence <- 0
state$branches <- list()
state$tags <- list()
state$branch <- "main"
state$detached <- NULL
state$work <- list()
state$index <- list()
state$conflicts <- character()
state$operation <- NULL
state$stash <- list()
state$ignores <- character()

say <- function(...) cat(paste0(...), "\n", sep = "")
fail <- function(message) {
  stop(structure(list(message = message, call = NULL),
                 class = c("VcsError", "error", "condition")))
}
ordered <- function(x) sort(unique(x), method = "radix")
paths <- function(...) ordered(unlist(lapply(list(...), names), use.names = FALSE))
differences <- function(a, b) {
  selected <- paths(a, b)
  selected[vapply(selected, function(p) !identical(a[[p]], b[[p]]), logical(1))]
}
equal_trees <- function(a, b) length(differences(a, b)) == 0L
match_path <- function(destination, source, path) {
  destination[path] <- source[path]
  if (is.null(source[[path]])) destination[[path]] <- NULL
  destination
}
head_id <- function() {
  if (is.null(state$branch)) state$detached else state$branches[[state$branch]]
}
commit_at <- function(id) state$commits[[id]]
head_commit <- function() commit_at(head_id())
move_head <- function(id) {
  if (is.null(state$branch)) state$detached <- id else state$branches[[state$branch]] <- id
}
create_commit <- function(parents, tree, message) {
  lines <- c(paste("commit", state$sequence),
             if (length(parents)) paste("parent", parents),
             vapply(paths(tree), function(p) paste("file", p, tree[[p]]), character(1)),
             paste("message", message))
  text <- paste0(paste(lines, collapse = "\n"), "\n")
  hash <- 0
  for (code in as.integer(charToRaw(text))) hash <- (hash * 131 + code) %% 2147483647
  id <- sprintf("%08x", as.integer(hash))
  state$commits[[id]] <- list(id = id, seq = state$sequence, parents = parents,
                              tree = tree, message = message)
  state$sequence <- state$sequence + 1
  id
}
record_commit <- function(parents, tree, message) {
  old <- commit_at(parents[[1]])$tree
  changed <- differences(old, tree)
  added <- sum(vapply(changed, function(p) is.null(old[[p]]), logical(1)))
  deleted <- sum(vapply(changed, function(p) is.null(tree[[p]]), logical(1)))
  modified <- length(changed) - added - deleted
  id <- create_commit(parents, tree, message)
  move_head(id)
  location <- if (is.null(state$branch)) "detached HEAD" else state$branch
  say("[", location, " ", id, "] ", message, " (", added, " added, ", modified,
      " modified, ", deleted, " deleted)")
}
resolve <- function(revision) {
  parts <- strsplit(revision, "~", fixed = TRUE)[[1]]
  anchor <- parts[[1]]
  id <- if (anchor == "HEAD") head_id() else state$branches[[anchor]]
  if (is.null(id)) id <- state$tags[[anchor]]
  if (is.null(id) && !is.null(commit_at(anchor))) id <- anchor
  steps <- if (length(parts) == 1L) 0L else as.integer(parts[[2]])
  if (steps > 0L) {
    for (i in seq_len(steps)) {
      if (!is.null(id)) {
        parents <- commit_at(id)$parents
        id <- if (length(parents)) parents[[1]] else NULL
      }
    }
  }
  if (is.null(id)) fail(paste0("unknown revision '", revision, "'"))
  id
}
distances <- function(id) {
  result <- list()
  result[[id]] <- 0L
  queue <- id
  at <- 1L
  while (at <= length(queue)) {
    current <- queue[[at]]
    at <- at + 1L
    for (parent in commit_at(current)$parents) {
      if (is.null(result[[parent]])) {
        result[[parent]] <- result[[current]] + 1L
        queue <- c(queue, parent)
      }
    }
  }
  result
}
ancestor <- function(a, b) !is.null(distances(b)[[a]])
merge_base <- function(a, b) {
  da <- distances(a)
  db <- distances(b)
  common <- intersect(names(da), names(db))
  candidates <- common[!vapply(common, function(x) {
    any(vapply(setdiff(common, x), function(y) ancestor(x, y), logical(1)))
  }, logical(1))]
  scores <- vapply(candidates, function(x) max(da[[x]], db[[x]]), integer(1))
  sequences <- vapply(candidates, function(x) commit_at(x)$seq, numeric(1))
  candidates[[order(scores, -sequences)[[1]]]]
}
summary_line <- function(id) {
  refs <- character()
  if (head_id() == id) refs <- c(refs, if (is.null(state$branch)) "HEAD" else paste("HEAD ->", state$branch))
  for (name in paths(state$branches)) {
    if (state$branches[[name]] == id && (is.null(state$branch) || name != state$branch)) refs <- c(refs, name)
  }
  for (name in paths(state$tags)) {
    if (state$tags[[name]] == id) refs <- c(refs, paste0("tag: ", name))
  }
  paste0(id, if (length(refs)) paste0(" (", paste(refs, collapse = ", "), ")") else "",
         " ", commit_at(id)$message)
}
changes <- function(a, b) {
  changed <- differences(a, b)
  if (!length(changed)) say("(no changes)")
  for (p in changed) {
    if (is.null(a[[p]])) {
      say("A ", p, ": ", b[[p]])
    } else if (is.null(b[[p]])) {
      say("D ", p, ": ", a[[p]])
    } else {
      say("M ", p, ": ", a[[p]], " -> ", b[[p]])
    }
  }
}
check_progress <- function() {
  if (!is.null(state$operation)) fail(paste(state$operation$kind, "in progress"))
}
uncommitted <- function() {
  !equal_trees(state$index, head_commit()$tree) ||
    any(vapply(paths(state$index), function(p) !identical(state$work[[p]], state$index[[p]]), logical(1)))
}
check_uncommitted <- function() {
  if (uncommitted()) fail("uncommitted changes")
}
check_overwrite <- function(selected) {
  h <- head_commit()$tree
  for (p in ordered(selected)) {
    if (!identical(state$index[[p]], h[[p]]) || !identical(state$work[[p]], h[[p]])) {
      fail(paste0("local changes to '", p, "' would be overwritten"))
    }
  }
}
switch_tree <- function(tree) {
  changed <- differences(head_commit()$tree, tree)
  check_overwrite(changed)
  for (p in changed) {
    state$index <- match_path(state$index, tree, p)
    state$work <- match_path(state$work, tree, p)
  }
}
merge_trees <- function(base, ours, theirs) {
  result <- list()
  conflicts <- character()
  markers <- list()
  for (p in paths(base, ours, theirs)) {
    b <- base[[p]]
    o <- ours[[p]]
    t <- theirs[[p]]
    if (identical(t, b) || identical(o, t)) {
      result <- match_path(result, ours, p)
    } else if (identical(o, b)) {
      result <- match_path(result, theirs, p)
    } else {
      conflicts <- c(conflicts, p)
      result <- match_path(result, ours, p)
      markers[[p]] <- paste0("<<<<<<< ", if (is.null(o)) "(deleted)" else o,
                             " ======= ", if (is.null(t)) "(deleted)" else t, " >>>>>>>")
    }
  }
  list(tree = result, conflicts = conflicts, markers = markers)
}
apply_change <- function(base, theirs, kind, target, message, parents, merge_base_id = NULL) {
  merged <- merge_trees(base, head_commit()$tree, theirs)
  changed <- differences(head_commit()$tree, merged$tree)
  check_overwrite(c(changed, merged$conflicts))
  if (kind == "merge") say("Merge base ", merge_base_id)
  if (kind != "merge" && !length(merged$conflicts) && equal_trees(merged$tree, head_commit()$tree)) {
    say("nothing to commit")
    return(invisible(NULL))
  }
  for (p in changed) {
    state$index <- match_path(state$index, merged$tree, p)
    state$work <- match_path(state$work, merged$tree, p)
  }
  if (!length(merged$conflicts)) {
    record_commit(parents, merged$tree, message)
  } else {
    for (p in merged$conflicts) {
      state$work[[p]] <- merged$markers[[p]]
      say("CONFLICT ", p)
    }
    state$conflicts <- merged$conflicts
    state$operation <- list(kind = kind, target = target)
    say(switch(kind, merge = "Automatic merge failed; fix conflicts and then commit the result.",
               revert = paste("error: could not revert", target),
               paste("error: could not apply", target)))
  }
}
ignored <- function(path) {
  is.null(state$index[[path]]) && !(path %in% state$conflicts) &&
    any(vapply(state$ignores, function(pattern) grepl(pattern, path, perl = TRUE), logical(1)))
}
pathspec <- function(path) fail(paste0("pathspec '", path, "' did not match any files"))
missing_path <- function(path, revision) fail(paste0("path '", path, "' does not exist in '", revision, "'"))
head_report <- function() say("HEAD is now at ", head_id(), " ", head_commit()$message)
status <- function() {
  h <- head_commit()$tree
  say(if (is.null(state$branch)) paste("HEAD detached at", head_id()) else paste("On branch", state$branch))
  if (!is.null(state$operation)) {
    labels <- c(merge = "Merging", revert = "Reverting", `cherry-pick` = "Cherry-picking")
    say(labels[[state$operation$kind]], " ", state$operation$target)
  }
  lines <- character()
  for (p in ordered(c(paths(h, state$index, state$work), state$conflicts))) {
    if (p %in% state$conflicts) {
      lines <- c(lines, paste("UU", p))
    } else if (!is.null(state$index[[p]])) {
      x <- if (is.null(h[[p]])) "A" else if (!identical(h[[p]], state$index[[p]])) "M" else "."
      y <- if (is.null(state$work[[p]])) "D" else if (!identical(state$work[[p]], state$index[[p]])) "M" else "."
      if (x != "." || y != ".") lines <- c(lines, paste0(x, y, " ", p))
    } else {
      if (!is.null(h[[p]])) lines <- c(lines, paste("D.", p))
      if (!is.null(state$work[[p]]) && !ignored(p)) lines <- c(lines, paste("??", p))
    }
  }
  if (!length(lines)) lines <- "nothing to commit, working tree clean"
  for (line in lines) say(line)
}
rebase <- function(target) {
  check_progress()
  if (ancestor(target, head_id())) {
    say("Already up to date")
    return(invisible(NULL))
  }
  check_uncommitted()
  history <- character()
  current <- head_id()
  while (!ancestor(current, target)) {
    history <- c(history, current)
    current <- commit_at(current)$parents[[1]]
  }
  history <- rev(history)
  tree <- commit_at(target)$tree
  actions <- list()
  for (id in history) {
    old <- commit_at(id)
    merged <- merge_trees(commit_at(old$parents[[1]])$tree, tree, old$tree)
    if (length(merged$conflicts)) fail(paste0("could not rebase ", id, ": conflict in '", merged$conflicts[[1]], "'"))
    if (equal_trees(merged$tree, tree)) {
      actions[[length(actions) + 1L]] <- list(id = id, pick = FALSE)
    } else {
      tree <- merged$tree
      actions[[length(actions) + 1L]] <- list(id = id, pick = TRUE, tree = tree)
    }
  }
  switch_tree(tree)
  for (action in actions) {
    old <- commit_at(action$id)
    if (action$pick) {
      fresh <- create_commit(target, action$tree, old$message)
      say("pick ", old$id, " -> ", fresh, " ", old$message)
      target <- fresh
    } else {
      say("skip ", old$id, " ", old$message)
    }
  }
  move_head(target)
  head_report()
}
stash_command <- function(action) {
  if (identical(action, "LIST")) {
    if (!length(state$stash)) say("(no stash entries)")
    for (i in seq_along(state$stash)) say("stash@{", i - 1L, "}: ", state$stash[[i]]$label)
  } else if (identical(action, "DROP")) {
    if (!length(state$stash)) fail("no stash entries")
    entry <- state$stash[[1]]
    state$stash <- state$stash[-1]
    say("Dropped stash@{0}: ", entry$label)
  } else if (identical(action, "POP")) {
    if (!length(state$stash)) fail("no stash entries")
    check_progress()
    check_uncommitted()
    entry <- state$stash[[1]]
    merged <- merge_trees(commit_at(entry$base)$tree, head_commit()$tree, entry$tree)
    if (length(merged$conflicts)) fail(paste0("stash conflict in '", merged$conflicts[[1]], "'"))
    changed <- differences(head_commit()$tree, merged$tree)
    check_overwrite(changed)
    for (p in changed) state$work <- match_path(state$work, merged$tree, p)
    state$stash <- state$stash[-1]
    say("Restored stash@{0}: ", entry$label)
    changes(head_commit()$tree, merged$tree)
  } else {
    check_progress()
    if (!uncommitted()) {
      say("No local changes to save")
      return(invisible(NULL))
    }
    selected <- paths(state$index, head_commit()$tree)
    saved <- list()
    for (p in selected) {
      saved <- match_path(saved, state$work, p)
      state$work <- match_path(state$work, head_commit()$tree, p)
    }
    state$index <- head_commit()$tree
    location <- if (is.null(state$branch)) "(no branch)" else state$branch
    label <- paste0("WIP on ", location, ": ", head_id(), " ", head_commit()$message)
    state$stash <- c(list(list(label = label, base = head_id(), tree = saved)), state$stash)
    say("Saved stash@{0}: ", label)
  }
}
reachable <- function(roots) {
  result <- character()
  for (id in roots) result <- union(result, names(distances(id)))
  result
}
graph <- function() {
  live <- reachable(c(head_id(), unlist(state$branches), unlist(state$tags)))
  sequences <- vapply(live, function(id) commit_at(id)$seq, numeric(1))
  lanes <- character()
  for (id in live[order(-sequences)]) {
    if (!(id %in% lanes)) lanes <- c(lanes, id)
    first <- match(id, lanes)
    symbols <- ifelse(lanes == id, "/", "|")
    symbols[[first]] <- "*"
    say(paste(symbols, collapse = " "), " ", summary_line(id))
    lanes <- lanes[lanes != id | seq_along(lanes) == first]
    parents <- commit_at(id)$parents
    if (!length(parents)) {
      lanes <- lanes[-first]
    } else {
      lanes[[first]] <- parents[[1]]
      if (length(parents) == 2L && !(parents[[2]] %in% lanes)) lanes <- append(lanes, parents[[2]], after = first)
    }
  }
}
execute <- function(line) {
  words <- strsplit(line, " ", fixed = TRUE)[[1]]
  command <- words[[1]]
  args <- words[-1]
  path <- if (length(args)) args[[1]] else NULL
  rest <- if (length(args)) substring(line, nchar(command) + 2L) else ""
  h <- head_commit()$tree
  switch(command,
    WRITE = {
      state$work[[path]] <- substring(rest, nchar(path) + 2L)
    },
    REMOVE = {
      if (is.null(state$work[[path]])) fail(paste0("no such file '", path, "'"))
      state$work[[path]] <- NULL
    },
    ADD = {
      if (path == "ALL") {
        selected <- paths(state$work, state$index)
        selected <- selected[!vapply(selected, ignored, logical(1))]
        for (p in selected) state$index <- match_path(state$index, state$work, p)
        state$conflicts <- character()
      } else {
        if (!is.null(state$work[[path]]) && ignored(path)) fail(paste0("path '", path, "' is ignored"))
        if (is.null(state$work[[path]]) && is.null(state$index[[path]]) && !(path %in% state$conflicts)) pathspec(path)
        state$index <- match_path(state$index, state$work, path)
        state$conflicts <- setdiff(state$conflicts, path)
      }
    },
    RM = {
      if (is.null(state$index[[path]])) pathspec(path)
      state$index[[path]] <- NULL
      state$work[[path]] <- NULL
      state$conflicts <- setdiff(state$conflicts, path)
    },
    UNSTAGE = {
      if (is.null(state$index[[path]]) && is.null(h[[path]])) pathspec(path)
      state$index <- match_path(state$index, h, path)
    },
    RESTORE = {
      if (length(args) == 1L) {
        if (is.null(state$index[[path]])) pathspec(path)
        state$work[[path]] <- state$index[[path]]
      } else {
        tree <- commit_at(resolve(args[[2]]))$tree
        if (is.null(tree[[path]])) missing_path(path, args[[2]])
        state$index[[path]] <- tree[[path]]
        state$work[[path]] <- tree[[path]]
        state$conflicts <- setdiff(state$conflicts, path)
      }
    },
    IGNORE = {
      chars <- strsplit(path, "", fixed = TRUE)[[1]]
      pieces <- vapply(chars, function(ch) {
        if (ch == "*") ".*" else if (ch == "?") "." else if (ch == ".") "\\." else ch
      }, character(1))
      state$ignores <- c(state$ignores, paste0("\\A", paste0(pieces, collapse = ""), "\\z"))
    },
    COMMIT = {
      if (length(state$conflicts)) fail("unresolved conflicts")
      if (!is.null(state$operation) && state$operation$kind == "merge") {
        record_commit(c(head_id(), state$operation$target), state$index, rest)
        state$operation <- NULL
      } else if (equal_trees(state$index, h)) {
        say("nothing to commit")
      } else {
        record_commit(head_id(), state$index, rest)
        state$operation <- NULL
      }
    },
    AMEND = {
      check_progress()
      if (!length(head_commit()$parents)) fail("cannot amend the root commit")
      record_commit(head_commit()$parents, state$index, rest)
    },
    STATUS = status(),
    LS = {
      tree <- if (length(args)) commit_at(resolve(path))$tree else state$work
      if (!length(tree)) say("(empty)")
      for (p in paths(tree)) say(p, " ", tree[[p]])
    },
    CAT = {
      revision <- if (length(args) == 2L) args[[2]] else NULL
      tree <- if (is.null(revision)) state$work else commit_at(resolve(revision))$tree
      if (is.null(tree[[path]])) {
        if (!is.null(revision)) missing_path(path, revision)
        fail(paste0("no such file '", path, "'"))
      }
      say(tree[[path]])
    },
    DIFF = {
      if (!length(args)) {
        target <- state$work[intersect(names(state$work), names(state$index))]
        changes(state$index, target)
      } else if (path == "STAGED") {
        changes(h, state$index)
      } else {
        a <- resolve(path)
        b <- resolve(args[[2]])
        changes(commit_at(a)$tree, commit_at(b)$tree)
      }
    },
    LOG = {
      current <- head_id()
      count <- 0L
      repeat {
        say(summary_line(current))
        count <- count + 1L
        parents <- commit_at(current)$parents
        if (!length(parents) || (!is.null(path) && count == as.integer(path))) break
        current <- parents[[1]]
      }
    },
    SHOW = {
      id <- resolve(if (is.null(path)) "HEAD" else path)
      commit <- commit_at(id)
      say("commit ", summary_line(id))
      say("parents: ", if (length(commit$parents)) paste(commit$parents, collapse = " ") else "none")
      changes(if (length(commit$parents)) commit_at(commit$parents[[1]])$tree else list(), commit$tree)
    },
    BLAME = {
      if (is.null(h[[path]])) missing_path(path, "HEAD")
      value <- h[[path]]
      id <- head_id()
      repeat {
        parents <- commit_at(id)$parents
        if (!length(parents) || !identical(commit_at(parents[[1]])$tree[[path]], value)) break
        id <- parents[[1]]
      }
      say(id, " (", commit_at(id)$message, ") ", value)
    },
    BRANCH = reference_command("branch", args),
    TAG = reference_command("tag", args),
    BRANCHES = {
      if (is.null(state$branch)) say("* (HEAD detached at ", head_id(), ")")
      for (name in paths(state$branches)) {
        id <- state$branches[[name]]
        mark <- if (!is.null(state$branch) && name == state$branch) "*" else " "
        say(mark, " ", name, " ", id, " ", commit_at(id)$message)
      }
    },
    TAGS = {
      if (!length(state$tags)) say("(no tags)")
      for (name in paths(state$tags)) {
        id <- state$tags[[name]]
        say(name, " ", id, " ", commit_at(id)$message)
      }
    },
    SWITCH = {
      if (is.null(state$branches[[path]])) fail(paste0("no such branch '", path, "'"))
      if (identical(state$branch, path)) {
        say("Already on '", path, "'")
      } else {
        check_progress()
        switch_tree(commit_at(state$branches[[path]])$tree)
        state$branch <- path
        say("Switched to branch '", path, "'")
      }
    },
    DETACH = {
      id <- resolve(path)
      check_progress()
      switch_tree(commit_at(id)$tree)
      state$branch <- NULL
      state$detached <- id
      head_report()
    },
    MERGE = {
      target <- resolve(path)
      check_progress()
      old <- head_id()
      if (ancestor(target, old)) {
        say("Already up to date")
      } else if (ancestor(old, target)) {
        switch_tree(commit_at(target)$tree)
        move_head(target)
        say("Fast-forward ", old, "..", target)
      } else {
        check_uncommitted()
        base <- merge_base(old, target)
        apply_change(commit_at(base)$tree, commit_at(target)$tree, "merge", target,
                     paste("Merge", path), c(old, target), base)
      }
    },
    MERGEBASE = {
      a <- resolve(path)
      b <- resolve(args[[2]])
      say(merge_base(a, b))
    },
    REBASE = rebase(resolve(path)),
    RESET = {
      id <- resolve(args[[2]])
      tree <- commit_at(id)$tree
      if (path == "HARD") {
        for (p in union(paths(state$index, tree), state$conflicts)) state$work <- match_path(state$work, tree, p)
      }
      if (path != "SOFT") state$index <- tree
      move_head(id)
      state$conflicts <- character()
      state$operation <- NULL
      head_report()
    },
    REVERT = revert_or_pick(path, TRUE),
    CHERRYPICK = revert_or_pick(path, FALSE),
    STASH = stash_command(path),
    GRAPH = graph(),
    DESCRIBE = {
      id <- resolve(if (is.null(path)) "HEAD" else path)
      distance <- distances(id)
      candidates <- paths(state$tags)
      candidates <- candidates[vapply(candidates, function(name) !is.null(distance[[state$tags[[name]]]]), logical(1))]
      if (!length(candidates)) fail(paste0("no tag can describe '", id, "'"))
      scores <- vapply(candidates, function(name) distance[[state$tags[[name]]]], integer(1))
      name <- candidates[[which.min(scores)]]
      d <- min(scores)
      say(if (d == 0L) name else paste0(name, "-", d, "-g", id))
    },
    GC = {
      roots <- c(head_id(), unlist(state$branches), unlist(state$tags),
                 vapply(state$stash, function(entry) entry$base, character(1)))
      if (!is.null(state$operation)) roots <- c(roots, state$operation$target)
      live <- reachable(roots)
      old_size <- length(state$commits)
      state$commits <- state$commits[intersect(names(state$commits), live)]
      say("Removed unreachable commits: ", old_size - length(state$commits))
    }
  )
}
reference_command <- function(kind, args) {
  refs <- if (kind == "branch") state$branches else state$tags
  if (args[[1]] == "-d") {
    name <- args[[2]]
    if (is.null(refs[[name]])) fail(paste0("no such ", kind, " '", name, "'"))
    if (kind == "branch") {
      if (identical(state$branch, name)) fail(paste0("cannot delete current branch '", name, "'"))
      if (!ancestor(refs[[name]], head_id())) fail(paste0("branch '", name, "' is not fully merged"))
    }
    id <- refs[[name]]
    refs[[name]] <- NULL
    say("Deleted ", kind, " ", name, " (was ", id, ")")
  } else {
    name <- args[[1]]
    if (!is.null(refs[[name]])) fail(paste0(kind, " '", name, "' already exists"))
    id <- resolve(if (length(args) == 2L) args[[2]] else "HEAD")
    refs[[name]] <- id
    say("Created ", kind, " ", name, " at ", id)
  }
  if (kind == "branch") state$branches <- refs else state$tags <- refs
}
revert_or_pick <- function(revision, revert) {
  id <- resolve(revision)
  check_progress()
  check_uncommitted()
  commit <- commit_at(id)
  parent_tree <- if (length(commit$parents)) commit_at(commit$parents[[1]])$tree else list()
  if (revert) {
    apply_change(commit$tree, parent_tree, "revert", id, paste0('Revert "', commit$message, '"'), head_id())
  } else {
    apply_change(parent_tree, commit$tree, "cherry-pick", id, commit$message, head_id())
  }
}

root <- create_commit(character(), list(), "init")
state$branches$main <- root
input <- file("stdin", "r")
repeat {
  line <- readLines(input, n = 1L, warn = FALSE)
  if (!length(line) || line == "EXIT") break
  tryCatch(execute(line), VcsError = function(error) say("error: ", conditionMessage(error)))
}
