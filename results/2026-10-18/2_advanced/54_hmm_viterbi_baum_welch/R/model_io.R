ordered_sum <- function(values) {
  total <- 0
  for (value in values) total <- total+value
  total
}
normalize <- function(values) values/ordered_sum(values)
make_model <- function(name,states,symbols,missing,initial,transition,emission) {
  for (i in seq_len(nrow(transition))) {
    transition[i,] <- normalize(transition[i,])
    emission[i,] <- normalize(emission[i,])
  }
  list(
      name=name,
      states=states,
      symbols=symbols,
      missing=missing,
      initial=normalize(initial),
      transition=transition,
      emission=emission
  )
}
read_inputs <- function() {
  read_tokens <- function(name) strsplit(readLines(file.path("input",name))," ",fixed=TRUE)
  rows <- read_tokens("model.txt")
  states <- rows[[1L]][-1L]
  symbols <- rows[[2L]][-1L]
  k <- length(states)
  initial <- as.numeric(rows[[4L]][-1L])
  transition <- do.call(rbind,lapply(rows[seq.int(5L,4L+k)],function(row) as.numeric(row[-(1:2)])))
  emission <- do.call(rbind,lapply(rows[seq.int(5L+k,4L+2L*k)],function(row) as.numeric(row[-(1:2)])))
  model <- make_model("INITIAL",states,symbols,rows[[3L]][2L],initial,transition,emission)
  list(
      model=model,
      sequences=read_tokens("sequences.txt"),
      labeled=read_tokens("labeled.txt"),
      parameters=read_tokens("params.txt")
  )
}
real_text <- function(value,places=4L) {
  if (is.null(value)) return("-")
  text <- sprintf(paste0("%.",places,"f"),value)
  if (startsWith(text,"-") && as.numeric(text) == 0) substring(text,2L) else text
}
model_lines <- function(model) {
  lines <- c(paste("MODEL",model$name),paste("STATES",paste(model$states,collapse=" ")),paste("SYMBOLS",paste(model$symbols,collapse=" ")),
    paste("MISSING",model$missing),paste(
        "INITIAL",
        paste(vapply(model$initial,real_text,character(1)),collapse=" ")
    ))
  for (i in seq_along(model$states)) lines <- c(
      lines,
      paste(
          "TRANSITION",
          model$states[i],
          paste(vapply(model$transition[i,],real_text,character(1)),collapse=" ")
      )
  )
  for (i in seq_along(model$states)) lines <- c(
      lines,
      paste("EMISSION",model$states[i],paste(vapply(model$emission[i,],real_text,character(1)),collapse=" "))
  )
  lines
}
write_lines <- function(name,lines) {
  dir.create("output",showWarnings=FALSE)
  writeLines(lines,file.path("output",name),useBytes=TRUE)
}
