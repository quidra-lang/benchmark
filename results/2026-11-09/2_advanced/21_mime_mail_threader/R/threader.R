new_container <- function(id = "") {
  container <- new.env(parent = emptyenv())
  container$id <- id
  container$message <- container$parent <- container$subject <- NULL
  container$children <- list()
  container
}

adopt <- function(parent, child) {
  child$parent <- parent
  parent$children[[length(parent$children) + 1L]] <- child
}
ancestor_or_self <- function(container, other) {
  while (!is.null(other)) {
    if (identical(container, other)) return(TRUE)
    other <- other$parent
  }
  FALSE
}

new_threader <- function() {
  threader <- new.env(parent = emptyenv())
  threader$table <- new.env(hash = TRUE, parent = emptyenv())
  threader$containers <- list()
  threader
}
container_of <- function(threader, id) {
  if (!exists(id, envir = threader$table, inherits = FALSE)) {
    container <- new_container(id)
    assign(id, container, envir = threader$table)
    threader$containers[[length(threader$containers) + 1L]] <- container
  }
  get(id, envir = threader$table, inherits = FALSE)
}
threader_add <- function(threader, message) {
  container <- if (nzchar(message$id)) container_of(threader, message$id) else new_container()
  if (!nzchar(message$id)) threader$containers[[length(threader$containers) + 1L]] <- container
  container$message <- message
  references <- lapply(message$references, function(id) container_of(threader, id))
  if (length(references) > 1L) for (i in seq_len(length(references) - 1L)) {
    current <- references[[i]]
    following <- references[[i + 1L]]
    if (is.null(following$parent) && !ancestor_or_self(following, current)) adopt(current, following)
  }
  if (!is.null(container$parent)) {
    parent <- container$parent
    parent$children <- Filter(function(child) !identical(child, container), parent$children)
    container$parent <- NULL
  }
  if (length(references) > 0L && !ancestor_or_self(container, references[[length(references)]])) {
    adopt(references[[length(references)]], container)
  }
}

prune <- function(containers, at_root) {
  result <- list()
  for (container in containers) {
    container$children <- prune(container$children, FALSE)
    if (!is.null(container$message) || at_root && length(container$children) >= 2L) {
      result[[length(result) + 1L]] <- container
      next
    }
    for (child in container$children) child$parent <- if (at_root) NULL else container$parent
    result <- c(result, container$children)
  }
  result
}

message_order <- function(messages) {
  order(vapply(messages, function(message) is.null(message$date), logical(1)),
        vapply(messages, function(message) if (is.null(message$date)) 0 else message$date, numeric(1)),
        vapply(messages, function(message) message$id, character(1)),
        vapply(messages, function(message) message$number, integer(1)), method = "radix")
}
container_key <- function(container) {
  if (!is.null(container$message)) return(container$message)
  keys <- lapply(container$children, container_key)
  keys[[message_order(keys)[1L]]]
}
sort_containers <- function(containers) {
  for (container in containers) container$children <- sort_containers(container$children)
  if (length(containers) == 0L) return(containers)
  containers[message_order(lapply(containers, container_key))]
}
root_subject <- function(root) {
  if (!is.null(root$message)) root$message$base_subject else root$children[[1L]]$message$base_subject
}
merge_by_subject <- function(roots) {
  groups <- new.env(hash = TRUE, parent = emptyenv())
  subjects <- character()
  for (root in roots) {
    subject <- root_subject(root)
    if (nzchar(subject)) {
      if (!exists(subject, envir = groups, inherits = FALSE)) {
        subjects <- c(subjects, subject)
        assign(subject, list(), envir = groups)
      }
      assign(subject, c(get(subject, envir = groups), list(root)), envir = groups)
    }
  }
  merged <- Filter(function(root) {
    subject <- root_subject(root)
    !nzchar(subject) || length(get(subject, envir = groups)) == 1L
  }, roots)
  for (subject in subjects) {
    group <- get(subject, envir = groups)
    if (length(group) < 2L) next
    missing <- Filter(function(root) is.null(root$message), group)
    originals <- Filter(function(root) !is.null(root$message) && !root$message$reply, group)
    if (length(missing) > 0L) {
      target <- missing[[1L]]
    } else if (length(originals) == 1L) {
      target <- originals[[1L]]
    } else {
      target <- new_container()
      target$subject <- subject
    }
    for (root in group) {
      if (identical(root, target)) next
      if (!is.null(root$message)) adopt(target, root) else for (child in root$children) adopt(target, child)
    }
    merged[[length(merged) + 1L]] <- target
  }
  merged
}

build_threads <- function(messages) {
  threader <- new_threader()
  for (message in messages) threader_add(threader, message)
  roots <- Filter(function(container) is.null(container$parent), threader$containers)
  roots <- sort_containers(prune(roots, TRUE))
  sort_containers(merge_by_subject(roots))
}
