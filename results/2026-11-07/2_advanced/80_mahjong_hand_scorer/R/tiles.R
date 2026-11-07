TILE_SUITS <- c("m", "p", "s", "z")
WINDS <- c("E", "S", "W", "N")
WIND_TILES <- setNames(27:30, WINDS)
YAOCHUU <- c(0L, 8L, 9L, 17L, 18L, 26L, 27L, 28L, 29L, 30L, 31L, 32L, 33L)
GREEN_TILES <- c(19L, 20L, 21L, 23L, 25L, 32L)

parse_tiles <- function(text, allow_empty = FALSE) {
    if (text == "-") return(if (allow_empty) list() else NULL)
    result <- list()
    digits <- integer()
    for (character in strsplit(text, "", fixed = TRUE)[[1L]]) {
        if (character >= "0" && character <= "9") {
            digits <- c(digits, as.integer(character))
        } else if (character %in% TILE_SUITS && length(digits)) {
            suit <- match(character, TILE_SUITS) - 1L
            for (digit in digits) {
                if (suit == 3L && (digit < 1L || digit > 7L)) return(NULL)
                number <- if (digit == 0L) 5L else digit
                result[[length(result) + 1L]] <- list(kind = suit * 9L + number - 1L, red = digit == 0L)
            }
            digits <- integer()
        } else {
            return(NULL)
        }
    }
    if (length(result) && !length(digits)) result else NULL
}

tile_name <- function(kind) paste0(kind %% 9L + 1L, TILE_SUITS[kind %/% 9L + 1L])
block_notation <- function(kinds) {
    ordered <- sort(kinds)
    paste0(paste0(ordered %% 9L + 1L, collapse = ""), TILE_SUITS[ordered[1L] %/% 9L + 1L])
}

tile_counts <- function(tiles) {
    counts <- integer(34L)
    for (tile in tiles) counts[tile$kind + 1L] <- counts[tile$kind + 1L] + 1L
    counts
}

is_honor <- function(kind) kind >= 27L
is_terminal <- function(kind) kind < 27L && kind %% 9L %in% c(0L, 8L)
is_yaochuu <- function(kind) is_honor(kind) || is_terminal(kind)
next_dora <- function(kind) {
    if (kind < 27L) return((kind %/% 9L) * 9L + (kind %% 9L + 1L) %% 9L)
    if (kind < 31L) return(27L + (kind - 26L) %% 4L)
    31L + (kind - 30L) %% 3L
}
