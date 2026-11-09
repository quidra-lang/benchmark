calculate_diagnostics <- function(fit,params) {
  n <- fit$n
  r <- fit$rank
  df <- n-r
  sigma <- sqrt(fit$rss/df)
  rows <- lapply(seq_len(n),function(i) {
    h <- fit$leverage[i]
    residual <- fit$eps[i]
    z <- residual/(sigma*sqrt(1-h))
    studentized <- z*sqrt((df-1)/(df-z*z))
    cooks <- z*z*h/(r*(1-h))
    dffits <- studentized*sqrt(h/(1-h))
    flags <- ""
    if (h > params$LEVERAGE[1L]*r/n) flags <- paste0(flags,"H")
    if (abs(studentized) > params$STUDENTIZED[1L]) flags <- paste0(flags,"O")
    if (cooks > params$COOK[1L]/n) flags <- paste0(flags,"C")
    if (abs(dffits) > params$DFFITS[1L]*sqrt(r/n)) flags <- paste0(flags,"F")
    deleted <- sigma*sqrt((df-z*z)/(df-1))
    dfbetas <- fit$g[i,]*residual/(1-h)/(deleted*sqrt(fit$variance))
    list(
        standardized=z,
        studentized=studentized,
        cooks=cooks,
        dffits=dffits,
        flags=if (nzchar(flags)) flags else "-",
        dfbetas=dfbetas
    )
  })
  dw <- ordered_sum(diff(fit$eps)*diff(fit$eps))/fit$rss
  squared <- fit$eps*fit$eps
  auxiliary <- fit_ols(fit$matrix[,fit$accepted,drop=FALSE],squared,rep(1,n),params$RANK_TOL[1L])
  mean <- ordered_sum(squared)/n
  tss <- ordered_sum((squared-mean)*(squared-mean))
  bp <- n*(1-auxiliary$rss/tss)
  bp_df <- auxiliary$rank-1L
  mean <- ordered_sum(fit$eps)/n
  centered <- fit$eps-mean
  m2 <- ordered_sum(centered*centered)/n
  m3 <- ordered_sum(centered*centered*centered)/n
  m4 <- ordered_sum(centered*centered*centered*centered)/n
  skewness <- m3/(m2*sqrt(m2))
  kurtosis <- m4/(m2*m2)
  jb <- n/6*(skewness*skewness+(kurtosis-3)*(kurtosis-3)/4)
  list(rows=rows,dw=dw,bp=c(bp,bp_df,chi_pvalue(bp,bp_df)),jb=c(jb,chi_pvalue(jb,2L),skewness,kurtosis))
}
