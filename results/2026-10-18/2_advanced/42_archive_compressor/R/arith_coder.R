frequency_table <- function() {
  result <- new.env(parent=emptyenv())
  result$frequencies <- rep(1,257L)
  result$total <- 257L
  result$rescales <- 0L
  result
}
update_frequency <- function(table,symbol) {
  table$frequencies[symbol+1L] <- table$frequencies[symbol+1L]+32
  table$total <- table$total+32L
  if (table$total >= 8192L) {
    table$frequencies <- (table$frequencies+1) %/% 2
    table$total <- sum(table$frequencies)
    table$rescales <- table$rescales+1L
  }
}
encode_arith <- function(data) {
  writer <- bit_writer()
  tables <- vector("list",256L)
  low <- 0
  high <- 65535
  follow <- 0L
  context <- 10L
  emit <- function(bit) {
    write_bits(writer,bit,1L)
    for (unused in seq_len(follow)) write_bits(writer,1L-bit,1L)
    follow <<- 0L
  }
  for (symbol in c(data,256L)) {
    if (is.null(tables[[context+1L]])) tables[[context+1L]] <- frequency_table()
    table <- tables[[context+1L]]
    cumulative <- sum(table$frequencies[seq_len(symbol)])
    frequency <- table$frequencies[symbol+1L]
    span <- high-low+1
    high <- low+(span*(cumulative+frequency)) %/% table$total-1
    low <- low+(span*cumulative) %/% table$total
    repeat {
      if (high < 32768) emit(0L)
      else if (low >= 32768) {
        emit(1L)
        low <- low-32768
        high <- high-32768
      } else if (low >= 16384 && high < 49152) {
        follow <- follow+1L
        low <- low-16384
        high <- high-16384
      } else break
      low <- 2*low
      high <- 2*high+1
    }
    if (symbol != 256L) {
      update_frequency(table,symbol)
      context <- symbol
    }
  }
  follow <- follow+1L
  emit(if (low < 16384) 0L else 1L)
  used <- Filter(Negate(is.null),tables)
  list(payload=finish(writer),stats=list(bits=writer$count,contexts=length(used),
    rescales=sum(vapply(used,function(t) t$rescales,numeric(1)))))
}
decode_arith <- function(payload,original) {
  reader <- bit_reader(payload,zero_fill=TRUE)
  tables <- vector("list",256L)
  output <- byte_buffer()
  low <- 0
  high <- 65535
  context <- 10L
  value <- read_bits(reader,16L)
  repeat {
    if (is.null(tables[[context+1L]])) tables[[context+1L]] <- frequency_table()
    table <- tables[[context+1L]]
    span <- high-low+1
    quantile <- ((value-low+1)*table$total-1) %/% span
    cumulative <- symbol <- 0L
    while (quantile >= cumulative+table$frequencies[symbol+1L]) {
      cumulative <- cumulative+table$frequencies[symbol+1L]
      symbol <- symbol+1L
    }
    frequency <- table$frequencies[symbol+1L]
    high <- low+(span*(cumulative+frequency)) %/% table$total-1
    low <- low+(span*cumulative) %/% table$total
    repeat {
      if (high < 32768) {
      } else if (low >= 32768) {
        low <- low-32768
        high <- high-32768
        value <- value-32768
      } else if (low >= 16384 && high < 49152) {
        low <- low-16384
        high <- high-16384
        value <- value-16384
      } else break
      low <- 2*low
      high <- 2*high+1
      value <- 2*value+read_bits(reader,1L)
    }
    if (symbol == 256L) {
      if (output$n < original) decode_error("early_end",output$n)
      return(buffer_data(output))
    }
    if (output$n == original) decode_error("overrun",output$n)
    append_bytes(output,symbol)
    update_frequency(table,symbol)
    context <- symbol
  }
}
