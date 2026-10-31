read_ppm <- function(path) {
  lines <- readLines(path)
  dimensions <- as.integer(strsplit(lines[2L]," ",fixed=TRUE)[[1L]])
  image <- array(0,c(dimensions[2L],dimensions[1L],3L))
  for (y in seq_len(dimensions[2L])) {
    values <- as.numeric(strsplit(lines[y+3L]," ",fixed=TRUE)[[1L]])
    for (x in seq_len(dimensions[1L])) image[y,x,] <- values[seq.int(3L*x-2L,3L*x)]
  }
  image
}
write_ppm <- function(path,image) {
  lines <- c("P3",paste(dim(image)[2L],dim(image)[1L]),"255")
  for (y in seq_len(dim(image)[1L])) {
    values <- unlist(lapply(seq_len(dim(image)[2L]),function(x) image[y,x,]),use.names=FALSE)
    lines <- c(lines,paste(sprintf("%.0f",values),collapse=" "))
  }
  writeLines(lines,path,useBytes=TRUE)
}
read_params <- function(path) {
  params <- list()
  for (line in readLines(path)) {
    words <- strsplit(line," ",fixed=TRUE)[[1L]]
    name <- words[1L]
    params[[name]] <- if (name %in% c("sampling","huffman")) words[2L] else if (name %in% c(
        "qualities",
        "truncate"
    )) as.integer(words[-1L]) else as.integer(words[2L])
  }
  params
}
read_tables <- function(path) {
  lines <- readLines(path)
  matrix_at <- function(start) do.call(
      rbind,
      lapply(lines[seq.int(start,start+7L)],function(line) as.numeric(strsplit(line," ",fixed=TRUE)[[1L]]))
  )
  tables <- list()
  for (start in seq.int(28L,37L,3L)) {
    words <- strsplit(lines[start]," ",fixed=TRUE)[[1L]]
    tables[[table_key(words[2L],words[3L])]] <- new_huffman(
        as.integer(strsplit(lines[start+1L]," ",fixed=TRUE)[[1L]]),
        as.integer(strsplit(lines[start+2L]," ",fixed=TRUE)[[1L]])
    )
  }
  list(transform=matrix_at(2L),basic=list(matrix_at(11L),matrix_at(20L)),standard=tables)
}
read_hex <- function(path) {
  text <- paste(readLines(path),collapse="")
  starts <- seq.int(1L,nchar(text),2L)
  strtoi(substring(text,starts,starts+1L),base=16L)
}
write_hex <- function(path,data) {
  lines <- character()
  for (start in seq.int(1L,length(data),32L)) lines <- c(
      lines,
      paste(sprintf("%02x",as.integer(data[seq.int(start,min(start+31L,length(data)))])),collapse="")
  )
  writeLines(lines,path,useBytes=TRUE)
}
