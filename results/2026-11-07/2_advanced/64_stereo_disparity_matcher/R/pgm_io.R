integer_text <- function(value) sprintf("%.0f",value)
read_pgm <- function(path) {
  lines <- readLines(path)
  dimensions <- as.integer(strsplit(lines[2L]," ",fixed=TRUE)[[1L]])
  list(
      width=dimensions[1L],
      height=dimensions[2L],
      pixels=as.numeric(unlist(strsplit(lines[-(1:3)]," ",fixed=TRUE)))
  )
}
read_parameters <- function() {
  params <- list(sample_pixels=list())
  for (line in readLines("input/params.txt")) {
    words <- strsplit(line," ",fixed=TRUE)[[1L]]
    name <- words[1L]
    if (name == "sample") params$sample_pixels[[length(params$sample_pixels)+1L]] <- as.integer(words[2:3]) else if (name %in% c(
        "wta_cost",
        "sgm_cost"
    )) params[[name]] <- words[2L] else if (endsWith(name,"_windows")) params[[name]] <- as.integer(words[-1L]) else params[[name]] <- as.numeric(words[2L])
  }
  params
}
write_pgm <- function(path,width,height,pixels) {
  lines <- c("P2",paste(width,height),"255")
  for (y in 0:(height-1L)) lines <- c(
      lines,
      paste(integer_text(pixels[seq.int(y*width+1L,(y+1L)*width)]),collapse=" ")
  )
  writeLines(lines,path,useBytes=TRUE)
}
