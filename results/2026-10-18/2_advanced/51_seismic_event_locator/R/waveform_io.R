load_inputs <- function() {
  geometry <- strsplit(readLines("input/stations.csv")[-1L],",",fixed=TRUE)
  lines <- readLines("input/waveforms.txt")
  blocks <- list()
  cursor <- 1L
  while (cursor <= length(lines)) {
    header <- strsplit(lines[cursor]," ",fixed=TRUE)[[1L]]
    code <- header[2L]
    start <- as.numeric(header[3L])
    count <- as.integer(header[4L])
    cursor <- cursor+1L
    samples <- numeric()
    while (length(samples) < count) {
      samples <- c(samples,as.numeric(strsplit(lines[cursor]," ",fixed=TRUE)[[1L]]))
      cursor <- cursor+1L
    }
    blocks[[code]] <- list(start=start,samples=samples)
  }
  stations <- lapply(seq_along(geometry),function(i) {
    row <- geometry[[i]]
    list(code=row[1L],x=as.numeric(row[2L]),y=as.numeric(row[3L]),elevation=as.numeric(row[4L]),order=i,
      start=blocks[[row[1L]]]$start,samples=blocks[[row[1L]]]$samples)
  })
  params <- list()
  for (line in readLines("input/params.txt")) {
    fields <- strsplit(line," ",fixed=TRUE)[[1L]]
    params[[fields[1L]]] <- as.numeric(fields[-1L])
  }
  list(stations=stations,params=params)
}
