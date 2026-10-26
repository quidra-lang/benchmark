read_lines <- function(path) readLines(path, warn = FALSE)

read_rows <- function(path, attributes, classes) {
  lines <- read_lines(path)[-1L]
  lapply(lines, function(line) {
    fields <- strsplit(line, ",", fixed = TRUE)[[1L]]
    values <- vapply(attributes, function(attribute) {
      text <- fields[attribute$index + 1L]
      if (text == "?") NA_real_
      else if (attribute$integer) as.numeric(text)
      else as.numeric(match(text, attribute$values))
    }, numeric(1L))
    list(id = fields[1L], values = values, label = match(fields[length(fields)], classes))
  })
}

load_dataset <- function() {
  schema <- lapply(read_lines("input/schema.txt"), strsplit, split = " ", fixed = TRUE)
  schema <- lapply(schema, `[[`, 1L)
  definitions <- schema[-length(schema)]
  attributes <- lapply(seq_along(definitions), function(index) {
    fields <- definitions[[index]]
    list(index = index, name = fields[2L], integer = fields[3L] == "INT", values = fields[-seq_len(3L)])
  })
  target <- schema[[length(schema)]][2L]
  classes <- schema[[length(schema)]][-seq_len(2L)]
  settings <- list()
  for (line in read_lines("input/params.txt")) {
    fields <- strsplit(line, " ", fixed = TRUE)[[1L]]
    settings[[tolower(fields[1L])]] <- as.numeric(fields[-1L])
  }
  list(attributes = attributes, target = target, classes = classes,
       train = read_rows("input/train.csv", attributes, classes),
       validation = read_rows("input/validation.csv", attributes, classes),
       test = read_rows("input/test.csv", attributes, classes), settings = settings)
}
