new_trie <- function() {
  trie <- new.env(parent=emptyenv())
  trie$children <- list(integer(26L))
  trie$terminal <- FALSE
  trie$words <- 0L
  trie
}
tile_index <- function(letter) ifelse(letter == "?",27L,match(letter,LETTERS))
rack_counts <- function(rack) tabulate(tile_index(strsplit(rack,"",fixed=TRUE)[[1L]]),nbins=27L)
add_word <- function(trie,word) {
  node <- 1L
  for (letter in strsplit(word,"",fixed=TRUE)[[1L]]) {
    i <- tile_index(letter)
    if (trie$children[[node]][i] == 0L) {
      trie$children[[length(trie$children)+1L]] <- integer(26L)
      trie$terminal <- c(trie$terminal,FALSE)
      trie$children[[node]][i] <- length(trie$children)
    }
    node <- trie$children[[node]][i]
  }
  if (trie$terminal[node]) return(FALSE)
  trie$terminal[node] <- TRUE
  trie$words <- trie$words+1L
  TRUE
}
prefix_node <- function(trie,word) {
  node <- 1L
  for (letter in strsplit(word,"",fixed=TRUE)[[1L]]) {
    node <- trie$children[[node]][tile_index(letter)]
    if (node == 0L) break
  }
  node
}
has_word <- function(trie,word) {
  node <- prefix_node(trie,word)
  node != 0L && trie$terminal[node]
}
anagrams <- function(trie,rack) {
  counts <- rack_counts(rack)
  result <- character()
  visit <- function(node,word) {
    if (trie$terminal[node]) result <<- c(result,word)
    for (i in which(trie$children[[node]] != 0L)) {
      tile <- if (counts[i] > 0L) i else 27L
      if (counts[tile] > 0L) {
        counts[tile] <<- counts[tile]-1L
        visit(trie$children[[node]][i],paste0(word,LETTERS[i]))
        counts[tile] <<- counts[tile]+1L
      }
    }
  }
  visit(1L,"")
  result
}
