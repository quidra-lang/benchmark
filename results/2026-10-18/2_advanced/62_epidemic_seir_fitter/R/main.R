source("data_io.R")
source("models.R")
source("integrator.R")
source("fitting.R")
source("report.R")

ordered_sum <- function(values) {
  total <- 0
  for (value in values) total <- total+value
  total
}
squared_errors <- function(series,coefficient,observations) {
  total <- 0
  for (i in seq_along(series)) {
    difference <- coefficient*series[i]-observations[i]
    total <- total+difference*difference
  }
  total
}
peak <- function(series) which.max(series)
line <- function(s,name,...) {
  s[[name]] <- c(s[[name]],paste(...,collapse=" "))
}
integer_text <- function(value) sprintf("%.0f",value)
multiplier_sequence <- function(interventions,days) {
  result <- numeric(days)
  index <- 1L
  for (day in seq_len(days)) {
    while (index < length(interventions) && interventions[[index+1L]]$day <= day) index <- index+1L
    result[day] <- interventions[[index]]$multiplier
  }
  result
}
final_size <- function(reproduction) {
  if (reproduction <= 1) return(0)
  lo <- 1-1/reproduction
  hi <- 1
  for (unused in seq_len(20L)) {
    middle <- (lo+hi)/2
    if (1-middle-exp(-reproduction*middle) > 0) lo <- middle else hi <- middle
  }
  (lo+hi)/2
}
power_method <- function(matrix) {
  n <- nrow(matrix)
  vector <- rep(1/n,n)
  eigenvalue <- 0
  for (unused in seq_len(200L)) {
    product <- vapply(seq_len(n),function(g) ordered_sum(matrix[g,]*vector),numeric(1))
    eigenvalue <- ordered_sum(product)
    vector <- product/eigenvalue
  }
  list(value=eigenvalue,vector=vector)
}
prepare_study <- function(data) {
  s <- list2env(data,parent=emptyenv())
  s$days <- length(s$cases)
  s$populations <- vapply(s$groups,function(g) as.numeric(g$population),numeric(1))
  s$fatalities <- vapply(s$groups,function(g) g$fatality,numeric(1))
  s$population <- sum(s$populations)
  s$case_total <- sum(as.numeric(s$cases))
  s$death_total <- sum(as.numeric(s$deaths))
  s$fatality <- ordered_sum(s$populations*s$fatalities)/s$population
  s$sigma <- s$params$sigma
  s$gamma0 <- s$params$gamma
  exposed <- s$params$initial[1L]
  infectious <- s$params$initial[2L]
  s$initial <- c(s$population-exposed-infectious,exposed,infectious,0,0,0)
  s$sir_initial <- c(s$population-exposed-infectious,exposed+infectious,0,0)
  s$age_initial <- numeric()
  for (n in s$populations) {
    e <- exposed*n/s$population
    i <- infectious*n/s$population
    s$age_initial <- c(s$age_initial,n-e-i,e,i,0,0,0)
  }
  s$multipliers <- multiplier_sequence(s$interventions,s$days)
  s$week_ranges <- lapply(seq.int(1L,s$days,7L),function(first) c(first,min(first+6L,s$days)))
  s$cache <- new.env(hash=TRUE,parent=emptyenv())
  s$fit_lines <- character()
  s$reproduction_lines <- character()
  s$age_lines <- character()
  s
}
rmse <- function(s,error,n=s$days) sqrt(error/n)
seird_states <- function(s,beta,gamma,multipliers=s$multipliers,initial=s$initial,sigma=s$sigma) {
  simulate(seird(s$population,sigma,s$fatality,beta,gamma),initial,multipliers,6L)
}
incidence_for <- function(s,beta,gamma) {
  key <- paste(sprintf("%a",beta),sprintf("%a",gamma),sep=",")
  if (!exists(key,s$cache,inherits=FALSE)) assign(
      key,
      vapply(seird_states(s,beta,gamma),function(state) state[6L],numeric(1)),
      s$cache
  )
  get(key,s$cache,inherits=FALSE)
}
fit_error <- function(s,beta,gamma,rho) squared_errors(incidence_for(s,beta,gamma),rho,s$cases)
golden_records <- function(s,round_number,name,search) {
  for (index in seq_along(search$records)) {
    values <- search$records[[index]]
    line(
        s,
        "fit_lines",
        "golden",
        round_number,
        name,
        index-1L,
        "a",
        fmt(values[1L],6L),
        "b",
        fmt(values[2L],6L),
        "c",
        fmt(values[3L],6L),
        "d",
        fmt(values[4L],6L),
        "rmse",
        fmt(rmse(s,values[5L])),
        fmt(rmse(s,values[6L]))
    )
  }
  line(s,"fit_lines","golden_result",round_number,name,fmt(search$point,6L),"sse",fmt(search$value,1L))
}
fit_model <- function(s) {
  bmin <- s$params$beta_grid[[1L]]
  bmax <- s$params$beta_grid[[2L]]
  nb <- s$params$beta_grid[[3L]]
  rmin <- s$params$rho_grid[[1L]]
  rmax <- s$params$rho_grid[[2L]]
  nr <- s$params$rho_grid[[3L]]
  betas <- vapply(0:(nb-1L),function(i) bmin+(bmax-bmin)*i/(nb-1L),numeric(1))
  rhos <- vapply(0:(nr-1L),function(j) rmin+(rmax-rmin)*j/(nr-1L),numeric(1))
  s$delta_beta <- (bmax-bmin)/(nb-1L)
  s$delta_rho <- (rmax-rmin)/(nr-1L)
  line(
      s,
      "fit_lines",
      "data days",
      s$days,
      "cases",
      integer_text(s$case_total),
      "deaths",
      integer_text(s$death_total),
      "population",
      integer_text(s$population),
      "fatality",
      fmt(s$fatality,6L)
  )
  line(s,"fit_lines","grid gamma",fmt(s$gamma0),"rho",paste(vapply(rhos,fmt,character(1)),collapse=" "))
  best <- Inf
  best_i <- best_j <- 1L
  for (i in seq_along(betas)) {
    errors <- numeric(nr)
    for (j in seq_along(rhos)) {
      value <- fit_error(s,betas[i],s$gamma0,rhos[j])
      errors[j] <- value
      if (value < best) {
        best <- value
        best_i <- i
        best_j <- j
      }
    }
    line(
        s,
        "fit_lines",
        "grid beta",
        fmt(betas[i]),
        "rmse",
        paste(vapply(errors,function(value) fmt(rmse(s,value),2L),character(1)),collapse=" ")
    )
  }
  grid_sse <- best
  grid_beta <- beta <- betas[best_i]
  grid_rho <- rho <- rhos[best_j]
  line(
      s,
      "fit_lines",
      "grid_best beta",
      fmt(grid_beta),
      "rho",
      fmt(grid_rho),
      "sse",
      fmt(grid_sse,1L),
      "rmse",
      fmt(rmse(s,grid_sse))
  )
  iterations <- s$params$golden[1L]
  for (round_number in seq_len(s$params$golden[2L])) {
    search <- golden(
        function(value) fit_error(s,value,s$gamma0,rho),
        beta-s$delta_beta,
        beta+s$delta_beta,
        iterations
    )
    golden_records(s,round_number,"beta",search)
    beta <- search$point
    search <- golden(
        function(value) fit_error(s,beta,s$gamma0,value),
        rho-s$delta_rho,
        rho+s$delta_rho,
        iterations
    )
    golden_records(s,round_number,"rho",search)
    rho <- search$point
    golden_sse <- search$value
  }
  golden_beta <- beta
  nm <- s$params$nelder_mead
  search <- nelder_mead(
      function(b,g) fit_error(s,b,g,rho),
      beta,
      s$gamma0,
      s$params$simplex[1L],
      s$params$simplex[2L],
      nm[[1L]],
      nm[[2L]],
      nm[[3L]],
      nm[[4L]],
      nm[[5L]]
  )
  for (vertex in search$initial) line(
      s,
      "fit_lines",
      "simplex",
      vertex$number,
      "beta",
      fmt(vertex$beta,6L),
      "gamma",
      fmt(vertex$gamma,6L),
      "rmse",
      fmt(rmse(s,vertex$value))
  )
  for (iteration in seq_along(search$records)) {
    record <- search$records[[iteration]]
    vertex <- record$vertex
    line(
        s,
        "fit_lines",
        "nelder_mead",
        iteration,
        record$operation,
        "beta",
        fmt(vertex$beta,6L),
        "gamma",
        fmt(vertex$gamma,6L),
        "rmse",
        fmt(rmse(s,vertex$value))
    )
  }
  for (rank in seq_along(search$vertices)) {
    vertex <- search$vertices[[rank]]
    line(
        s,
        "fit_lines",
        "final_simplex",
        rank,
        "beta",
        fmt(vertex$beta,6L),
        "gamma",
        fmt(vertex$gamma,6L),
        "rmse",
        fmt(rmse(s,vertex$value))
    )
  }
  vertex <- search$vertices[[1L]]
  s$beta <- vertex$beta
  s$gamma <- vertex$gamma
  s$rho <- rho
  s$sse_nm <- vertex$value
  s$r0 <- s$beta/s$gamma
  mean <- s$case_total/s$days
  sst <- ordered_sum(vapply(s$cases,function(value) (value-mean)*(value-mean),numeric(1)))
  line(
      s,
      "fit_lines",
      "fitted beta",
      fmt(s$beta,6L),
      "gamma",
      fmt(s$gamma,6L),
      "rho",
      fmt(rho,6L),
      "sigma",
      fmt(s$sigma,6L),
      "r0",
      fmt(s$r0)
  )
  line(
      s,
      "fit_lines",
      "sse grid",
      fmt(grid_sse,1L),
      "golden",
      fmt(golden_sse,1L),
      "nelder_mead",
      fmt(s$sse_nm,1L),
      "rmse",
      fmt(rmse(s,s$sse_nm)),
      "r2",
      fmt(1-s$sse_nm/sst)
  )
  stages <- list(
      list("grid",grid_beta,s$gamma0,grid_rho,grid_sse),
      list("golden",golden_beta,s$gamma0,rho,golden_sse),
      list("nelder_mead",s$beta,s$gamma,rho,s$sse_nm)
  )
  for (stage in stages) line(
      s,
      "fit_lines",
      "stage",
      stage[[1L]],
      "beta",
      fmt(stage[[2L]],6L),
      "gamma",
      fmt(stage[[3L]],6L),
      "rho",
      fmt(stage[[4L]],6L),
      "r0",
      fmt(stage[[2L]]/stage[[3L]]),
      "rmse",
      fmt(rmse(s,stage[[5L]]))
  )
}
fitted_diagnostics <- function(s) {
  s$states <- c(list(s$initial),seird_states(s,s$beta,s$gamma))
  s$incidence <- vapply(s$states[-1L],function(state) state[6L],numeric(1))
  s$reported <- s$rho*s$incidence
  s$residuals <- s$cases-s$reported
  s$model_deaths <- vapply(seq_len(s$days),function(d) s$states[[d+1L]][5L]-s$states[[d]][5L],numeric(1))
  s$rt <- vapply(seq_len(s$days),function(d) s$r0*s$multipliers[d]*s$states[[d]][1L]/s$population,numeric(1))
  s$averages <- vapply(seq_len(s$days),function(d) sum(s$cases[max(1L,d-6L):d])/min(d,7L),numeric(1))
  s$cumulative_cases <- numeric(s$days)
  s$cumulative_reported <- numeric(s$days)
  observed_total <- reported_total <- 0
  for (d in seq_len(s$days)) {
    observed_total <- observed_total+s$cases[d]
    reported_total <- reported_total+s$reported[d]
    s$cumulative_cases[d] <- observed_total
    s$cumulative_reported[d] <- reported_total
  }
  s$reported_total <- reported_total
  absolute <- abs(s$residuals)
  largest <- peak(absolute)
  positive <- sum(s$residuals > 0)
  runs <- 1L+sum((s$residuals[-1L] > 0) != (s$residuals[-s$days] > 0))
  square <- ordered_sum(s$residuals*s$residuals)
  differences <- s$residuals[-1L]-s$residuals[-s$days]
  dw <- ordered_sum(differences*differences)/square
  line(
      s,
      "fit_lines",
      "residuals sum",
      fmt(ordered_sum(s$residuals),1L),
      "mae",
      fmt(ordered_sum(absolute)/s$days,1L),
      "max",
      fmt(s$residuals[largest],1L),
      "day",
      largest,
      "positive",
      positive,
      "runs",
      runs,
      "durbin_watson",
      fmt(dw)
  )
  correlations <- vapply(
      seq_len(7L),
      function(lag) ordered_sum(s$residuals[seq_len(s$days-lag)]*s$residuals[seq.int(lag+1L,s$days)])/square,
      numeric(1)
  )
  line(s,"fit_lines","autocorrelation",paste(vapply(correlations,fmt,character(1)),collapse=" "))
  outliers <- 0L
  for (d in seq_len(s$days)) {
    z <- s$residuals[d]/sqrt(s$reported[d])
    if (abs(z) > s$params$outlier) {
      line(s,"fit_lines","outlier",d,"observed",s$cases[d],"fitted",fmt(s$reported[d],1L),"z",fmt(z))
      outliers <- outliers+1L
    }
  }
  line(s,"fit_lines","outliers",outliers)
  factors <- numeric(7L)
  for (weekday in seq_len(7L)) {
    indices <- seq.int(weekday,s$days,7L)
    observed <- sum(as.numeric(s$cases[indices]))
    fitted <- ordered_sum(s$reported[indices])
    factors[weekday] <- observed/fitted
    line(
        s,
        "fit_lines",
        "weekday",
        weekday,
        "observed",
        integer_text(observed),
        "fitted",
        fmt(fitted,1L),
        "factor",
        fmt(factors[weekday])
    )
  }
  adjusted <- s$reported*factors[(seq_len(s$days)-1L) %% 7L+1L]
  line(s,"fit_lines","weekday_adjusted rmse",fmt(rmse(s,squared_errors(adjusted,1,s$cases))))
  infections <- ordered_sum(s$incidence)
  line(
      s,
      "fit_lines",
      "burden infections",
      fmt(infections,1L),
      "ascertainment",
      fmt(s$case_total/infections),
      "deaths_per_infection",
      fmt(s$death_total/infections,6L)
  )
  numerator <- ordered_sum(s$model_deaths*s$deaths)
  scale <- numerator/ordered_sum(s$model_deaths*s$model_deaths)
  line(
      s,
      "fit_lines",
      "deaths observed",
      integer_text(s$death_total),
      "model",
      fmt(s$states[[length(s$states)]][5L],1L),
      "rmse",
      fmt(rmse(s,squared_errors(s$model_deaths,1,s$deaths))),
      "scale",
      fmt(scale),
      "implied_fatality",
      fmt(s$fatality*scale,6L),
      "cfr",
      fmt(s$death_total/s$case_total)
  )
  correlations <- numeric(s$params$death_lag+1L)
  for (lag in 0:s$params$death_lag) {
    head <- as.numeric(s$cases[seq_len(s$days-lag)])
    tail <- as.numeric(s$deaths[seq.int(lag+1L,s$days)])
    a <- sum(head*tail)
    b <- sum(head*head)
    y <- sum(tail*tail)
    correlations[lag+1L] <- a/sqrt(b*y)
    line(s,"fit_lines","death_lag",lag,"correlation",fmt(correlations[lag+1L]),"cfr",fmt(sum(tail)/sum(head)))
  }
  line(s,"fit_lines","death_best_lag",peak(correlations)-1L)
  previous <- 0
  for (week in seq_along(s$week_ranges)) {
    first <- s$week_ranges[[week]][1L]
    last <- s$week_ranges[[week]][2L]
    observed <- sum(as.numeric(s$cases[first:last]))
    growth <- if (week == 1L) "-" else fmt(observed/previous)
    line(
        s,
        "fit_lines",
        "weekly",
        week,
        "days",
        first,
        last,
        "observed",
        integer_text(observed),
        "fitted",
        fmt(ordered_sum(s$reported[first:last]),1L),
        "deaths_observed",
        integer_text(sum(as.numeric(s$deaths[first:last]))),
        "deaths_model",
        fmt(ordered_sum(s$model_deaths[first:last]),1L),
        "growth",
        growth
    )
    previous <- observed
  }
}
profiles <- function(s) {
  fitted <- c(s$beta,s$gamma,s$rho)
  variance <- s$sse_nm/(s$days-3L)
  s$standard_errors <- numeric(3L)
  names <- c("beta","gamma","rho")
  for (index in seq_along(names)) {
    value <- fitted[index]
    errors <- numeric(11L)
    for (offset in -5:5) {
      point <- value*(1+offset/100)
      parameters <- fitted
      parameters[index] <- point
      error <- fit_error(s,parameters[1L],parameters[2L],parameters[3L])
      errors[offset+6L] <- error
      line(s,"fit_lines","profile",names[index],offset,"value",fmt(point,6L),"rmse",fmt(rmse(s,error)))
    }
    h <- value/100
    curvature <- (errors[7L]-2*errors[6L]+errors[5L])/(h*h)
    s$standard_errors[index] <- sqrt(2*variance/curvature)
    line(s,"fit_lines","profile_se",names[index],fmt(s$standard_errors[index],6L))
  }
}
backtest <- function(s) {
  holdout <- s$params$holdout
  training <- s$days-holdout
  cache <- new.env(hash=TRUE,parent=emptyenv())
  training_error <- function(beta,rho) {
    key <- sprintf("%a",beta)
    if (!exists(key,cache,inherits=FALSE)) assign(
        key,
        vapply(
            seird_states(s,beta,s$gamma,multipliers=s$multipliers[seq_len(training)]),
            function(state) state[6L],
            numeric(1)
        ),
        cache
    )
    squared_errors(get(key,cache,inherits=FALSE),rho,s$cases[seq_len(training)])
  }
  iterations <- s$params$golden[1L]
  beta <- golden(
      function(value) training_error(value,s$rho),
      s$beta-s$delta_beta,
      s$beta+s$delta_beta,
      iterations
  )$point
  search <- golden(function(value) training_error(beta,value),s$rho-s$delta_rho,s$rho+s$delta_rho,iterations)
  rho <- search$point
  tail <- seq.int(training+1L,s$days)
  forecasts <- rho*incidence_for(s,beta,s$gamma)[tail]
  test_error <- squared_errors(forecasts,1,s$cases[tail])
  full_error <- squared_errors(s$reported[tail],1,s$cases[tail])
  line(
      s,
      "fit_lines",
      "backtest train_days",
      training,
      "beta",
      fmt(beta,6L),
      "rho",
      fmt(rho,6L),
      "train_rmse",
      fmt(rmse(s,search$value,training)),
      "test_rmse",
      fmt(rmse(s,test_error,holdout)),
      "full_fit_test_rmse",
      fmt(rmse(s,full_error,holdout))
  )
  for (index in seq_along(forecasts)) {
    d <- training+index
    line(
        s,
        "fit_lines",
        "backtest_day",
        d,
        "observed",
        s$cases[d],
        "forecast",
        fmt(forecasts[index],1L),
        "error",
        fmt(s$cases[d]-forecasts[index],1L)
    )
  }
}
estimate_effects <- function(s) {
  estimated <- s$interventions
  after <- s$sse_nm
  width <- s$params$effect_width
  if (length(s$interventions) > 1L) for (index in seq.int(2L,length(s$interventions))) {
    day <- s$interventions[[index]]$day
    given <- s$interventions[[index]]$multiplier
    objective <- function(value) {
      changed <- estimated
      changed[[index]] <- list(day=day,multiplier=value)
      states <- seird_states(s,s$beta,s$gamma,multipliers=multiplier_sequence(changed,s$days))
      squared_errors(vapply(states,function(state) state[6L],numeric(1)),s$rho,s$cases)
    }
    search <- golden(objective,given-width,given+width,s$params$golden[1L])
    estimated[[index]] <- list(day=day,multiplier=search$point)
    after <- search$value
    line(
        s,
        "fit_lines",
        "effect",
        index,
        "day",
        day,
        "given",
        fmt(given),
        "estimated",
        fmt(search$point,6L),
        "sse",
        fmt(after,1L)
    )
  }
  line(s,"fit_lines","effect_sse before",fmt(s$sse_nm,1L),"after",fmt(after,1L),"rmse",fmt(rmse(s,after)))
}
sensitivity <- function(s) {
  fitted <- c(s$beta,s$gamma,s$sigma,s$rho)
  names <- c("beta","gamma","sigma","rho")
  for (index in seq_along(names)) for (factor in c(0.9,1.1)) {
    parameters <- fitted
    parameters[index] <- parameters[index]*factor
    beta <- parameters[1L]
    gamma <- parameters[2L]
    rho <- parameters[4L]
    states <- seird_states(s,beta,gamma,sigma=parameters[3L])
    incidence <- vapply(states,function(state) state[6L],numeric(1))
    day <- peak(incidence)
    line(
        s,
        "fit_lines",
        "sensitivity",
        names[index],
        fmt(factor,2L),
        "r0",
        fmt(beta/gamma),
        "rmse",
        fmt(rmse(s,squared_errors(incidence,rho,s$cases))),
        "peak_day",
        day,
        "peak",
        fmt(rho*incidence[day],1L),
        "attack",
        fmt((s$population-states[[length(states)]][1L])/s$population)
    )
  }
}
age_states_for <- function(s,contacts=s$normalized_contacts,multipliers=s$multipliers,initial=s$age_initial) {
  simulate(
      age_seird(s$populations,s$fatalities,s$sigma,s$beta,s$gamma,contacts),
      initial,
      multipliers,
      seq.int(6L,length(s$age_initial),6L)
  )
}
next_generation <- function(s,contacts) {
  n <- length(s$groups)
  matrix <- matrix(0,n,n)
  for (g in seq_len(n)) for (h in seq_len(n)) matrix[g,h] <- s$r0*contacts[
      g,
      h
  ]*s$populations[g]/s$populations[h]
  matrix
}
analyze_age <- function(s) {
  n <- length(s$groups)
  row_totals <- vapply(seq_len(n),function(g) ordered_sum(s$contacts[g,]),numeric(1))
  kbar <- ordered_sum(s$populations*row_totals)/s$population
  s$normalized_contacts <- s$contacts/kbar
  matrix <- next_generation(s,s$normalized_contacts)
  eigen <- power_method(matrix)
  for (g in seq_len(n)) line(
      s,
      "age_lines",
      "ngm",
      s$groups[[g]]$name,
      paste(vapply(matrix[g,],fmt,character(1)),collapse=" ")
  )
  line(
      s,
      "age_lines",
      "r0_age",
      fmt(eigen$value),
      "ratio",
      fmt(eigen$value/s$r0),
      "kbar",
      fmt(kbar),
      "eigenvector",
      paste(vapply(eigen$vector,fmt,character(1)),collapse=" ")
  )
  final <- rep(1,n)
  for (unused in seq_len(100L)) final <- vapply(
      seq_len(n),
      function(g) 1-exp(-ordered_sum(s$r0*s$normalized_contacts[g,]*final)),
      numeric(1)
  )
  long_states <- age_states_for(s,multipliers=rep(1,730L))
  end_state <- long_states[[length(long_states)]]
  simulated <- vapply(
      seq_len(n),
      function(g) (s$populations[g]-end_state[6L*g-5L])/s$populations[g],
      numeric(1)
  )
  for (g in seq_len(n)) line(
      s,
      "age_lines",
      "final_size_age",
      s$groups[[g]]$name,
      "equation",
      fmt(final[g]),
      "simulated",
      fmt(simulated[g])
  )
  line(
      s,
      "age_lines",
      "final_size_age total equation",
      fmt(ordered_sum(s$populations*final)/s$population),
      "simulated",
      fmt(ordered_sum(s$populations*simulated)/s$population)
  )
  s$age_states <- c(list(s$age_initial),age_states_for(s))
  inflows <- seq.int(6L,6L*n,6L)
  s$age_incidence <- vapply(s$age_states[-1L],function(state) ordered_sum(state[inflows]),numeric(1))
  for (day in seq.int(1L,s$days,7L)) {
    previous <- s$age_states[[day]]
    matrix <- matrix(0,n,n)
    for (g in seq_len(n)) for (h in seq_len(n)) matrix[g,h] <- s$multipliers[day]*s$r0*s$normalized_contacts[
        g,
        h
    ]*previous[6L*g-5L]/s$populations[h]
    eigen <- power_method(matrix)
    line(s,"age_lines","age_rt",day,fmt(eigen$value),"homogeneous",fmt(s$rt[day]))
  }
  for (week in seq_along(s$week_ranges)) {
    first <- s$week_ranges[[week]][1L]
    last <- s$week_ranges[[week]][2L]
    totals <- vapply(
        seq_len(n),
        function(g) ordered_sum(vapply(first:last,function(d) s$age_states[[d+1L]][6L*g],numeric(1))),
        numeric(1)
    )
    line(
        s,
        "age_lines",
        "age_weekly",
        week,
        "days",
        first,
        last,
        paste(vapply(totals,function(value) fmt(value,1L),character(1)),collapse=" ")
    )
  }
  infections <- vapply(
      seq_len(n),
      function(g) ordered_sum(vapply(s$age_states[-1L],function(state) state[6L*g],numeric(1))),
      numeric(1)
  )
  infection_total <- ordered_sum(infections)
  end_state <- s$age_states[[length(s$age_states)]]
  for (g in seq_len(n)) {
    incidence <- vapply(s$age_states[-1L],function(state) state[6L*g],numeric(1))
    day <- peak(incidence)
    attack <- (s$populations[g]-end_state[6L*g-5L])/s$populations[g]
    line(
        s,
        "age_lines",
        "age",
        s$groups[[g]]$name,
        "attack",
        fmt(attack),
        "infections",
        fmt(infections[g],1L),
        "share",
        fmt(infections[g]/infection_total),
        "deaths",
        fmt(end_state[6L*g-1L],1L),
        "peak_day",
        day,
        "peak",
        fmt(incidence[day],1L)
    )
  }
  for (change in s$params$contact_change) {
    tau <- vapply(s$groups,function(group) if (group$name == change$group) change$factor else 1,numeric(1))
    contacts <- matrix(0,n,n)
    for (g in seq_len(n)) for (h in seq_len(n)) contacts[g,h] <- s$normalized_contacts[g,h]*tau[g]*tau[h]
    eigen <- power_method(next_generation(s,contacts))
    states <- age_states_for(s,contacts=contacts)
    infections <- ordered_sum(vapply(states,function(state) ordered_sum(state[inflows]),numeric(1)))
    end_state <- states[[length(states)]]
    deaths <- ordered_sum(end_state[seq.int(5L,6L*n,6L)])
    attack <- ordered_sum(vapply(
        seq_len(n),
        function(g) s$populations[g]-end_state[6L*g-5L],
        numeric(1)
    ))/s$population
    line(
        s,
        "age_lines",
        "contact_change",
        change$name,
        "group",
        change$group,
        "factor",
        fmt(change$factor),
        "r0_age",
        fmt(eigen$value),
        "infections",
        fmt(infections,1L),
        "deaths",
        fmt(deaths,1L),
        "attack",
        fmt(attack)
    )
  }
}
sir_incidence <- function(s,beta) {
  vapply(
      simulate(sir(s$population,beta,s$gamma),s$sir_initial,s$multipliers,4L),
      function(state) state[4L],
      numeric(1)
  )
}
compare_models <- function(s) {
  series <- list(sir=sir_incidence(s,s$beta),seir=s$incidence,age=s$age_incidence)
  for (name in names(series)) {
    incidence <- series[[name]]
    rho <- ordered_sum(s$cases*incidence)/ordered_sum(incidence*incidence)
    line(
        s,
        "fit_lines",
        "model",
        name,
        "rmse",
        fmt(rmse(s,squared_errors(incidence,s$rho,s$cases))),
        "peak_day",
        peak(incidence),
        "rho_opt",
        fmt(rho,6L),
        "rmse_opt",
        fmt(rmse(s,squared_errors(incidence,rho,s$cases)))
    )
  }
  search <- golden(
      function(value) squared_errors(sir_incidence(s,value),s$rho,s$cases),
      s$params$beta_grid[[1L]],
      s$params$beta_grid[[2L]],
      s$params$golden[1L]
  )
  line(
      s,
      "fit_lines",
      "model sir_fit beta",
      fmt(search$point,6L),
      "rmse",
      fmt(rmse(s,search$value)),
      "peak_day",
      peak(sir_incidence(s,search$point))
  )
}
counterfactual_reported <- function(s,interventions) {
  states <- seird_states(s,s$beta,s$gamma,multipliers=multiplier_sequence(interventions,s$days))
  vapply(states,function(state) s$rho*state[6L],numeric(1))
}
first_day <- function(values,predicate,offset=0L) {
  indices <- which(vapply(values,predicate,logical(1)))
  if (length(indices)) as.character(offset+indices[1L]) else "never"
}
analyze_reproduction <- function(s) {
  line(s,"reproduction_lines","r0",fmt(s$r0),"herd_immunity",fmt(1-1/s$r0))
  long_states <- seird_states(s,s$beta,s$gamma,multipliers=rep(1,730L))
  line(
      s,
      "reproduction_lines",
      "final_size equation",
      fmt(final_size(s$r0)),
      "simulated",
      fmt((s$population-long_states[[length(long_states)]][1L])/s$population)
  )
  length_interval <- s$params$generation
  states <- simulate(generation(s$sigma,s$gamma),c(1,0,0),rep(1,length_interval),3L)
  amounts <- vapply(states,function(state) state[3L],numeric(1))
  coverage <- ordered_sum(amounts)
  weights <- amounts/coverage
  mean <- ordered_sum((seq_along(weights)-0.5)*weights)
  line(
      s,
      "reproduction_lines",
      "generation mean",
      fmt(mean),
      "theory",
      fmt(1/s$sigma+1/s$gamma),
      "coverage",
      fmt(coverage)
  )
  for (day in seq_along(weights)) line(s,"reproduction_lines","generation_weight",day,fmt(weights[day],6L))
  pressures <- numeric(s$days)
  for (d in seq_len(s$days)) if (d > 1L) {
    lags <- seq_len(min(length_interval,d-1L))
    pressures[d] <- ordered_sum(weights[lags]*s$cases[d-lags])
  }
  incidence_day <- peak(s$incidence)
  infectious <- vapply(s$states[-1L],function(state) state[3L],numeric(1))
  infectious_day <- peak(infectious)
  observed_day <- peak(s$cases)
  average_day <- peak(s$averages)
  line(
      s,
      "reproduction_lines",
      "peak model day",
      incidence_day,
      "incidence",
      fmt(s$incidence[incidence_day],1L),
      "reported",
      fmt(s$reported[incidence_day],1L),
      "infectious_day",
      infectious_day,
      "infectious",
      fmt(infectious[infectious_day],1L)
  )
  line(
      s,
      "reproduction_lines",
      "peak observed day",
      observed_day,
      "cases",
      s$cases[observed_day],
      "average7_day",
      average_day,
      "average7",
      fmt(s$averages[average_day],2L)
  )
  for (index in seq_along(s$interventions)) {
    first <- s$interventions[[index]]$day
    last <- if (index < length(s$interventions)) s$interventions[[index+1L]]$day-1L else s$days
    residuals <- s$residuals[first:last]
    error <- ordered_sum(residuals*residuals)
    n <- last-first+1L
    line(
        s,
        "reproduction_lines",
        "period",
        index,
        "days",
        first,
        last,
        "multiplier",
        fmt(s$interventions[[index]]$multiplier),
        "rt_start",
        fmt(s$rt[first]),
        "rt_end",
        fmt(s$rt[last]),
        "observed",
        integer_text(sum(as.numeric(s$cases[first:last]))),
        "fitted",
        fmt(ordered_sum(s$reported[first:last]),1L),
        "rmse",
        fmt(rmse(s,error,n)),
        "bias",
        fmt(ordered_sum(residuals)/n,1L)
    )
  }
  for (target in s$params$milestones) line(
      s,
      "reproduction_lines",
      "milestone",
      integer_text(target),
      "observed",
      first_day(s$cumulative_cases,function(value) value >= target),
      "fitted",
      first_day(s$cumulative_reported,function(value) value >= target)
  )
  reported <- counterfactual_reported(s,s$interventions[1L])
  total <- ordered_sum(reported)
  day <- peak(reported)
  line(
      s,
      "reproduction_lines",
      "counterfactual none reported",
      fmt(total,1L),
      "peak_day",
      day,
      "peak",
      fmt(reported[day],1L),
      "averted",
      fmt(total-s$reported_total,1L)
  )
  if (length(s$interventions) > 1L) for (index in seq.int(2L,length(s$interventions))) {
    total <- ordered_sum(counterfactual_reported(s,s$interventions[-index]))
    line(
        s,
        "reproduction_lines",
        "counterfactual without",
        index,
        "reported",
        fmt(total,1L),
        "averted",
        fmt(total-s$reported_total,1L)
    )
  }
  if (length(s$interventions) > 1L) for (index in seq.int(
      2L,
      length(s$interventions)
  )) for (shift in c(-7L,7L)) {
    changed <- s$interventions
    changed[[index]]$day <- changed[[index]]$day+shift
    total <- ordered_sum(counterfactual_reported(s,changed))
    line(
        s,
        "reproduction_lines",
        "timing",
        index,
        "shift",
        shift,
        "reported",
        fmt(total,1L),
        "change",
        fmt(total-s$reported_total,1L)
    )
  }
  for (d in seq.int(2L,s$days)) if ((s$rt[d] < 1) != (s$rt[d-1L] < 1)) line(
      s,
      "reproduction_lines",
      "rt_cross day",
      d,
      if (s$rt[d] < 1) "down" else "up"
  )
  for (d in seq_len(s$days)) {
    empirical <- if (d < length_interval+7L) "-" else fmt(sum(as.numeric(s$cases[(d-6L):d]))/ordered_sum(pressures[(d-6L):d]))
    line(s,"reproduction_lines","rt",d,"model",fmt(s$rt[d]),"empirical",empirical)
  }
  s$reproduction_lines <- c(s$reproduction_lines,s$age_lines)
}
scenario_projections <- function(s) {
  horizon <- s$params$horizon
  threshold <- s$params$threshold
  rows <- "scenario,day,incidence,reported"
  baseline <- NULL
  for (scenario in s$params$scenario) {
    name <- scenario$name
    multiplier <- scenario$multiplier
    future <- rep(multiplier,horizon)
    states <- seird_states(s,s$beta,s$gamma,multipliers=future,initial=s$states[[length(s$states)]])
    incidence <- vapply(states,function(state) state[6L],numeric(1))
    reported <- s$rho*incidence
    for (day in seq_len(horizon)) rows <- c(
        rows,
        paste(name,s$days+day,fmt(incidence[day],1L),fmt(reported[day],1L),sep=",")
    )
    reproduction <- s$r0*multiplier*s$states[[length(s$states)]][1L]/s$population
    total <- ordered_sum(reported)
    if (is.null(baseline)) baseline <- total
    day <- peak(reported)
    line(
        s,
        "reproduction_lines",
        "scenario",
        name,
        "multiplier",
        fmt(multiplier),
        "rt",
        fmt(reproduction),
        "reported",
        fmt(total,1L),
        "peak_day",
        s$days+day,
        "peak",
        fmt(reported[day],1L),
        "attack",
        fmt((s$population-states[[length(states)]][1L])/s$population),
        "final_size",
        fmt(final_size(s$r0*multiplier)),
        "averted",
        fmt(baseline-total,1L),
        "below",
        first_day(reported,function(value) value < threshold,s$days),
        "days_above",
        sum(reported >= threshold)
    )
    beta_low <- s$beta-2*s$standard_errors[1L]
    beta_high <- s$beta+2*s$standard_errors[1L]
    band <- vapply(c(beta_low,beta_high),function(beta) {
      full <- seird_states(s,beta,s$gamma,multipliers=c(s$multipliers,future))
      ordered_sum(vapply(full[seq.int(s$days+1L,length(full))],function(state) s$rho*state[6L],numeric(1)))
    },numeric(1))
    line(
        s,
        "reproduction_lines",
        "scenario_band",
        name,
        "beta_low",
        fmt(beta_low,6L),
        "reported_low",
        fmt(band[1L],1L),
        "beta_high",
        fmt(beta_high,6L),
        "reported_high",
        fmt(band[2L],1L)
    )
    age_states <- age_states_for(s,multipliers=future,initial=s$age_states[[length(s$age_states)]])
    end_state <- age_states[[length(age_states)]]
    attacks <- vapply(
        seq_along(s$populations),
        function(g) (s$populations[g]-end_state[6L*g-5L])/s$populations[g],
        numeric(1)
    )
    deaths <- ordered_sum(end_state[seq.int(5L,length(end_state),6L)])
    line(
        s,
        "reproduction_lines",
        "scenario_age",
        name,
        "attack",
        paste(vapply(attacks,fmt,character(1)),collapse=" "),
        "deaths",
        fmt(deaths,1L)
    )
  }
  rows
}
trajectories <- function(s) {
  lines <- "day,S,E,I,R,D,incidence,reported,observed,average7,cumulative_observed,cumulative_reported"
  for (d in seq_len(s$days)) {
    values <- c(
        as.character(d),
        vapply(s$states[[d+1L]],function(value) fmt(value,1L),character(1)),
        fmt(s$reported[d],1L),
        as.character(s$cases[d]),
        fmt(s$averages[d],2L),
        integer_text(s$cumulative_cases[d]),
        fmt(s$cumulative_reported[d],1L)
    )
    lines <- c(lines,paste(values,collapse=","))
  }
  lines
}
main <- function() {
  s <- prepare_study(read_inputs())
  fit_model(s)
  fitted_diagnostics(s)
  profiles(s)
  backtest(s)
  estimate_effects(s)
  sensitivity(s)
  analyze_age(s)
  compare_models(s)
  analyze_reproduction(s)
  scenarios <- scenario_projections(s)
  write_outputs(list(
      "fit.txt"=s$fit_lines,
      "trajectories.csv"=trajectories(s),
      "scenarios.csv"=scenarios,
      "reproduction.txt"=s$reproduction_lines,
      "curve_plot.txt"=curve_plot(s$cases,s$reported)
  ))
}
main()
