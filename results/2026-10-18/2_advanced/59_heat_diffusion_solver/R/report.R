real_text <- function(value,places) {
  text <- sprintf(paste0("%.",places,"f"),value)
  if (startsWith(text,"-") && as.numeric(text) == 0) substring(text,2L) else text
}
time_text <- function(milliseconds) paste0(milliseconds %/% 1000L,".",sprintf("%03d",milliseconds %% 1000L))
temperature_lines <- function(plate,field) vapply(
    seq_len(plate$height)-1L,
    function(r) paste(
        vapply(seq_len(plate$width)-1L,function(c) real_text(field[cell(plate,r,c)],2L),character(1)),
        collapse=" "
    ),
    character(1)
)
isotherm_lines <- function(plate,field,bands) {
  hottest <- which.max(field)
  counts <- integer(length(bands)+1L)
  characters <- character(length(field))
  for (p in seq_along(field)) {
    digit <- sum(bands <= field[p])
    counts[digit+1L] <- counts[digit+1L]+1L
    characters[p] <- if (p == hottest) "*" else as.character(digit)
  }
  list(
      counts=counts,
      lines=vapply(
          seq_len(plate$height)-1L,
          function(r) paste(characters[seq.int(r*plate$width+1L,(r+1L)*plate$width)],collapse=""),
          character(1)
      )
  )
}
write_lines <- function(name,lines) {
  dir.create("output",showWarnings=FALSE)
  writeLines(lines,file.path("output",name),useBytes=TRUE)
}
