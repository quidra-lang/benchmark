read_table <- function(path,kinds=NULL) {
  records <- strsplit(readLines(path),",",fixed=TRUE)
  columns <- records[[1L]]
  records <- records[-1L]
  if (is.null(kinds)) kinds <- setNames(vapply(seq_along(columns),function(j)
    any(vapply(records,function(r) r[j] != "NA" && grepl("^[A-Z]",r[j]),logical(1))),logical(1)),columns)
  rows <- lapply(records,function(r) {
    row <- setNames(vector("list",length(columns)),columns)
    for (j in seq_along(columns)) row[j] <- list(if (r[j] == "NA") NULL else if (kinds[[columns[j]]]) r[j] else as.numeric(r[j]))
    row
  })
  list(columns=columns,kinds=kinds,rows=rows)
}
read_params <- function() {
  rows <- strsplit(readLines("input/params.txt")," ",fixed=TRUE)
  setNames(lapply(rows,function(row) as.numeric(row[-1L])),vapply(rows,`[`,character(1),1L))
}
