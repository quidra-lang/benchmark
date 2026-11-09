read_dataset <- function() {
  subjects <- lapply(strsplit(readLines("input/subjects.csv")[-1L],",",fixed=TRUE),function(r)
    list(id=as.integer(r[1L]),group=r[2L],time=as.integer(r[3L]),event=as.integer(r[4L]),
      age=as.integer(r[5L]),sex=r[6L],stage=as.integer(r[7L])))
  subjects <- subjects[order(vapply(subjects,`[[`,integer(1),"id"))]
  settings <- list()
  for (line in readLines("input/params.txt")) {
    words <- strsplit(line," ",fixed=TRUE)[[1L]]
    key <- words[1L]
    settings[[key]] <- if (key %in% c(
        "GROUPS",
        "STRATA",
        "SUBGROUPS",
        "COX"
    )) words[-1L] else as.integer(words[-1L])
  }
  list(subjects=subjects,params=settings)
}
