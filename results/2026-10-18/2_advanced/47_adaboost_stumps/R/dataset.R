read_inputs <- function() {
  binary <- function(path) {
    lines <- strsplit(readLines(path),",",fixed=TRUE)
    list(features=lines[[1L]][-c(1L,length(lines[[1L]]))],rows=lapply(lines[-1L],function(r)
      list(id=r[1L],x=as.numeric(r[-c(1L,length(r))]),label=as.integer(tail(r,1L)))))
  }
  training <- binary("input/train.csv")
  testing <- binary("input/test.csv")
  lines <- strsplit(readLines("input/multiclass.csv"),",",fixed=TRUE)
  multi_features <- lines[[1L]][seq.int(2L,length(lines[[1L]])-2L)]
  multi_train <- multi_test <- list()
  for (r in lines[-1L]) {
    row <- list(id=r[1L],x=as.numeric(r[seq.int(2L,length(r)-2L)]),label=as.integer(r[length(r)-1L]))
    if (tail(
        r,
        1L
    ) == "train") multi_train[[length(multi_train)+1L]] <- row else multi_test[[length(multi_test)+1L]] <- row
  }
  params <- list()
  for (line in readLines("input/params.txt")) {
    words <- strsplit(line," ",fixed=TRUE)[[1L]]
    params[[words[1L]]] <- if (words[1L] == "VARIANTS") words[-1L] else as.numeric(words[-1L])
  }
  list(features=training$features,train=training$rows,test=testing$rows,multi_features=multi_features,
    multi_train=multi_train,multi_test=multi_test,params=params)
}
