minstd <- function(seed) {
  state <- as.numeric(seed)
  draw <- function() {
    state <<- (48271 * state) %% 2147483647
    state
  }
  below <- function(limit) draw() %% limit
  shuffle <- function(items) {
    if (length(items) >= 2L) {
      for (index in seq.int(length(items), 2L)) {
        other <- below(index) + 1L
        saved <- items[index]
        items[index] <- items[other]
        items[other] <- saved
      }
    }
    items
  }
  list(draw = draw, below = below, shuffle = shuffle)
}
