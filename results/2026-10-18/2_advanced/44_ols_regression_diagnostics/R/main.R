for (module in c("dataframe","formula","qr_solver","inference","diagnostics")) source(paste0(module,".R"))
table <- function(header,rows,marks=rep("",length(rows))) {
  records <- c(list(header),lapply(rows,as.character))
  widths <- vapply(seq_along(header),function(c) max(vapply(Filter(function(row) c <= length(row),records),
    function(row) nchar(row[c],type="bytes"),integer(1))),integer(1))
  lines <- character()
  for (i in seq_along(records)) {
    row <- records[[i]]
    line <- paste0(row[1L],strrep(" ",widths[1L]-nchar(row[1L])))
    for (c in seq_along(row)[-1L]) line <- paste0(line,"  ",strrep(" ",widths[c]-nchar(row[c])),row[c])
    mark <- if (i == 1L) "" else marks[i-1L]
    if (nzchar(mark)) line <- paste(line,mark)
    lines <- c(lines,sub(" +$","",line))
  }
  lines
}
data_summary <- function(data) {
  numeric <- data$columns[!data$kinds[data$columns]]
  rows <- lapply(numeric,function(name) {
    values <- unlist(lapply(data$rows,`[[`,name),use.names=FALSE)
    n <- length(values)
    mean <- ordered_sum(values)/n
    sd <- sqrt(ordered_sum((values-mean)*(values-mean))/(n-1L))
    c(name,n,length(data$rows)-n,four(mean),four(sd),four(min(values)),four(max(values)))
  })
  lines <- c(sprintf("Data: %d rows, %d columns",length(data$rows),length(data$columns)),"","Numeric columns:",
    table(c("column","n","missing","Mean","SD","Min","Max"),rows),"","Categorical columns:")
  for (name in data$columns) {
    if (!data$kinds[[name]]) next
    values <- unlist(lapply(data$rows,`[[`,name),use.names=FALSE)
    levels <- sort(unique(values),method="radix")
    counts <- vapply(levels,function(level) paste(level,sum(values == level)),character(1))
    lines <- c(lines,sprintf("%s: %d values, %d missing, %d levels: %s",name,length(values),length(data$rows)-length(values),
      length(levels),paste(counts,collapse=", ")))
  }
  rows <- lapply(numeric,function(a) {
    fields <- a
    for (b in numeric) {
      pairs <- Filter(function(row) !is.null(row[[a]]) && !is.null(row[[b]]),data$rows)
      xs <- vapply(pairs,`[[`,numeric(1),a)
      ys <- vapply(pairs,`[[`,numeric(1),b)
      mx <- ordered_sum(xs)/length(pairs)
      my <- ordered_sum(ys)/length(pairs)
      cross <- ordered_sum((xs-mx)*(ys-my))
      sx <- ordered_sum((xs-mx)*(xs-mx))
      sy <- ordered_sum((ys-my)*(ys-my))
      fields <- c(fields,four(cross/sqrt(sx*sy)))
    }
    fields
  })
  c(lines,"","Correlations (pairwise complete observations):",table(c("column",numeric),rows),"")
}
information_criteria <- function(fit) {
  n <- fit$n
  r <- fit$rank
  likelihood <- 0.5*(ordered_sum(log(fit$weights))-n*(log(2*pi)+1-log(n)+log(fit$rss)))
  list(ll=likelihood,aic=-2*likelihood+2*(r+1L),bic=-2*likelihood+log(n)*(r+1L))
}
residual_quantile <- function(values,proportion) {
  position <- (length(values)-1L)*proportion
  k <- floor(position)
  if (k+1L < length(values)) values[k+1L]+(position-k)*(values[k+2L]-values[k+1L]) else values[k+1L]
}
model_statistics <- function(fit,confidence) {
  n <- fit$n
  r <- fit$rank
  df <- n-r
  sigma <- sqrt(fit$rss/df)
  sw <- ordered_sum(fit$weights)
  mean <- ordered_sum(fit$weights*fit$response)/sw
  tss <- ordered_sum(fit$weights*(fit$response-mean)*(fit$response-mean))
  r2 <- 1-fit$rss/tss
  adjusted <- 1-(1-r2)*(n-1L)/df
  f <- ((tss-fit$rss)/(r-1L))/(fit$rss/df)
  criteria <- information_criteria(fit)
  press <- ordered_sum((fit$eps/(1-fit$leverage))*(fit$eps/(1-fit$leverage)))
  residuals <- sort(fit$eps)
  quantiles <- vapply(c(0,0.25,0.5,0.75,1),function(p) residual_quantile(residuals,p),numeric(1))
  c(list(df=df,sigma=sigma,weight_sum=sw,tss=tss,r2=r2,adjusted=adjusted,f=f,p=f_pvalue(f,r-1L,df)),
    criteria,list(press=press,predicted=1-press/tss,quantiles=quantiles,critical=t_quantile(confidence,df)))
}
fit_subset <- function(design,terms,tolerance) fit_ols(
    subset_matrix(design,terms),
    design$response,
    design$weights,
    tolerance
)
marginal_tests <- function(design,fit,terms,tolerance) {
  lapply(removable(design$model,terms),function(index) {
    reduced <- fit_subset(design,terms[terms != index],tolerance)
    df <- fit$rank-reduced$rank
    ss <- reduced$rss-fit$rss
    f <- if (df > 0L) (ss/df)/(fit$rss/(fit$n-fit$rank)) else NULL
    p <- if (df > 0L) f_pvalue(f,df,fit$n-fit$rank) else NULL
    list(index=index,name=design$model$terms[[index]]$name,df=df,ss=ss,rss=reduced$rss,f=f,p=p)
  })
}
coefficient_inference <- function(fit,stats) {
  lapply(seq_along(fit$beta),function(j) {
    estimate <- fit$beta[[j]]
    if (is.null(estimate)) return(list(
        estimate=NULL,
        se=NULL,
        t=NULL,
        p=NULL,
        lower=NULL,
        upper=NULL,
        robust_se=NULL,
        robust_t=NULL,
        robust_p=NULL
    ))
    k <- match(j,fit$accepted)
    se <- stats$sigma*sqrt(fit$variance[k])
    t <- estimate/se
    robust <- sqrt(ordered_sum(fit$eps*fit$eps/((1-fit$leverage)*(1-fit$leverage))*fit$g[,k]*fit$g[,k]))
    robust_t <- estimate/robust
    list(estimate=estimate,se=se,t=t,p=t_pvalue(t,stats$df),lower=estimate-stats$critical*se,
      upper=estimate+stats$critical*se,robust_se=robust,robust_t=robust_t,robust_p=t_pvalue(
          robust_t,
          stats$df
      ))
  })
}
sequential_anova <- function(design,fit) {
  results <- list()
  for (index in seq_along(design$model$terms)) {
    effects <- which(vapply(design$columns[fit$accepted],function(column) column$term == index,logical(1)))
    df <- length(effects)
    if (!df) next
    ss <- ordered_sum(fit$effects[effects]*fit$effects[effects])
    ms <- ss/df
    f <- ms/(fit$rss/(fit$n-fit$rank))
    results[[length(results)+1L]] <- list(
        name=design$model$terms[[index]]$name,
        df=df,
        ss=ss,
        ms=ms,
        f=f,
        p=f_pvalue(f,df,fit$n-fit$rank)
    )
  }
  results
}
variance_inflation <- function(design,fit,stats,params) {
  lapply(fit$accepted[-1L],function(column) {
    response <- fit$matrix[,column]
    others <- fit$accepted[fit$accepted != column]
    auxiliary <- fit_ols(fit$matrix[,others,drop=FALSE],response,fit$weights,params$RANK_TOL[1L])
    mean <- ordered_sum(fit$weights*response)/stats$weight_sum
    tss <- ordered_sum(fit$weights*(response-mean)*(response-mean))
    r2 <- 1-auxiliary$rss/tss
    vif <- 1/(1-r2)
    list(name=design$columns[[column]]$name,value=vif,high=vif > params$VIF[1L])
  })
}
reset_test <- function(fit,tolerance) {
  matrix <- cbind(fit$matrix[,fit$accepted,drop=FALSE],fit$fitted*fit$fitted,fit$fitted*fit$fitted*fit$fitted)
  augmented <- fit_ols(matrix,fit$response,fit$weights,tolerance)
  q <- augmented$rank-fit$rank
  df <- fit$n-augmented$rank
  f <- ((fit$rss-augmented$rss)/q)/(augmented$rss/df)
  c(f,q,df,f_pvalue(f,q,df))
}
diagnostic_decisions <- function(design,fit,diagnostic,params) {
  rows <- diagnostic$rows
  dw <- diagnostic$dw
  dw_label <- if (dw < params$DURBIN_WATSON[1L]) "positive autocorrelation" else if (dw > 4-params$DURBIN_WATSON[1L])
    "negative autocorrelation" else "no autocorrelation"
  bp_label <- if (diagnostic$bp[3L] < params$BREUSCH_PAGAN[1L]) "heteroscedastic" else "homoscedastic"
  jb_label <- if (diagnostic$jb[2L] < params$NORMALITY[1L]) "non-normal" else "normal"
  outlier <- which.max(abs(vapply(rows,`[[`,numeric(1),"studentized")))
  unadjusted <- t_pvalue(rows[[outlier]]$studentized,fit$n-fit$rank-1L)
  largest_cooks <- head(order(-vapply(rows,`[[`,numeric(1),"cooks"),seq_along(rows)),3L)
  largest_dfbetas <- lapply(seq_along(fit$accepted),function(k) {
    i <- which.max(abs(vapply(rows,function(row) row$dfbetas[k],numeric(1))))
    list(name=design$columns[[fit$accepted[k]]]$name,row=design$numbers[i],value=rows[[i]]$dfbetas[k])
  })
  counts <- setNames(
      vapply(
          c("H","O","C","F"),
          function(flag) sum(vapply(rows,function(row) grepl(flag,row$flags,fixed=TRUE),logical(1))),
          numeric(1)
      ),
      c("H","O","C","F")
  )
  counts <- c(counts,any=sum(vapply(rows,function(row) row$flags != "-",logical(1))))
  list(dw_label=dw_label,bp_label=bp_label,jb_label=jb_label,outlier=outlier,unadjusted=unadjusted,
    bonferroni=min(
        1,
        fit$n*unadjusted
    ),largest_cooks=largest_cooks,largest_dfbetas=largest_dfbetas,counts=counts)
}
prediction_report <- function(number,design,fit,stats,prediction_data) {
  lines <- character()
  predicted_count <- actual_count <- covered_count <- 0L
  squared_errors <- 0
  for (i in seq_along(prediction_data$rows)) {
    row <- prediction_data$rows[[i]]
    fields <- as.character(c(number,i))
    if (!predictable(design,row)) {
      lines <- c(lines,paste(c(fields,rep("NA",9L)),collapse=","))
      next
    }
    predicted_count <- predicted_count+1L
    values <- design_values(design,row)
    predicted <- ordered_sum(vapply(fit$accepted,function(j) values[j]*fit$beta[[j]],numeric(1)))
    u <- vapply(seq_len(fit$rank),function(k) ordered_sum(values[fit$accepted]*fit$inverse[,k]),numeric(1))
    se <- stats$sigma*sqrt(ordered_sum(u*u))
    cw <- stats$critical*se
    pw <- stats$critical*sqrt(stats$sigma*stats$sigma+se*se)
    lower <- predicted-pw
    upper <- predicted+pw
    fields <- c(fields,vapply(c(predicted,se,predicted-cw,predicted+cw,lower,upper),four,character(1)))
    actual <- row[[design$model$response]]
    if (is.null(actual)) fields <- c(fields,rep("NA",3L)) else {
      actual_count <- actual_count+1L
      error <- actual-predicted
      squared_errors <- squared_errors+error*error
      covered <- lower <= actual && actual <= upper
      covered_count <- covered_count+as.integer(covered)
      fields <- c(fields,four(actual),four(error),if (covered) "yes" else "no")
    }
    lines <- c(lines,paste(fields,collapse=","))
  }
  list(lines=lines,check=list(predicted=predicted_count,actual=actual_count,
    rmse=if (actual_count) sqrt(squared_errors/actual_count) else NULL,covered=covered_count))
}
analyze_model <- function(number,design,params,prediction_data) {
  fit <- fit_ols(design$matrix,design$response,design$weights,params$RANK_TOL[1L])
  stats <- model_statistics(fit,params$CONFIDENCE[1L])
  diagnostic <- calculate_diagnostics(fit,params)
  predictions <- prediction_report(number,design,fit,stats,prediction_data)
  list(number=number,design=design,fit=fit,stats=stats,coefficients=coefficient_inference(fit,stats),
    anova=sequential_anova(design,fit),marginal=marginal_tests(
        design,
        fit,
        seq_along(design$model$terms),
        params$RANK_TOL[1L]
    ),
    vif=variance_inflation(design,fit,stats,params),diagnostics=diagnostic,decisions=diagnostic_decisions(
        design,
        fit,
        diagnostic,
        params
    ),
    reset=reset_test(fit,params$RANK_TOL[1L]),predictions=predictions$lines,check=predictions$check)
}
diagnostic_summary <- function(report) {
  design <- report$design
  fit <- report$fit
  d <- report$diagnostics
  decisions <- report$decisions
  bp <- d$bp
  jb <- d$jb
  reset <- report$reset
  i <- decisions$outlier
  counts <- decisions$counts
  lines <- c("Diagnostics:",sprintf("Durbin-Watson: %s (%s)",four(d$dw),decisions$dw_label),
    sprintf(
        "Breusch-Pagan: %s on %d DF, p-value: %s (%s)",
        four(bp[1L]),
        bp[2L],
        probability(bp[3L]),
        decisions$bp_label
    ),
    sprintf(
        "Jarque-Bera: %s on 2 DF, p-value: %s, skewness %s, kurtosis %s (%s)",
        four(jb[1L]),
        probability(jb[2L]),
        four(jb[3L]),
        four(jb[4L]),
        decisions$jb_label
    ),
    sprintf(
        "RESET (powers 2 and 3): F %s on %d and %d DF, p-value: %s",
        four(reset[1L]),
        reset[2L],
        reset[3L],
        probability(reset[4L])
    ),
    sprintf("Outlier test: row %d, studentized %s, unadjusted p-value: %s, Bonferroni p-value: %s",design$numbers[i],
      four(d$rows[[i]]$studentized),probability(decisions$unadjusted),probability(decisions$bonferroni)),
    sprintf(
        "Flagged rows: leverage %d, outlier %d, cooks %d, dffits %d, any %d",
        counts[["H"]],
        counts[["O"]],
        counts[["C"]],
        counts[["F"]],
        counts[["any"]]
    ),
    "Largest Cook's distances:")
  for (i in decisions$largest_cooks) {
    row <- d$rows[[i]]
    lines <- c(
        lines,
        sprintf(
            "row %d: cooks_d %s, leverage %s, studentized %s, flags %s",
            design$numbers[i],
            four(row$cooks),
            four(fit$leverage[i]),
            four(row$studentized),
            row$flags
        )
    )
  }
  c(lines,"Largest absolute DFBETAS:",table(c("column","row","DFBETAS"),lapply(decisions$largest_dfbetas,
    function(item) c(item$name,item$row,four(item$value)))))
}
model_summary <- function(report,total_rows,confidence) {
  design <- report$design
  fit <- report$fit
  stats <- report$stats
  names <- vapply(design$columns,`[[`,character(1),"name")
  coefficients <- report$coefficients
  aliases <- if (length(fit$aliases)) paste(names[fit$aliases],collapse=", ") else "none"
  q <- stats$quantiles
  lines <- c(sprintf("Model %d: %s",report$number,design$model$original),paste("Terms:",paste(vapply(design$model$terms,`[[`,character(1),"name"),collapse=", ")),
    paste(
        "Weights:",
        if (is.null(design$model$weight)) "none" else design$model$weight
    ),sprintf("Observations: %d used, %d dropped",fit$n,total_rows-fit$n),
    sprintf("Columns: %d, rank %d, aliased: %s",fit$p,fit$rank,aliases),"",
    sprintf(
        "Residuals: Min %s, 1Q %s, Median %s, 3Q %s, Max %s",
        four(q[1L]),
        four(q[2L]),
        four(q[3L]),
        four(q[4L]),
        four(q[5L])
    ),"","Coefficients:")
  rows <- lapply(seq_along(names),function(i) {
    coef <- coefficients[[i]]
    c(names[i],four(coef$estimate),four(coef$se),four(coef$t),probability(coef$p))
  })
  lines <- c(lines,table(c("term","Estimate","Std. Error","t value","Pr(>|t|)"),rows,vapply(coefficients,function(coef) significance(coef$p),character(1))),
    "---","Signif. codes: 0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1","",
    sprintf("Residual standard error: %s on %d degrees of freedom",four(stats$sigma),stats$df),
    sprintf("Multiple R-squared: %s, Adjusted R-squared: %s",four(stats$r2),four(stats$adjusted)),
    sprintf(
        "F-statistic: %s on %d and %d DF, p-value: %s",
        four(stats$f),
        fit$rank-1L,
        stats$df,
        probability(stats$p)
    ),
    sprintf("Log-likelihood: %s, AIC: %s, BIC: %s",four(stats$ll),four(stats$aic),four(stats$bic)),
    sprintf("PRESS: %s, Predicted R-squared: %s",four(stats$press),four(stats$predicted)),"",
    sprintf("Confidence intervals (level %s, t %s):",four(confidence),four(stats$critical)))
  rows <- lapply(
      seq_along(names),
      function(i) c(names[i],four(coefficients[[i]]$lower),four(coefficients[[i]]$upper))
  )
  lines <- c(lines,table(c("term","Lower","Upper"),rows),"","Robust standard errors (HC3):")
  rows <- lapply(seq_along(names),function(i) {
    coef <- coefficients[[i]]
    c(names[i],four(coef$robust_se),four(coef$robust_t),probability(coef$robust_p))
  })
  lines <- c(lines,table(c("term","Std. Error","t value","Pr(>|t|)"),rows,vapply(coefficients,function(coef) significance(coef$robust_p),character(1))),
    "","Analysis of variance (sequential):")
  rows <- lapply(report$anova,function(t) c(t$name,t$df,four(t$ss),four(t$ms),four(t$f),probability(t$p)))
  rows <- c(rows,list(c("Residuals",stats$df,four(fit$rss),four(fit$rss/stats$df))))
  lines <- c(lines,table(c("term","Df","Sum Sq","Mean Sq","F value","Pr(>F)"),rows,
    c(
        vapply(report$anova,function(t) significance(t$p),character(1)),
        ""
    )),"","Marginal F tests (drop one term):")
  rows <- lapply(report$marginal,function(t) c(t$name,t$df,four(t$ss),four(t$rss),four(t$f),probability(t$p)))
  lines <- c(lines,table(c("term","Df","Sum Sq","RSS","F value","Pr(>F)"),rows,vapply(report$marginal,function(t) significance(t$p),character(1))),
    "","Variance inflation factors:")
  rows <- lapply(report$vif,function(v) c(v$name,four(v$value)))
  c(
      lines,
      table(c("column","VIF"),rows,vapply(report$vif,function(v) if (v$high) "high" else "",character(1))),
      "",
      diagnostic_summary(report)
  )
}
summary_report <- function(data,reports,params) {
  lines <- data_summary(data)
  for (i in seq_along(reports)) {
    if (i > 1L) lines <- c(lines,"")
    lines <- c(lines,model_summary(reports[[i]],length(data$rows),params$CONFIDENCE[1L]))
  }
  rows <- lapply(reports,function(r) c(r$number,r$fit$n,r$fit$rank,four(r$stats$sigma),four(r$stats$r2),four(r$stats$adjusted),
    four(r$stats$predicted),four(r$stats$aic),four(r$stats$bic)))
  lines <- c(
      lines,
      "",
      "Model comparison:",
      table(c("model","n","rank","sigma","R-squared","Adj. R-squared","Pred. R-squared","AIC","BIC"),rows),
      "",
      "Prediction check:"
  )
  for (report in reports) {
    check <- report$check
    lines <- c(lines,sprintf("model %d: %d predicted, %d with actual values, RMSE %s, inside prediction interval %d",
      report$number,check$predicted,check$actual,four(check$rmse),check$covered))
  }
  lines
}
diagnostics_csv <- function(reports) {
  lines <- "model,row,fitted,residual,leverage,studentized,cooks_d,dffits,flags"
  for (r in reports) for (i in seq_along(r$diagnostics$rows)) {
    row <- r$diagnostics$rows[[i]]
    fields <- c(
        r$number,
        r$design$numbers[i],
        vapply(
            c(r$fit$fitted[i],r$fit$residual[i],r$fit$leverage[i],row$studentized,row$cooks,row$dffits),
            four,
            character(1)
        ),
        row$flags
    )
    lines <- c(lines,paste(fields,collapse=","))
  }
  lines
}
selection_report <- function(report,params) {
  design <- report$design
  model <- design$model
  tolerance <- params$RANK_TOL[1L]
  alpha <- params$ALPHA_REMOVE[1L]
  terms <- seq_along(model$terms)
  fit <- report$fit
  lines <- sprintf("Backward elimination (model 1, alpha %s, rows %d)",four(alpha),fit$n)
  step <- 1L
  repeat {
    criteria <- information_criteria(fit)
    df <- fit$n-fit$rank
    lines <- c(
        lines,
        sprintf(
            "Step %d: %s (RSS %s, df %d, AIC %s)",
            step,
            format_formula(model,terms),
            four(fit$rss),
            df,
            four(criteria$aic)
        )
    )
    if (!length(terms)) {
      lines <- c(lines,"  stop: no removable terms")
      break
    }
    tests <- marginal_tests(design,fit,terms,tolerance)
    for (t in tests) lines <- c(
        lines,
        sprintf("  - %s: F %s on %d and %d DF, p-value %s",t$name,four(t$f),t$df,df,probability(t$p))
    )
    largest <- tests[[which.max(vapply(tests,`[[`,numeric(1),"p"))]]
    if (largest$p <= alpha) {
      lines <- c(
          lines,
          sprintf("  stop: largest p-value %s is not above %s",probability(largest$p),four(alpha))
      )
      break
    }
    lines <- c(lines,paste("  remove",largest$name))
    terms <- terms[terms != largest$index]
    fit <- fit_subset(design,terms,tolerance)
    step <- step+1L
  }
  lines <- c(
      lines,
      paste("Final model:",format_formula(model,terms)),
      "",
      sprintf("Forward selection by AIC (model 1, rows %d)",length(design$rows))
  )
  terms <- integer()
  step <- 1L
  repeat {
    fit <- fit_subset(design,terms,tolerance)
    aic <- information_criteria(fit)$aic
    lines <- c(lines,sprintf("Step %d: %s (AIC %s)",step,format_formula(model,terms),four(aic)))
    options <- candidates(model,terms)
    if (!length(options)) {
      lines <- c(lines,"  stop: no candidate terms remain")
      break
    }
    choices <- list()
    for (index in options) {
      subset <- sort(c(terms,index))
      candidate_aic <- information_criteria(fit_subset(design,subset,tolerance))$aic
      choices[[length(choices)+1L]] <- list(index=index,aic=candidate_aic,subset=subset)
      lines <- c(lines,sprintf("  + %s: AIC %s",model$terms[[index]]$name,four(candidate_aic)))
    }
    choice <- choices[[which.min(vapply(choices,`[[`,numeric(1),"aic"))]]
    if (choice$aic >= aic) {
      lines <- c(lines,"  stop: no candidate lowers the AIC")
      break
    }
    lines <- c(lines,paste("  add",model$terms[[choice$index]]$name))
    terms <- choice$subset
    step <- step+1L
  }
  lines <- c(lines,paste("Final model:",format_formula(model,terms)),"")
  subsets <- list()
  for (mask in seq.int(0L,2^length(model$terms)-1L)) {
    subset <- which(vapply(
        seq_along(model$terms),
        function(i) bitwAnd(mask,bitwShiftL(1L,i-1L)) != 0L,
        logical(1)
    ))
    if (!hierarchical(model,subset)) next
    fit <- fit_subset(design,subset,tolerance)
    criteria <- information_criteria(fit)
    subsets[[length(subsets)+1L]] <- list(
        bic=criteria$bic,
        mask=mask,
        aic=criteria$aic,
        rank=fit$rank,
        subset=subset
    )
  }
  subsets <- subsets[order(vapply(subsets,`[[`,numeric(1),"bic"),vapply(subsets,`[[`,numeric(1),"mask"))]
  lines <- c(
      lines,
      sprintf("Best subsets by BIC (model 1, rows %d, subsets %d)",length(design$rows),length(subsets))
  )
  for (position in seq_len(min(params$BEST_SUBSETS[1L],length(subsets)))) {
    subset <- subsets[[position]]
    lines <- c(
        lines,
        sprintf(
            "%d. BIC %s, AIC %s, rank %d: %s",
            position,
            four(subset$bic),
            four(subset$aic),
            subset$rank,
            format_formula(model,subset$subset)
        )
    )
  }
  lines
}
plot_grid <- function(horizontal,vertical,lo,hi,width,height,limit) {
  grid <- matrix(0L,height,width)
  for (i in seq_along(horizontal)) {
    column <- min(floor((horizontal[i]-lo)/(hi-lo)*width),width-1L)
    row <- max(0L,min(floor((limit-vertical[i])/(2*limit)*height),height-1L))
    grid[row+1L,column+1L] <- grid[row+1L,column+1L]+1L
  }
  grid
}
plot_frame <- function(grid) {
  height <- nrow(grid)
  width <- ncol(grid)
  border <- paste0("+",strrep("-",width),"+")
  c(border,vapply(seq_len(height),function(i) {
    empty <- if (i-1L == height %/% 2L) "-" else "."
    cells <- ifelse(grid[i,] >= 10L,"*",ifelse(grid[i,] > 0L,as.character(grid[i,]),empty))
    paste0("|",paste(cells,collapse=""),"|")
  },character(1)),border)
}
residual_plot <- function(report,params) {
  width <- params$PLOT[1L]
  height <- params$PLOT[2L]
  limit <- params$PLOT[3L]
  fit <- report$fit
  studentized <- vapply(report$diagnostics$rows,`[[`,numeric(1),"studentized")
  lo <- min(fit$fitted)
  hi <- max(fit$fitted)
  grid <- plot_grid(fit$fitted,studentized,lo,hi,width,height,limit)
  lines <- c(sprintf("Model %d: studentized residuals vs fitted values",report$number),
    sprintf(
        "fitted %s to %s, studentized %s to %s",
        four(lo),
        four(hi),
        four(-limit),
        four(limit)
    ),plot_frame(grid),
    sprintf(
        "points: %d, above +2: %d, below -2: %d, outside range: %d",
        fit$n,
        sum(studentized > 2),
        sum(studentized < -2),
        sum(abs(studentized) > limit)
    ),
    "Histogram of studentized residuals:")
  counts <- rowSums(grid)
  maximum_count <- max(counts)
  for (i in seq_along(counts)) {
    n <- counts[i]
    lower <- limit-2*limit*i/height
    upper <- limit-2*limit*(i-1L)/height
    bar <- (n*40+maximum_count-1) %/% maximum_count
    lines <- c(
        lines,
        paste0(
            sprintf("%s to %s: %d",four(lower),four(upper),n),
            if (bar > 0L) paste0(" ",strrep("#",bar)) else ""
        )
    )
  }
  hi <- max(fit$leverage)
  c(lines,sprintf("Model %d: studentized residuals vs leverage",report$number),
    sprintf("leverage 0.0000 to %s, studentized %s to %s",four(hi),four(-limit),four(limit)),
    plot_frame(plot_grid(fit$leverage,studentized,0,hi,width,height,limit)))
}
main <- function() {
  data <- read_table("input/data.csv")
  prediction_data <- read_table("input/predict.csv",data$kinds)
  params <- read_params()
  models <- lapply(readLines("input/model.txt"),parse_model)
  reports <- lapply(
      seq_along(models),
      function(i) analyze_model(i,build_design(models[[i]],data),params,prediction_data)
  )
  contents <- list("summary.txt"=summary_report(data,reports,params),"diagnostics.csv"=diagnostics_csv(reports),
    "selection.txt"=selection_report(
        reports[[1L]],
        params
    ),"predictions.csv"=c("model,row,fit,se_fit,conf_lower,conf_upper,pred_lower,pred_upper,actual,error,covered",
      unlist(lapply(reports,`[[`,"predictions"),use.names=FALSE)))
  plots <- character()
  for (i in seq_along(reports)) {
    if (i > 1L) plots <- c(plots,"")
    plots <- c(plots,residual_plot(reports[[i]],params))
  }
  contents[["residual_plot.txt"]] <- plots
  for (name in names(contents)) writeLines(contents[[name]],file.path("output",name),useBytes=TRUE)
}
main()
