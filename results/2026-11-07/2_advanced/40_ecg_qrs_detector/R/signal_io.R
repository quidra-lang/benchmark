read_ecg <- function() {
  rows <- strsplit(readLines("input/ecg.csv")[-1L], ",", fixed=TRUE)
  vapply(rows, function(row) as.numeric(row[2L]), numeric(1))
}
read_annotations <- function() {
  lapply(strsplit(readLines("input/annotations.csv")[-1L], ",", fixed=TRUE),
         function(row) list(sample=as.numeric(row[1L]), label=row[2L]))
}
read_params <- function() {
  rows <- strsplit(readLines("input/params.txt"), " ", fixed=TRUE)
  setNames(vapply(rows, function(row) as.numeric(row[2L]), numeric(1)),
           vapply(rows, `[`, character(1), 1L))
}
write_lines <- function(name, lines) {
  dir.create("output", showWarnings=FALSE)
  writeLines(lines, file.path("output", name), useBytes=TRUE)
}
