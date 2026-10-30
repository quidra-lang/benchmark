STARTS <- c("if", "ifdef", "ifndef")
BRANCHES <- c("elif", "elifdef", "elifndef", "else")
directive_name <- function(tokens) if (length(tokens) >= 2L && tokens[[1L]]$spelling == "#" && tokens[[2L]]$kind == "identifier") tokens[[2L]]$spelling else NULL
detect_guard <- function(lines) {
  nonempty <- lapply(Filter(function(logical) length(logical$tokens) > 0L, lines), function(logical) logical$tokens)
  if (!length(nonempty)) return(NULL)
  first <- nonempty[[1L]]
  last <- nonempty[[length(nonempty)]]
  if (length(first) != 3L || !identical(directive_name(first), "ifndef") || first[[3L]]$kind != "identifier") return(NULL)
  if (length(last) != 2L || !identical(directive_name(last), "endif")) return(NULL)
  depth <- 0L
  for (index in seq_along(nonempty)) {
    name <- directive_name(nonempty[[index]])
    if (length(name) && name %in% BRANCHES && depth == 1L) return(NULL)
    if (length(name) && name %in% STARTS) depth <- depth + 1L else if (identical(name, "endif")) depth <- depth - 1L
    if (depth == 0L && index != length(nonempty)) return(NULL)
  }
  if (depth == 0L) first[[3L]]$spelling else NULL
}
new_include_manager <- function() new_record(files = new.env(hash = TRUE, parent = emptyenv()), order = character())
search_header <- function(name, quoted) {
  paths <- if (quoted) c(name, paste0("include/", name)) else paste0("include/", name)
  for (path in paths) {
    full <- file.path("input", path)
    if (file.exists(full) && !file.info(full)$isdir) return(path)
  }
  NULL
}
load_source <- function(manager, path) {
  if (!exists(path, manager$files, inherits = FALSE)) {
    full <- file.path("input", path)
    contents <- rawToChar(readBin(full, "raw", n = file.info(full)$size))
    lines <- lex_source(contents)
    source <- new_record(path = path, physical_lines = sum(strsplit(contents, "", fixed = TRUE)[[1L]] == "\n"),
                         lines = lines, guard = detect_guard(lines), once = FALSE,
                         entered = 0L, skipped = 0L, output_lines = 0L, skipped_lines = 0L)
    assign(path, source, manager$files)
    manager$order <- c(manager$order, path)
  }
  get(path, manager$files, inherits = FALSE)
}
