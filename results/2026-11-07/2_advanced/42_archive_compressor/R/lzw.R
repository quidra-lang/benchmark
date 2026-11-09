encode_lzw <- function(data) {
  writer <- bit_writer()
  initial_dictionary <- function() {
    result <- new.env(hash=TRUE,parent=emptyenv())
    for (value in seq.int(0L,255L)) assign(as.character(value),value,result)
    result
  }
  dictionary <- initial_dictionary()
  next_code <- 258L
  since_clear <- codes <- clears <- longest <- 0L
  widths <- integer(4L)
  emit <- function(code,sequence_length=0L) {
    width <- min(12L,bits(258L+since_clear))
    write_bits(writer,code,width)
    codes <<- codes+1L
    widths[width-8L] <<- widths[width-8L]+1L
    longest <<- max(longest,sequence_length)
    if (code == 256L) {
      clears <<- clears+1L
      since_clear <<- 0L
    } else since_clear <<- since_clear+1L
  }
  emit(256L)
  sequence <- ""
  sequence_length <- 0L
  for (value in data) {
    byte <- as.character(value)
    extended <- if (sequence_length) paste0(sequence,",",byte) else byte
    if (exists(extended,dictionary,inherits=FALSE)) {
      sequence <- extended
      sequence_length <- sequence_length+1L
      next
    }
    emit(get(sequence,dictionary,inherits=FALSE),sequence_length)
    assign(extended,next_code,dictionary)
    next_code <- next_code+1L
    if (next_code == 4096L) {
      emit(256L)
      dictionary <- initial_dictionary()
      next_code <- 258L
    }
    sequence <- byte
    sequence_length <- 1L
  }
  if (sequence_length) emit(get(sequence,dictionary,inherits=FALSE),sequence_length)
  emit(257L)
  list(payload=finish(writer),stats=list(codes=codes,clears=clears,widths=widths,longest=longest))
}
decode_lzw <- function(payload,original) {
  reader <- bit_reader(payload)
  initial_dictionary <- function() c(lapply(seq.int(0L,255L),identity),list(NULL,NULL))
  dictionary <- initial_dictionary()
  previous <- -1L
  since_clear <- 0L
  output <- byte_buffer()
  repeat {
    count <- since_clear
    code <- read_bits(reader,min(12L,bits(258L+count)),output$n)
    if (code == 256L) {
      dictionary <- initial_dictionary()
      previous <- -1L
      since_clear <- 0L
      next
    }
    since_clear <- since_clear+1L
    if (code == 257L) {
      if (output$n < original) decode_error("early_end",output$n)
      return(buffer_data(output))
    }
    if (count == 3838L) decode_error("bad_code",output$n)
    next_code <- length(dictionary)
    if (previous < 0L) {
      if (code >= 256L) decode_error("bad_code",output$n)
      sequence <- dictionary[[code+1L]]
    } else if (code < next_code) sequence <- dictionary[[code+1L]]
    else if (code == next_code) sequence <- c(dictionary[[previous+1L]],dictionary[[previous+1L]][1L])
    else decode_error("bad_code",output$n)
    if (output$n+length(sequence) > original) decode_error("overrun",output$n)
    append_bytes(output,sequence)
    if (previous >= 0L) dictionary[[length(dictionary)+1L]] <- c(dictionary[[previous+1L]],sequence[1L])
    previous <- code
  }
}
