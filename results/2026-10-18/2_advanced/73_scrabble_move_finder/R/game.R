TILE_ORDER <- c(LETTERS,"?")
new_minstd <- function(seed) {
  random <- new.env(parent=emptyenv())
  random$state <- seed
  random
}
next_random <- function(random) {
  next_state <- 48271L*(random$state %% 44488L)-3399L*(random$state %/% 44488L)
  if (next_state <= 0L) next_state <- next_state+2147483647L
  random$state <- next_state
  next_state
}
shuffle_bag <- function(bag,random) {
  if (length(bag$tiles) > 1L) for (i in seq.int(length(bag$tiles),2L)) {
    j <- next_random(random) %% i+1L
    saved <- bag$tiles[i]
    bag$tiles[i] <- bag$tiles[j]
    bag$tiles[j] <- saved
  }
  invisible(NULL)
}
make_bag <- function(counts,random) {
  bag <- new.env(parent=emptyenv())
  bag$tiles <- rep(TILE_ORDER,counts)
  shuffle_bag(bag,random)
  bag
}
draw_tiles <- function(bag,n) {
  drawn <- character()
  for (i in seq_len(min(n,length(bag$tiles)))) {
    drawn <- c(drawn,tail(bag$tiles,1L))
    bag$tiles <- bag$tiles[-length(bag$tiles)]
  }
  paste(drawn,collapse="")
}
exchange_tiles <- function(bag,returned,random) {
  drawn <- draw_tiles(bag,nchar(returned))
  bag$tiles <- c(bag$tiles,sort(strsplit(returned,"",fixed=TRUE)[[1L]],method="radix"))
  shuffle_bag(bag,random)
  drawn
}
collection_points <- function(collection,values) sum(values[tile_index(strsplit(
    collection,
    "",
    fixed=TRUE
)[[1L]])])
