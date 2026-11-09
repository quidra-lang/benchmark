read_all <- function() {
  points <- lapply(
      strsplit(readLines("input/points.csv")[-1L],",",fixed=TRUE),
      function(row) list(id=row[1L],x=as.numeric(row[2L]),y=as.numeric(row[3L]))
  )
  lines <- readLines("input/init.txt")
  initial <- list()
  cursor <- 1L
  while (cursor <= length(lines)) {
    if (!nzchar(lines[cursor])) {
      cursor <- cursor+1L
      next
    }
    k <- as.integer(strsplit(lines[cursor]," ",fixed=TRUE)[[1L]][2L])
    weights <- as.numeric(strsplit(lines[cursor+1L]," ",fixed=TRUE)[[1L]][-1L])
    means <- covariances <- list()
    for (j in seq_len(k)) {
      values <- as.numeric(strsplit(lines[cursor+1L+j]," ",fixed=TRUE)[[1L]][-(1:2)])
      means[[j]] <- values[1:2]
      covariances[[j]] <- values[3:5]
    }
    initial[[as.character(k)]] <- list(weights=weights,means=means,covariances=covariances,type="")
    cursor <- cursor+k+2L
  }
  raw <- list()
  for (words in strsplit(readLines("input/params.txt")," ",fixed=TRUE)) raw[[words[1L]]] <- words[-1L]
  settings <- list(ks=as.integer(raw$K),types=raw$TYPES,iterations=as.integer(raw$ITERATIONS),epsilon=as.numeric(raw$REGULARIZATION),
    settle=as.numeric(raw$SETTLE_TOLERANCE),kmeans_iterations=as.integer(raw$KMEANS_MAX_ITERATIONS),cv_folds=as.integer(raw$CV_FOLDS),
    uncertain=as.numeric(raw$UNCERTAIN_THRESHOLD),low_density=as.numeric(raw$LOW_DENSITY_THRESHOLD),gof_edges=as.numeric(raw$GOF_EDGES),
    map_x=as.numeric(raw$MAP_X),map_y=as.numeric(raw$MAP_Y),map_size=as.integer(raw$MAP_SIZE))
  list(points=points,initial=initial,settings=settings)
}
