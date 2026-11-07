minstd <- function(seed) {
  generator <- new.env(parent=emptyenv())
  generator$state <- as.numeric(seed)
  generator
}
draw <- function(generator) {
  generator$state <- (48271*generator$state) %% 2147483647
  generator$state
}
shuffle_order <- function(generator,values) {
  if (length(values) > 1L) for (i in seq.int(length(values),2L)) {
    j <- as.integer(draw(generator) %% i)+1L
    temporary <- values[i]
    values[i] <- values[j]
    values[j] <- temporary
  }
  values
}
read_images <- function(name) lapply(strsplit(readLines(file.path("input",name))[-1L],",",fixed=TRUE),function(words) {
  pixels <- words[3L]
  list(
      id=words[1L],
      label=as.integer(words[2L]),
      pixels=pixels,
      vector=as.numeric(strsplit(pixels,"",fixed=TRUE)[[1L]])
  )
})
load_inputs <- function() {
  blocks <- strsplit(
      trimws(paste(readLines(file.path("input","network.txt")),collapse="\n")),
      "\n\n",
      fixed=TRUE
  )[[1L]]
  dimensions <- strsplit(blocks[1L]," ",fixed=TRUE)[[1L]]
  width <- as.integer(dimensions[2L])
  height <- as.integer(dimensions[3L])
  networks <- lapply(blocks[-1L],function(block) {
    rows <- strsplit(block,"\n",fixed=TRUE)[[1L]]
    name <- strsplit(rows[1L]," ",fixed=TRUE)[[1L]][2L]
    layers <- lapply(rows[-1L],function(row) {
      words <- strsplit(row," ",fixed=TRUE)[[1L]]
      list(kind=words[1L],units=as.integer(words[2L]),activation=words[3L])
    })
    list(name=name,layers=layers,width=width,height=height,classes=tail(layers,1L)[[1L]]$units)
  })
  weights <- list()
  blocks <- strsplit(
      trimws(paste(readLines(file.path("input","weights.txt")),collapse="\n")),
      "\n\n",
      fixed=TRUE
  )[[1L]]
  for (block in blocks) {
    rows <- strsplit(block,"\n",fixed=TRUE)[[1L]]
    name <- strsplit(rows[1L]," ",fixed=TRUE)[[1L]][2L]
    theta <- numeric()
    for (row in rows[-1L]) {
      words <- strsplit(row," ",fixed=TRUE)[[1L]]
      if (words[1L] %in% c("W","B")) theta <- c(theta,as.numeric(words[-1L]))
    }
    weights[[name]] <- theta
  }
  settings <- list(runs=list())
  for (line in readLines(file.path("input","params.txt"))) {
    words <- strsplit(line," ",fixed=TRUE)[[1L]]
    key <- words[1L]
    values <- words[-1L]
    if (key == "RUN") settings$runs[[length(settings$runs)+1L]] <- list(
        name=values[1L],
        network=values[2L],
        optimizer=values[3L],
        rate=as.numeric(values[4L]),
        decay=as.numeric(values[5L]),
        extra=as.numeric(values[-seq_len(5L)])
    ) else if (key == "LR_STEP") {
      settings$lr_step <- as.integer(values[1L])
      settings$lr_gamma <- as.numeric(values[2L])
    } else if (key %in% c("PRUNE","NOISE")) settings[[tolower(key)]] <- as.integer(values) else {
      translated <- if (key == "GRADIENT_CHECK_STRIDE") "gradient_stride" else tolower(key)
      settings[[translated]] <- as.integer(values[1L])
    }
  }
  list(
      train=read_images("train.csv"),
      test=read_images("test.csv"),
      networks=networks,
      weights=weights,
      settings=settings
  )
}
