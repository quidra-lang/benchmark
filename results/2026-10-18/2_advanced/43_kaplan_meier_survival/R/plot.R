curve_lines <- function(groups,collections,estimates,width,height,time_limit) {
  cells <- matrix(" ",height,width)
  step <- time_limit %/% width
  for (g in seq_along(groups)) {
    group <- groups[g]
    letter <- LETTERS[g]
    maximum_time <- max(vapply(collections[[group]],`[[`,integer(1),"time"))
    previous <- NULL
    for (column in seq_len(width)-1L) {
      time <- column*step
      if (time > maximum_time) break
      band <- min(height-1L,floor(row_at(estimates[[group]],time)$survival*height))
      occupied <- if (is.null(previous) || previous-1L <= band) band else seq.int(band,previous-1L)
      for (row in occupied) cells[row+1L,column+1L] <- if (cells[row+1L,column+1L] == " ") letter else "*"
      previous <- band
    }
  }
  border <- paste0("   +",strrep("-",width),"+")
  c(border,vapply(rev(seq_len(height))-1L,function(band) paste0(sprintf("%3d|",(100L*band) %/% height),
    paste(cells[band+1L,],collapse=""),"|"),character(1)),border)
}
