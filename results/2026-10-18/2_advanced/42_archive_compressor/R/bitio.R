decode_error <- function(kind,position) stop(structure(list(message=paste(kind,"at",position),call=NULL,
  kind=kind,position=position),class=c("decode_error","error","condition")))
byte_buffer <- function() {
  result <- new.env(parent=emptyenv())
  result$bytes <- numeric(1024L)
  result$n <- 0L
  result
}
append_bytes <- function(buffer,values) {
  n <- length(values)
  if (!n) return(invisible(NULL))
  required <- buffer$n+n
  if (required > length(buffer$bytes)) length(buffer$bytes) <- max(required,2L*length(buffer$bytes))
  buffer$bytes[seq.int(buffer$n+1L,required)] <- values
  buffer$n <- required
  invisible(NULL)
}
buffer_data <- function(buffer) buffer$bytes[seq_len(buffer$n)]
bit_writer <- function() {
  result <- byte_buffer()
  result$partial <- result$used <- result$count <- 0L
  result
}
write_bits <- function(writer,value,width) {
  for (shift in rev(seq_len(width)-1L)) {
    writer$partial <- 2L*writer$partial+(value %/% (2^shift)) %% 2
    writer$used <- writer$used+1L
    if (writer$used == 8L) {
      append_bytes(writer,writer$partial)
      writer$partial <- writer$used <- 0L
    }
  }
  writer$count <- writer$count+width
}
finish <- function(writer) {
  data <- buffer_data(writer)
  if (writer$used) data <- c(data,writer$partial*2^(8L-writer$used))
  data
}
bit_reader <- function(bytes,zero_fill=FALSE) {
  result <- new.env(parent=emptyenv())
  result$bytes <- bytes
  result$position <- 0L
  result$zero_fill <- zero_fill
  result
}
read_bits <- function(reader,width,position=0L) {
  limit <- 8L*length(reader$bytes)
  if (!reader$zero_fill && reader$position+width > limit) decode_error("end_of_data",position)
  value <- 0
  for (unused in seq_len(width)) {
    value <- 2*value
    if (reader$position < limit) value <- value+(reader$bytes[reader$position %/% 8L+1L] %/% (2^(7L-reader$position %% 8L))) %% 2
    reader$position <- reader$position+1L
  }
  value
}
bits <- function(value) {
  width <- 0L
  while (value > 0) {
    value <- value %/% 2
    width <- width+1L
  }
  width
}
