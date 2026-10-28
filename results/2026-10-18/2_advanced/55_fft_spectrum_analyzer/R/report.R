real_text <- function(value) {
  text <- sprintf("%.4f",value)
  ifelse(text == "-0.0000","0.0000",text)
}
field_text <- function(value) if (is.double(value)) real_text(value) else as.character(value)
fields <- function(...) {
  items <- list(...)
  paste(
      vapply(seq_along(items),function(i) paste0(names(items)[i],"=",field_text(items[[i]])),character(1)),
      collapse=" "
  )
}
write_lines <- function(name,lines) {
  dir.create("output",showWarnings=FALSE)
  writeLines(lines,file.path("output",name),useBytes=TRUE)
}
write_csv <- function(name,header,rows) write_lines(
    name,
    c(header,vapply(rows,function(row) paste(vapply(row,field_text,character(1)),collapse=","),character(1)))
)
shade_lines <- function(grid,fs,n,band_db) {
  maximum_value <- max(unlist(grid,use.names=FALSE))
  shades <- strsplit(" .:-=+*#%@","",fixed=TRUE)[[1L]]
  lines <- character()
  for (k in seq.int(n %/% 2L,0L)) {
    pixels <- vapply(
        grid,
        function(row) shades[max(0L,9L-floor(-20*log10(row[k+1L]/maximum_value)/band_db))+1L],
        character(1)
    )
    frequency <- real_text(k*fs/n)
    lines <- c(
        lines,
        paste0(strrep(" ",max(0L,9L-nchar(frequency))),frequency," |",paste(pixels,collapse=""),"|")
    )
  }
  lines
}
