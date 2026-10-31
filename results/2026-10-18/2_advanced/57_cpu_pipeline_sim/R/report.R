decimal <- function(numerator,denominator) {
  scaled <- (2L*numerator*10000L+denominator) %/% (2L*denominator)
  paste0(scaled %/% 10000L,".",sprintf("%04d",scaled %% 10000L))
}
percentage <- function(numerator,denominator) {
  if (denominator == 0L) return("-")
  scaled <- (2L*numerator*10000L+denominator) %/% (2L*denominator)
  paste0(scaled %/% 100L,".",sprintf("%02d",scaled %% 100L))
}
reduced_fraction <- function(numerator,denominator) {
  a <- numerator
  b <- denominator
  while (b != 0L) {
    remainder <- a %% b
    a <- b
    b <- remainder
  }
  paste0(numerator %/% a,"/",denominator %/% a)
}
hexadecimal <- function(value) sprintf("%08x",as.integer(value))
register_text <- function(value) if (value == -1L) "-" else paste0("r",value)
cycle_heading <- function(start,ending) paste0(
    "cycle",
    strrep(" ",18L),
    paste(seq.int(start,ending) %% 10L,collapse="")
)
diagram_row <- function(number,pc,kind,characters,annotation="") {
  identifier <- if (number == 0L) "     -" else sprintf("%6d",number)
  paste0(identifier," ",hexadecimal(pc)," ",sprintf("%-6s",kind)," ",characters,annotation)
}
join_parts <- function(parts) {
  lines <- character()
  for (part in parts) {
    if (length(lines)) lines <- c(lines,"")
    lines <- c(lines,part)
  }
  lines
}
write_lines <- function(name,lines) {
  dir.create("output",showWarnings=FALSE)
  writeLines(lines,file.path("output",name),useBytes=TRUE)
}
