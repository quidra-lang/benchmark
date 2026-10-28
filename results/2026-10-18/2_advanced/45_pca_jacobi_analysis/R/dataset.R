read_table <- function(path) {
  lines <- strsplit(readLines(path),",",fixed=TRUE)
  names <- lines[[1L]][-1L]
  records <- lines[-1L]
  ids <- vapply(records,`[`,character(1),1L)
  values <- do.call(
      rbind,
      lapply(records,function(row) as.numeric(replace(row[-1L],row[-1L] == "NA",NA_character_)))
  )
  list(names=names,ids=ids,values=values)
}
load_dataset <- function() {
  settings <- list()
  for (line in readLines("input/params.txt")) {
    words <- strsplit(line," ",fixed=TRUE)[[1L]]
    key <- words[1L]
    settings[[key]] <- if (key %in% c("MISSING","SCALING","COMPONENTS")) words[2L] else as.numeric(words[-1L])
  }
  list(
      data=read_table("input/data.csv"),
      supplementary=read_table("input/supplementary.csv"),
      settings=settings
  )
}
