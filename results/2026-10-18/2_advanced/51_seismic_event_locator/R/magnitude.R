base10log <- function(value) log(value)/2.302585092994046
median_value <- function(values) {
  ordered <- sort(values)
  n <- length(ordered)
  if (n %% 2L) ordered[n %/% 2L+1L] else (ordered[n %/% 2L]+ordered[n %/% 2L+1L])/2
}
per_pick_magnitude <- function(pick,r,params) {
  local <- params$local_magnitude
  duration <- params$duration_magnitude
  md <- duration[1L]+duration[2L]*base10log(pick$duration/100)+duration[3L]*r
  ml <- if (pick$clipped) NULL else base10log(pick$amplitude)+local[1L]*base10log(r/100)+local[2L]*(r-100)+local[3L]
  list(r=r,ml=ml,md=md)
}
magnitude_hundredths <- function(value) if (value < 0) -floor(-value*100+0.5) else floor(value*100+0.5)
class_number <- function(value) floor((magnitude_hundredths(value)+5)/10)
magnitude_class <- function(value) {
  absolute <- abs(value)
  paste0(if (value < 0) "-" else "",sprintf("%.0f",absolute %/% 10),".",sprintf("%.0f",absolute %% 10))
}
frequency_statistics <- function(magnitudes) {
  classes <- vapply(magnitudes,class_number,numeric(1))
  values <- sort(unique(classes))
  counts <- vapply(values,function(value) sum(classes == value),integer(1))
  completeness <- values[order(-counts,values)[1L]]
  above <- classes[classes >= completeness]
  mc <- completeness/10
  mean <- sum(above)/(10*length(above))
  b <- 0.4342944819032518/(mean-(mc-0.05))
  list(
      values=values,
      counts=counts,
      completeness=completeness,
      nb=length(above),
      b=b,
      sigma=b/sqrt(length(above)),
      a=base10log(length(above))+b*mc
  )
}
