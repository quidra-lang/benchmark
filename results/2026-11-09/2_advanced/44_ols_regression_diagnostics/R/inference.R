log_gamma <- function(x) {
  coefficients <- c(
      76.18009172947146,
      -86.50532032941677,
      24.01409824083091,
      -1.231739572450155,
      0.001208650973866179,
      -0.000005395239384953
  )
  t <- x+5.5
  adjustment <- t-(x+0.5)*log(t)
  series <- 1.000000000190015
  for (j in seq_along(coefficients)) series <- series+coefficients[j]/(x+j)
  -adjustment+log(2.5066282746310005*series/x)
}
replace_small <- function(value) if (abs(value) < 1e-300) 1e-300 else value
beta_fraction <- function(a,b,x) {
  c <- 1
  d <- 1/replace_small(1-(a+b)*x/(a+1))
  h <- d
  for (m in seq_len(1000L)) {
    q <- m*(b-m)*x/((a-1+2*m)*(a+2*m))
    d <- 1/replace_small(1+q*d)
    c <- replace_small(1+q/c)
    h <- h*(d*c)
    q <- -(a+m)*(a+b+m)*x/((a+2*m)*(a+1+2*m))
    d <- 1/replace_small(1+q*d)
    c <- replace_small(1+q/c)
    delta <- d*c
    h <- h*delta
    if (abs(delta-1) < 1e-15) break
  }
  h
}
incomplete_beta <- function(x,a,b) {
  if (x <= 0) return(0)
  if (x >= 1) return(1)
  factor <- exp(log_gamma(a+b)-log_gamma(a)-log_gamma(b)+a*log(x)+b*log(1-x))
  if (x < (a+1)/(a+b+2)) factor*beta_fraction(a,b,x)/a else 1-factor*beta_fraction(b,a,1-x)/b
}
upper_gamma <- function(a,x) {
  if (x <= 0) return(1)
  factor <- exp(-x+a*log(x)-log_gamma(a))
  if (x < a+1) {
    term <- 1/a
    e <- a
    series <- term
    for (unused in seq_len(1000L)) {
      e <- e+1
      term <- term*(x/e)
      series <- series+term
      if (abs(term) < abs(series)*1e-15) break
    }
    return(1-series*factor)
  }
  beta <- x+1-a
  c <- 1/1e-300
  d <- 1/beta
  h <- d
  for (i in seq_len(1000L)) {
    q <- -i*(i-a)
    beta <- beta+2
    d <- 1/replace_small(q*d+beta)
    c <- replace_small(beta+q/c)
    delta <- d*c
    h <- h*delta
    if (abs(delta-1) < 1e-15) break
  }
  factor*h
}
t_pvalue <- function(t,df) incomplete_beta(df/(df+t*t),df/2,0.5)
f_pvalue <- function(f,a,b) incomplete_beta(b/(b+a*f),b/2,a/2)
chi_pvalue <- function(x,df) upper_gamma(df/2,x/2)
t_quantile <- function(confidence,df) {
  lo <- 0
  hi <- 1000
  for (unused in seq_len(100L)) {
    mid <- (lo+hi)/2
    if (t_pvalue(mid,df) > 1-confidence) lo <- mid else hi <- mid
  }
  (lo+hi)/2
}
significance <- function(p) {
  if (is.null(p)) "" else if (p < 0.001) "***" else if (p < 0.01) "**" else if (p < 0.05) "*" else if (p < 0.1) "." else ""
}
four <- function(value) {
  if (is.null(value)) return("NA")
  text <- sprintf("%.4f",value)
  if (text == "-0.0000") "0.0000" else text
}
probability <- function(value) if (is.null(value)) "NA" else if (value < 0.0001) "<0.0001" else four(value)
