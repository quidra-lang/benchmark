read_binary <- function(name) lapply(strsplit(readLines(file.path("input",name))[-1L],",",fixed=TRUE),function(words)
  list(id=words[1L],point=as.numeric(words[2:3]),label=as.integer(words[4L])))
read_inputs <- function() {
  training <- read_binary("train.csv")
  testing <- read_binary("test.csv")
  multi_training <- multi_testing <- list()
  for (line in readLines(file.path("input","multiclass.csv"))[-1L]) {
    words <- strsplit(line,",",fixed=TRUE)[[1L]]
    example <- list(
        id=words[1L],
        point=as.numeric(words[2:3]),
        class_number=as.integer(words[4L]),
        role=words[5L]
    )
    if (words[5L] == "train") multi_training[[length(multi_training)+1L]] <- example else multi_testing[[length(multi_testing)+1L]] <- example
  }
  settings <- list(kernels=list())
  for (line in readLines(file.path("input","params.txt"))) {
    words <- strsplit(line," ",fixed=TRUE)[[1L]]
    key <- tolower(words[1L])
    values <- words[-1L]
    if (key == "kernel") {
      kind <- values[2L]
      kernel <- list(name=values[1L],kind=kind,degree=if (kind == "poly") as.integer(values[3L]) else 0L,
        gamma=if (kind == "poly") as.numeric(values[4L]) else if (kind == "rbf") as.numeric(values[3L]) else 0,coef0=if (kind == "poly") as.numeric(values[5L]) else 0)
      settings$kernels[[length(settings$kernels)+1L]] <- kernel
    } else if (key %in% c(
        "max_passes",
        "folds",
        "newton_iterations"
    )) settings[[key]] <- as.integer(values[1L]) else if (key %in% c("learning_curve","plot_size"))
      settings[[key]] <- as.integer(values) else if (key == "multiclass") settings[[key]] <- list(
          values[1L],
          as.numeric(values[2L])
      ) else if (key == "pegasos")
      settings[[key]] <- list(
          as.numeric(values[1L]),
          as.integer(values[2L]),
          as.integer(values[3L])
      ) else if (key %in% c("c_grid","plot_x","plot_y"))
      settings[[key]] <- as.numeric(values) else settings[[key]] <- as.numeric(values[1L])
  }
  list(
      training=training,
      testing=testing,
      multi_training=multi_training,
      multi_testing=multi_testing,
      settings=settings
  )
}
