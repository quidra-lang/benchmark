LOT_RULES <- c("LFL", "FOQ", "POQ", "MIN")

lot_values <- function(rule, text) {
  values <- as.numeric(strsplit(text, "/", fixed = TRUE)[[1L]])
  fits <- if (rule == "LFL") length(values) == 1L && values[1L] == 0 else if (rule == "MIN") {
    length(values) == 2L && all(values >= 1)
  } else length(values) == 1L && values[1L] >= 1
  if (fits) values else NULL
}

lot_label <- function(item) {
  if (item$rule == "LFL") return("LFL")
  paste(item$rule, paste(integer_text(item$lot), collapse = if (item$rule == "MIN") "/" else ""))
}

read_items <- function(errors) {
  items <- list()
  for (row in read_rows("items.csv")) {
    fields <- row$fields
    id <- fields[1L]
    rule <- fields[3L]
    reason <- if (id %in% names(items)) paste("duplicate item", id) else if (!rule %in% LOT_RULES) paste("unknown lot rule", rule) else NULL
    lot <- if (is.null(reason)) lot_values(rule, fields[4L]) else NULL
    if (is.null(reason) && is.null(lot)) reason <- paste("bad lot parameter", fields[4L], "for", rule)
    if (!is.null(reason)) {
      record_error(errors, "items.csv", row$line, reason)
      next
    }
    items[[id]] <- list(id = id, lead_time = as.integer(fields[2L]), rule = rule, lot = lot,
                        safety_stock = as.numeric(fields[5L]), on_hand = as.numeric(fields[6L]),
                        material = as.numeric(fields[7L]), labor = as.numeric(fields[8L]), description = fields[9L])
  }
  items
}
