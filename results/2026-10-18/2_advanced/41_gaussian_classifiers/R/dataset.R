read_inputs <- function() {
  table <- function(path) {
    records <- strsplit(readLines(path),",",fixed=TRUE)
    list(features=records[[1L]][-c(1L,length(records[[1L]]))],rows=lapply(records[-1L],function(row)
      list(id=as.integer(row[1L]),x=as.numeric(row[-c(1L,length(row))]),label=tail(row,1L))))
  }
  train <- table("input/train.csv")
  test <- table("input/test.csv")$rows
  features <- train$features
  train <- train$rows
  classes <- sort(unique(vapply(train,`[[`,character(1),"label")),method="radix")
  add_class <- function(row) { row$y <- match(row$label,classes); row }
  train <- lapply(train,add_class)
  test <- lapply(test,add_class)
  lines <- strsplit(readLines("input/costs.csv"),",",fixed=TRUE)
  columns <- lines[[1L]][-1L]
  costs <- matrix(0,nrow=length(classes),ncol=length(classes))
  for (row in lines[-1L]) costs[match(row[1L],classes),] <- as.numeric(row[-1L])[match(classes,columns)]
  params <- list()
  subsets <- pairs <- list()
  for (line in readLines("input/params.txt")) {
    words <- strsplit(line," ",fixed=TRUE)[[1L]]
    key <- words[1L]
    args <- words[-1L]
    if (key == "SUBSET") subsets[[length(subsets)+1L]] <- list(
        name=args[1L],
        features=match(args[-1L],features)
    )
    else if (key == "PAIR") pairs[[length(pairs)+1L]] <- match(args,features)
    else params[[key]] <- if (key == "PRIOR") args[1L] else as.numeric(args)
  }
  list(
      features=features,
      classes=classes,
      train=train,
      test=test,
      costs=costs,
      params=params,
      subsets=subsets,
      pairs=pairs
  )
}
