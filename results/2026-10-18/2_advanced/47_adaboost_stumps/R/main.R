for (module in c("dataset","stumps","adaboost","variants","evaluation")) source(paste0(module,".R"))
minstd <- function(seed) {
  generator <- new.env(parent=emptyenv())
  generator$state <- seed
  generator
}
draw <- function(generator) {
  generator$state <- (48271*generator$state) %% 2147483647
  generator$state
}
train_variant <- function(variant,rows,params) {
  rounds <- params$ROUNDS[1L]
  switch(variant,discrete=train_discrete(rows,rounds),
    real=train_real(rows,rounds,params$BINS[1L],params$SMOOTHING[1L],params$CONVERGENCE[1L]),
    gentle=train_gentle(rows,rounds),logit=train_logit(rows,rounds,params$CLIP[1L]))
}
row_score <- function(rounds,values) ordered_sum(vapply(
    rounds,
    function(r) stump_output(r$stump,values),
    numeric(1)
))
score_rows <- function(rounds,rows) vapply(rows,function(row) row_score(rounds,row$x),numeric(1))
magnitude <- function(record) max(abs(record$stump$values))
total_magnitude <- function(rounds) ordered_sum(vapply(rounds,magnitude,numeric(1)))
count_errors <- function(rows,scores) sum(vapply(
    seq_along(rows),
    function(i) prediction(scores[i]) != rows[[i]]$label,
    logical(1)
))
add_round_scores <- function(record,rows,scores) {
  for (i in seq_along(rows)) scores[i] <- scores[i]+stump_output(record$stump,rows[[i]]$x)
  scores
}
contributions <- function(rounds,values,n) {
  result <- numeric(n)
  for (record in rounds) {
    j <- record$stump$feature
    result[j] <- result[j]+stump_output(record$stump,values)
  }
  result
}
loss <- function(rows,scores,variant) {
  result <- 0
  for (i in seq_along(rows)) {
    margin <- rows[[i]]$label*scores[i]
    result <- result+if (variant == "logit") log(1+exp(-2*margin)) else exp(-margin)
  }
  result/length(rows)
}
metrics_line <- function(kind,variant,rounds,rows,scores) {
  tp <- fp <- tn <- fn <- 0L
  for (i in seq_along(rows)) {
    p <- prediction(scores[i])
    y <- rows[[i]]$label
    tp <- tp+as.integer(p == 1L && y == 1L)
    fp <- fp+as.integer(p == 1L && y == -1L)
    tn <- tn+as.integer(p == -1L && y == -1L)
    fn <- fn+as.integer(p == -1L && y == 1L)
  }
  area <- auc(rows,scores)
  paste0(kind," ",variant," rounds ",rounds," correct ",tp+tn,"/",length(rows)," accuracy ",ratio(tp+tn,length(rows)),
    " tp ",tp," fp ",fp," tn ",tn," fn ",fn," precision ",ratio(tp,tp+fp)," recall ",ratio(tp,tp+fn),
    " f1 ",ratio(2L*tp,2L*tp+fp+fn)," auc ",ratio(area[1L],area[2L])," loss ",number(loss(
        rows,
        scores,
        variant
    )))
}
training_curve <- function(rounds,training,testing,variant) {
  train_scores <- numeric(length(training))
  test_scores <- numeric(length(testing))
  scale <- 0
  curve <- list()
  for (t in seq_along(rounds)) {
    record <- rounds[[t]]
    train_scores <- add_round_scores(record,training,train_scores)
    test_scores <- add_round_scores(record,testing,test_scores)
    scale <- scale+magnitude(record)
    margins <- vapply(seq_along(training),function(i) training[[i]]$label*train_scores[i],numeric(1))
    curve[[t]] <- list(round=t,train_errors=count_errors(training,train_scores),test_errors=count_errors(testing,test_scores),
      train_loss=loss(
          training,
          train_scores,
          variant
      ),test_loss=loss(testing,test_scores,variant),margin=min(margins)/scale)
  }
  curve
}
cross_validate <- function(rows,params) {
  space <- search_space(rows)
  maximum_rounds <- params$ROUNDS[1L]
  k <- params$FOLDS[1L]
  folds <- list()
  errors <- integer(maximum_rounds)
  assignment <- (seq_along(rows)-1L) %% k
  for (fold in seq_len(k)-1L) {
    indices <- which(assignment == fold)
    n <- length(rows)-length(indices)
    weights <- ifelse(assignment == fold,0,1/n)
    model <- train_discrete(rows,maximum_rounds,weights=weights,space=space)
    validation <- rows[indices]
    scores <- numeric(length(indices))
    fold_errors <- integer(maximum_rounds)
    for (t in seq_len(maximum_rounds)) {
      if (t <= length(model$rounds)) scores <- add_round_scores(model$rounds[[t]],validation,scores)
      fold_errors[t] <- count_errors(validation,scores)
      errors[t] <- errors[t]+fold_errors[t]
    }
    folds[[length(folds)+1L]] <- list(indices=indices,train=n,model=model,errors=fold_errors)
  }
  selected <- which.min(errors)
  scores <- numeric(length(rows))
  for (fold in folds) {
    rounds <- head(fold$model$rounds,selected)
    for (i in fold$indices) scores[i] <- row_score(rounds,rows[[i]]$x)
  }
  list(folds=folds,errors=errors,selected=selected,scores=scores)
}
magnitude_importance <- function(rounds,n,samme=FALSE) {
  scores <- numeric(n)
  counts <- integer(n)
  for (record in rounds) {
    j <- record$stump$feature
    scores[j] <- scores[j]+if (samme) record$alpha else magnitude(record)
    counts[j] <- counts[j]+1L
  }
  list(scores=scores,counts=counts,total=ordered_sum(scores),order=order(-scores,seq_len(n)))
}
importance_lines <- function(importance,features) {
  lines <- "importance"
  for (rank in seq_along(importance$order)) {
    j <- importance$order[rank]
    lines <- c(lines,paste0(rank," ",features[j]," score ",number(importance$scores[j])," share ",
      ratio(importance$scores[j],importance$total)," rounds ",importance$counts[j]))
  }
  lines
}
analyze_variants <- function(inputs,selected) {
  analysis <- list()
  for (variant in inputs$params$VARIANTS) {
    model <- train_variant(variant,inputs$train,inputs$params)
    rounds <- if (variant == "discrete") head(model$rounds,selected) else model$rounds
    analysis[[variant]] <- list(full=model,rounds=rounds,scale=total_magnitude(rounds),train=score_rows(rounds,inputs$train),
      test=score_rows(rounds,inputs$test),curve=training_curve(model$rounds,inputs$train,inputs$test,variant),
      importance=magnitude_importance(rounds,length(inputs$features)))
  }
  analysis
}
ensemble_lines <- function(inputs,analysis,cv) {
  params <- inputs$params
  lines <- character()
  for (variant in params$VARIANTS) {
    if (length(lines)) lines <- c(lines,"")
    model <- analysis[[variant]]$full
    header <- paste0("variant ",variant," rounds ",length(model$rounds)," stop ",model$stop)
    if (variant == "real") header <- paste0(header," bins ",params$BINS[1L]," smoothing ",number(params$SMOOTHING[1L]),
      " convergence ",number(params$CONVERGENCE[1L],6L))
    if (variant == "logit") header <- paste0(header," clip ",number(params$CLIP[1L]))
    lines <- c(lines,header)
    if (variant == "real") for (j in seq_along(inputs$features)) {
      lines <- c(
          lines,
          paste0(
              "cuts ",
              inputs$features[j],
              " ",
              paste(vapply(model$cuts[[j]],number,character(1)),collapse=" ")
          )
      )
    }
    for (t in seq_along(model$rounds)) {
      record <- model$rounds[[t]]
      stump <- record$stump
      line <- paste0("round ",t," feature ",inputs$features[stump$feature])
      if (variant == "real") {
        line <- paste0(line," z ",number(record$z)," bound ",number(record$bound)," values ",
          paste(vapply(stump$values,number,character(1)),collapse=" "))
      } else {
        line <- paste0(line," threshold ",number(stump$thresholds[1L]))
        if (variant == "discrete") {
          line <- paste0(line," polarity ",record$polarity," error ",number(record$error)," alpha ",number(record$alpha),
            " z ",number(record$z)," bound ",number(record$bound))
        } else {
          line <- paste0(
              line,
              " left ",
              number(stump$values[1L]),
              " right ",
              number(stump$values[2L]),
              " error ",
              number(record$error)
          )
          if (variant == "logit") line <- paste0(line," loss ",number(record$loss))
        }
      }
      lines <- c(lines,line)
      if (variant == "discrete") {
        i <- which.max(record$weights)
        ess <- 1/ordered_sum(record$weights*record$weights)
        lines <- c(
            lines,
            paste0(
                "weights ",
                t,
                " max ",
                number(record$weights[i],6L),
                " id ",
                inputs$train[[i]]$id,
                " ess ",
                number(ess)
            )
        )
      }
    }
    if (variant == "discrete") {
      t <- cv$selected
      lines <- c(
          lines,
          paste0("cv folds ",params$FOLDS[1L]," selected ",t," errors ",cv$errors[t],"/",length(inputs$train))
      )
      for (phi in seq_along(cv$folds)) {
        fold <- cv$folds[[phi]]
        validation <- length(fold$indices)
        lines <- c(lines,paste0("fold ",phi," train ",fold$train," validation ",validation," rounds ",length(fold$model$rounds),
          " stop ",fold$model$stop," selected ",fold$errors[t],"/",validation," final ",tail(
              fold$errors,
              1L
          ),"/",validation))
      }
      lines <- c(lines,paste0("cv_errors ",paste(cv$errors,collapse=" ")))
    }
  }
  lines
}
prediction_lines <- function(inputs,analysis) {
  lines <- paste0("id,variant,score,label,",paste(inputs$features,collapse=","))
  for (i in seq_along(inputs$test)) for (variant in inputs$params$VARIANTS) {
    row <- inputs$test[[i]]
    result <- analysis[[variant]]
    score <- result$test[i]
    parts <- contributions(result$rounds,row$x,length(inputs$features))
    lines <- c(lines,paste0(row$id,",",variant,",",number(score),",",prediction(score),",",
      paste(vapply(parts,number,character(1)),collapse=",")))
  }
  lines
}
roc_lines <- function(inputs,analysis) {
  lines <- "variant,threshold,tp,fp"
  labels <- vapply(inputs$test,function(row) row$label,integer(1))
  for (variant in inputs$params$VARIANTS) {
    scores <- analysis[[variant]]$test
    for (threshold in sort(unique(scores),decreasing=TRUE)) {
      tp <- sum(scores >= threshold & labels == 1L)
      fp <- sum(scores >= threshold & labels == -1L)
      lines <- c(lines,paste(variant,number(threshold),tp,fp,sep=","))
    }
  }
  lines
}
permutation_importance <- function(rounds,rows,n,repeats,generator) {
  base <- length(rows)-count_errors(rows,score_rows(rounds,rows))
  results <- list()
  for (j in seq_len(n)) {
    counts <- integer(repeats)
    for (r in seq_len(repeats)) {
      permutation <- seq_along(rows)
      for (i in seq.int(length(rows),2L)) {
        other <- draw(generator) %% i+1L
        temporary <- permutation[i]
        permutation[i] <- permutation[other]
        permutation[other] <- temporary
      }
      correct <- 0L
      for (i in seq_along(rows)) {
        values <- rows[[i]]$x
        values[j] <- rows[[permutation[i]]]$x[j]
        correct <- correct+as.integer(prediction(row_score(rounds,values)) == rows[[i]]$label)
      }
      counts[r] <- correct
    }
    results[[j]] <- list(feature=j,drop=sum(base-counts),low=min(counts),high=max(counts))
  }
  ranks <- order(-vapply(results,function(r) r$drop,numeric(1)),seq_len(n))
  list(base=base,results=results[ranks])
}
margin_lines <- function(inputs,analysis) {
  lines <- character()
  repeats <- inputs$params$PERMUTATION[1L]
  generator <- minstd(inputs$params$PERMUTATION[2L])
  n <- length(inputs$train)
  m <- length(inputs$test)
  for (variant in inputs$params$VARIANTS) {
    if (length(lines)) lines <- c(lines,"")
    r <- analysis[[variant]]
    train_margins <- vapply(seq_len(n),function(i) inputs$train[[i]]$label*r$train[i]/r$scale,numeric(1))
    test_margins <- vapply(seq_len(m),function(i) inputs$test[[i]]$label*r$test[i]/r$scale,numeric(1))
    lines <- c(lines,paste0("variant ",variant," rounds ",length(r$rounds)," scale ",number(r$scale)),
      paste0("train min ",number(min(train_margins))," mean ",number(ordered_sum(train_margins)/n)))
    for (theta in inputs$params$MARGINS) {
      total <- count_at_most(train_margins,theta)
      lines <- c(lines,paste0("train le ",number(theta)," ",total,"/",n," ",ratio(total,n)))
    }
    histogram <- integer(20L)
    for (margin in train_margins) {
      bin <- min(19L,floor((margin+1)*10))+1L
      histogram[bin] <- histogram[bin]+1L
    }
    lines <- c(lines,paste0("histogram ",paste(histogram,collapse=" ")))
    hardest <- head(order(train_margins,seq_len(n)),5L)
    for (i in hardest) lines <- c(
        lines,
        paste0(
            "hardest ",
            inputs$train[[i]]$id,
            " label ",
            inputs$train[[i]]$label,
            " margin ",
            number(train_margins[i])
        )
    )
    lines <- c(
        lines,
        paste0("test min ",number(min(test_margins))," mean ",number(ordered_sum(test_margins)/m))
    )
    for (theta in inputs$params$MARGINS) {
      total <- count_at_most(test_margins,theta)
      lines <- c(lines,paste0("test le ",number(theta)," ",total,"/",m," ",ratio(total,m)))
    }
    for (theta in inputs$params$MARGINS) {
      confident <- which(abs(test_margins) > theta)
      correct <- sum(vapply(confident,function(i) prediction(r$test[i]) == inputs$test[[i]]$label,logical(1)))
      lines <- c(lines,paste0("test confident ",number(theta)," ",length(confident),"/",m," correct ",correct,"/",
        length(confident)," ",ratio(correct,length(confident))))
    }
    lines <- c(lines,importance_lines(r$importance,inputs$features))
    permutation <- permutation_importance(r$rounds,inputs$test,length(inputs$features),repeats,generator)
    lines <- c(lines,paste0("permutation repeats ",repeats," base ",permutation$base,"/",m))
    for (rank in seq_along(permutation$results)) {
      result <- permutation$results[[rank]]
      lines <- c(lines,paste0(rank," ",inputs$features[result$feature]," drop ",ratio(result$drop,repeats*m),
        " min ",result$low,"/",m," max ",result$high,"/",m))
    }
  }
  lines
}
shape_lines <- function(inputs,analysis) {
  lines <- character()
  for (variant in inputs$params$VARIANTS) {
    if (length(lines)) lines <- c(lines,"")
    rounds <- analysis[[variant]]$rounds
    lines <- c(lines,paste0("variant ",variant," rounds ",length(rounds)))
    for (j in seq_along(inputs$features)) {
      collected <- Filter(function(record) record$stump$feature == j,rounds)
      cuts <- sort(unique(unlist(lapply(collected,function(record) record$stump$thresholds),use.names=FALSE)))
      values <- ordered_sum(vapply(collected,function(record) record$stump$values[1L],numeric(1)))
      for (cut in cuts) values <- c(values,ordered_sum(vapply(collected,function(record)
        record$stump$values[sum(record$stump$thresholds <= cut)+1L],numeric(1))))
      lines <- c(lines,paste0("feature ",inputs$features[j]," rounds ",length(collected)," cuts ",length(cuts),
        " range ",number(max(values)-min(values))))
      for (i in seq_along(values)) {
        lower <- if (i == 1L) "-inf" else number(cuts[i-1L])
        upper <- if (i > length(cuts)) "inf" else number(cuts[i])
        lines <- c(lines,paste0("interval ",lower," ",upper," value ",number(values[i])))
      }
    }
  }
  lines
}
calibration_lines <- function(variant,rows,scores) {
  counts <- positive <- integer(5L)
  totals <- numeric(5L)
  brier <- 0
  for (i in seq_along(rows)) {
    p <- 1/(1+exp(-2*scores[i]))
    target <- as.integer(rows[[i]]$label == 1L)
    brier <- brier+(p-target)*(p-target)
    j <- min(4L,floor(p*5))+1L
    counts[j] <- counts[j]+1L
    totals[j] <- totals[j]+p
    positive[j] <- positive[j]+target
  }
  lines <- paste0("calibration ",variant," brier ",number(brier/length(rows)))
  ranges <- c("0.0-0.2","0.2-0.4","0.4-0.6","0.6-0.8","0.8-1.0")
  for (i in seq_len(5L)) lines <- c(
      lines,
      paste0(
          "bin ",
          ranges[i],
          " count ",
          counts[i],
          " mean ",
          ratio(totals[i],counts[i]),
          " positives ",
          positive[i]
      )
  )
  lines
}
bootstrap_lines <- function(inputs,analysis) {
  samples <- inputs$params$BOOTSTRAP[1L]
  seed <- inputs$params$BOOTSTRAP[2L]
  generator <- minstd(seed)
  variants <- inputs$params$VARIANTS
  m <- length(inputs$test)
  counts <- correct <- list()
  for (variant in variants) {
    counts[[variant]] <- integer(samples)
    correct[[variant]] <- vapply(
        seq_len(m),
        function(i) prediction(analysis[[variant]]$test[i]) == inputs$test[[i]]$label,
        logical(1)
    )
  }
  for (r in seq_len(samples)) {
    selected <- vapply(seq_len(m),function(i) draw(generator) %% m+1L,numeric(1))
    for (variant in variants) counts[[variant]][r] <- sum(correct[[variant]][selected])
  }
  lines <- paste0("bootstrap samples ",samples," seed ",seed)
  trim <- samples %/% 40L
  for (variant in variants) {
    ordered <- sort(counts[[variant]])
    lines <- c(lines,paste0(variant," mean ",ratio(sum(counts[[variant]]),samples*m)," low ",ratio(ordered[trim+1L],m),
      " high ",ratio(ordered[samples-trim],m)))
  }
  if (length(variants) > 1L) for (a in seq_len(length(variants)-1L)) for (b in seq.int(
      a+1L,
      length(variants)
  )) {
    first <- variants[a]
    second <- variants[b]
    wins <- sum(counts[[first]] > counts[[second]])
    ties <- sum(counts[[first]] == counts[[second]])
    lines <- c(lines,paste0(first," ",second," first ",wins," tie ",ties," second ",samples-wins-ties))
  }
  lines
}
feature_summary <- function(rows,j) {
  values <- vapply(rows,function(row) row$x[j],numeric(1))
  paste(
      number(min(values)),
      number(max(values)),
      number(ordered_sum(values)/length(values)),
      length(unique(values))
  )
}
summary_lines <- function(inputs,analysis,cv) {
  training <- inputs$train
  testing <- inputs$test
  params <- inputs$params
  variants <- params$VARIANTS
  n <- length(training)
  m <- length(testing)
  lines <- paste0("data train ",n," test ",m," features ",length(inputs$features)," positives ",
    sum(vapply(
        training,
        function(row) row$label == 1L,
        logical(1)
    ))," ",sum(vapply(testing,function(row) row$label == 1L,logical(1))))
  for (j in seq_along(inputs$features)) lines <- c(
      lines,
      paste0(
          "feature ",
          inputs$features[j],
          " train ",
          feature_summary(training,j),
          " test ",
          feature_summary(testing,j)
      )
  )
  t <- cv$selected
  lines <- c(
      lines,
      paste0("cv selected ",t," errors ",cv$errors[t],"/",n," rate ",ratio(cv$errors[t],n)),
      metrics_line("oof","discrete",t,training,cv$scores)
  )
  committee_train <- numeric(n)
  committee_test <- numeric(m)
  committee_rounds <- 0L
  for (variant in variants) {
    r <- analysis[[variant]]
    rounds <- length(r$rounds)
    lines <- c(
        lines,
        metrics_line("train",variant,rounds,training,r$train),
        metrics_line("test",variant,rounds,testing,r$test)
    )
    committee_rounds <- committee_rounds+rounds
    committee_train <- committee_train+r$train/r$scale
    committee_test <- committee_test+r$test/r$scale
  }
  lines <- c(lines,metrics_line("train","committee",committee_rounds,training,committee_train),
    metrics_line("test","committee",committee_rounds,testing,committee_test))
  for (variant in variants) {
    curve <- analysis[[variant]]$curve
    a <- curve[[which.min(vapply(curve,function(point) point$train_errors,numeric(1)))]]
    b <- curve[[which.min(vapply(curve,function(point) point$test_errors,numeric(1)))]]
    lines <- c(lines,paste0("curve ",variant," rounds ",length(curve)," train_min ",a$train_errors,"/",n," at ",a$round,
      " test_min ",b$test_errors,"/",m," at ",b$round))
  }
  predictions <- lapply(analysis,function(r) vapply(r$test,prediction,integer(1)))
  wrong <- vapply(Filter(function(i) all(vapply(variants,function(v) predictions[[v]][i] != testing[[i]]$label,logical(1))),seq_len(m)),
    function(i) testing[[i]]$id,character(1))
  lines <- c(
      lines,
      paste0("all_wrong ",length(wrong),if (length(wrong)) paste0(" ",paste(wrong,collapse=" ")) else ""),
      "agreement"
  )
  if (length(variants) > 1L) for (a in seq_len(length(variants)-1L)) for (b in seq.int(
      a+1L,
      length(variants)
  )) {
    first <- variants[a]
    second <- variants[b]
    agree <- sum(predictions[[first]] == predictions[[second]])
    only_first <- sum(vapply(
        seq_len(m),
        function(i) predictions[[first]][i] == testing[[i]]$label && predictions[[second]][i] != testing[[i]]$label,
        logical(1)
    ))
    only_second <- sum(vapply(
        seq_len(m),
        function(i) predictions[[second]][i] == testing[[i]]$label && predictions[[first]][i] != testing[[i]]$label,
        logical(1)
    ))
    difference <- abs(only_first-only_second)-1L
    lines <- c(lines,paste0(first," ",second," agree ",agree,"/",m," only_first ",only_first," only_second ",only_second,
      " chi2 ",ratio(difference*difference,only_first+only_second)))
  }
  lines <- c(lines,bootstrap_lines(inputs,analysis))
  for (variant in variants) lines <- c(lines,calibration_lines(variant,testing,analysis[[variant]]$test))
  lines
}
class_errors <- function(rows,predictions) sum(vapply(
    seq_along(rows),
    function(i) rows[[i]]$label != predictions[i],
    logical(1)
))
confusion_lines <- function(rows,predictions,classes) {
  matrix <- confusion(rows,predictions,classes)
  lines <- "confusion"
  for (i in seq_len(classes)) lines <- c(lines,paste(matrix[i,],collapse=" "))
  for (i in seq_len(classes)) lines <- c(
      lines,
      paste0(
          "class ",
          i,
          " precision ",
          ratio(matrix[i,i],sum(matrix[,i])),
          " recall ",
          ratio(matrix[i,i],sum(matrix[i,]))
      )
  )
  lines
}
multiclass_report <- function(inputs) {
  training <- inputs$multi_train
  testing <- inputs$multi_test
  params <- inputs$params
  classes <- params$CLASSES[1L]
  maximum_rounds <- params$SAMME_ROUNDS[1L]
  model <- train_samme(training,maximum_rounds,classes)
  train_scores <- matrix(0,length(training),classes)
  test_scores <- matrix(0,length(testing),classes)
  curve <- list()
  for (t in seq_along(model$rounds)) {
    record <- model$rounds[[t]]
    for (i in seq_along(training)) {
      j <- stump_output(record$stump,training[[i]]$x)
      train_scores[i,j] <- train_scores[i,j]+record$alpha
    }
    for (i in seq_along(testing)) {
      j <- stump_output(record$stump,testing[[i]]$x)
      test_scores[i,j] <- test_scores[i,j]+record$alpha
    }
    curve[[t]] <- c(
        t,
        class_errors(training,apply(train_scores,1L,which.max)),
        class_errors(testing,apply(test_scores,1L,which.max))
    )
  }
  train_predictions <- apply(train_scores,1L,which.max)
  test_predictions <- apply(test_scores,1L,which.max)
  lines <- paste0(
      "samme classes ",
      classes,
      " train ",
      length(training),
      " test ",
      length(testing),
      " rounds ",
      length(model$rounds),
      " stop ",
      model$stop
  )
  for (t in seq_along(model$rounds)) {
    record <- model$rounds[[t]]
    stump <- record$stump
    lines <- c(lines,paste0("round ",t," feature ",inputs$multi_features[stump$feature]," threshold ",number(stump$thresholds[1L]),
      " left ",stump$values[1L]," right ",stump$values[2L]," error ",number(record$error)," alpha ",number(record$alpha)))
  }
  for (kind in c("train","test")) {
    rows <- if (kind == "train") training else testing
    predictions <- if (kind == "train") train_predictions else test_predictions
    errors <- class_errors(rows,predictions)
    lines <- c(lines,paste0(kind," errors ",errors,"/",length(rows)," rate ",ratio(errors,length(rows))))
  }
  lines <- c(lines,confusion_lines(testing,test_predictions,classes),
    importance_lines(
        magnitude_importance(model$rounds,length(inputs$multi_features),samme=TRUE),
        inputs$multi_features
    ),
    "",paste0("ovr classes ",classes," rounds ",maximum_rounds))
  ovr_train <- matrix(0,length(training),classes)
  ovr_test <- matrix(0,length(testing),classes)
  for (class in seq_len(classes)) {
    binary_train <- lapply(training,function(row) { row$label <- if (row$label == class) 1L else -1L; row })
    binary_test <- lapply(testing,function(row) { row$label <- if (row$label == class) 1L else -1L; row })
    binary <- train_discrete(binary_train,maximum_rounds)
    a <- score_rows(binary$rounds,binary_train)
    b <- score_rows(binary$rounds,binary_test)
    ovr_train[,class] <- a
    ovr_test[,class] <- b
    positives <- sum(vapply(training,function(row) row$label == class,logical(1)))
    lines <- c(lines,paste0("class ",class," rounds ",length(binary$rounds)," stop ",binary$stop," positives ",positives,
      " train_errors ",count_errors(
          binary_train,
          a
      ),"/",length(training)," test_errors ",count_errors(binary_test,b),"/",length(testing)))
  }
  ovr_train_predictions <- apply(ovr_train,1L,which.max)
  ovr_test_predictions <- apply(ovr_test,1L,which.max)
  for (kind in c("train","test")) {
    rows <- if (kind == "train") training else testing
    predictions <- if (kind == "train") ovr_train_predictions else ovr_test_predictions
    errors <- class_errors(rows,predictions)
    lines <- c(lines,paste0(kind," errors ",errors,"/",length(rows)," rate ",ratio(errors,length(rows))))
  }
  lines <- c(lines,confusion_lines(testing,ovr_test_predictions,classes),
    paste0("agreement ",sum(test_predictions == ovr_test_predictions),"/",length(testing)),"","predictions")
  for (i in seq_along(testing)) lines <- c(lines,paste0(testing[[i]]$id," class ",testing[[i]]$label," samme ",test_predictions[i],
    " ovr ",ovr_test_predictions[i]," scores ",paste(
        vapply(test_scores[i,],number,character(1)),
        collapse=" "
    )))
  list(lines=lines,curve=curve)
}
test_minimum <- function(rounds,testing) {
  scores <- numeric(length(testing))
  counts <- integer(length(rounds))
  for (t in seq_along(rounds)) {
    scores <- add_round_scores(rounds[[t]],testing,scores)
    counts[t] <- count_errors(testing,scores)
  }
  index <- which.min(counts)
  c(counts[index],index)
}
experiment_lines <- function(inputs,analysis,selected) {
  training <- inputs$train
  testing <- inputs$test
  params <- inputs$params
  n <- length(training)
  m <- length(testing)
  lines <- character()
  for (q in params$SIZES) {
    size <- (n*q) %/% 100L
    subset <- head(training,size)
    lines <- c(lines,paste0("size ",q," rows ",size))
    for (variant in params$VARIANTS) {
      model <- train_variant(variant,subset,params)
      a <- count_errors(subset,score_rows(model$rounds,subset))
      b <- count_errors(testing,score_rows(model$rounds,testing))
      lines <- c(
          lines,
          paste0(
              variant,
              " rounds ",
              length(model$rounds),
              " stop ",
              model$stop,
              " train_errors ",
              a,
              "/",
              size,
              " test_errors ",
              b,
              "/",
              m
          )
      )
    }
  }
  for (nu in params$SHRINKAGE) {
    model <- train_discrete(training,params$ROUNDS[1L],shrinkage=nu)
    a <- count_errors(training,score_rows(model$rounds,training))
    b <- count_errors(testing,score_rows(model$rounds,testing))
    minimum <- test_minimum(model$rounds,testing)
    lines <- c(lines,paste0("shrinkage ",number(nu)," rounds ",length(model$rounds)," stop ",model$stop," train_errors ",a,"/",n,
      " test_errors ",b,"/",m," test_min ",minimum[1L],"/",m," at ",minimum[2L]))
  }
  ranked <- analysis$discrete$importance$order
  for (k in seq_along(inputs$features)) {
    features <- sort(head(ranked,k))
    a <- lapply(training,function(row) { row$x <- row$x[features]; row })
    b <- lapply(testing,function(row) { row$x <- row$x[features]; row })
    model <- train_discrete(a,selected)
    train_errors <- count_errors(a,score_rows(model$rounds,a))
    test_errors <- count_errors(b,score_rows(model$rounds,b))
    lines <- c(lines,paste0("top ",k," features ",paste(inputs$features[features],collapse=" ")," rounds ",length(model$rounds),
      " train_errors ",train_errors,"/",n," test_errors ",test_errors,"/",m))
  }
  for (q in params$NOISE[-1L]) {
    f <- (n*q) %/% 100L
    generator <- minstd(params$NOISE[1L])
    permutation <- seq_len(n)
    for (i in seq_len(f)) {
      other <- draw(generator) %% (n-i+1L)+i
      temporary <- permutation[i]
      permutation[i] <- permutation[other]
      permutation[other] <- temporary
    }
    flipped <- head(permutation,f)
    noisy <- lapply(seq_len(n),function(i) {
      row <- training[[i]]
      if (i %in% flipped) row$label <- -row$label
      row
    })
    lines <- c(lines,paste0("noise ",q," flipped ",f))
    for (variant in params$VARIANTS) {
      model <- train_variant(variant,noisy,params)
      a <- count_errors(noisy,score_rows(model$rounds,noisy))
      b <- count_errors(testing,score_rows(model$rounds,testing))
      minimum <- test_minimum(model$rounds,testing)
      weights <- tail(model$rounds,1L)[[1L]]$weights
      flipped_weight <- ordered_sum(weights[sort(flipped)])
      lines <- c(lines,paste0(variant," rounds ",length(model$rounds)," stop ",model$stop," train_errors ",a,"/",n," test_errors ",b,"/",m,
        " test_min ",minimum[1L],"/",m," at ",minimum[2L]," flipped_weight ",number(flipped_weight)))
    }
  }
  lines
}
error_curve_lines <- function(inputs,analysis,samme_curve) {
  lines <- "variant,round,train_error,test_error,train_loss,test_loss,min_margin"
  for (variant in inputs$params$VARIANTS) for (point in analysis[[variant]]$curve) {
    lines <- c(lines,paste(variant,point$round,ratio(point$train_errors,length(inputs$train)),ratio(point$test_errors,length(inputs$test)),
      number(point$train_loss),number(point$test_loss),number(point$margin),sep=","))
  }
  for (point in samme_curve) lines <- c(lines,paste0("samme,",point[1L],",",ratio(point[2L],length(inputs$multi_train)),",",
    ratio(point[3L],length(inputs$multi_test)),",-,-,-"))
  lines
}
main <- function() {
  inputs <- read_inputs()
  cv <- cross_validate(inputs$train,inputs$params)
  analysis <- analyze_variants(inputs,cv$selected)
  samme <- multiclass_report(inputs)
  reports <- list("ensemble.txt"=ensemble_lines(inputs,analysis,cv),"error_curve.csv"=error_curve_lines(inputs,analysis,samme$curve),
    "predictions.csv"=prediction_lines(inputs,analysis),"roc.csv"=roc_lines(inputs,analysis),"margins.txt"=margin_lines(
        inputs,
        analysis
    ),
    "shapes.txt"=shape_lines(inputs,analysis),"samme.txt"=samme$lines,"summary.txt"=summary_lines(
        inputs,
        analysis,
        cv
    ),
    "experiments.txt"=experiment_lines(inputs,analysis,cv$selected))
  for (name in names(reports)) write_lines(name,reports[[name]])
}
main()
