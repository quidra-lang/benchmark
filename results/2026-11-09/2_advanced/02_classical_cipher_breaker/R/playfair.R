SQUARE_LETTERS <- "ABCDEFGHIKLMNOPQRSTUVWXYZ"

build_square <- function(key) {
  intToUtf8(unique(c(utf8ToInt(key), utf8ToInt(SQUARE_LETTERS))))
}

prepare_playfair <- function(text) {
  codes <- utf8ToInt(chartr("J", "I", text))
  result <- integer(2L * length(codes))
  i <- 1L
  used <- 0L
  while (i <= length(codes)) {
    first <- codes[i]
    if (i < length(codes) && codes[i + 1L] != first) {
      second <- codes[i + 1L]
      i <- i + 2L
    } else {
      second <- if (first == 88L) 81L else 88L
      i <- i + 1L
    }
    result[used + 1L] <- first
    result[used + 2L] <- second
    used <- used + 2L
  }
  result[seq_len(used)]
}

playfair_pairs <- function(text) {
  text <- chartr("J", "I", text)
  starts <- 2L * seq_len(nchar(text) %/% 2L) - 1L
  substring(text, starts, starts + 1L)
}

valid_playfair <- function(text) {
  codes <- utf8ToInt(chartr("J", "I", text))
  if (length(codes) %% 2L != 0L) return(FALSE)
  starts <- 2L * seq_len(length(codes) %/% 2L) - 1L
  all(codes[starts] != codes[starts + 1L])
}

playfair_transform <- function(text, key, decrypt = FALSE) {
  codes <- if (decrypt) utf8ToInt(chartr("J", "I", text)) else prepare_playfair(text)
  square <- utf8ToInt(build_square(key))
  positions <- match(codes, square) - 1L
  rows <- positions %/% 5L
  columns <- positions %% 5L
  first <- 2L * seq_len(length(codes) %/% 2L) - 1L
  second <- first + 1L
  same_row <- rows[first] == rows[second]
  same_column <- !same_row & columns[first] == columns[second]
  row_positions <- c(first[same_row], second[same_row])
  column_positions <- c(first[same_column], second[same_column])
  step <- if (decrypt) 4L else 1L
  columns[row_positions] <- (columns[row_positions] + step) %% 5L
  rows[column_positions] <- (rows[column_positions] + step) %% 5L
  rectangle <- !same_row & !same_column
  columns[c(first[rectangle], second[rectangle])] <-
    columns[c(second[rectangle], first[rectangle])]
  intToUtf8(square[5L * rows + columns + 1L])
}
