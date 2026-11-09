for (module in c("dataset","numerics","estimators","group_tests","cox","plot")) source(paste0(module,".R"))
number <- function(value,digits=4L) {
  if (is.null(value)) return("NA")
  text <- sprintf(paste0("%.",digits,"f"),value)
  if (startsWith(text,"-") && as.numeric(text) == 0) substring(text,2L) else text
}
day <- function(value) if (is.null(value)) "NA" else as.character(value)
percentile_time <- function(rows,threshold,column="survival") {
  for (row in rows) {
    value <- if (row$survival == 0) 0 else row[[column]]
    if (!is.null(value) && value <= threshold) return(row$time)
  }
  NULL
}
restricted_mean <- function(rows,tau) {
  selected <- Filter(function(r) r$time <= tau,rows)
  times <- c(0,vapply(selected,`[[`,integer(1),"time"),tau)
  survival <- c(1,vapply(selected,`[[`,numeric(1),"survival"))
  rectangles <- survival*diff(times)
  tails <- numeric(length(rectangles))
  tails[length(tails)] <- tail(rectangles,1L)
  for (i in rev(seq_len(length(tails)-1L))) tails[i] <- rectangles[i]+tails[i+1L]
  variance <- 0
  for (i in seq_along(selected)) {
    row <- selected[[i]]
    variance <- variance+tails[i+1L]*tails[i+1L]*(row$events/(row$risk*(row$risk-row$events)))
  }
  estimate <- tails[1L]
  error <- sqrt(variance)
  c(estimate,error,estimate-Z95*error,estimate+Z95*error)
}
collection_summary <- function(subjects,params) {
  rows <- kaplan_meier(subjects)
  life <- life_table(subjects,params$LIFE_TABLE[1L],params$LIFE_TABLE[2L])
  events <- sum(vapply(subjects,`[[`,integer(1),"event"))
  person_days <- sum(vapply(subjects,`[[`,integer(1),"time"))
  rate <- 1000*events/person_days
  eta <- Z95/sqrt(events)
  reverse <- lapply(subjects,function(s) { s$event <- 1L-s$event; s })
  followup <- percentile_time(kaplan_meier(reverse),0.5)
  life_median <- NULL
  previous <- 1
  for (row in life) {
    if (row$survival <= 0.5) {
      life_median <- row$start+params$LIFE_TABLE[1L]*(previous-0.5)/(previous-row$survival)
      break
    }
    previous <- row$survival
  }
  percentiles <- lapply(seq_len(3L),function(i) {
    q <- c(0.75,0.5,0.25)[i]
    list(
        percentile=c(25L,50L,75L)[i],
        time=percentile_time(rows,q),
        lower=percentile_time(rows,q,"lower"),
        upper=percentile_time(rows,q,"upper")
    )
  })
  list(rows=rows,life=life,subjects=length(subjects),events=events,censored=length(subjects)-events,
    maximum=max(vapply(subjects,`[[`,integer(1),"time")),person_days=person_days,rate=rate,
    lower=exp(log(rate)-eta),upper=exp(log(rate)+eta),followup=followup,life_median=life_median,
    percentiles=percentiles,rmst=restricted_mean(rows,params$TAU[1L]))
}
km_table_lines <- function(name,subjects,summary,params) {
  lines <- c(sprintf("group %s subjects %d events %d censored %d max_time %d",name,summary$subjects,summary$events,summary$censored,summary$maximum),
    sprintf(
        "person_days %d rate %s lower %s upper %s",
        summary$person_days,
        number(summary$rate),
        number(summary$lower),
        number(summary$upper)
    ),
    paste("followup_median",day(summary$followup)),paste("life_table_median",number(summary$life_median)))
  for (p in summary$percentiles) lines <- c(
      lines,
      sprintf("percentile %d time %s lower %s upper %s",p$percentile,day(p$time),day(p$lower),day(p$upper))
  )
  rmst <- summary$rmst
  lines <- c(
      lines,
      sprintf(
          "rmst tau %d estimate %s se %s lower %s upper %s",
          params$TAU[1L],
          number(rmst[1L]),
          number(rmst[2L]),
          number(rmst[3L]),
          number(rmst[4L])
      )
  )
  for (time in params$REPORT_TIMES) {
    row <- row_at(summary$rows,time)
    risk <- sum(vapply(subjects,function(s) s$time >= time,logical(1)))
    events <- sum(vapply(subjects,function(s) s$time <= time && s$event == 1L,logical(1)))
    lines <- c(lines,sprintf("at %d at_risk %d events %d survival %s std_err %s lower %s upper %s cum_hazard %s hazard_se %s",
      time,risk,events,number(row$survival),number(row$se),number(row$lower),number(row$upper),number(row$hazard),number(row$hazard_se)))
  }
  columns <- c("time","at_risk","events","censored","survival","std_err","lower","upper","cum_haz","haz_se")
  lines <- c(lines,paste(sprintf("%9s",columns),collapse=""))
  for (row in summary$rows) {
    fields <- c(as.character(c(row$time,row$risk,row$events,row$censored)),vapply(c("survival","se","lower","upper","hazard","hazard_se"),
      function(key) number(row[[key]]),character(1)))
    lines <- c(lines,paste(sprintf("%9s",fields),collapse=""))
  }
  lines
}
life_table_lines <- function(names,summaries) {
  lines <- "group,interval,at_risk,events,withdrawn,exposed,q,survival,std_err,hazard"
  for (name in names) for (row in summaries[[name]]$life) lines <- c(lines,paste(c(name,paste0(row$start,"-",row$stop),
    row$risk,row$events,row$withdrawn,number(
        row$exposed,
        1L
    ),number(row$q),number(row$survival),number(row$se),number(row$hazard)),collapse=","))
  lines
}
baseline_lines <- function(subjects,groups,collections,names) {
  lines <- "baseline"
  for (name in names) {
    rows <- collections[[name]]
    n <- length(rows)
    ages <- vapply(rows,`[[`,integer(1),"age")
    mean_age <- sum(ages)/n
    deviation <- sqrt(total((ages-mean_age)*(ages-mean_age))/(n-1L))
    ages <- sort(ages)
    median <- (ages[(n-1L) %/% 2L+1L]+ages[n %/% 2L+1L])/2
    males <- sum(vapply(rows,function(s) s$sex == "M",logical(1)))
    stages <- vapply(
        seq_len(4L),
        function(stage) sum(vapply(rows,function(s) s$stage == stage,logical(1))),
        numeric(1)
    )
    lines <- c(lines,sprintf("  group %s subjects %d age_mean %s age_sd %s age_median %s male %d stage %s",
      name,n,number(mean_age),number(deviation),number(median,1L),males,paste(stages,collapse=" ")))
  }
  ranked <- subjects[order(vapply(subjects,`[[`,integer(1),"age"))]
  ranks <- numeric(length(subjects))
  ids <- vapply(subjects,`[[`,integer(1),"id")
  ties <- 0
  position <- 1L
  while (position <= length(ranked)) {
    stop <- position
    while (stop <= length(ranked) && ranked[[stop]]$age == ranked[[position]]$age) stop <- stop+1L
    rank <- (position+stop-1L)/2
    for (i in seq.int(position,stop-1L)) ranks[match(ranked[[i]]$id,ids)] <- rank
    t <- stop-position
    ties <- ties+t*t*t-t
    position <- stop
  }
  weighted <- total(vapply(groups,function(group) {
    members <- collections[[group]]
    rank_sum <- total(ranks[match(vapply(members,`[[`,integer(1),"id"),ids)])
    rank_sum*rank_sum/length(members)
  },numeric(1)))
  n <- length(subjects)
  k <- length(groups)
  raw <- 12*weighted/(n*(n+1L))-3*(n+1L)
  statistic <- raw/(1-ties/(n*n*n-n))
  lines <- c(
      lines,
      sprintf(
          "  age kruskal_wallis chisq %s df %d p %s",
          number(statistic),
          k-1L,
          number(chi_square_p(statistic,k-1L))
      )
  )
  for (variable in c("sex","stage")) {
    levels <- sort(
        unique(vapply(subjects,function(s) as.character(s[[variable]]),character(1))),
        method="radix"
    )
    counts <- vapply(
        levels,
        function(level) sum(vapply(subjects,function(s) as.character(s[[variable]]) == level,logical(1))),
        numeric(1)
    )
    statistic <- 0
    for (group in groups) for (j in seq_along(levels)) {
      members <- collections[[group]]
      observed <- sum(vapply(members,function(s) as.character(s[[variable]]) == levels[j],logical(1)))
      expected <- length(members)*counts[j]/n
      statistic <- statistic+(observed-expected)*(observed-expected)/expected
    }
    df <- (k-1L)*(length(levels)-1L)
    lines <- c(
        lines,
        sprintf("  %s chisq %s df %d p %s",variable,number(statistic),df,number(chi_square_p(statistic,df)))
    )
  }
  lines
}
group_lines <- function(test) vapply(seq_along(test$groups),function(h)
  sprintf("  group %s events %d observed %s expected %s o_minus_e %s variance %s",test$groups[h],test$events[h],
    number(test$observed[h]),number(test$expected[h]),number(test$observed[h]-test$expected[h]),number(test$covariance[
        h,
        h
    ])),character(1))
test_fields <- function(test) sprintf(
    "chisq %s df %d p %s",
    number(test$statistic),
    test$degrees,
    number(test$p)
)
two_group <- function(subjects,groups,population) {
  test <- weighted_test(subjects,groups,"logrank",population)
  test$ratio <- (test$observed[2L]/test$expected[2L])/(test$observed[1L]/test$expected[1L])
  test$variance <- 1/test$expected[1L]+1/test$expected[2L]
  test$log_ratio <- log(test$ratio)
  test$lower <- exp(test$log_ratio-Z95*sqrt(test$variance))
  test$upper <- exp(test$log_ratio+Z95*sqrt(test$variance))
  test
}
difference_fields <- function(difference,error) {
  statistic <- difference/error
  sprintf("difference %s se %s lower %s upper %s z %s p %s",number(difference),number(error),
    number(difference-Z95*error),number(difference+Z95*error),number(statistic),number(chi_square_p(
        statistic*statistic,
        1L
    )))
}
comparison_sections <- function(subjects,params,collections,summaries,names) {
  groups <- params$GROUPS
  n <- length(subjects)
  k <- length(groups)
  sections <- list(baseline_lines(subjects,groups,collections,names))
  lines <- character()
  tests <- lapply(WEIGHTS,function(weight) weighted_test(subjects,groups,weight,n))
  for (i in seq_along(WEIGHTS)) lines <- c(
      lines,
      paste("test",WEIGHTS[i],test_fields(tests[[i]])),
      group_lines(tests[[i]])
  )
  test <- tests[[1L]]
  trend <- total(seq_len(k)*(test$observed-test$expected))
  variance <- total(vapply(
      seq_len(k),
      function(g) total(vapply(seq_len(k),function(h) (g*h)*test$covariance[g,h],numeric(1))),
      numeric(1)
  ))
  statistic <- trend*trend/variance
  sections[[length(sections)+1L]] <- c(
      lines,
      sprintf("test logrank_trend chisq %s df 1 p %s",number(statistic),number(chi_square_p(statistic,1L)))
  )
  variable <- params$STRATA[1L]
  levels <- sort(unique(vapply(subjects,function(s) as.character(s[[variable]]),character(1))),method="radix")
  strata <- lapply(levels,function(level) Filter(function(s) as.character(s[[variable]]) == level,subjects))
  lines <- character()
  for (weight in WEIGHTS) {
    tests <- lapply(strata,function(rows) weighted_test(rows,groups,weight,n))
    combined <- combine_strata(tests,groups)
    lines <- c(lines,sprintf("stratified %s by %s %s",weight,variable,test_fields(combined)))
    for (i in seq_along(levels)) {
      rows <- strata[[i]]
      test <- tests[[i]]
      lines <- c(lines,sprintf("  stratum %s subjects %d events %d chisq %s p %s",levels[i],length(rows),
        sum(vapply(rows,`[[`,integer(1),"event")),number(test$statistic),number(test$p)))
    }
    lines <- c(lines,group_lines(combined))
  }
  sections[[length(sections)+1L]] <- lines
  landmark <- params$LANDMARK[1L]
  selected <- Filter(function(s) s$time > landmark,subjects)
  test <- weighted_test(selected,groups,"logrank",n)
  sections[[length(sections)+1L]] <- c(
      sprintf("landmark %d subjects %d %s",landmark,length(selected),test_fields(test)),
      group_lines(test)
  )
  pairs <- list()
  for (a in seq_len(k-1L)) for (b in seq.int(a+1L,k)) pairs[[length(pairs)+1L]] <- groups[c(a,b)]
  tests <- lapply(pairs,function(pair) two_group(Filter(function(s) s$group %in% pair,subjects),pair,n))
  adjusted <- numeric(length(pairs))
  order <- order(vapply(tests,`[[`,numeric(1),"p"),seq_along(tests))
  previous <- 0
  for (rank in seq_along(order)) {
    i <- order[rank]
    previous <- max(previous,min(1,(length(pairs)-rank+1L)*tests[[i]]$p))
    adjusted[i] <- previous
  }
  lines <- "pairwise logrank adjust holm"
  for (i in seq_along(pairs)) {
    pair <- pairs[[i]]
    test <- tests[[i]]
    lines <- c(lines,sprintf("  %s %s chisq %s p %s p_holm %s hr %s lower %s upper %s",pair[1L],pair[2L],
      number(test$statistic),number(test$p),number(adjusted[i]),number(test$ratio),number(test$lower),number(test$upper)))
  }
  sections[[length(sections)+1L]] <- lines
  lines <- paste("subgroups reference",groups[1L])
  for (variable in params$SUBGROUPS) {
    levels <- sort(
        unique(vapply(subjects,function(s) as.character(s[[variable]]),character(1))),
        method="radix"
    )
    for (group in groups[-1L]) {
      tests <- list()
      for (level in levels) {
        selected <- Filter(
            function(s) as.character(s[[variable]]) == level && s$group %in% c(groups[1L],group),
            subjects
        )
        test <- two_group(selected,c(groups[1L],group),n)
        tests[[length(tests)+1L]] <- test
        lines <- c(lines,sprintf("  %s %s %s subjects %d events %d hr %s lower %s upper %s p %s",variable,level,group,
          length(selected),sum(vapply(selected,`[[`,integer(1),"event")),number(test$ratio),number(test$lower),number(test$upper),number(test$p)))
      }
      weights <- vapply(tests,function(test) 1/test$variance,numeric(1))
      logarithms <- vapply(tests,`[[`,numeric(1),"log_ratio")
      mean <- total(weights*logarithms)/total(weights)
      statistic <- total(weights*(logarithms-mean)*(logarithms-mean))
      df <- length(levels)-1L
      lines <- c(
          lines,
          sprintf(
              "  %s %s heterogeneity chisq %s df %d p %s",
              variable,
              group,
              number(statistic),
              df,
              number(chi_square_p(statistic,df))
          )
      )
    }
  }
  sections[[length(sections)+1L]] <- lines
  control <- summaries[[groups[1L]]]
  lines <- sprintf("rmst_difference tau %d reference %s",params$TAU[1L],groups[1L])
  for (group in groups[-1L]) {
    summary <- summaries[[group]]
    error <- sqrt(summary$rmst[2L]*summary$rmst[2L]+control$rmst[2L]*control$rmst[2L])
    lines <- c(lines,paste0("  ",group," ",difference_fields(summary$rmst[1L]-control$rmst[1L],error)))
  }
  sections[[length(sections)+1L]] <- lines
  lines <- paste("rate_ratio reference",groups[1L])
  for (group in groups[-1L]) {
    summary <- summaries[[group]]
    ratio <- summary$rate/control$rate
    error <- sqrt(1/summary$events+1/control$events)
    logarithm <- log(ratio)
    statistic <- logarithm/error
    lines <- c(lines,sprintf("  %s ratio %s lower %s upper %s z %s p %s",group,number(ratio),number(exp(logarithm-Z95*error)),
      number(exp(logarithm+Z95*error)),number(statistic),number(chi_square_p(statistic*statistic,1L))))
  }
  sections[[length(sections)+1L]] <- lines
  lines <- paste("survival_difference reference",groups[1L])
  for (time in params$REPORT_TIMES) {
    baseline <- row_at(control$rows,time)
    for (group in groups[-1L]) {
      row <- row_at(summaries[[group]]$rows,time)
      error <- sqrt(row$se*row$se+baseline$se*baseline$se)
      lines <- c(
          lines,
          sprintf("  at %d %s %s",time,group,difference_fields(row$survival-baseline$survival,error))
      )
    }
  }
  sections[[length(sections)+1L]] <- lines
  sections
}
covariate_vectors <- function(subjects,names) lapply(subjects,function(s) vapply(names,function(name)
  if (name == "age") s$age else if (name == "stage") s$stage else if (name == "male") as.integer(s$sex == "M") else as.integer(s$group == name),integer(1)))
coefficient_fields <- function(coefficient,error) {
  statistic <- coefficient/error
  sprintf("coef %s se %s z %s p %s hr %s lower %s upper %s",number(coefficient),number(error),number(statistic),
    number(chi_square_p(
        statistic*statistic,
        1L
    )),number(exp(coefficient)),number(exp(coefficient-Z95*error)),number(exp(coefficient+Z95*error)))
}
hazard_at <- function(rows,time) {
  for (row in rev(rows)) if (row[1L] <= time) return(row[2L])
  0
}
cox_lines <- function(subjects,params) {
  names <- params$COX
  vectors <- covariate_vectors(subjects,names)
  model <- fit_cox(subjects,vectors)
  beta <- model$beta
  final <- model$final
  null <- model$null
  covariance <- inverse_matrix(final$information)
  n <- length(subjects)
  p <- length(names)
  events <- sum(vapply(subjects,`[[`,integer(1),"event"))
  lines <- sprintf(
      "cox covariates %s subjects %d events %d event_times %d",
      paste(names,collapse=" "),
      n,
      events,
      length(final$event_sums)
  )
  for (iteration in model$iterations) lines <- c(lines,sprintf("iter %d loglik %s beta %s",iteration$number,
    number(iteration$loglik),paste(vapply(iteration$beta,number,character(1)),collapse=" ")))
  lines <- c(lines,sprintf("final loglik %s null_loglik %s",number(final$loglik),number(null$loglik)))
  for (c in seq_len(p)) lines <- c(
      lines,
      paste("term",names[c],coefficient_fields(beta[c],sqrt(covariance[c,c])))
  )
  group_indices <- which(!(names %in% c("age","male","stage")))
  for (i in seq_len(max(0L,length(group_indices)-1L))) for (j in seq.int(i+1L,length(group_indices))) {
    a <- group_indices[i]
    b <- group_indices[j]
    error <- sqrt(covariance[b,b]+covariance[a,a]-2*covariance[a,b])
    lines <- c(lines,paste("contrast",names[b],"vs",names[a],coefficient_fields(beta[b]-beta[a],error)))
  }
  likelihood_ratio <- 2*(final$loglik-null$loglik)
  wald <- total(vapply(seq_len(p),function(c) beta[c]*total(final$information[c,]*beta),numeric(1)))
  solution <- solve_system(null$information,null$score)
  score <- total(null$score*solution)
  statistics <- c(likelihood_ratio=likelihood_ratio,wald=wald,score=score)
  for (label in names(statistics)) lines <- c(
      lines,
      sprintf(
          "%s chisq %s df %d p %s",
          label,
          number(statistics[[label]]),
          p,
          number(chi_square_p(statistics[[label]],p))
      )
  )
  for (c in seq_len(p)) {
    likelihood <- if (p == 1L) null$loglik else fit_cox(
        subjects,
        lapply(vectors,function(x) x[-c])
    )$final$loglik
    statistic <- 2*(final$loglik-likelihood)
    lines <- c(
        lines,
        sprintf(
            "drop %s loglik %s chisq %s df 1 p %s",
            names[c],
            number(likelihood),
            number(statistic),
            number(chi_square_p(statistic,1L))
        )
    )
  }
  comparable <- concordant <- tied <- 0L
  for (i in seq_along(subjects)) {
    a <- subjects[[i]]
    if (a$event != 1L) next
    for (j in seq_along(subjects)) {
      b <- subjects[[j]]
      if (i == j || !(a$time < b$time || (a$time == b$time && b$event == 0L))) next
      comparable <- comparable+1L
      if (identical(vectors[[i]],vectors[[j]])) tied <- tied+1L else
        if (final$predictors[i] > final$predictors[j]) concordant <- concordant+1L
    }
  }
  lines <- c(
      lines,
      sprintf(
          "concordance %s comparable %d concordant %d tied %d",
          number((2*concordant+tied)/(2*comparable)),
          comparable,
          concordant,
          tied
      )
  )
  event_indices <- which(vapply(subjects,function(s) s$event == 1L,logical(1)))
  event_indices <- event_indices[order(vapply(subjects[event_indices],`[[`,integer(1),"time"),vapply(subjects[event_indices],`[[`,integer(1),"id"))]
  count_events <- length(event_indices)
  mean_time <- sum(vapply(subjects[event_indices],`[[`,integer(1),"time"))/count_events
  for (c in seq_len(p)) {
    residuals <- vapply(event_indices,function(i) {
      sums <- final$event_sums[[as.character(subjects[[i]]$time)]]
      vectors[[i]][c]-sums$s1[c]/sums$s0
    },numeric(1))
    mean_residual <- total(residuals)/count_events
    sxy <- sxx <- syy <- 0
    for (j in seq_along(event_indices)) {
      i <- event_indices[j]
      x <- residuals[j]-mean_residual
      y <- subjects[[i]]$time-mean_time
      sxy <- sxy+x*y
      sxx <- sxx+x*x
      syy <- syy+y*y
    }
    rho <- sxy/sqrt(sxx*syy)
    statistic <- 0.5*log((1+rho)/(1-rho))*sqrt(count_events-3L)
    lines <- c(
        lines,
        sprintf(
            "ph_check %s rho %s z %s p %s",
            names[c],
            number(rho),
            number(statistic),
            number(chi_square_p(statistic*statistic,1L))
        )
    )
  }
  hazard <- list()
  cumulative <- 0
  times <- sort(as.integer(names(final$event_sums)))
  for (time in times) {
    sums <- final$event_sums[[as.character(time)]]
    cumulative <- cumulative+sums$events/sums$s0
    hazard[[length(hazard)+1L]] <- c(time,cumulative)
  }
  residuals <- lapply(seq_along(subjects),function(i) {
    s <- subjects[[i]]
    martingale <- s$event-hazard_at(hazard,s$time)*exp(final$predictors[i])
    deviance <- if (s$event == 1L) sqrt(-2*(martingale+log(1-martingale))) else sqrt(-2*martingale)
    if (!(martingale > 0)) deviance <- -deviance
    list(subject=s,martingale=martingale,deviance=deviance)
  })
  residual_order <- order(-abs(vapply(residuals,`[[`,numeric(1),"deviance")),vapply(subjects,`[[`,integer(1),"id"))
  r <- params$RESIDUALS[1L]
  lines <- c(lines,sprintf("residuals top %d",r))
  for (item in residuals[residual_order[seq_len(r)]]) {
    s <- item$subject
    lines <- c(
        lines,
        sprintf(
            "  id %d group %s time %d event %d martingale %s deviance %s",
            s$id,
            s$group,
            s$time,
            s$event,
            number(item$martingale),
            number(item$deviance)
        )
    )
  }
  means <- list()
  for (c in seq_len(p)) if (names[c] %in% c(
      "age",
      "male",
      "stage"
  )) means[[names[c]]] <- sum(vapply(vectors,`[`,integer(1),c))/n
  fields <- vapply(names(means),function(name) paste(name,number(means[[name]])),character(1))
  lines <- c(lines,paste("adjusted_survival mean",if (length(fields)) paste(fields,collapse=" ") else "none"))
  groups <- params$GROUPS
  risks <- setNames(vapply(groups,function(group) exp(total(vapply(seq_len(p),function(c)
    beta[c]*(if (names[c] %in% names(means)) means[[names[c]]] else as.integer(names[c] == group)),numeric(1)))),numeric(1)),groups)
  for (time in params$REPORT_TIMES) {
    cumulative <- hazard_at(hazard,time)
    fields <- vapply(groups,function(group) paste(group,number(exp(-cumulative*risks[[group]]))),character(1))
    lines <- c(lines,sprintf("  at %d %s",time,paste(fields,collapse=" ")))
  }
  medians <- vapply(groups,function(group) {
    selected <- which(vapply(hazard,function(row) exp(-row[2L]*risks[[group]]) <= 0.5,logical(1)))
    paste(group,if (length(selected)) as.character(hazard[[selected[1L]]][1L]) else "NA")
  },character(1))
  c(lines,paste0("  median ",paste(medians,collapse=" ")))
}
plot_lines <- function(params,collections,summaries) {
  groups <- params$GROUPS
  width <- params$PLOT[1L]
  height <- params$PLOT[2L]
  time_limit <- params$PLOT[3L]
  divisions <- params$PLOT[4L]
  estimates <- setNames(lapply(groups,function(group) summaries[[group]]$rows),groups)
  legend <- paste(paste(LETTERS[seq_along(groups)],groups),collapse=" ")
  lines <- c(sprintf("km_plot width %d height %d time %d",width,height,time_limit),paste("legend",legend),
    curve_lines(groups,collections,estimates,width,height,time_limit),sprintf(
        "time 0 to %d days, %d days per column",
        time_limit,
        time_limit %/% width
    ))
  times <- (seq_len(divisions+1L)-1L)*(time_limit %/% divisions)
  lines <- c(lines,paste("at_risk",paste(times,collapse=" ")))
  for (group in groups) {
    counts <- vapply(
        times,
        function(time) sum(vapply(collections[[group]],function(s) s$time >= time,logical(1))),
        numeric(1)
    )
    lines <- c(lines,paste(group,paste(counts,collapse=" ")))
  }
  lines
}
join_sections <- function(sections) {
  lines <- character()
  for (section in sections) {
    if (length(lines)) lines <- c(lines,"")
    lines <- c(lines,section)
  }
  lines
}
write_lines <- function(name,lines) writeLines(lines,file.path("output",name),useBytes=TRUE)
main <- function() {
  data <- read_dataset()
  subjects <- data$subjects
  params <- data$params
  groups <- params$GROUPS
  names <- c(groups,"all")
  collections <- setNames(
      lapply(names,function(group) Filter(function(s) group == "all" || s$group == group,subjects)),
      names
  )
  summaries <- setNames(lapply(names,function(name) collection_summary(collections[[name]],params)),names)
  dir.create("output",showWarnings=FALSE)
  tables <- lapply(names,function(name) km_table_lines(name,collections[[name]],summaries[[name]],params))
  write_lines("km_tables.txt",join_sections(tables))
  write_lines("life_table.csv",life_table_lines(names,summaries))
  write_lines("tests.txt",join_sections(comparison_sections(subjects,params,collections,summaries,names)))
  write_lines("cox.txt",cox_lines(subjects,params))
  write_lines("km_plot.txt",plot_lines(params,collections,summaries))
}
main()
