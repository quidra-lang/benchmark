fmt <- function(value,places=4L) {
  text <- sprintf(paste0("%.",places,"f"),value)
  if (startsWith(text,"-") && as.numeric(text) == 0) substring(text,2L) else text
}
curve_plot <- function(observed,fitted) {
  days <- length(observed)
  largest <- max(observed)
  width <- nchar(as.character(largest))
  grid <- matrix(".",20L,70L)
  for (column in seq.int(0L,69L)) {
    day <- (column*(days-1L)) %/% 69L+1L
    observed_row <- min(19L,(20L*observed[day]) %/% largest)
    fitted_row <- min(19L,floor(20*fitted[day]/largest))
    grid[observed_row+1L,column+1L] <- "o"
    grid[fitted_row+1L,column+1L] <- if (observed_row == fitted_row) "#" else "*"
  }
  lines <- paste("plot observed o fitted * both # days 1",days,"max",largest)
  for (row in seq.int(19L,0L)) {
    label <- as.character((largest*row) %/% 20L)
    lines <- c(lines,paste0(strrep(" ",width-nchar(label)),label," |",paste(grid[row+1L,],collapse="")))
  }
  ticks <- paste(ifelse(seq.int(0L,69L) %% 10L == 0L,"+","-"),collapse="")
  lines <- c(lines,paste0(strrep(" ",width+1L),"+",ticks))
  labels <- rep(" ",70L)
  for (column in seq.int(0L,60L,by=10L)) {
    text <- as.character(1L+(column*(days-1L)) %/% 69L)
    characters <- strsplit(text,"",fixed=TRUE)[[1L]]
    labels[column+seq_along(characters)] <- characters
  }
  c(lines,sub(" +$","",paste0(strrep(" ",width+2L),paste(labels,collapse=""))))
}
