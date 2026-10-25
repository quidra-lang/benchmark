rail_numbers <- function(length, rails) {
  cycle <- 2L * rails - 2L
  offsets <- (seq_len(length) - 1L) %% cycle
  pmin(offsets, cycle - offsets)
}

rail_order <- function(length, rails) {
  order(rail_numbers(length, rails), seq_len(length), method = "radix")
}

rail_fence_transform <- function(text, key, decrypt = FALSE) {
  codes <- utf8ToInt(text)
  positions <- rail_order(length(codes), key)
  if (decrypt) {
    result <- integer(length(codes))
    result[positions] <- codes
  } else {
    result <- codes[positions]
  }
  intToUtf8(result)
}

column_ranks <- function(key) {
  codes <- utf8ToInt(key)
  ranks <- integer(length(codes))
  ranks[order(codes, seq_along(codes), method = "radix")] <- seq_along(codes)
  ranks
}

rank_string <- function(key) {
  paste(column_ranks(key), collapse = "")
}

columnar_order <- function(length, key) {
  positions <- seq_len(length)
  columns <- (positions - 1L) %% nchar(key) + 1L
  order(column_ranks(key)[columns], positions, method = "radix")
}

columnar_transform <- function(text, key, decrypt = FALSE) {
  codes <- utf8ToInt(text)
  positions <- columnar_order(length(codes), key)
  if (decrypt) {
    result <- integer(length(codes))
    result[positions] <- codes
  } else {
    result <- codes[positions]
  }
  intToUtf8(result)
}
