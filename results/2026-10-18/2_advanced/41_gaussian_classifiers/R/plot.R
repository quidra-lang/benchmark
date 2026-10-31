real_text <- function(value) {
  text <- sprintf("%.4f",value)
  text[text == "-0.0000"] <- "0.0000"
  text
}
reals <- function(values) paste(real_text(values),collapse=" ")
fraction_text <- function(value) {
  if (is.null(value)) return("-")
  paste0(sprintf("%.0f",value[1L]),"/",sprintf("%.0f",value[2L])," ",real_text(value[1L]/value[2L]))
}
ratio_text <- function(a,b) fraction_text(reduced_fraction(a,b))
frame <- function(grid) {
  border <- paste0("+",strrep("-",ncol(grid)),"+")
  c(
      border,
      vapply(seq_len(nrow(grid)),function(i) paste0("|",paste(grid[i,],collapse=""),"|"),character(1)),
      border
  )
}
cell <- function(value,low,high,n) floor((value-low)/(high-low)*(n-1)+0.5)
join_sections <- function(sections) {
  lines <- character()
  for (section in sections) {
    if (length(lines)) lines <- c(lines,"")
    lines <- c(lines,section)
  }
  lines
}
write_lines <- function(name,lines) {
  dir.create("output",showWarnings=FALSE)
  writeLines(lines,file.path("output",name),useBytes=TRUE)
}
