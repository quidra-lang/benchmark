source("records.R")
source("cleaning.R")
source("harmonic_fit.R")
source("predict.R")
source("report.R")

DOODSON_WEIGHTS <- c(0,2,1,1,2,0,1,1,0,2,0,1,1,0,1,0,0,1,0,1)
LEADING <- c("M2","S2","K1","O1")
ordered_sum <- function(values) {
  result <- 0
  for (value in values) result <- result+value
  result
}
average <- function(values) ordered_sum(values)/length(values)
rms <- function(values) sqrt(ordered_sum(values*values)/length(values))
words <- function(...) paste(...,collapse=" ")
kv <- function(name,value) paste0(name,"=",value)
select_constituents <- function(constituents,tau,rayleigh) {
  selected <- list()
  status <- character()
  for (c in constituents) {
    if (c$speed*tau < 360*rayleigh) {
      status[c$name] <- "short"
      next
    }
    conflicts <- which(vapply(
        selected,
        function(chosen) abs(c$speed-chosen$speed)*tau < 360*rayleigh,
        logical(1)
    ))
    if (length(conflicts)) status[c$name] <- paste0("conflict:",selected[[conflicts[1L]]]$name) else {
      status[c$name] <- "fitted"
      selected[[length(selected)+1L]] <- c
    }
  }
  list(selected=selected,status=status)
}
residual_statistics <- function(values,usable,model) {
  residuals <- setNames(
      vapply(usable,function(t) values[[as.character(t)]]-predict_height(model,t),numeric(1)),
      as.character(usable)
  )
  squared <- ordered_sum(residuals*residuals)
  dof <- length(usable)-model$unknowns
  observed <- values[as.character(usable)]
  mean <- average(observed)
  total <- ordered_sum((observed-mean)*(observed-mean))
  paired <- usable[as.character(usable+1L) %in% names(residuals)]
  a <- residuals[as.character(paired)]
  b <- residuals[as.character(paired+1L)]
  lag1 <- ordered_sum(a*b)/ordered_sum(a*a)
  list(
      residuals=residuals,
      squared=squared,
      variance=squared/dof,
      dof=dof,
      rms=sqrt(squared/length(usable)),
      max_abs=max(abs(residuals)),
      explained_percent=100*(1-squared/total),
      lag1=lag1
  )
}
constituent_errors <- function(model,variance,min_snr) {
  errors <- list()
  for (c in model$selected) {
    constant <- model$constants[[c$name]]
    a <- constant$a
    b <- constant$b
    amp <- constant$amplitude
    ia <- constant$index_a
    ib <- constant$index_b
    va <- variance*model$inverse[ia,ia]
    vb <- variance*model$inverse[ib,ib]
    cab <- variance*model$inverse[ia,ib]
    ae <- sqrt(a*a*va+b*b*vb+2*a*b*cab)/amp
    pe <- sqrt(b*b*va+a*a*vb-2*a*b*cab)/(amp*amp)*180/TIDE_PI
    ratio <- amp/ae
    snr <- ratio*ratio
    errors[[c$name]] <- list(
        amplitude_error=ae,
        phase_error=pe,
        snr=snr,
        significant=if (snr >= min_snr) "yes" else "no"
    )
  }
  errors
}
cross_validate <- function(values,usable,first,last,constituents,rayleigh,residuals) {
  mid <- first+(last-first) %/% 2L
  training <- usable[usable <= mid]
  testing <- usable[usable > mid]
  selected <- select_constituents(constituents,tail(training,1L)-training[1L],rayleigh)$selected
  model <- fit(values,training,selected)
  observed <- values[as.character(testing)]
  errors <- observed-vapply(testing,function(t) predict_height(model,t),numeric(1))
  squared <- ordered_sum(errors*errors)
  mean <- average(observed)
  variation <- ordered_sum((observed-mean)*(observed-mean))
  final <- residuals[as.character(testing)]
  list(
      midpoint=mid,
      training_count=length(training),
      testing_count=length(testing),
      constituents=length(selected),
      rms=sqrt(squared/length(testing)),
      in_sample_rms=sqrt(ordered_sum(final*final)/length(testing)),
      skill=1-squared/variation
  )
}
residual_events <- function(usable,residuals,threshold,minimum_hours) {
  events <- list()
  current <- integer()
  current_sign <- ""
  flush <- function() {
    if (length(current) < minimum_hours) return(invisible(NULL))
    values <- residuals[as.character(current)]
    peak <- current[if (current_sign == "positive") which.max(values) else which.min(values)]
    events[[length(events)+1L]] <<- list(
        kind=current_sign,
        start=current[1L],
        stop=tail(current,1L),
        peak=peak,
        value=residuals[[as.character(peak)]]
    )
  }
  for (t in usable) {
    value <- residuals[[as.character(t)]]
    kind <- if (value > threshold) "positive" else if (value < -threshold) "negative" else ""
    if (kind != "" && kind == current_sign && length(current) && t == tail(
        current,
        1L
    )+1L) current <- c(current,t) else {
      flush()
      current <- if (kind == "") integer() else t
      current_sign <- kind
    }
  }
  flush()
  events
}
daily_means <- function(cleaning,model) {
  rows <- list()
  for (day in (cleaning$first %/% 24L):(cleaning$last %/% 24L)) {
    noon <- 24L*day+12L
    if (noon-19L < cleaning$first || noon+19L > cleaning$last) next
    total <- 0
    missing <- 0L
    for (j in -19:19) {
      t <- noon+j
      if (t %in% cleaning$usable) value <- cleaning$values[[as.character(t)]] else {
        value <- predict_height(model,t)
        missing <- missing+1L
      }
      total <- total+DOODSON_WEIGHTS[abs(j)+1L]*value
    }
    rows[[length(rows)+1L]] <- list(day=day,level=total/30,filled=missing)
  }
  levels <- vapply(rows,function(row) row$level,numeric(1))
  mean <- average(levels)
  mean_day <- (length(rows)-1L)/2
  x <- 0:(length(rows)-1L)-mean_day
  numerator <- ordered_sum(x*(levels-mean))
  denominator <- ordered_sum(x*x)
  list(
      rows=rows,
      days=length(rows),
      average=mean,
      slope_mm_per_day=1000*numerator/denominator,
      max=rows[[which.max(levels)]],
      min=rows[[which.min(levels)]]
  )
}
refine_extrema <- function(model,start,hours,grid,min_range) {
  extrema <- find_extrema(model,start,hours,grid)
  raw <- length(extrema)
  while (length(extrema) >= 2L) {
    differences <- vapply(
        seq_len(length(extrema)-1L),
        function(i) abs(extrema[[i]]$height-extrema[[i+1L]]$height),
        numeric(1)
    )
    index <- which.min(differences)
    if (differences[index] >= min_range) break
    extrema <- extrema[-c(index,index+1L)]
  }
  for (i in seq_along(extrema)) {
    extrema[[i]]$rounded <- as.integer(floor(extrema[[i]]$minute+0.5))
    extrema[[i]]$day <- extrema[[i]]$rounded %/% 1440L
  }
  days <- unique(vapply(extrema,function(e) e$day,integer(1)))
  for (day in days) for (kind in c("high","low")) {
    indices <- which(vapply(extrema,function(e) e$day == day && e$kind == kind,logical(1)))
    if (!length(indices)) next
    heights <- vapply(extrema[indices],function(e) e$height,numeric(1))
    best <- indices[if (kind == "high") which.max(heights) else which.min(heights)]
    for (i in indices) extrema[[i]]$label <- if (kind == "high") if (i == best) "HHW" else "LHW" else if (i == best) "LLW" else "HLW"
  }
  list(extrema=extrema,raw=raw)
}
daily_extrema <- function(extrema,start,days) {
  table <- list()
  for (day in seq.int(start,start+days-1L)) {
    highs <- vapply(
        Filter(function(e) e$day == day && e$kind == "high",extrema),
        function(e) e$height,
        numeric(1)
    )
    lows <- vapply(
        Filter(function(e) e$day == day && e$kind == "low",extrema),
        function(e) e$height,
        numeric(1)
    )
    hhw <- if (length(highs)) max(highs) else NULL
    llw <- if (length(lows)) min(lows) else NULL
    span <- if (is.null(hhw) || is.null(llw)) NULL else hhw-llw
    table[[length(table)+1L]] <- list(
        day=day,
        high_waters=length(highs),
        low_waters=length(lows),
        hhw=hhw,
        llw=llw,
        range=span
    )
  }
  table
}
characteristics <- function(model,extrema,daily,hourly,start,hours) {
  constants <- model$constants
  highs <- Filter(function(e) e$kind == "high",extrema)
  lows <- Filter(function(e) e$kind == "low",extrema)
  mhhw <- average(vapply(Filter(function(d) !is.null(d$hhw),daily),function(d) d$hhw,numeric(1)))
  mllw <- average(vapply(Filter(function(d) !is.null(d$llw),daily),function(d) d$llw,numeric(1)))
  mhw <- average(vapply(highs,function(e) e$height,numeric(1)))
  mlw <- average(vapply(lows,function(e) e$height,numeric(1)))
  mtl <- (mhw+mlw)/2
  dtl <- (mhhw+mllw)/2
  mn <- mhw-mlw
  gt <- mhhw-mllw
  rises <- falls <- integer()
  if (length(extrema) > 1L) for (i in seq.int(2L,length(extrema))) {
    previous <- extrema[[i-1L]]
    current <- extrema[[i]]
    if (previous$kind == "low" && current$kind == "high") rises <- c(rises,current$rounded-previous$rounded)
    if (previous$kind == "high" && current$kind == "low") falls <- c(falls,current$rounded-previous$rounded)
  }
  m2 <- constants$M2
  s2 <- constants$S2
  m4 <- constants$M4
  phase <- 2*m2$phase-m4$phase
  while (phase < 0) phase <- phase+360
  while (phase >= 360) phase <- phase-360
  form <- (constants$K1$amplitude+constants$O1$amplitude)/(m2$amplitude+s2$amplitude)
  kind <- if (form < 0.25) "semidiurnal" else if (form < 1.5) "mixed_semidiurnal" else if (form < 3) "mixed_diurnal" else "diurnal"
  complete <- Filter(function(d) !is.null(d$range),daily)
  complete_ranges <- vapply(complete,function(d) d$range,numeric(1))
  total_amp <- ordered_sum(vapply(model$selected,function(c) constants[[c$name]]$amplitude,numeric(1)))
  dw <- s2$speed-m2$speed
  dg <- s2$phase-m2$phase
  q1 <- (dw*start-dg)/180
  q2 <- (dw*(start+hours)-dg)/180
  spring_neap <- list()
  lo <- ceiling(min(q1,q2))
  hi <- floor(max(q1,q2))
  if (lo <= hi) for (q in seq.int(lo,hi)) {
    t <- (dg+180*q)/dw
    if (start <= t && t <= start+hours) spring_neap[[length(spring_neap)+1L]] <- list(
        kind=if (q %% 2L == 0L) "spring" else "neap",
        minute=as.integer(floor(60*t+0.5))
    )
  }
  list(
      mhhw=mhhw,
      mllw=mllw,
      mhw=mhw,
      mlw=mlw,
      mtl=mtl,
      dtl=dtl,
      mn=mn,
      gt=gt,
      highs=highs,
      lows=lows,
      rise_minutes=average(rises),
      fall_minutes=average(falls),
      m4_m2_ratio=m4$amplitude/m2$amplitude,
      relative_phase=phase,
      dominance=if (phase < 180) "flood" else "ebb",
      form_number=form,
      type=kind,
      spring=2*(m2$amplitude+s2$amplitude),
      neap=2*(m2$amplitude-s2$amplitude),
      hat=model$mean_level+total_amp,
      lat=model$mean_level-total_amp,
      highest=highs[[which.max(vapply(highs,function(e) e$height,numeric(1)))]],
      lowest=lows[[which.min(vapply(lows,function(e) e$height,numeric(1)))]],
      widest=complete[[which.max(complete_ranges)]],
      narrowest=complete[[which.min(complete_ranges)]],
      above_mhhw=100*sum(hourly > mhhw)/length(hourly),
      below_mllw=100*sum(hourly < mllw)/length(hourly),
      spring_neap=spring_neap
  )
}
inspect_station <- function(station,record,constituents,settings,start) {
  cleaning <- prepare_record(record,settings$flat_run)
  selection <- select_constituents(constituents,cleaning$record_length,settings$rayleigh)
  selected <- selection$selected
  preliminary <- fit(cleaning$values,cleaning$candidates,selected)
  residuals <- setNames(
      vapply(
          cleaning$candidates,
          function(t) cleaning$values[[as.character(t)]]-predict_height(preliminary,t),
          numeric(1)
      ),
      as.character(cleaning$candidates)
  )
  prefit <- rms(residuals)
  cleaning <- detect_spikes(cleaning,residuals,settings)
  cleaning$prefit_rms <- prefit
  model <- fit(cleaning$values,cleaning$usable,selected)
  residual <- residual_statistics(cleaning$values,cleaning$usable,model)
  errors <- constituent_errors(model,residual$variance,settings$snr_min)
  validation <- cross_validate(
      cleaning$values,
      cleaning$usable,
      cleaning$first,
      cleaning$last,
      constituents,
      settings$rayleigh,
      residual$residuals
  )
  surges <- residual_events(cleaning$usable,residual$residuals,settings$surge_threshold,settings$surge_hours)
  means <- daily_means(cleaning,model)
  hourly <- predict_hours(model,start,settings$prediction_hours)
  refined <- refine_extrema(model,start,settings$prediction_hours,settings$grid_minutes,settings$min_range)
  extrema <- refined$extrema
  daily <- daily_extrema(extrema,start %/% 24L,settings$prediction_hours %/% 24L)
  c <- characteristics(model,extrema,daily,hourly,start,settings$prediction_hours)
  list(
      code=station$code,
      name=station$name,
      cleaning=cleaning,
      status=selection$status,
      model=model,
      residual=residual,
      errors=errors,
      validation=validation,
      surges=surges,
      daily_means=means,
      hourly=hourly,
      extrema=extrema,
      raw_extrema=refined$raw,
      daily=daily,
      characteristics=c
  )
}
station_outputs <- function(station,constituents,settings) {
  code <- station$code
  c <- station$cleaning
  m <- station$model
  r <- station$residual
  stamp <- function(t) datetime_at_hour(settings$epoch,t)
  minute_stamp <- function(t) datetime_at_minute(settings$epoch,t)
  date <- function(day) date_at_day(settings$epoch,day)
  cleaning <- c(
      words(kv("station",code),kv("name",station$name)),
      words(
          "span",
          kv("start",stamp(c$first)),
          kv("end",stamp(c$last)),
          kv("hours",c$record_length+1L),
          kv("record_length",c$record_length)
      ),
      words(
          "counts",
          kv("rows",c$rows),
          kv("numeric",length(c$numeric_times)),
          kv("na",sum(c$reasons == "na")),
          kv("absent",sum(c$reasons == "absent")),
          kv("flat",sum(c$reasons == "flat")),
          kv("spikes",length(c$spikes)),
          kv("usable",length(c$usable))
      )
  )
  for (run in c$flat_runs) cleaning <- c(
      cleaning,
      words(
          "flat",
          kv("start",stamp(run$start)),
          kv("end",stamp(run$stop)),
          kv("value",decimal(run$value,3L)),
          kv("removed",run$stop-run$start)
      )
  )
  cleaning <- c(
      cleaning,
      words(
          "spike_test",
          kv("window",settings$spike_window),
          kv("candidates",length(c$candidates)),
          kv("tested",c$tested),
          kv("prefit_rms",decimal(c$prefit_rms,4L))
      )
  )
  for (spike in c$spikes) cleaning <- c(
      cleaning,
      words(
          "spike",
          kv("time",stamp(spike$time)),
          kv("value",decimal(spike$value,3L)),
          kv("residual",decimal(spike$residual,4L)),
          kv("median",decimal(spike$median,4L)),
          kv("mad",decimal(spike$mad,4L)),
          kv("limit",decimal(spike$limit,4L))
      )
  )
  for (gap in c$gaps) cleaning <- c(
      cleaning,
      words(
          "gap",
          kv("start",stamp(gap$start)),
          kv("end",stamp(gap$stop)),
          kv("hours",gap$stop-gap$start+1L),
          kv("cause",gap$cause)
      )
  )
  constants <- character()
  for (constituent in constituents) {
    name <- constituent$name
    status <- station$status[[name]]
    if (status != "fitted") constants <- c(
        constants,
        paste0(paste(code,name,decimal(constituent$speed,7L),status,sep=","),",,,,,,")
    ) else {
      constant <- m$constants[[name]]
      error <- station$errors[[name]]
      constants <- c(
          constants,
          paste(
              c(
                  code,
                  name,
                  decimal(constituent$speed,7L),
                  "fitted",
                  decimal(constant$amplitude,4L),
                  decimal(constant$phase,2L),
                  decimal(error$amplitude_error,4L),
                  decimal(error$phase_error,2L),
                  decimal(error$snr,1L),
                  error$significant
              ),
              collapse=","
          )
      )
    }
  }
  extremes <- words(
      kv("station",code),
      kv("extremes",length(station$extrema)),
      kv("raw",station$raw_extrema),
      kv("removed",station$raw_extrema-length(station$extrema))
  )
  for (i in seq_along(station$extrema)) {
    e <- station$extrema[[i]]
    change <- if (i == 1L) "none" else decimal(e$height-station$extrema[[i-1L]]$height,3L)
    extremes <- c(extremes,words(minute_stamp(e$rounded),e$label,decimal(e$height,3L),kv("change",change)))
  }
  for (day in station$daily) extremes <- c(
      extremes,
      words(
          "day",
          kv("date",date(day$day)),
          kv("high_waters",day$high_waters),
          kv("low_waters",day$low_waters),
          kv("hhw",optional(day$hhw,3L)),
          kv("llw",optional(day$llw,3L)),
          kv("range",optional(day$range,3L))
      )
  )
  summary <- c(
      paste0("[station ",code,"] ",station$name),
      words(
          "record",
          kv("first",stamp(c$first)),
          kv("last",stamp(c$last)),
          kv("length",c$record_length),
          kv("usable",length(c$usable))
      ),
      words(
          "fit",
          kv("constituents",length(m$selected)),
          kv("unknowns",m$unknowns),
          kv("dof",r$dof),
          kv("mean_level",decimal(m$mean_level,4L))
      ),
      words(
          "residual",
          kv("rms",decimal(r$rms,4L)),
          kv("max_abs",decimal(r$max_abs,4L)),
          kv("explained_percent",decimal(r$explained_percent,4L)),
          kv("lag1_autocorrelation",decimal(r$lag1,4L))
      )
  )
  top <- c$usable[order(-abs(r$residuals[as.character(c$usable)]),c$usable)][seq_len(settings$top_residuals)]
  for (rank in seq_along(top)) {
    t <- top[rank]
    summary <- c(
        summary,
        words(
            "top_residual",
            kv("rank",rank),
            kv("time",stamp(t)),
            kv("observed",decimal(c$values[[as.character(t)]],3L)),
            kv("fitted",decimal(predict_height(m,t),4L)),
            kv("residual",decimal(r$residuals[[as.character(t)]],4L))
        )
    )
  }
  v <- station$validation
  summary <- c(
      summary,
      words(
          "validation",
          kv("split",stamp(v$midpoint)),
          kv("train",v$training_count),
          kv("test",v$testing_count),
          kv("constituents",v$constituents),
          kv("rms",decimal(v$rms,4L)),
          kv("in_sample_rms",decimal(v$in_sample_rms,4L)),
          kv("skill",decimal(v$skill,4L))
      )
  )
  t <- station$characteristics
  summary <- c(
      summary,
      words(kv("form_number",decimal(t$form_number,4L)),kv("type",t$type)),
      words(
          "ranges",
          kv("spring",decimal(t$spring,3L)),
          kv("neap",decimal(t$neap,3L)),
          kv("mn",decimal(t$mn,3L)),
          kv("gt",decimal(t$gt,3L))
      ),
      words(
          "asymmetry",
          kv("rise_minutes",decimal(t$rise_minutes,1L)),
          kv("fall_minutes",decimal(t$fall_minutes,1L)),
          kv("m4_m2_ratio",decimal(t$m4_m2_ratio,4L)),
          kv("relative_phase",decimal(t$relative_phase,2L)),
          kv("dominance",t$dominance)
      )
  )
  summary <- c(
      summary,
      paste(
          "datums",
          paste(
              vapply(
                  c("mhhw","mhw","mtl","dtl","mlw","mllw"),
                  function(name) kv(name,decimal(t[[name]],3L)),
                  character(1)
              ),
              collapse=" "
          )
      ),
      words("bounds",kv("hat",decimal(t$hat,3L)),kv("lat",decimal(t$lat,3L))),
      words(
          "window",
          kv("high_waters",length(t$highs)),
          kv("low_waters",length(t$lows)),
          kv("highest",decimal(t$highest$height,3L)),
          kv("highest_time",minute_stamp(t$highest$rounded)),
          kv("lowest",decimal(t$lowest$height,3L)),
          kv("lowest_time",minute_stamp(t$lowest$rounded))
      ),
      words(
          "daily_range",
          kv("widest",decimal(t$widest$range,3L)),
          kv("widest_date",date(t$widest$day)),
          kv("narrowest",decimal(t$narrowest$range,3L)),
          kv("narrowest_date",date(t$narrowest$day))
      ),
      words("exceedance",kv("above_mhhw",decimal(t$above_mhhw,2L)),kv("below_mllw",decimal(t$below_mllw,2L)))
  )
  for (event in t$spring_neap) summary <- c(summary,words(event$kind,kv("time",minute_stamp(event$minute))))
  summary <- c(
      summary,
      words(
          "surges",
          kv("count",length(station$surges)),
          kv("threshold",decimal(settings$surge_threshold,3L)),
          kv("min_hours",settings$surge_hours)
      )
  )
  for (surge in station$surges) summary <- c(
      summary,
      words(
          "surge",
          kv("type",surge$kind),
          kv("start",stamp(surge$start)),
          kv("end",stamp(surge$stop)),
          kv("hours",surge$stop-surge$start+1L),
          kv("peak",decimal(surge$value,4L)),
          kv("peak_time",stamp(surge$peak))
      )
  )
  d <- station$daily_means
  summary <- c(
      summary,
      words(
          "daily_mean",
          kv("days",d$days),
          kv("average",decimal(d$average,4L)),
          kv("slope_mm_per_day",decimal(d$slope_mm_per_day,3L)),
          kv("max",decimal(d$max$level,4L)),
          kv("max_date",date(d$max$day)),
          kv("min",decimal(d$min$level,4L)),
          kv("min_date",date(d$min$day))
      )
  )
  for (row in d$rows) summary <- c(
      summary,
      words("daily_mean",kv("date",date(row$day)),kv("level",decimal(row$level,4L)),kv("filled",row$filled))
  )
  list(cleaning=cleaning,constants=constants,extremes=extremes,summary=summary)
}
nearest_lag <- function(extrema,reference) {
  average(vapply(extrema,function(e) {
    times <- vapply(reference,function(r) r$rounded,integer(1))
    e$rounded-times[order(abs(times-e$rounded),times)[1L]]
  },numeric(1)))
}
comparisons <- function(stations,settings) {
  reference <- stations[[settings$reference]]
  lines <- paste0("[comparison] reference=",settings$reference)
  for (station in settings$stations) {
    code <- station$code
    if (code == settings$reference) next
    own <- stations[[code]]$characteristics
    ref <- reference$characteristics
    lines <- c(
        lines,
        words(
            code,
            "tide",
            kv("hw_lag_min",decimal(nearest_lag(own$highs,ref$highs),1L)),
            kv("lw_lag_min",decimal(nearest_lag(own$lows,ref$lows),1L)),
            kv("range_ratio",decimal(own$gt/ref$gt,4L)),
            kv("mtl_diff",decimal(own$mtl-ref$mtl,3L))
        )
    )
    for (name in LEADING) {
      current <- stations[[code]]$model$constants[[name]]
      refc <- reference$model$constants[[name]]
      phase <- current$phase-refc$phase
      if (phase > 180) phase <- phase-360
      if (phase <= -180) phase <- phase+360
      lines <- c(
          lines,
          words(
              code,
              name,
              kv("amplitude_ratio",decimal(current$amplitude/refc$amplitude,4L)),
              kv("phase_diff",decimal(phase,2L)),
              kv("time_lag_min",decimal(phase/current$speed*60,1L))
          )
      )
    }
  }
  lines
}
correlations <- function(stations,order,max_lag) {
  lines <- paste0("[correlation] max_lag=",max_lag)
  for (i in seq_len(length(order)-1L)) for (j in seq.int(i+1L,length(order))) {
    a <- stations[[order[i]]]
    b <- stations[[order[j]]]
    by_lag <- list()
    lags <- seq.int(-max_lag,max_lag)
    for (lag in lags) {
      times <- a$cleaning$usable[as.character(a$cleaning$usable+lag) %in% names(b$residual$residuals)]
      x <- a$residual$residuals[as.character(times)]
      y <- b$residual$residuals[as.character(times+lag)]
      mx <- average(x)
      my <- average(y)
      sxy <- ordered_sum((x-mx)*(y-my))
      sxx <- ordered_sum((x-mx)*(x-mx))
      syy <- ordered_sum((y-my)*(y-my))
      by_lag[[as.character(lag)]] <- c(sxy/sqrt(sxx*syy),length(times))
    }
    values <- vapply(lags,function(lag) by_lag[[as.character(lag)]][1L],numeric(1))
    best <- lags[order(-values,abs(lags),lags)[1L]]
    lines <- c(
        lines,
        words(
            paste0(order[i],"-",order[j]),
            kv("lag0",decimal(by_lag[["0"]][1L],4L)),
            kv("best_lag",best),
            kv("best",decimal(by_lag[[as.character(best)]][1L],4L)),
            kv("pairs",by_lag[[as.character(best)]][2L])
        )
    )
  }
  lines
}
plot_lines <- function(station,settings,start) {
  width <- settings$plot_hours
  top <- settings$plot_top
  bottom <- settings$plot_bottom
  step <- settings$plot_step
  rows <- (top-bottom) %/% step+1L
  grid <- matrix(" ",rows,width)
  marks <- rep("",width)
  zero_row <- floor((top-100*station$model$mean_level)/step+0.5)
  if (zero_row >= 0L && zero_row < rows) grid[zero_row+1L,] <- "-"
  for (e in station$extrema) {
    column <- (e$rounded-60L*start+30L) %/% 60L
    if (column >= 0L && column < width) marks[column+1L] <- if (e$kind == "high") "H" else "L"
  }
  for (column in 0:(width-1L)) {
    row <- floor((top-100*predict_height(station$model,start+column))/step+0.5)
    if (row < 0L) grid[1L,column+1L] <- "^" else if (row >= rows) grid[rows,column+1L] <- "v" else grid[
        row+1L,
        column+1L
    ] <- if (marks[column+1L] != "") marks[column+1L] else "*"
  }
  labels <- vapply(0:(rows-1L),function(q) decimal((top-q*step)/100,2L),character(1))
  c(
      words(
          "[plot]",
          kv("station",station$code),
          kv("start",datetime_at_hour(settings$epoch,start)),
          kv("hours",width),
          kv("step_cm",step)
      ),
      render_plot(grid,labels)
  )
}
main <- function() {
  input <- read_all_inputs()
  settings <- input$settings
  constituents <- input$constituents
  order <- vapply(settings$stations,function(station) station$code,character(1))
  start <- epoch_hours(settings$epoch,settings$prediction_start)
  stations <- setNames(
      lapply(
          settings$stations,
          function(station) inspect_station(
              station,
              input$observations[[station$code]],
              constituents,
              settings,
              start
          )
      ),
      order
  )
  cleaning <- extremes <- summary <- character()
  constants <- "station,constituent,speed,status,amplitude,phase,amplitude_error,phase_error,snr,significant"
  for (code in order) {
    lines <- station_outputs(stations[[code]],constituents,settings)
    cleaning <- c(cleaning,lines$cleaning)
    constants <- c(constants,lines$constants)
    extremes <- c(extremes,lines$extremes)
    summary <- c(summary,lines$summary)
  }
  predictions <- paste0("time,",paste(order,collapse=","))
  for (i in 0:settings$prediction_hours) predictions <- c(
      predictions,
      paste0(
          datetime_at_hour(settings$epoch,start+i),
          ",",
          paste(
              vapply(order,function(code) decimal(stations[[code]]$hourly[i+1L],3L),character(1)),
              collapse=","
          )
      )
  )
  summary <- c(
      summary,
      comparisons(stations,settings),
      correlations(stations,order,settings$correlation_lag),
      plot_lines(stations[[settings$plot_code]],settings,start)
  )
  outputs <- list(
      "cleaning.txt"=cleaning,
      "constituents.csv"=constants,
      "predictions.csv"=predictions,
      "extremes.txt"=extremes,
      "summary.txt"=summary
  )
  for (name in names(outputs)) write_lines(name,outputs[[name]])
}
main()
