decimal <- function(value,places) {
  text <- sprintf(paste0("%.",places,"f"),value)
  if (startsWith(text,"-") && as.numeric(text) == 0) substring(text,2L) else text
}
optional <- function(value,places) if (is.null(value)) "none" else decimal(value,places)
write_lines <- function(name,lines) {
  dir.create("output",showWarnings=FALSE)
  writeLines(lines,file.path("output",name),useBytes=TRUE)
}
render_plot <- function(grid,labels) {
  width <- max(nchar(labels))
  lines <- vapply(
      seq_len(nrow(grid)),
      function(row) paste0(sprintf(paste0("%",width,"s"),labels[row])," |",paste(grid[row,],collapse=""),"|"),
      character(1)
  )
  axis <- paste(ifelse((0:(ncol(grid)-1L)) %% 6L == 0L,"+","-"),collapse="")
  c(lines,paste0(strrep(" ",width)," +",axis,"+"))
}
