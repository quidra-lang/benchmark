for (i in 1:9) {
  fields <- vapply(1:9, function(j) sprintf("%3d", i * j), character(1))
  cat(paste(fields, collapse = ""), "\n", sep = "")
}
