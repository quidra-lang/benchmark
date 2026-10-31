codec_error <- function(kind) stop(structure(
    list(message=kind,call=NULL,kind=kind),
    class=c("jpeg_decode_error","error","condition")
))
new_bit_writer <- function() list2env(
    list(data=integer(),buffer=0L,pending=0L,padding_bits=0L,stuffed_bytes=0L),
    parent=emptyenv()
)
write_bits <- function(writer,value,width) {
  if (width == 0L) return(invisible(NULL))
  for (shift in seq.int(width-1L,0L)) {
    writer$buffer <- 2L*writer$buffer+bitwAnd(bitwShiftR(as.integer(value),shift),1L)
    writer$pending <- writer$pending+1L
    if (writer$pending == 8L) {
      writer$data <- c(writer$data,writer$buffer)
      if (writer$buffer == 255L) {
        writer$data <- c(writer$data,0L)
        writer$stuffed_bytes <- writer$stuffed_bytes+1L
      }
      writer$buffer <- writer$pending <- 0L
    }
  }
}
pad_bits <- function(writer) {
  if (writer$pending != 0L) {
    width <- 8L-writer$pending
    writer$padding_bits <- writer$padding_bits+width
    write_bits(writer,power2(width)-1L,width)
  }
}
restart <- function(writer,number) {
  pad_bits(writer)
  writer$data <- c(writer$data,255L,208L+number %% 8L)
}
new_bit_reader <- function(data,position) list2env(
    list(data=data,position=position,buffer=0L,remaining=0L),
    parent=emptyenv()
)
read_bit <- function(reader) {
  if (reader$remaining == 0L) {
    value <- reader$data[reader$position+1L]
    if (value == 255L) {
      if (reader$data[reader$position+2L] != 0L) codec_error("marker")
      reader$position <- reader$position+2L
    } else reader$position <- reader$position+1L
    reader$buffer <- value
    reader$remaining <- 8L
  }
  reader$remaining <- reader$remaining-1L
  bitwAnd(bitwShiftR(reader$buffer,reader$remaining),1L)
}
read_bits <- function(reader,width) {
  value <- 0L
  for (unused in seq_len(width)) value <- 2L*value+read_bit(reader)
  value
}
discard_bits <- function(reader) {
  reader$buffer <- reader$remaining <- 0L
}
find_resync <- function(data,position) {
  for (offset in seq.int(
      position,
      length(data)-2L
  )) if (data[offset+1L] == 255L && ((data[offset+2L] >= 208L && data[offset+2L] <= 215L) || data[offset+2L] == 217L)) return(offset)
  stop("missing resynchronization marker")
}
