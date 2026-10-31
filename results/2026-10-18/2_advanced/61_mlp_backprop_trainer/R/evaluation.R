real_text <- function(value,places) {
  if (is.null(value)) return("-")
  result <- sprintf(paste0("%.",places,"f"),value)
  if (startsWith(result,"-") && as.numeric(result) == 0) substring(result,2L) else result
}
ratio <- function(numerator,denominator) {
  if (denominator == 0L) return("-")
  rounded <- (20000L*numerator+denominator) %/% (2L*denominator)
  paste0(rounded %/% 10000L,".",sprintf("%04d",rounded %% 10000L))
}
best_two <- function(scores) head(order(-scores,seq_along(scores)),2L)-1L
confusion <- function(outcomes,classes) {
  table <- matrix(0L,classes,classes)
  for (outcome in outcomes) table[outcome$label+1L,outcome$predicted+1L] <- table[
      outcome$label+1L,
      outcome$predicted+1L
  ]+1L
  table
}
class_measures <- function(table,klass) {
  support <- sum(table[klass+1L,])
  predicted <- sum(table[,klass+1L])
  true <- table[klass+1L,klass+1L]
  list(
      support=support,
      predicted=predicted,
      precision=ratio(true,predicted),
      recall=ratio(true,support),
      f1=ratio(2L*true,support+predicted)
  )
}
level_maps <- function(levels,width,height) vapply(
    seq_len(height)-1L,
    function(r) paste(
        vapply(
            levels,
            function(level) paste(level[seq.int(r*width+1L,(r+1L)*width)],collapse=""),
            character(1)
        ),
        collapse=" "
    ),
    character(1)
)
ascii_image <- function(pixels,width) {
  characters <- strsplit(pixels,"",fixed=TRUE)[[1L]]
  vapply(
      seq.int(1L,length(characters),by=width),
      function(i) paste(ifelse(characters[seq.int(i,i+width-1L)] == "1","#","."),collapse=""),
      character(1)
  )
}
binary_frequency <- function(images,label,pixels) {
  chosen <- Filter(function(image) image$label == label,images)
  if (!length(chosen)) return(integer(pixels))
  vapply(
      seq_len(pixels),
      function(i) min(
          9L,
          (10L*sum(vapply(
              chosen,
              function(image) substring(image$pixels,i,i) == "1",
              logical(1)
          ))) %/% length(chosen)
      ),
      integer(1)
  )
}
