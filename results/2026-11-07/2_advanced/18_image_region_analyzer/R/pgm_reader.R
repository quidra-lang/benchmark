read_images <- function(path) {
  lines <- readLines(path, warn = FALSE)
  content <- sub("#.*$", "", lines)
  words <- unlist(strsplit(content, " ", fixed = TRUE), use.names = FALSE)
  words <- words[nzchar(words)]
  images <- list()
  position <- 1L
  while (position <= length(words)) {
    name <- words[position + 1L]
    width <- as.integer(words[position + 3L])
    height <- as.integer(words[position + 4L])
    maxval <- as.integer(words[position + 5L])
    position <- position + 6L
    count <- width * height
    values <- as.numeric(words[seq.int(position, length.out = count)])
    pixels <- matrix(values, nrow = height, ncol = width, byrow = TRUE)
    position <- position + count
    images[[length(images) + 1L]] <- list(name = name, width = width, height = height, maxval = maxval, pixels = pixels)
  }
  images
}
