read_dataset <- function() {
  read_csv <- function(path) lapply(strsplit(readLines(path)[-1L],",",fixed=TRUE),as.integer)
  points <- read_csv("input/points.csv")
  rectangles <- read_csv("input/rects.csv")
  rows <- strsplit(readLines("input/params.txt")," ",fixed=TRUE)
  parameters <- list(world=as.integer(rows[[1L]][2L]),bucket=as.integer(rows[[2L]][2L]),maximum=as.integer(rows[[3L]][2L]),
    minimum=as.integer(rows[[3L]][3L]),cell_size=as.integer(rows[[4L]][2L]))
  commands <- lapply(
      strsplit(readLines("input/queries.txt")," ",fixed=TRUE),
      function(words) list(name=words[1L],values=as.integer(words[-1L]))
  )
  list(points=points,rectangles=rectangles,parameters=parameters,commands=commands)
}
