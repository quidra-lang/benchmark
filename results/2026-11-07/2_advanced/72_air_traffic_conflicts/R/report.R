decimal <- function(value,digits=3L) {
  scale <- 10^digits
  rounded <- floor(abs(value)*scale+0.5)/scale
  text <- sprintf(paste0("%.",digits,"f"),rounded)
  ifelse(value < 0 & rounded != 0,paste0("-",text),text)
}
signed_integer <- function(number) if (number > 0L) paste0("+",number) else as.character(number)
chart <- function(rows) {
  border <- paste0("+",strrep("-",nchar(rows[1L],type="bytes")),"+")
  c(border,paste0("|",rows,"|"),border)
}
write_lines <- function(name,lines) {
  dir.create("output",showWarnings=FALSE)
  connection <- file(paste0("output/",name),"wb")
  on.exit(close(connection))
  if (length(lines)) writeChar(paste0(paste(lines,collapse="\n"),"\n"),connection,eos=NULL,useBytes=TRUE)
}
