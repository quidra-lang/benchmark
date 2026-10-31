read_inputs <- function() {
  lines <- readLines("input/network.txt",warn=FALSE)
  lines <- lines[nzchar(lines) & !startsWith(lines,"#")]
  names <- character()
  states <- parents <- expert <- list()
  position <- 1L
  while (position <= length(lines)) {
    fields <- strsplit(lines[position]," ",fixed=TRUE)[[1L]]
    position <- position+1L
    if (fields[1L] == "VARIABLE") {
      names <- c(names,fields[2L])
      states[[length(states)+1L]] <- fields[-c(1L,2L)]
      parents[[length(parents)+1L]] <- integer()
      expert[length(expert)+1L] <- list(NULL)
    } else if (fields[1L] == "PARENTS") parents[[match(fields[2L],names)]] <- match(
        fields[-c(1L,2L)],
        names
    ) else {
      v <- match(fields[2L],names)
      rows <- prod(lengths(states)[parents[[v]]])
      cpt <- matrix(0,rows,length(states[[v]]))
      for (row in seq_len(rows)) {
        cpt[row,] <- as.numeric(strsplit(lines[position]," ",fixed=TRUE)[[1L]])
        position <- position+1L
      }
      expert[[v]] <- cpt
    }
  }
  csv <- readLines("input/samples.csv",warn=FALSE)
  columns <- match(strsplit(csv[1L],",",fixed=TRUE)[[1L]],names)
  samples <- lapply(csv[-1L],function(line) {
    sample <- integer(length(names))
    fields <- strsplit(line,",",fixed=TRUE)[[1L]]
    for (column in seq_along(columns)) sample[columns[column]] <- match(
        fields[column],
        states[[columns[column]]]
    )
    sample
  })
  settings <- strsplit(readLines("input/params.txt",warn=FALSE)," ",fixed=TRUE)
  params <- list(alpha=as.numeric(settings[[1L]][2L]),method=settings[[2L]][2L],
    order=match(settings[[3L]][-1L],names),limit=as.integer(settings[[4L]][2L]),
    seed=as.numeric(settings[[5L]][2L]),sources=vapply(
        settings[-seq_len(5L)],
        function(fields) fields[3L],
        character(1)
    ))
  list(names=names,states=states,parents=parents,expert=expert,samples=samples,
    queries=readLines("input/queries.txt",warn=FALSE),params=params)
}
