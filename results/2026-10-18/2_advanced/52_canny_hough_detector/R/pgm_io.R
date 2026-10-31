integer_text <- function(value) sprintf("%.0f",value)
read_inputs <- function() {
  lines <- readLines("input/image.pgm")
  dimensions <- as.integer(strsplit(lines[2L]," ",fixed=TRUE)[[1L]])
  image <- do.call(rbind,lapply(strsplit(lines[-seq_len(3L)]," ",fixed=TRUE),as.integer))
  trig <- do.call(
      rbind,
      lapply(strsplit(readLines("input/trig.txt")," ",fixed=TRUE),function(row) as.integer(row[2:3]))
  )
  params <- list()
  for (line in readLines("input/params.txt")) {
    words <- strsplit(line," ",fixed=TRUE)[[1L]]
    params[[words[1L]]] <- as.numeric(words[-1L])
  }
  list(image=image,trig=trig,params=params)
}
write_lines <- function(name,lines) {
  dir.create("output",showWarnings=FALSE)
  writeLines(lines,file.path("output",name),useBytes=TRUE)
}
write_pgm <- function(name,image) {
  lines <- c(
      "P2",
      paste(ncol(image),nrow(image)),
      "255",
      vapply(seq_len(nrow(image)),function(y) paste(integer_text(image[y,]),collapse=" "),character(1))
  )
  write_lines(name,lines)
}
