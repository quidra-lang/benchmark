AFFINE_MULTIPLIERS <- c(1L, 3L, 5L, 7L, 9L, 11L, 15L, 17L, 19L, 21L, 23L, 25L)

replace_letters <- function(text, values) {
  codes <- utf8ToInt(text)
  positions <- which(is_letter(codes))
  bases <- 65L + 32L * as.integer(codes[positions] >= 97L)
  codes[positions] <- bases + values
  intToUtf8(codes)
}

caesar_transform <- function(text, key, decrypt = FALSE) {
  shift <- if (decrypt) -key else key
  replace_letters(text, (letter_values(text) + shift) %% 26L)
}

modular_inverse <- function(multiplier) {
  inverses <- seq_len(25L)
  inverses[which((multiplier * inverses) %% 26L == 1L)[1L]]
}

affine_transform <- function(text, key, decrypt = FALSE) {
  values <- letter_values(text)
  if (decrypt) {
    values <- modular_inverse(key[1L]) * (values - key[2L])
  } else {
    values <- key[1L] * values + key[2L]
  }
  replace_letters(text, values %% 26L)
}

vigenere_transform <- function(text, key, decrypt = FALSE) {
  values <- letter_values(text)
  shifts <- rep_len(letter_values(key), length(values))
  if (decrypt) shifts <- -shifts
  replace_letters(text, (values + shifts) %% 26L)
}

autokey_transform <- function(text, key, decrypt = FALSE) {
  values <- letter_values(text)
  shifts <- letter_values(key)
  if (decrypt) {
    plain <- integer(length(values))
    for (i in seq_along(values)) {
      shift <- if (i <= length(shifts)) shifts[i] else plain[i - length(shifts)]
      plain[i] <- (values[i] - shift) %% 26L
    }
    values <- plain
  } else {
    stream <- c(shifts, values)[seq_along(values)]
    values <- (values + stream) %% 26L
  }
  replace_letters(text, values)
}
