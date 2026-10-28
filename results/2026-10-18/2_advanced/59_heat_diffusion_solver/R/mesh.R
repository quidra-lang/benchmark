LEFT <- 1L
RIGHT <- 2L
TOP <- 3L
BOTTOM <- 4L
EDGE_FACES <- c(left=LEFT,right=RIGHT,top=TOP,bottom=BOTTOM)
cell <- function(plate,row,column) row*plate$width+column+1L
coordinates <- function(plate,point) c((point-1L) %/% plate$width,(point-1L) %% plate$width)
read_plate <- function() {
  rows <- readLines(file.path("input","plate.txt"))
  words <- strsplit(rows[1L]," ",fixed=TRUE)[[1L]]
  width <- as.integer(words[1L])
  height <- as.integer(words[2L])
  neighbors <- matrix(0L,width*height,4L)
  for (r in seq_len(height)-1L) for (c in seq_len(width)-1L) {
    p <- r*width+c+1L
    neighbors[p,] <- c(
        if (c > 0L) p-1L else 0L,
        if (c+1L < width) p+1L else 0L,
        if (r > 0L) p-width else 0L,
        if (r+1L < height) p+width else 0L
    )
  }
  list(width=width,height=height,dx=as.numeric(words[3L]),thickness=as.numeric(words[4L]),count=width*height,
    codes=strsplit(paste(rows[-1L],collapse=""),"",fixed=TRUE)[[1L]],neighbors=neighbors)
}
segment_faces <- function(plate,edge,start,ending) {
  face <- unname(EDGE_FACES[edge])
  if (edge %in% c("top","bottom")) {
    row <- if (edge == "top") 0L else plate$height-1L
    return(lapply(seq.int(start,ending),function(column) c(cell(plate,row,column),face)))
  }
  column <- if (edge == "left") 0L else plate$width-1L
  lapply(seq.int(start,ending),function(row) c(cell(plate,row,column),face))
}
source_cells <- function(plate,r1,c1,r2,c2) {
  cells <- integer()
  for (r in seq.int(r1,r2)) for (c in seq.int(c1,c2)) cells <- c(cells,cell(plate,r,c))
  cells
}
