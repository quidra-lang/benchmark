real_text <- function(value) {
  if (is.null(value)) return("-")
  text <- sprintf("%.4f",value)
  if (text == "-0.0000") "0.0000" else text
}
optional <- function(value) if (is.null(value)) "-" else sprintf("%.0f",value)
write_lines <- function(name,lines) {
  dir.create("output",showWarnings=FALSE)
  writeLines(lines,file.path("output",name),useBytes=TRUE)
}
