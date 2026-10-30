new_doc <- function(kind, value = "", children = list(), amount = 0L,
                    broken = "", flat = "", forced = FALSE) {
  new_record(kind = kind, value = value, children = children, amount = amount,
             broken = broken, flat = flat, forced = forced, mode = "unset")
}
doc_text <- function(value) new_doc("text", value = value)
LINE <- new_doc("line")
SOFTLINE <- new_doc("softline")
HARDLINE <- new_doc("hardline")
BREAK_PARENT <- new_doc("break_parent")
suffix <- function(value) new_doc("suffix", value = value)
if_break <- function(broken, flat) new_doc("if_break", broken = broken, flat = flat)
concat <- function(...) {
  elements <- list()
  add <- function(part) {
    if (is.null(part)) return(invisible(NULL))
    if (is.character(part)) part <- doc_text(part)
    if (is.list(part)) {
      for (child in part) add(child)
    } else if (part$kind == "concat") {
      for (child in part$children) add(child)
    } else if (part$kind == "text") {
      if (!nzchar(part$value)) return(invisible(NULL))
      size <- length(elements)
      if (size > 0L && elements[[size]]$kind == "text") {
        elements[[size]] <<- doc_text(paste0(elements[[size]]$value, part$value))
      } else {
        elements[[size + 1L]] <<- doc_text(part$value)
      }
    } else {
      elements[[length(elements) + 1L]] <<- part
    }
  }
  for (part in list(...)) add(part)
  if (!length(elements)) return(doc_text(""))
  if (length(elements) == 1L) elements[[1L]] else new_doc("concat", children = elements)
}
force_broken <- function(document) {
  document$kind %in% c("hardline", "break_parent") || any(vapply(document$children, force_broken, logical(1L)))
}
group <- function(child) {
  child <- concat(child)
  new_doc("group", children = list(child), forced = force_broken(child))
}
nest <- function(amount, child) new_doc("nest", children = list(concat(child)), amount = amount)
align_doc <- function(child) new_doc("align", children = list(concat(child)))
all_groups <- function(document) {
  if (is.null(document)) return(list())
  groups <- if (document$kind == "group") list(document) else list()
  for (child in document$children) groups <- c(groups, all_groups(child))
  groups
}
