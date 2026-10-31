LEVELS <- strsplit(" .:-=+*#%@","",fixed=TRUE)[[1L]]
dec <- function(value,places=4L) {
  text <- sprintf(paste0("%.",places,"f"),value)
  if (startsWith(text,"-") && as.numeric(text) == 0) substring(text,2L) else text
}
optional <- function(value) if (is.null(value)) "-" else dec(value)
real_values <- function(items) paste(vapply(items,dec,character(1)),collapse=" ")
integer_values <- function(items) paste(sprintf("%.0f",items),collapse=" ")
framed <- function(grid) {
  border <- paste0("+",strrep("-",ncol(grid)),"+")
  c(
      border,
      vapply(seq_len(nrow(grid)),function(r) paste0("|",paste(grid[r,],collapse=""),"|"),character(1)),
      border
  )
}
write_lines <- function(name,lines) {
  dir.create("output",showWarnings=FALSE)
  writeLines(lines,file.path("output",name),useBytes=TRUE)
}
write_blocks <- function(name,blocks) {
  lines <- character()
  for (block in blocks) {
    if (length(lines)) lines <- c(lines,"")
    lines <- c(lines,block)
  }
  write_lines(name,lines)
}
