fraction <- function(a,b) {
  numerator <- a
  denominator <- b
  while (denominator != 0) {
    remainder <- numerator %% denominator
    numerator <- denominator
    denominator <- remainder
  }
  paste0(sprintf("%.0f",a %/% numerator),"/",sprintf("%.0f",b %/% numerator))
}
ids <- function(values) if (length(values)) paste(values,collapse=" ") else "-"
distances <- function(values) if (length(values)) paste(
    vapply(values,function(pair) paste(pair,collapse=":"),character(1)),
    collapse=" "
) else "-"
write_lines <- function(name,lines) {
  dir.create("output",showWarnings=FALSE)
  writeLines(lines,file.path("output",name),useBytes=TRUE)
}
