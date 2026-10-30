TYPES <- c("ABS32", "REL32", "ABS16", "HI16", "LO16", "GPREL16", "CALL24")
WIDTHS <- c(ABS32 = 4L, REL32 = 4L, ABS16 = 2L, HI16 = 2L, LO16 = 2L, GPREL16 = 2L, CALL24 = 3L)
RANGES <- list(ABS32 = c(-2 ^ 31, 2 ^ 32), REL32 = c(-2 ^ 31, 2 ^ 31), ABS16 = c(-2 ^ 15, 2 ^ 16),
               HI16 = c(-2 ^ 31, 2 ^ 32), GPREL16 = c(-2 ^ 15, 2 ^ 15), CALL24 = c(-2 ^ 25, 2 ^ 25))
unpaired_hi16 <- function(relocations, index) {
  current <- relocations[[index]]
  if (current$type != "HI16") return(FALSE)
  if (index == length(relocations)) return(TRUE)
  following <- relocations[[index + 1L]]
  !(following$type == "LO16" && identical(following$symbol, current$symbol) && following$addend == current$addend)
}
relocation_value <- function(type, symbol, addend, place, gp) {
  value <- symbol + addend
  if (type %in% c("REL32", "CALL24")) value <- value - place
  if (type == "GPREL16") value <- value - gp
  field <- if (type == "HI16") ((value %% 2 ^ 32 + 32768) %/% 65536) %% 65536 else if (type == "CALL24") (value %/% 4) %% 2 ^ 24 else value %% (2 ^ (8L * WIDTHS[[type]]))
  range <- RANGES[[type]]
  within_range <- is.null(range) || (range[[1L]] <= value && value < range[[2L]])
  list(value = value, field = field, within_range = within_range)
}
