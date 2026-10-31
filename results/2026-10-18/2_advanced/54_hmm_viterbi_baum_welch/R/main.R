for (module in c("model_io","inference","training","evaluation","sampler")) source(paste0(module,".R"))
interpret_parameters <- function(rows,model) {
  raw <- setNames(lapply(rows,function(row) row[-1L]),vapply(rows,`[`,character(1),1L))
  integer_keys <- c("iterations","folds","min_sequence_length","max_missing_percent","merge_gap","min_segment_length","min_rich_percent",
    "min_motif_percent","boundary_tolerance","posterior_seed","posterior_samples","sample_seed","sample_count","sample_length")
  params <- setNames(lapply(integer_keys,function(name) as.integer(raw[[name]][1L])),integer_keys)
  params$pseudocount <- as.numeric(raw$pseudocount[1L])
  params$confidence <- as.numeric(raw$confidence[1L])
  params$smoothing <- lapply(raw$smoothing,function(text) list(text=text,value=as.numeric(text)))
  params$segment_state <- match(raw$segment_state[1L],model$states)
  params$motif <- match(raw$motif,model$symbols)
  params$rich_symbols <- match(raw$rich_symbols,model$symbols)
  params
}
characters <- function(text) strsplit(text,"",fixed=TRUE)[[1L]]
rejection_reason <- function(name,observations,labels,seen,model,params) {
  if (exists(name,envir=seen,inherits=FALSE)) return("duplicate name")
  seen[[name]] <- TRUE
  for (i in seq_along(observations)) {
    character <- observations[i]
    if (!character %in% model$symbols && character != model$missing) return(paste(
        "invalid symbol",
        character,
        "at position",
        i
    ))
  }
  if (!is.null(labels)) {
    for (i in seq_along(labels)) if (!labels[i] %in% model$states) return(paste(
        "invalid label",
        labels[i],
        "at position",
        i
    ))
    if (length(observations) != length(labels)) return(paste(
        "length mismatch",
        length(observations),
        length(labels)
    ))
  }
  if (length(observations) < params$min_sequence_length) return(paste("too short",length(observations)))
  missing <- sum(observations == model$missing)
  if (100L*missing > params$max_missing_percent*length(observations)) return(paste(
      "too many missing",
      missing
  ))
  NULL
}
encode_observations <- function(text,model) {
  result <- match(text,model$symbols)
  result[text == model$missing] <- 0L
  result
}
validate_inputs <- function(sequence_rows,labeled_rows,model,params) {
  sequences <- training <- testing <- list()
  rejections <- character()
  seen <- new.env(hash=TRUE,parent=emptyenv())
  for (line in seq_along(sequence_rows)) {
    row <- sequence_rows[[line]]
    name <- row[1L]
    observations <- characters(toupper(row[2L]))
    reason <- rejection_reason(name,observations,NULL,seen,model,params)
    if (is.null(reason)) sequences[[length(sequences)+1L]] <- list(
        name=name,
        observations=encode_observations(observations,model),
        path=NULL
    ) else
      rejections <- c(rejections,paste("REJECT sequences.txt line",line,name,reason))
  }
  seen <- new.env(hash=TRUE,parent=emptyenv())
  for (offset in seq.int(1L,length(labeled_rows),by=2L)) {
    row <- labeled_rows[[offset]]
    name <- row[1L]
    role <- row[2L]
    observations <- characters(toupper(row[3L]))
    labels <- characters(labeled_rows[[offset+1L]][1L])
    reason <- rejection_reason(name,observations,labels,seen,model,params)
    if (is.null(reason)) {
      record <- list(
          name=name,
          observations=encode_observations(observations,model),
          path=match(labels,model$states)
      )
      if (role == "TRAIN") training[[length(training)+1L]] <- record else testing[[length(testing)+1L]] <- record
    } else rejections <- c(rejections,paste("REJECT labeled.txt line",offset,name,reason))
  }
  list(sequences=sequences,training=training,testing=testing,rejections=rejections)
}
maximum_change <- function(previous,current) max(
    abs(previous$initial-current$initial),
    abs(previous$transition-current$transition),
    abs(previous$emission-current$emission)
)
train_baum_welch <- function(initial,observations,heldout,params) {
  current <- initial
  previous_loglik <- total_loglik(current,observations)
  initial_loglik <- previous_loglik
  heldout_loglik <- total_loglik(current,heldout)
  best_heldout <- heldout_loglik
  best_iteration <- violations <- 0L
  trace <- c(
      "iteration,loglik,heldout,change,max_change,status",
      paste0("0,",real_text(previous_loglik),",",real_text(heldout_loglik),",,,")
  )
  for (iteration in seq_len(params$iterations)) {
    updated <- baum_welch_step(current,observations,params$pseudocount)
    loglik <- total_loglik(updated,observations)
    heldout_loglik <- total_loglik(updated,heldout)
    change <- loglik-previous_loglik
    largest <- maximum_change(current,updated)
    violation <- loglik < previous_loglik-0.000001*abs(previous_loglik)
    violations <- violations+as.integer(violation)
    if (heldout_loglik > best_heldout) {
      best_heldout <- heldout_loglik
      best_iteration <- iteration
    }
    status <- if (violation) "violation" else "ok"
    trace <- c(
        trace,
        paste(
            iteration,
            real_text(loglik),
            real_text(heldout_loglik),
            real_text(change),
            real_text(largest,6L),
            status,
            sep=","
        )
    )
    current <- updated
    previous_loglik <- loglik
  }
  list(
      model=current,
      trace=trace,
      summary=list(
          iterations=params$iterations,
          initial_loglik=initial_loglik,
          final_loglik=previous_loglik,
          violations=violations,
          best_heldout_iteration=best_iteration
      )
  )
}
viterbi_paths <- function(model,observations) {
  paths <- list()
  total <- 0
  for (sequence in observations) {
    result <- viterbi(model,sequence)
    paths[[length(paths)+1L]] <- result$path
    total <- total+result$logprob
  }
  list(paths=paths,logprob=total)
}
train_viterbi <- function(initial,observations,params) {
  current <- initial
  decoded <- viterbi_paths(current,observations)
  paths <- decoded$paths
  loglik <- total_loglik(current,observations)
  trace <- c(
      "iteration,logprob,loglik,changed",
      paste0("0,",real_text(decoded$logprob),",",real_text(loglik),",")
  )
  iterations <- changed <- 0L
  for (iteration in seq_len(params$iterations)) {
    pairs <- lapply(seq_along(observations),function(i) list(observations=observations[[i]],path=paths[[i]]))
    current <- estimate_by_counting(initial,pairs,params$pseudocount,"VITERBI_TRAINING")
    updated <- viterbi_paths(current,observations)
    changed <- sum(vapply(
        seq_along(paths),
        function(i) length(paths[[i]])-correct_count(paths[[i]],updated$paths[[i]]),
        integer(1)
    ))
    loglik <- total_loglik(current,observations)
    trace <- c(trace,paste(iteration,real_text(updated$logprob),real_text(loglik),changed,sep=","))
    paths <- updated$paths
    iterations <- iteration
    if (changed == 0L) break
  }
  list(model=current,trace=trace,summary=list(iterations=iterations,converged=changed == 0L))
}
record_pairs <- function(records) lapply(
    records,
    function(record) list(observations=record$observations,path=record$path)
)
cross_validate <- function(initial,records,params) {
  folds <- params$folds
  k <- length(initial$states)
  positions <- sum(vapply(records,function(record) length(record$observations),integer(1)))
  results <- list()
  assignment <- (seq_along(records)-1L) %% folds
  for (candidate in params$smoothing) {
    matrix <- confusion_matrix(k)
    fold_results <- list()
    total_correct <- 0L
    for (f in seq_len(folds)-1L) {
      fitting <- records[assignment != f]
      validation <- records[assignment == f]
      model <- estimate_by_counting(initial,record_pairs(fitting),candidate$value)
      fold_positions <- fold_correct <- 0L
      for (record in validation) {
        path <- viterbi(model,record$observations)$path
        fold_positions <- fold_positions+length(path)
        fold_correct <- fold_correct+correct_count(record$path,path)
        matrix <- accumulate_confusion(matrix,record$path,path)
      }
      total_correct <- total_correct+fold_correct
      fold_results[[length(fold_results)+1L]] <- list(
          records=length(validation),
          positions=fold_positions,
          correct=fold_correct
      )
    }
    results[[length(results)+1L]] <- list(
        candidate=candidate$text,
        alpha=candidate$value,
        correct=total_correct,
        folds=fold_results,
        matrix=matrix
    )
  }
  selected <- results[[which.max(vapply(results,function(result) result$correct,integer(1)))]]
  lines <- paste("CROSS_VALIDATION folds",folds)
  for (result in results) lines <- c(
      lines,
      paste(
          "SMOOTHING",
          result$candidate,
          "positions",
          positions,
          "correct",
          result$correct,
          "accuracy",
          fraction(result$correct,positions)
      )
  )
  lines <- c(lines,paste("SELECTED",selected$candidate))
  for (f in seq_along(selected$folds)) {
    row <- selected$folds[[f]]
    lines <- c(
        lines,
        paste(
            "FOLD",
            f,
            "records",
            row$records,
            "positions",
            row$positions,
            "correct",
            row$correct,
            "accuracy",
            fraction(row$correct,row$positions)
        )
    )
  }
  lines <- c(lines,matrix_lines(initial$states,selected$matrix),metric_lines(initial$states,selected$matrix))
  list(model=estimate_by_counting(initial,record_pairs(records),selected$alpha),selected=selected,lines=lines)
}
learning_curve <- function(initial,training,testing,alpha) {
  positions <- sum(vapply(testing,function(record) length(record$observations),integer(1)))
  lines <- "LEARNING_CURVE"
  for (n in seq_along(training)) {
    model <- estimate_by_counting(initial,record_pairs(head(training,n)),alpha)
    correct <- sum(vapply(
        testing,
        function(record) correct_count(record$path,viterbi(model,record$observations)$path),
        integer(1)
    ))
    lines <- c(lines,paste("RECORDS",n,"correct",correct,"accuracy",fraction(correct,positions)))
  }
  lines
}
extract_segments <- function(path,params) {
  segments <- list()
  for (run in runs(path)) {
    if (run[1L] != params$segment_state) next
    start <- run[2L]
    ending <- run[3L]
    n <- length(segments)
    if (n > 0L && start-segments[[n]][2L]-1L <= params$merge_gap) segments[[n]][2L] <- ending else segments[[n+1L]] <- c(
        start,
        ending
    )
  }
  Filter(function(segment) segment[2L]-segment[1L]+1L >= params$min_segment_length,segments)
}
composition <- function(observations,segment,params) {
  start <- segment[1L]
  ending <- segment[2L]
  first <- params$motif[1L]
  second <- params$motif[2L]
  observed <- rich <- first_count <- second_count <- pairs <- 0L
  for (t in seq.int(start,ending)) {
    symbol <- observations[t]
    if (symbol != 0L) {
      observed <- observed+1L
      rich <- rich+as.integer(symbol %in% params$rich_symbols)
      first_count <- first_count+as.integer(symbol == first)
      second_count <- second_count+as.integer(symbol == second)
    }
    if (t < ending && symbol == first && observations[t+1L] == second) pairs <- pairs+1L
  }
  denominator <- first_count*second_count
  island <- denominator > 0L && 100L*rich >= params$min_rich_percent*observed && 100L*pairs*observed >= params$min_motif_percent*denominator
  list(
      rich=if (observed == 0L) NULL else rich/observed,
      pair=if (denominator == 0L) NULL else pairs*observed/denominator,
      island=island
  )
}
evaluate_model <- function(model,records,params) {
  decoded <- lapply(records,function(record) decode(model,record$observations))
  blocks <- list()
  correct_totals <- integer()
  for (decoder in c("VITERBI","POSTERIOR")) {
    matrix <- confusion_matrix(length(model$states))
    regions <- bounds <- integer(4L)
    calibration <- matrix(0L,10L,2L)
    record_lines <- character()
    total_correct <- 0L
    for (i in seq_along(records)) {
      record <- records[[i]]
      result <- decoded[[i]]
      path <- if (decoder == "VITERBI") result$viterbi else result$posterior
      correct <- correct_count(record$path,path)
      total_correct <- total_correct+correct
      matrix <- accumulate_confusion(matrix,record$path,path)
      predicted <- extract_segments(path,params)
      truth <- lapply(
          Filter(function(run) run[1L] == params$segment_state,runs(record$path)),
          function(run) run[2:3]
      )
      regions <- regions+region_counts(predicted,truth)
      bounds <- bounds+boundary_counts(path,record$path,params$boundary_tolerance)
      if (decoder == "POSTERIOR") for (t in seq_along(path)) {
        bin <- min(floor(10*result$confidence[t]),9L)+1L
        calibration[bin,1L] <- calibration[bin,1L]+1L
        calibration[bin,2L] <- calibration[bin,2L]+as.integer(path[t] == record$path[t])
      }
      record_lines <- c(record_lines,paste("RECORD",record$name,"length",length(path),"correct",correct))
    }
    lines <- c(paste("EVALUATION",model$name,decoder),matrix_lines(model$states,matrix),metric_lines(model$states,matrix),
      paste(
          "REGIONS",
          model$states[params$segment_state],
          "predicted",
          regions[1L],
          "true",
          regions[2L],
          "precision",
          fraction(regions[3L],regions[1L]),
          "recall",
          fraction(regions[4L],regions[2L])
      ),
      paste(
          "BOUNDARIES predicted",
          bounds[1L],
          "true",
          bounds[2L],
          "precision",
          fraction(bounds[3L],bounds[1L]),
          "recall",
          fraction(bounds[4L],bounds[2L])
      ))
    if (decoder == "POSTERIOR") for (b in seq_len(10L)-1L) {
      positions <- calibration[b+1L,1L]
      correct <- calibration[b+1L,2L]
      if (positions == 0L) next
      interval <- if (b == 9L) "0.9-1.0" else paste0("0.",b,"-0.",b+1L)
      lines <- c(
          lines,
          paste(
              "CALIBRATION",
              interval,
              "positions",
              positions,
              "correct",
              correct,
              "accuracy",
              fraction(correct,positions)
          )
      )
    }
    blocks[[length(blocks)+1L]] <- c(lines,record_lines)
    correct_totals <- c(correct_totals,total_correct)
  }
  list(blocks=blocks,scores=correct_totals)
}
state_string <- function(model,path) paste(model$states[path],collapse="")
imputed_string <- function(model,observations,posterior) {
  symbols <- character(length(observations))
  for (t in seq_along(observations)) {
    observation <- observations[t]
    if (observation != 0L) {
      symbols[t] <- model$symbols[observation]
    } else {
      probabilities <- vapply(
          seq_along(model$symbols),
          function(c) ordered_sum(vapply(
              seq_along(model$states),
              function(i) posterior[t,i]*model$emission[i,c],
              numeric(1)
          )),
          numeric(1)
      )
      symbols[t] <- tolower(model$symbols[maximum_index(probabilities)])
    }
  }
  paste(symbols,collapse="")
}
annotate_sequences <- function(model,records,decoded,params) {
  generator <- minstd(params$posterior_seed)
  decoding_lines <- character()
  segment_lines <- "sequence,decoder,start,end,length,mean_posterior,support,rich_fraction,motif_ratio,island"
  for (i in seq_along(records)) {
    record <- records[[i]]
    result <- decoded[[i]]
    samples <- lapply(
        seq_len(params$posterior_samples),
        function(unused) posterior_path(model,result$fb$forward,generator)
    )
    expected_segments <- sum(vapply(
        samples,
        function(path) length(extract_segments(path,params)),
        integer(1)
    ))/params$posterior_samples
    n <- length(record$observations)
    differences <- n-correct_count(result$viterbi,result$posterior)
    uncertain <- sum(result$confidence < params$confidence)
    confident <- paste(
        vapply(
            seq_along(result$posterior),
            function(t) if (result$confidence[t] < params$confidence) "." else model$states[result$posterior[t]],
            character(1)
        ),
        collapse=""
    )
    decoding_lines <- c(decoding_lines,paste("SEQUENCE",record$name,"length",n,"loglik",real_text(result$fb$loglik),"viterbi",real_text(result$viterbi_logprob),"differences",differences,"uncertain",uncertain,"expected_segments",real_text(expected_segments)),
      paste("VITERBI",state_string(model,result$viterbi)),paste("POSTERIOR",state_string(model,result$posterior)),paste("CONFIDENT",confident),paste(
          "IMPUTED",
          imputed_string(model,record$observations,result$fb$posterior)
      ))
    for (decoder in c("viterbi","posterior")) {
      path <- result[[decoder]]
      for (segment in extract_segments(path,params)) {
        start <- segment[1L]
        ending <- segment[2L]
        n <- ending-start+1L
        mean <- ordered_sum(result$fb$posterior[seq.int(start,ending),params$segment_state])/n
        support <- sum(vapply(
            samples,
            function(path) 2L*sum(path[seq.int(start,ending)] == params$segment_state) > n,
            logical(1)
        ))
        data <- composition(record$observations,segment,params)
        segment_lines <- c(
            segment_lines,
            paste(
                record$name,
                decoder,
                start,
                ending,
                n,
                real_text(mean),
                support,
                real_text(data$rich),
                real_text(data$pair),
                if (data$island) "yes" else "no",
                sep=","
            )
        )
      }
    }
  }
  list(decodings=decoding_lines,segments=segment_lines)
}
synthetic_output <- function(model,params) {
  generator <- minstd(params$sample_seed)
  lines <- character()
  viterbi_total <- posterior_total <- positions <- 0L
  for (number in seq_len(params$sample_count)) {
    generated <- synthetic_sequence(model,params$sample_length,generator)
    truth <- generated$states
    observations <- generated$observations
    result <- decode(model,observations)
    a <- correct_count(truth,result$viterbi)
    b <- correct_count(truth,result$posterior)
    viterbi_total <- viterbi_total+a
    posterior_total <- posterior_total+b
    positions <- positions+length(truth)
    lines <- c(lines,paste("SAMPLE",number,"loglik",real_text(result$fb$loglik),"viterbi",real_text(result$viterbi_logprob),"viterbi_correct",a,"posterior_correct",b),
      paste("STATES",state_string(model,truth)),paste(
          "SYMBOLS",
          paste(model$symbols[observations],collapse="")
      ),paste("VITERBI",state_string(model,result$viterbi)),paste("POSTERIOR",state_string(model,result$posterior)))
  }
  c(
      lines,
      paste(
          "TOTAL positions",
          positions,
          "viterbi_accuracy",
          fraction(viterbi_total,positions),
          "posterior_accuracy",
          fraction(posterior_total,positions)
      )
  )
}
path_statistics <- function(paths,k) {
  counts <- run_counts <- integer(k)
  total <- 0L
  for (path in paths) {
    total <- total+length(path)
    for (run in runs(path)) {
      counts[run[1L]] <- counts[run[1L]]+run[3L]-run[2L]+1L
      run_counts[run[1L]] <- run_counts[run[1L]]+1L
    }
  }
  list(counts=counts,runs=run_counts,total=total)
}
stationary_distribution <- function(model) {
  k <- length(model$states)
  matrix <- matrix(0,k,k+1L)
  for (equation in seq_len(k-1L)) for (state in seq_len(k)) matrix[equation,state] <- model$transition[
      state,
      equation
  ]-as.numeric(state == equation)
  matrix[k,] <- 1
  for (column in seq_len(k)) {
    candidates <- seq.int(column,k)
    pivot <- candidates[which.max(abs(matrix[candidates,column]))]
    temporary <- matrix[column,]
    matrix[column,] <- matrix[pivot,]
    matrix[pivot,] <- temporary
    divisor <- matrix[column,column]
    for (j in seq.int(column,k+1L)) matrix[column,j] <- matrix[column,j]/divisor
    for (row in seq_len(k)) {
      if (row == column) next
      factor <- matrix[row,column]
      for (j in seq.int(column,k+1L)) matrix[row,j] <- matrix[row,j]-factor*matrix[column,j]
    }
  }
  matrix[,k+1L]
}
state_permutations <- function(k) {
  result <- list()
  visit <- function(prefix) {
    if (length(prefix) == k) result[[length(result)+1L]] <<- prefix else for (j in seq_len(k)) if (!j %in% prefix) visit(c(
        prefix,
        j
    ))
  }
  visit(integer())
  result
}
state_alignment <- function(model,records) {
  k <- length(model$states)
  matrix <- confusion_matrix(k)
  positions <- 0L
  for (record in records) {
    path <- viterbi(model,record$observations)$path
    matrix <- accumulate_confusion(matrix,record$path,path)
    positions <- positions+length(path)
  }
  permutations <- state_permutations(k)
  counts <- vapply(
      permutations,
      function(p) sum(vapply(seq_len(k),function(j) matrix[p[j],j],integer(1))),
      integer(1)
  )
  best <- which.max(counts)
  mapping <- paste0(model$states,"=",model$states[permutations[[best]]],collapse=" ")
  paste("ALIGNMENT",mapping,"agreement",fraction(counts[best],positions))
}
model_diagnostics <- function(model,records,decoded,training,testing,params) {
  loglik <- 0
  observed <- segment_count <- segment_length <- islands <- 0L
  for (i in seq_along(records)) {
    record <- records[[i]]
    result <- decoded[[i]]
    loglik <- loglik+result$fb$loglik
    observed <- observed+sum(record$observations != 0L)
    for (segment in extract_segments(result$viterbi,params)) {
      segment_count <- segment_count+1L
      segment_length <- segment_length+segment[2L]-segment[1L]+1L
      islands <- islands+as.integer(composition(record$observations,segment,params)$island)
    }
  }
  test_loglik <- total_loglik(model,lapply(testing,function(record) record$observations))
  stats <- path_statistics(lapply(decoded,function(result) result$viterbi),length(model$states))
  stationary <- stationary_distribution(model)
  mean_length <- if (segment_count == 0L) NULL else segment_length/segment_count
  lines <- c(paste("MODEL",model$name),paste("LOGLIK unlabeled",real_text(loglik),"per_symbol",real_text(loglik/observed),"test",real_text(test_loglik)),
    paste(
        "SEGMENTS count",
        segment_count,
        "mean_length",
        real_text(mean_length),
        "islands",
        islands
    ),state_alignment(model,training))
  for (i in seq_along(model$states)) {
    duration <- 1/(1-model$transition[i,i])
    occupancy <- stats$counts[i]/stats$total
    mean_run <- if (stats$runs[i] == 0L) NULL else stats$counts[i]/stats$runs[i]
    lines <- c(
        lines,
        paste(
            "STATE",
            model$states[i],
            "stationary",
            real_text(stationary[i]),
            "duration",
            real_text(duration),
            "occupancy",
            real_text(occupancy),
            "mean_run",
            real_text(mean_run)
        )
    )
  }
  lines
}
input_report <- function(model,sequences,training,testing,rejections,sequence_count,labeled_count) {
  positions <- sum(vapply(sequences,function(record) length(record$observations),integer(1)))
  missing <- sum(vapply(sequences,function(record) sum(record$observations == 0L),integer(1)))
  labeled <- c(training,testing)
  labeled_positions <- sum(vapply(labeled,function(record) length(record$observations),integer(1)))
  labeled_missing <- sum(vapply(labeled,function(record) sum(record$observations == 0L),integer(1)))
  lines <- c("INPUT",paste("SEQUENCES accepted",length(sequences),"rejected",sequence_count-length(sequences),"positions",positions,"missing",missing),
    paste(
        "LABELED train",
        length(training),
        "test",
        length(testing),
        "rejected",
        labeled_count-length(labeled),
        "positions",
        labeled_positions,
        "missing",
        labeled_missing
    ),rejections)
  counts <- integer(length(model$symbols))
  for (record in sequences) for (symbol in record$observations) if (symbol != 0L) counts[symbol] <- counts[symbol]+1L
  composition_fields <- vapply(
      seq_along(model$symbols),
      function(i) paste(model$symbols[i],real_text(counts[i]/(positions-missing))),
      character(1)
  )
  lines <- c(lines,paste("COMPOSITION",paste(composition_fields,collapse=" ")))
  for (role in c("TRAIN","TEST")) {
    records <- if (role == "TRAIN") training else testing
    stats <- path_statistics(lapply(records,function(record) record$path),length(model$states))
    for (i in seq_along(model$states)) {
      mean_run <- if (stats$runs[i] == 0L) NULL else stats$counts[i]/stats$runs[i]
      lines <- c(
          lines,
          paste(
              "TRUTH",
              role,
              model$states[i],
              "occupancy",
              real_text(stats$counts[i]/stats$total),
              "mean_run",
              real_text(mean_run)
          )
      )
    }
  }
  lines
}
training_report <- function(models,bw,vt,selected,decoded,scores,test_positions) {
  lines <- c(paste("TRAINING BAUM_WELCH iterations",bw$iterations,"initial_loglik",real_text(bw$initial_loglik),"final_loglik",real_text(bw$final_loglik),"violations",bw$violations,"best_heldout_iteration",bw$best_heldout_iteration),
    paste(
        "TRAINING VITERBI_TRAINING iterations",
        vt$iterations,
        "converged",
        if (vt$converged) "yes" else "no"
    ),paste("TRAINING SUPERVISED smoothing",selected$candidate))
  preferences <- integer(length(models))
  for (i in seq_along(decoded[[1L]])) {
    best <- which.max(vapply(decoded,function(results) results[[i]]$fb$loglik,numeric(1)))
    preferences[best] <- preferences[best]+1L
  }
  lines <- c(
      lines,
      paste(
          "PREFERENCE",
          paste(
              vapply(seq_along(models),function(i) paste(models[[i]]$name,preferences[i]),character(1)),
              collapse=" "
          )
      )
  )
  positions <- sum(vapply(decoded[[1L]],function(result) length(result$viterbi),integer(1)))
  for (a in seq_len(length(models)-1L)) for (b in seq.int(a+1L,length(models))) {
    correct <- sum(vapply(
        seq_along(decoded[[a]]),
        function(i) correct_count(decoded[[a]][[i]]$viterbi,decoded[[b]][[i]]$viterbi),
        integer(1)
    ))
    lines <- c(lines,paste("AGREEMENT",models[[a]]$name,models[[b]]$name,fraction(correct,positions)))
  }
  for (i in seq_len(2L)) {
    name <- c("VITERBI","POSTERIOR")[i]
    best <- which.max(vapply(scores,function(row) row[i],integer(1)))
    lines <- c(
        lines,
        paste("BEST",name,models[[best]]$name,"accuracy",fraction(scores[[best]][i],test_positions))
    )
  }
  lines
}
join_blocks <- function(blocks) {
  lines <- character()
  for (block in blocks) {
    if (length(lines)) lines <- c(lines,"")
    lines <- c(lines,block)
  }
  lines
}
main <- function() {
  inputs <- read_inputs()
  initial <- inputs$model
  params <- interpret_parameters(inputs$parameters,initial)
  validated <- validate_inputs(inputs$sequences,inputs$labeled,initial,params)
  sequences <- validated$sequences
  training <- validated$training
  testing <- validated$testing
  observations <- lapply(sequences,function(record) record$observations)
  heldout <- lapply(c(training,testing),function(record) record$observations)
  bw <- train_baum_welch(initial,observations,heldout,params)
  vt <- train_viterbi(initial,observations,params)
  supervised <- cross_validate(initial,training,params)
  selected <- supervised$selected
  learning_lines <- learning_curve(initial,training,testing,selected$alpha)
  models <- list(initial,bw$model,vt$model,supervised$model)
  evaluation_blocks <- scores <- list()
  for (model in models) {
    evaluation <- evaluate_model(model,testing,params)
    evaluation_blocks <- c(evaluation_blocks,evaluation$blocks)
    scores[[length(scores)+1L]] <- evaluation$scores
  }
  evaluation_blocks <- c(evaluation_blocks,list(supervised$lines,learning_lines))
  decoded <- lapply(
      models,
      function(model) lapply(sequences,function(record) decode(model,record$observations))
  )
  annotation <- annotate_sequences(bw$model,sequences,decoded[[2L]],params)
  samples <- synthetic_output(bw$model,params)
  report_blocks <- list(input_report(
      initial,
      sequences,
      training,
      testing,
      validated$rejections,
      length(inputs$sequences),
      length(inputs$labeled) %/% 2L
  ))
  test_positions <- sum(vapply(testing,function(record) length(record$observations),integer(1)))
  report_blocks[[length(report_blocks)+1L]] <- training_report(
      models,
      bw$summary,
      vt$summary,
      selected,
      decoded,
      scores,
      test_positions
  )
  for (i in seq_along(models)) report_blocks[[length(report_blocks)+1L]] <- model_diagnostics(
      models[[i]],
      sequences,
      decoded[[i]],
      training,
      testing,
      params
  )
  reports <- list("trained_model.txt"=join_blocks(lapply(models[-1L],model_lines)),"loglik_trace.csv"=bw$trace,"viterbi_trace.csv"=vt$trace,
    "decodings.txt"=annotation$decodings,"segments.csv"=annotation$segments,"samples.txt"=samples,"evaluation.txt"=join_blocks(evaluation_blocks),"report.txt"=join_blocks(report_blocks))
  for (name in names(reports)) write_lines(name,reports[[name]])
}
main()
