for (module in c("signal_io","report","filters","detector","hrv")) source(paste0(module,".R"))
LABELS <- c("N","V","A")
CLASSES <- c("qrs","searchback","twave","refractory","noise")
fmt <- function(pattern,...) {
  arguments <- lapply(list(...),function(value) if (is.numeric(value)) integer_text(value) else value)
  do.call(sprintf,c(list(pattern),arguments))
}
csv_row <- function(...) {
  paste(
      vapply(list(...),function(value) if (is.numeric(value)) integer_text(value) else value,character(1)),
      collapse=","
  )
}
thresholds <- function(levels) {
  i <- levels$npki+(levels$spki-levels$npki) %/% 4
  f <- levels$npkf+(levels$spkf-levels$npkf) %/% 4
  list(thi1=i,thi2=i %/% 2,thf1=f,thf2=f %/% 2)
}
detect_beats <- function(peaks,signals,params) {
  initial <- levels <- initial_levels(signals)
  registered <- integer()
  intervals <- numeric()
  ra1 <- ra2 <- 200
  register <- function(index) {
    if (length(registered)) {
      elapsed <- peaks[[index]]$time-peaks[[tail(registered,1L)]]$time
      intervals <<- tail(c(intervals,elapsed),8L)
      ra1 <<- sum(intervals) %/% length(intervals)
      if (92*ra1 <= 100*elapsed && 100*elapsed <= 116*ra1) ra2 <<- ra1
    }
    registered <<- c(registered,index)
  }
  update <- function(index,kind) {
    peak <- peaks[[index]]
    if (kind == "noise") {
      levels$npki <<- (peak$peak_i+7*levels$npki) %/% 8
      levels$npkf <<- (peak$peak_f+7*levels$npkf) %/% 8
    } else {
      weight <- if (kind == "signal") 7 else 3
      divisor <- if (kind == "signal") 8 else 4
      levels$spki <<- (peak$peak_i+weight*levels$spki) %/% divisor
      levels$spkf <<- (peak$peak_f+weight*levels$spkf) %/% divisor
    }
  }
  searchback <- function(time) {
    repeat {
      last_time <- if (length(registered)) peaks[[tail(registered,1L)]]$time else 0
      if (time-last_time <= (ra2*params[["searchback_percent"]]) %/% 100) break
      threshold <- thresholds(levels)
      candidates <- which(vapply(peaks,function(p) p$kind == "noise" && last_time < p$time &&
        p$time < time && p$peak_i > threshold$thi2 && p$peak_f > threshold$thf2,logical(1)))
      if (!length(candidates)) break
      chosen <- candidates[which.max(vapply(peaks[candidates],`[[`,numeric(1),"peak_i"))]
      update(chosen,"searchback")
      peaks[[chosen]]$kind <<- "searchback"
      register(chosen)
    }
  }
  for (index in seq_along(peaks)) {
    searchback(peaks[[index]]$time)
    peak <- peaks[[index]]
    threshold <- thresholds(levels)
    peak$thr_i <- threshold$thi1
    peak$thr_f <- threshold$thf1
    previous <- if (length(registered)) peaks[[tail(registered,1L)]] else NULL
    elapsed <- if (is.null(previous)) 0 else peak$time-previous$time
    if (!is.null(previous) && elapsed < params[["refractory_ms"]] %/% 5) {
      peak$kind <- "refractory"
      peaks[[index]] <- peak
    } else if (peak$peak_i > peak$thr_i && peak$peak_f > peak$thr_f) {
      if (!is.null(previous) && elapsed < params[["twave_ms"]] %/% 5 && 2*peak$slope < previous$slope) {
        peak$kind <- "twave"
        peaks[[index]] <- peak
        update(index,"noise")
      } else {
        peak$kind <- "qrs"
        peaks[[index]] <- peak
        update(index,"signal")
        register(index)
      }
    } else {
      peak$kind <- "noise"
      peaks[[index]] <- peak
      update(index,"noise")
    }
  }
  searchback(length(signals$integrated))
  list(peaks=peaks,registered=registered,initial=initial,final=levels,
       threshold=thresholds(levels),ra1=ra1,ra2=ra2)
}
build_beats <- function(detection,band,params) {
  beats <- list()
  for (index in detection$registered) {
    peak <- detection$peaks[[index]]
    k <- length(beats)+1L
    sample <- max(0,peak$r-21)
    rr <- if (k == 1L) NULL else 5*(sample-beats[[k-1L]]$sample)
    width <- width_ms(band,peak$r)
    label <- "N"
    if (k >= 10L) {
      total <- sum(vapply(beats[seq.int(k-8L,k-1L)],`[[`,numeric(1),"rr"))
      if (800*rr < params[["premature_percent"]]*total) label <- if (width > params[["qrs_width_ms"]]) "V" else "A"
    }
    beats[[k]] <- list(sample=sample,rr=rr,hr=if (is.null(rr)) NULL else rdiv(6000000,rr),
      width=width,label=label,method=if (peak$kind == "qrs") "threshold" else "searchback",annotation=0L,offset=0)
  }
  beats
}
match_annotations <- function(beats,annotations,tolerance) {
  matched <- integer(length(annotations))
  for (k in seq_along(beats)) {
    distance <- vapply(annotations,function(ref) abs(ref$sample-beats[[k]]$sample),numeric(1))
    candidates <- which(matched == 0L & distance <= tolerance)
    if (!length(candidates)) next
    j <- candidates[which.min(distance[candidates])]
    matched[j] <- k
    beats[[k]]$annotation <- j
    beats[[k]]$offset <- 5*(beats[[k]]$sample-annotations[[j]]$sample)
  }
  list(beats=beats,matched=matched)
}
scale_position <- function(value,top,bottom,height) if (top > bottom) rdiv(
    (top-value)*(height-1),
    top-bottom
) else 0
axis_row <- function(columns,marker) paste0("       +",paste(vapply(seq_len(columns)-1L,
  function(i) if (marker(i)) "+" else "-",character(1)),collapse=""),"+")
label_row <- function(heading,markers) {
  text <- sprintf("%6s  ",heading)
  for (marker in markers) text <- paste0(text,strrep(" ",max(0,8+marker$column-nchar(text))),marker$text)
  sub(" +$","",text)
}
waveform <- function(upper,lower,height) {
  top <- max(upper)
  bottom <- min(lower)
  zero <- if (bottom <= 0 && 0 <= top) scale_position(0,top,bottom,height) else -1
  hi <- vapply(upper,scale_position,numeric(1),top=top,bottom=bottom,height=height)
  lo <- vapply(lower,scale_position,numeric(1),top=top,bottom=bottom,height=height)
  vapply(seq_len(height)-1L,function(row) {
    label <- if (row == 0L) integer_text(top) else if (row == height-1L) integer_text(bottom) else if (row == zero) "0" else ""
    cells <- ifelse(hi <= row & row <= lo,"#",if (row == zero) "-" else " ")
    paste0(sprintf("%6s |",label),paste(cells,collapse=""),"|")
  },character(1))
}
segments_for <- function(beats,annotations,matched,peaks,n,params) {
  step <- params[["segment_ms"]] %/% 5
  lapply(seq.int(0,n-1L,by=step),function(start) {
    stop <- min(start+step,n)
    refs <- which(vapply(annotations,function(ref) start <= ref$sample && ref$sample < stop,logical(1)))
    selected <- Filter(function(b) start <= b$sample && b$sample < stop,beats)
    tp <- sum(matched[refs] > 0L)
    list(start=5*start,stop=5*stop,refs=length(refs),tp=tp,fn=length(refs)-tp,
      fp=sum(vapply(selected,function(b) b$annotation == 0L,logical(1))),beats=length(selected),
      noise=sum(vapply(peaks,function(p) p$kind == "noise" && start <= p$time && p$time < stop,logical(1))),
      rr=unlist(lapply(selected,`[[`,"rr"),use.names=FALSE))
  })
}
csv_outputs <- function(ecg,signals,peaks,beats,annotations,matched,params) {
  lines <- "beat,sample,time_ms,rr_ms,hr_bpm,width_ms,label,method,ref_sample,ref_label"
  for (k in seq_along(beats)) {
    b <- beats[[k]]
    ref <- if (b$annotation) annotations[[b$annotation]] else NULL
    lines <- c(lines,csv_row(k,b$sample,5*b$sample,missing_dash(b$rr),if (is.null(b$hr)) "-" else two(b$hr),
      b$width,b$label,b$method,if (is.null(ref)) "-" else ref$sample,if (is.null(ref)) "-" else ref$label))
  }
  write_lines("beats.csv",lines)
  lines <- "peak,sample,r_sample,peak_i,peak_f,slope,thr_i,thr_f,class"
  for (k in seq_along(peaks)) {
    p <- peaks[[k]]
    lines <- c(lines,csv_row(k,p$time,p$r,p$peak_i,p$peak_f,p$slope,p$thr_i,p$thr_f,p$kind))
  }
  write_lines("peaks.csv",lines)
  records <- list()
  for (j in seq_along(annotations)) {
    ref <- annotations[[j]]
    k <- matched[j]
    if (!k) row <- csv_row(ref$sample,ref$label,"-","-","-","-","FN","-") else {
      b <- beats[[k]]
      row <- csv_row(
          ref$sample,
          ref$label,
          k,
          b$sample,
          b$label,
          b$offset,
          "TP",
          if (ref$label == b$label) "yes" else "no"
      )
    }
    records[[length(records)+1L]] <- list(sample=ref$sample,kind=0L,text=row)
  }
  for (k in seq_along(beats)) {
    b <- beats[[k]]
    if (b$annotation) next
    records[[length(records)+1L]] <- list(sample=b$sample,kind=1L,
      text=csv_row("-","-",k,b$sample,b$label,"-","FP","-"))
  }
  order_records <- order(vapply(records,`[[`,numeric(1),"sample"),vapply(records,`[[`,integer(1),"kind"))
  write_lines("matching.csv",c("ref_sample,ref_label,beat,beat_sample,beat_label,offset_ms,status,agree",
    vapply(records[order_records],`[[`,character(1),"text")))
  lines <- "sample,ecg,lowpass,bandpass,derivative,squared,integrated"
  for (i in seq_len(params[["excerpt_ms"]] %/% 5)) lines <- c(lines,
    csv_row(
        i-1L,
        ecg[i],
        signals$lowpass[i],
        signals$bandpass[i],
        signals$derivative[i],
        signals$squared[i],
        signals$integrated[i]
    ))
  write_lines("signals_excerpt.csv",lines)
}
performance_lines <- function(beats,annotations,matched,peaks,detection,segments,params,n) {
  classes <- setNames(
      vapply(CLASSES,function(c) sum(vapply(peaks,function(p) p$kind == c,logical(1))),numeric(1)),
      CLASSES
  )
  refs <- setNames(
      vapply(LABELS,function(c) sum(vapply(annotations,function(r) r$label == c,logical(1))),numeric(1)),
      LABELS
  )
  detected <- setNames(
      vapply(LABELS,function(c) sum(vapply(beats,function(b) b$label == c,logical(1))),numeric(1)),
      LABELS
  )
  tp <- sum(matched > 0L)
  fn <- length(annotations)-tp
  fp <- length(beats)-tp
  tally <- function(values) paste(paste0(names(values),"=",integer_text(unlist(values))),collapse=" ")
  lines <- c("DETECTOR",fmt("samples %s",n),fmt("duration_ms %s",5*n),
    fmt("peaks %s %s",length(peaks),tally(classes)),paste0("initial_levels ",tally(detection$initial)),
    paste0("final_levels ",tally(detection$final)),
    fmt("final_thresholds thr_i=%s thr_f=%s",detection$threshold$thi1,detection$threshold$thf1),
    fmt("final_rr_averages rravg1_ms=%s rravg2_ms=%s",5*detection$ra1,5*detection$ra2),
    "MATCHING",fmt("tolerance_ms %s",params[["match_ms"]]),
    fmt(
        "references %s %s",
        length(annotations),
        tally(refs)
    ),fmt("detections %s %s",length(beats),tally(detected)),
    fmt("true_positives %s",tp),fmt("false_positives %s",fp),fmt("false_negatives %s",fn),
    paste0("sensitivity ",ratio(tp,tp+fn)),paste0("positive_predictivity ",ratio(tp,tp+fp)),
    paste0("detection_error_rate ",ratio(fp+fn,length(annotations))))
  method_stats <- vapply(c("threshold","searchback"),function(method) {
    selected <- Filter(function(b) b$method == method,beats)
    fmt("%s=%s/%s",method,sum(vapply(selected,function(b) b$annotation > 0L,logical(1))),length(selected))
  },character(1))
  lines <- c(lines,paste0("by_method ",paste(method_stats,collapse=" ")))
  offsets <- vapply(Filter(function(b) b$annotation > 0L,beats),`[[`,numeric(1),"offset")
  lines <- c(lines,if (!length(offsets)) "offset_ms none" else fmt("offset_ms mean=%s mean_abs=%s max_abs=%s",
    two(rdiv(100*sum(offsets),tp)),two(rdiv(100*sum(abs(offsets)),tp)),max(abs(offsets))))
  confusion <- matrix(0,nrow=4L,ncol=4L,dimnames=list(c(LABELS,"extra"),c(LABELS,"miss")))
  for (j in seq_along(annotations)) {
    label <- if (matched[j]) beats[[matched[j]]]$label else "miss"
    c <- annotations[[j]]$label
    confusion[c,label] <- confusion[c,label]+1L
  }
  for (b in beats) if (!b$annotation) confusion["extra",b$label] <- confusion["extra",b$label]+1L
  padded <- function(values) paste(sprintf("%6s",integer_text(values)),collapse="")
  lines <- c(lines,"CONFUSION",paste0("ref  ",paste(sprintf("%6s",LABELS),collapse=""),"  miss"))
  for (c in LABELS) lines <- c(lines,paste0(c,"    ",padded(confusion[c,])))
  lines <- c(lines,paste0("extra",padded(confusion["extra",LABELS])))
  for (c in c("V","A")) {
    prefix <- if (c == "V") "veb" else "sveb"
    lines <- c(lines,paste0(prefix,"_sensitivity ",ratio(confusion[c,c],refs[[c]])),
      paste0(prefix,"_positive_predictivity ",ratio(confusion[c,c],detected[[c]])))
  }
  lines <- c(lines,fmt("SEGMENTS segment_ms=%s segments=%s",params[["segment_ms"]],length(segments)))
  for (s in segments) lines <- c(lines,fmt("%6s-%6s refs=%s tp=%s fp=%s fn=%s noise_peaks=%s",
    s$start,s$stop,s$refs,s$tp,s$fp,s$fn,s$noise))
  errors <- list()
  for (k in seq_along(beats)) {
    b <- beats[[k]]
    if (!b$annotation) errors[[length(errors)+1L]] <- list(sample=b$sample,kind=0L,
      text=fmt("false_positive beat=%s sample=%s time_ms=%s label=%s",k,b$sample,5*b$sample,b$label))
  }
  for (j in seq_along(annotations)) {
    ref <- annotations[[j]]
    if (!matched[j]) errors[[length(errors)+1L]] <- list(sample=ref$sample,kind=1L,
      text=fmt("false_negative sample=%s time_ms=%s label=%s",ref$sample,5*ref$sample,ref$label))
  }
  indices <- order(vapply(errors,`[[`,numeric(1),"sample"),vapply(errors,`[[`,integer(1),"kind"))
  c(lines,fmt("ERRORS count=%s",fp+fn),vapply(errors[indices],`[[`,character(1),"text"))
}
hrv_lines <- function(beats,annotations,segments,params) {
  rr <- vapply(beats[-1L],`[[`,numeric(1),"rr")
  stats <- rr_statistics(rr)
  lines <- c(
      "RR",
      fmt("beats %s",length(beats)),
      fmt("intervals %s",length(rr)),
      paste0("mean_rr_ms ",maybe_two(stats$mean_rr))
  )
  if (!length(rr)) lines <- c(lines,"min_rr_ms none","max_rr_ms none","mean_hr_bpm none") else {
    lines <- c(lines,fmt("min_rr_ms %s beat=%s",min(rr),which.min(rr)+1L),
      fmt("max_rr_ms %s beat=%s",max(rr),which.max(rr)+1L),paste0("mean_hr_bpm ",two(stats$mean_hr)))
  }
  nn <- list()
  for (k in seq.int(3L,length(beats))) {
    previous <- beats[[k-1L]]
    b <- beats[[k]]
    if (previous$label == "N" && b$label == "N" && 5*abs(b$rr-previous$rr) <= previous$rr) nn[[as.character(k)]] <- b$rr
  }
  pairs <- list()
  for (key in names(nn)) {
    previous <- as.character(as.integer(key)-1L)
    if (!is.null(nn[[previous]])) pairs[[length(pairs)+1L]] <- c(nn[[previous]],nn[[key]])
  }
  info <- nn_statistics(unlist(nn,use.names=FALSE),pairs)
  lines <- c(lines,"NN",fmt("intervals %s",info$e),paste0("mean_nn_ms ",maybe_two(info$mean_nn)),
    paste0("sdnn_ms ",maybe_two(info$sdnn)),fmt("differences %s",info$k),paste0(
        "rmssd_ms ",
        maybe_two(info$rmssd)
    ),
    paste0("sdsd_ms ",maybe_two(info$sdsd)),fmt("nn50 %s",info$nn50),
    if (is.null(info$pnn50)) "pnn50 none" else paste0("pnn50 ",two(info$pnn50),"%"),
    paste0("sd1_ms ",maybe_two(info$sd1)),paste0("sd2_ms ",maybe_two(info$sd2)),
    fmt("HISTOGRAM bin_ms=7.8125 bins=%s max=%s",length(info$histogram),info$max_count))
  bins <- sort(as.numeric(names(info$histogram)))
  for (bin in bins) {
    count <- as.numeric(info$histogram[[integer_text(bin)]])
    lines <- c(lines,fmt("%10s %10s %3s |%s",four(78125*bin),four(78125*(bin+1)),count,strrep("#",count)))
  }
  lines <- c(lines,if (!info$e) "triangular_index none" else
    fmt("triangular_index %s %s",fraction(info$e,info$max_count),two(info$triangular_index)))
  premature <- which(vapply(beats,function(b) b$label != "N",logical(1)))
  labels <- vapply(beats,`[[`,character(1),"label")
  lines <- c(
      lines,
      fmt("PREMATURE count=%s V=%s A=%s",length(premature),sum(labels == "V"),sum(labels == "A"))
  )
  for (k in premature) {
    b <- beats[[k]]
    total <- sum(vapply(beats[seq.int(k-8L,k-1L)],`[[`,numeric(1),"rr"))
    next_rr <- if (k < length(beats)) beats[[k+1L]]$rr else NULL
    compensation <- if (is.null(next_rr)) "-" else if (10*abs(4*(b$rr+next_rr)-total) <= total) "full" else
      if (4*(b$rr+next_rr) < total) "partial" else "long"
    ref <- if (b$annotation) annotations[[b$annotation]]$label else "-"
    lines <- c(lines,fmt("beat=%s sample=%s label=%s rr_ms=%s next_rr_ms=%s mean_ms=%s prematurity=%s%% compensation=%s width_ms=%s ref=%s",
      k,b$sample,b$label,b$rr,missing_dash(next_rr),two(rdiv(100*total,8)),two(rdiv(
          80000*b$rr,
          total
      )),compensation,b$width,ref))
  }
  runs <- list()
  for (label in c("V","A")) for (range in consecutive_ranges(which(labels == label))) {
    a <- range[1L]
    b <- range[2L]
    length_run <- b-a+1L
    kind <- if (length_run == 1L) "isolated" else if (length_run == 2L) "couplet" else "run"
    runs[[length(runs)+1L]] <- list(first=a,text=fmt("%s %s beats=%s-%s length=%s start_ms=%s",
      label,kind,a,b,length_run,5*beats[[a]]$sample))
  }
  runs <- runs[order(vapply(runs,`[[`,numeric(1),"first"))]
  lines <- c(lines,fmt("RUNS count=%s",length(runs)),vapply(runs,`[[`,character(1),"text"))
  events <- character()
  for (k in seq.int(2L,length(beats))) if (beats[[k]]$rr > params[["pause_ms"]])
    events <- c(
        events,
        fmt("pause beats=%s-%s rr_ms=%s start_ms=%s",k-1L,k,beats[[k]]$rr,5*beats[[k-1L]]$sample)
    )
  for (kind in c("bradycardia","tachycardia")) {
    selected <- which(if (kind == "bradycardia") rr > params[["brady_ms"]] else rr < params[["tachy_ms"]])+1L
    for (range in consecutive_ranges(selected)) {
      a <- range[1L]
      b <- range[2L]
      if (b-a+1L < 3L) next
      hr <- rdiv(6000000*(b-a+1L),sum(rr[seq.int(a-1L,b-1L)]))
      events <- c(
          events,
          fmt(
              "%s beats=%s-%s intervals=%s mean_hr=%s start_ms=%s",
              kind,
              a-1L,
              b,
              b-a+1L,
              two(hr),
              5*beats[[a-1L]]$sample
          )
      )
    }
  }
  for (span in c(2L,3L)) {
    chains <- list()
    for (k in which(labels == "V")) {
      n <- length(chains)
      previous <- if (n) tail(chains[[n]],1L) else 0L
      if (n && k == previous+span && all(labels[seq.int(
          previous+1L,
          k-1L
      )] == "N")) chains[[n]] <- c(chains[[n]],k)
      else chains[[n+1L]] <- k
    }
    kind <- if (span == 2L) "bigeminy" else "trigeminy"
    for (chain in chains) if (length(chain) >= 3L) events <- c(events,
      fmt(
          "%s beats=%s-%s cycles=%s start_ms=%s",
          kind,
          chain[1L],
          tail(chain,1L),
          length(chain),
          5*beats[[chain[1L]]]$sample
      ))
  }
  lines <- c(lines,fmt("EVENTS count=%s",length(events)),events,
    fmt("TREND segment_ms=%s segments=%s",params[["segment_ms"]],length(segments)))
  for (s in segments) {
    header <- fmt("%6s-%6s beats=%s ",s$start,s$stop,s$beats)
    if (!length(s$rr)) lines <- c(lines,paste0(header,"mean_hr=none min_hr=none max_hr=none |")) else {
      hr <- rdiv(6000000*length(s$rr),sum(s$rr))
      lines <- c(lines,paste0(header,fmt("mean_hr=%s min_hr=%s max_hr=%s |%s",two(hr),
        two(rdiv(6000000,max(s$rr))),two(rdiv(6000000,min(s$rr))),strrep("#",rdiv(hr,500)))))
    }
  }
  lines
}
chart_lines <- function(ecg,beats,params) {
  rr <- vapply(beats[-1L],`[[`,numeric(1),"rr")
  height <- params[["chart_rows"]]
  lines <- character()
  if (!length(rr)) lines <- c("TACHOGRAM intervals=0","POINCARE points=0") else {
    lo <- min(rr)
    hi <- max(rr)
    lines <- fmt("TACHOGRAM intervals=%s min_ms=%s max_ms=%s rows=%s",length(rr),lo,hi,height)
    for (row in seq_len(height)-1L) {
      label <- if (row == 0L) integer_text(hi) else if (row == height-1L) integer_text(lo) else ""
      positions <- vapply(rr,scale_position,numeric(1),top=hi,bottom=lo,height=height)
      lines <- c(lines,paste0(sprintf("%6s |",label),paste(ifelse(positions == row,"*"," "),collapse=""),"|"))
    }
    markers <- lapply(
        which((seq_along(rr)+1L) %% 10L == 0L),
        function(i) list(column=i-1L,text=as.character(i+1L))
    )
    lines <- c(lines,axis_row(length(rr),function(j) (j+2L) %% 10L == 0L),label_row("beat",markers),
      paste0(" label |",paste(vapply(beats[-1L],`[[`,character(1),"label"),collapse=""),"|"))
    size <- params[["poincare_size"]]
    cells <- matrix(0L,nrow=size,ncol=size)
    for (k in seq_len(length(rr)-1L)) {
      column <- if (hi > lo) rdiv((rr[k]-lo)*(size-1L),hi-lo) else 0L
      row <- scale_position(rr[k+1L],hi,lo,size)
      cells[row+1L,column+1L] <- cells[row+1L,column+1L]+1L
    }
    lines <- c(lines,fmt("POINCARE points=%s size=%s min_ms=%s max_ms=%s",length(rr)-1L,size,lo,hi))
    for (row in seq_len(size)) {
      label <- if (row == 1L) integer_text(hi) else if (row == size) integer_text(lo) else ""
      text <- paste(
          ifelse(cells[row,] == 0L,".",ifelse(cells[row,] <= 9L,integer_text(cells[row,]),"#")),
          collapse=""
      )
      lines <- c(lines,paste0(sprintf("%6s |",label),text,"|"))
    }
    lines <- c(lines,axis_row(size,function(i) FALSE),paste0("        ",integer_text(lo),
      strrep(" ",max(0,size-nchar(integer_text(lo))-nchar(integer_text(hi)))),integer_text(hi)))
  }
  for (label in LABELS) {
    chosen <- Filter(function(b) b$label == label && 60 <= b$sample && b$sample <= length(ecg)-100L,beats)
    if (!length(chosen)) {
      lines <- c(lines,fmt("TEMPLATE %s beats=0",label))
      next
    }
    baseline <- vapply(chosen,function(b) sum(ecg[seq.int(b$sample-59L,b$sample-50L)]),numeric(1))
    averaged <- vapply(seq.int(-60L,99L),function(j) rdiv(sum(vapply(seq_along(chosen),
      function(k) 10*ecg[chosen[[k]]$sample+j+1L]-baseline[k],numeric(1))),10*length(chosen)),numeric(1))
    lines <- c(lines,fmt("TEMPLATE %s beats=%s max_uv=%s max_ms=%s min_uv=%s min_ms=%s rows=%s",label,length(chosen),
      max(averaged),5*(which.max(averaged)-61L),min(averaged),5*(which.min(averaged)-61L),height))
    odd <- 2L*(seq_len(80L)-1L)+1L
    lines <- c(lines,waveform(pmax(averaged[odd],averaged[odd+1L]),pmin(averaged[odd],averaged[odd+1L]),height),
      axis_row(80L,function(i) i %% 10L == 0L),label_row("ms",lapply(seq.int(0L,70L,10L),
        function(i) list(column=i,text=as.character(10L*i-300L)))))
  }
  lines
}
rhythm_lines <- function(ecg,beats,annotations,params) {
  start <- params[["strip_start_ms"]] %/% 5
  n <- params[["strip_ms"]] %/% 5
  columns <- n %/% 10
  height <- params[["strip_rows"]]
  excerpt <- ecg[seq.int(start+1L,start+n)]
  upper <- vapply(seq_len(columns)-1L,function(i) max(excerpt[seq.int(10L*i+1L,10L*i+10L)]),numeric(1))
  lower <- vapply(seq_len(columns)-1L,function(i) min(excerpt[seq.int(10L*i+1L,10L*i+10L)]),numeric(1))
  lines <- c(fmt("RHYTHM start_ms=%s end_ms=%s columns=%s rows=%s max_uv=%s min_uv=%s",params[["strip_start_ms"]],
    params[["strip_start_ms"]]+params[["strip_ms"]],columns,height,max(excerpt),min(excerpt)),waveform(
        upper,
        lower,
        height
    ),
    axis_row(columns,function(i) i %% 20L == 0L),label_row("s",lapply(seq.int(0L,columns-1L,20L),
      function(i) list(column=i,text=integer_text((params[["strip_start_ms"]]+50*i) %/% 1000)))))
  beat_marks <- ref_marks <- rep(" ",columns)
  for (b in beats) if (start <= b$sample && b$sample < start+n) beat_marks[(b$sample-start) %/% 10+1L] <- b$label
  for (ref in annotations) if (start <= ref$sample && ref$sample < start+n) ref_marks[(ref$sample-start) %/% 10+1L] <- ref$label
  c(
      lines,
      paste0(" beats |",paste(beat_marks,collapse=""),"|"),
      paste0("  refs |",paste(ref_marks,collapse=""),"|")
  )
}
main <- function() {
  ecg <- read_ecg()
  annotations <- read_annotations()
  params <- read_params()
  signals <- filter_ecg(ecg)
  detection <- detect_beats(find_peaks(signals),signals,params)
  peaks <- detection$peaks
  matches <- match_annotations(
      build_beats(detection,signals$bandpass,params),
      annotations,
      params[["match_ms"]] %/% 5
  )
  beats <- matches$beats
  matched <- matches$matched
  segments <- segments_for(beats,annotations,matched,peaks,length(ecg),params)
  csv_outputs(ecg,signals,peaks,beats,annotations,matched,params)
  write_lines(
      "performance.txt",
      performance_lines(beats,annotations,matched,peaks,detection,segments,params,length(ecg))
  )
  write_lines("hrv.txt",hrv_lines(beats,annotations,segments,params))
  write_lines("charts.txt",chart_lines(ecg,beats,params))
  write_lines("rhythm_strip.txt",rhythm_lines(ecg,beats,annotations,params))
}
main()
