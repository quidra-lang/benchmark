for (module in c("dataset","layers","network","optimizers","evaluation")) source(paste0(module,".R"))
mean_value <- function(values) ordered_sum(values)/length(values)
weighted_l2 <- function(values) sqrt(ordered_sum(values*values))
network_catalog <- function(data) setNames(
    lapply(
        data$networks,
        function(architecture) list(
            architecture=architecture,
            layout=layout_for(architecture),
            initial=data$weights[[architecture$name]]
        )
    ),
    vapply(data$networks,function(architecture) architecture$name,character(1))
)
check_network <- function(name,network,training,settings) {
  generator <- minstd(settings$seed)
  order <- shuffle_order(generator,seq_along(training))
  batch <- training[head(order,min(settings$batch_size,length(order)))]
  layout <- network$layout
  theta <- network$initial
  analytic <- average_gradient(layout,theta,batch)$gradient
  checked <- seq.int(1L,layout$parameters,by=settings$gradient_stride)
  h <- 0.00001
  passed <- TRUE
  for (p in checked) {
    original <- theta[p]
    theta[p] <- original+h
    higher <- evaluate_network(layout,theta,batch)$loss
    theta[p] <- original-h
    lower <- evaluate_network(layout,theta,batch)$loss
    theta[p] <- original
    derivative <- (higher-lower)/(2*h)
    error <- abs(analytic[p]-derivative)/max(1,abs(analytic[p])+abs(derivative))
    if (error >= 0.000001) passed <- FALSE
  }
  lines <- c(
      paste("network",name),
      paste("parameters",layout$parameters),
      paste("batch",paste(vapply(batch,function(image) image$id,character(1)),collapse=" "))
  )
  for (l in seq_along(layout$layers)) {
    layer <- layout$layers[[l]]
    weights <- sum(seq.int(layer$weight_start,layer$weight_end) %in% checked)
    biases <- sum(seq.int(layer$bias_start,layer$bias_end) %in% checked)
    lines <- c(lines,paste("layer",l,"weights",weights,"biases",biases))
  }
  c(lines,paste("checked",length(checked)),paste("result",if (passed) "PASS" else "FAIL"))
}
gradient_check_lines <- function(catalog,architectures,training,settings) {
  lines <- character()
  for (architecture in architectures) {
    if (length(lines)) lines <- c(lines,"")
    lines <- c(lines,check_network(architecture$name,catalog[[architecture$name]],training,settings))
  }
  lines
}
train_run <- function(definition,network,training,validation,settings) {
  layout <- network$layout
  theta <- network$initial
  state <- initialize_optimizer(length(theta))
  generator <- minstd(settings$seed)
  order <- seq_along(training)
  epochs <- correctness <- list()
  best_epoch <- saved_correct <- wait <- updates <- 0L
  best_loss <- 0
  best_theta <- numeric()
  stop <- "max_epochs"
  for (epoch in seq_len(settings$max_epochs)) {
    rate <- epoch_rate(definition,epoch,settings$lr_step,settings$lr_gamma)
    order <- shuffle_order(generator,order)
    norms <- numeric()
    for (start in seq.int(1L,length(order),by=settings$batch_size)) {
      batch <- training[order[seq.int(start,min(length(order),start+settings$batch_size-1L))]]
      grad <- average_gradient(layout,theta,batch)$gradient
      for (p in seq_along(layout$is_weight)) if (layout$is_weight[p]) grad[p] <- grad[p]+definition$decay*theta[p]
      norms <- c(norms,weighted_l2(grad))
      theta <- update_parameters(theta,grad,state,definition,rate)
      updates <- updates+1L
    }
    train_eval <- evaluate_network(layout,theta,training)
    val_eval <- evaluate_network(layout,theta,validation)
    correctness[[length(correctness)+1L]] <- vapply(
        train_eval$outcomes,
        function(item) item$predicted == item$label,
        logical(1)
    )
    improved <- best_epoch == 0L || val_eval$loss < best_loss
    if (improved) {
      best_epoch <- epoch
      best_loss <- val_eval$loss
      saved_correct <- val_eval$correct
      best_theta <- theta
      wait <- 0L
    } else wait <- wait+1L
    epochs[[length(epochs)+1L]] <- list(
        epoch=epoch,
        lr=rate,
        grad_norm=mean_value(norms),
        train_loss=train_eval$loss,
        train_correct=train_eval$correct,
        val_loss=val_eval$loss,
        val_correct=val_eval$correct,
        improved=improved
    )
    if (wait >= settings$patience) {
      stop <- "early"
      break
    }
  }
  c(
      definition,
      list(
          network_data=network,
          best_theta=best_theta,
          best_epoch=best_epoch,
          best_val_loss=best_loss,
          best_val_correct=saved_correct,
          epochs=epochs,
          updates=updates,
          stop=stop,
          correctness=correctness
      )
  )
}
noisy_data <- function(test,settings) lapply(settings$noise,function(percent) {
  generator <- minstd(settings$seed)
  altered <- list()
  flipped <- 0L
  for (image in test) {
    vector <- image$vector
    for (p in seq_along(vector)) if (draw(generator) %% 100 < percent) {
      vector[p] <- 1-vector[p]
      flipped <- flipped+1L
    }
    image$vector <- vector
    altered[[length(altered)+1L]] <- image
  }
  list(percent=percent,images=altered,flipped=flipped)
})
prepare_run_evaluation <- function(run,training,test,settings,noise) {
  network <- run$network_data
  architecture <- network$architecture
  layout <- network$layout
  theta <- run$best_theta
  evaluated <- evaluate_network(layout,theta,test)
  outcomes <- evaluated$outcomes
  run$test <- evaluated
  run$confusion <- confusion(outcomes,architecture$classes)
  run$top2 <- sum(vapply(outcomes,function(item) item$label %in% best_two(item$scores),logical(1)))
  correct_confidence <- vapply(
      Filter(function(item) item$predicted == item$label,outcomes),
      function(item) item$confidence,
      numeric(1)
  )
  wrong_confidence <- vapply(
      Filter(function(item) item$predicted != item$label,outcomes),
      function(item) item$confidence,
      numeric(1)
  )
  run$confidence_correct <- if (length(correct_confidence)) mean_value(correct_confidence) else NULL
  run$confidence_wrong <- if (length(wrong_confidence)) mean_value(wrong_confidence) else NULL
  statuses <- run$correctness
  events <- vapply(seq_along(training),function(i) {
    if (length(statuses) < 2L) return(0L)
    sum(vapply(seq.int(2L,length(statuses)),function(e) statuses[[e-1L]][i] && !statuses[[e]][i],logical(1)))
  },integer(1))
  run$forgetting <- list(
      events=sum(events),
      rows=sum(events > 0L),
      never=sum(vapply(
          seq_along(training),
          function(i) !any(vapply(statuses,function(status) status[i],logical(1))),
          logical(1)
      ))
  )
  run$weight_norms <- run$weight_changes <- numeric()
  for (layer in layout$layers) {
    indices <- seq.int(layer$weight_start,layer$weight_end)
    run$weight_norms <- c(run$weight_norms,weighted_l2(theta[indices]))
    run$weight_changes <- c(run$weight_changes,weighted_l2(theta[indices]-network$initial[indices]))
  }
  bins <- replicate(settings$calibration_bins,list(),simplify=FALSE)
  for (item in outcomes) {
    bin <- min(length(bins)-1L,floor(item$confidence*length(bins)))+1L
    bins[[bin]][[length(bins[[bin]])+1L]] <- item
  }
  ece <- 0
  for (bucket in bins) if (length(bucket)) {
    accurate <- sum(vapply(bucket,function(item) item$predicted == item$label,logical(1)))
    confidence <- mean_value(vapply(bucket,function(item) item$confidence,numeric(1)))
    ece <- ece+length(bucket)/length(test)*abs(accurate/length(bucket)-confidence)
  }
  run$calibration <- bins
  run$ece <- ece
  run$hidden_summary <- lapply(seq_len(length(layout$layers)-1L),function(l) {
    layer <- layout$layers[[l]]
    means <- lapply(seq_len(architecture$classes)-1L,function(klass) {
      subset <- lapply(Filter(function(item) item$label == klass,outcomes),function(item) item$hidden[[l]])
      if (!length(subset)) return(NULL)
      vapply(seq_len(layer$outputs),function(j) mean_value(vapply(subset,`[`,numeric(1),j)),numeric(1))
    })
    available <- which(!vapply(means,is.null,logical(1)))
    preferred <- vapply(seq_len(layer$outputs),function(j) available[which.max(vapply(means[available],`[`,numeric(1),j))]-1L,integer(1))
    zero_counts <- vapply(
        seq_len(layer$outputs),
        function(j) sum(vapply(outcomes,function(item) item$hidden[[l]][j] == 0,logical(1))),
        integer(1)
    )
    list(means=means,preferred=preferred,zero_counts=zero_counts)
  })
  ordered_weights <- which(layout$is_weight)
  ordered_weights <- ordered_weights[order(abs(theta[ordered_weights]),ordered_weights)]
  run$pruning <- lapply(settings$prune,function(percent) {
    removed <- (percent*length(ordered_weights)) %/% 100L
    pruned <- theta
    pruned[head(ordered_weights,removed)] <- 0
    result <- evaluate_network(layout,pruned,test)
    list(percent=percent,removed=removed,correct=result$correct,loss=result$loss)
  })
  run$noise_results <- lapply(
      noise,
      function(item) list(
          percent=item$percent,
          flipped=item$flipped,
          correct=evaluate_network(layout,theta,item$images)$correct
      )
  )
  run$misclassified <- Filter(function(item) item$predicted != item$label,outcomes)
  run
}
training_log_lines <- function(runs,m,nv) {
  lines <- "run,epoch,lr,grad_norm,train_loss,train_acc,val_loss,val_acc,improved"
  for (run in runs) for (record in run$epochs) lines <- c(lines,paste(run$name,record$epoch,real_text(record$lr,6L),real_text(record$grad_norm,4L),real_text(record$train_loss,6L),
    ratio(
        record$train_correct,
        m
    ),real_text(record$val_loss,6L),ratio(record$val_correct,nv),if (record$improved) "1" else "0",sep=","))
  lines
}
final_weight_lines <- function(runs) {
  lines <- character()
  for (run in runs) {
    if (length(lines)) lines <- c(lines,"")
    lines <- c(lines,paste("RUN",run$name,"NETWORK",run$network,"EPOCH",run$best_epoch))
    for (l in seq_along(run$network_data$layout$layers)) {
      layer <- run$network_data$layout$layers[[l]]
      lines <- c(lines,paste("LAYER",l,layer$outputs,layer$inputs))
      cursor <- layer$weight_start
      for (unused in seq_len(layer$outputs)) {
        values <- run$best_theta[seq.int(cursor,cursor+layer$inputs-1L)]
        lines <- c(lines,paste("W",paste(vapply(values,real_text,character(1),4L),collapse=" ")))
        cursor <- cursor+layer$inputs
      }
      values <- run$best_theta[seq.int(layer$bias_start,layer$bias_end)]
      lines <- c(lines,paste("B",paste(vapply(values,real_text,character(1),4L),collapse=" ")))
    }
  }
  lines
}
prediction_lines <- function(runs) {
  lines <- "run,id,label,predicted,confidence"
  for (run in runs) for (item in run$test$outcomes) lines <- c(
      lines,
      paste(run$name,item$id,item$label,item$predicted,real_text(item$confidence,4L),sep=",")
  )
  lines
}
data_summary_lines <- function(training,validation,test,architecture) {
  width <- architecture$width
  height <- architecture$height
  classes <- architecture$classes
  pixels <- width*height
  lines <- c(
      "data",
      paste("train",length(training),"validation",length(validation),"test",length(test),"pixels",pixels)
  )
  for (klass in seq_len(classes)-1L) {
    group <- Filter(function(image) image$label == klass,training)
    val_count <- sum(vapply(validation,function(image) image$label == klass,logical(1)))
    test_count <- sum(vapply(test,function(image) image$label == klass,logical(1)))
    ink <- sum(vapply(group,function(image) sum(image$vector == 1),integer(1)))
    lines <- c(
        lines,
        paste(
            "class",
            klass,
            "train",
            length(group),
            "validation",
            val_count,
            "test",
            test_count,
            "ink",
            ratio(ink,length(group))
        )
    )
  }
  c(
      lines,
      paste("mean_images",paste(seq_len(classes)-1L,collapse=" ")),
      level_maps(lapply(seq_len(classes)-1L,function(k) binary_frequency(training,k,pixels)),width,height)
  )
}
run_evaluation_lines <- function(run,validation,test,settings) {
  n <- length(test)
  nv <- length(validation)
  forgetting <- run$forgetting
  lines <- c(paste("run",run$name,"network",run$network,"optimizer",run$optimizer),paste("epochs",length(run$epochs),"best_epoch",run$best_epoch,"stop",run$stop,"updates",run$updates),
    paste(
        "best_val_loss",
        real_text(run$best_val_loss,6L),
        "best_val_acc",
        ratio(run$best_val_correct,nv),
        "correct",
        paste0(run$best_val_correct,"/",nv)
    ),
    paste(
        "test_loss",
        real_text(run$test$loss,6L),
        "test_acc",
        ratio(run$test$correct,n),
        "correct",
        paste0(run$test$correct,"/",n)
    ),
    paste("top2_acc",ratio(run$top2,n),"correct",paste0(run$top2,"/",n)),paste(
        "confidence correct",
        real_text(run$confidence_correct,4L),
        "wrong",
        real_text(run$confidence_wrong,4L)
    ),
    paste("forgetting events",forgetting$events,"rows",forgetting$rows,"never_learned",forgetting$never),
    paste("weight_norms",paste(vapply(run$weight_norms,real_text,character(1),4L),collapse=" ")),paste(
        "weight_changes",
        paste(vapply(run$weight_changes,real_text,character(1),4L),collapse=" ")
    ),"curve")
  largest <- max(vapply(run$epochs,function(item) max(item$train_loss,item$val_loss),numeric(1)))
  for (item in run$epochs) {
    canvas <- rep(" ",40L)
    ct <- floor(39*item$train_loss/largest+0.5)
    cv <- floor(39*item$val_loss/largest+0.5)
    canvas[ct+1L] <- "t"
    canvas[cv+1L] <- if (ct == cv) "*" else "v"
    lines <- c(
        lines,
        paste0(
            sprintf("%2d",item$epoch),
            " |",
            paste(canvas,collapse=""),
            "|",
            if (item$epoch == run$best_epoch) " best" else ""
        )
    )
  }
  lines <- c(lines,"confusion")
  classes <- run$network_data$architecture$classes
  for (klass in seq_len(classes)-1L) lines <- c(
      lines,
      paste0(klass,": ",paste(run$confusion[klass+1L,],collapse=" "))
  )
  for (klass in seq_len(classes)-1L) {
    measures <- class_measures(run$confusion,klass)
    lines <- c(
        lines,
        paste(
            "class",
            klass,
            "support",
            measures$support,
            "predicted",
            measures$predicted,
            "precision",
            measures$precision,
            "recall",
            measures$recall,
            "f1",
            measures$f1
        )
    )
  }
  lines <- c(lines,"calibration")
  for (bin in seq_along(run$calibration)) {
    bucket <- run$calibration[[bin]]
    accurate <- sum(vapply(bucket,function(item) item$predicted == item$label,logical(1)))
    confidence <- if (length(bucket)) mean_value(vapply(
        bucket,
        function(item) item$confidence,
        numeric(1)
    )) else NULL
    lines <- c(
        lines,
        paste(
            "bin",
            bin,
            real_text((bin-1L)/length(run$calibration),2L),
            real_text(bin/length(run$calibration),2L),
            "count",
            length(bucket),
            "accuracy",
            ratio(accurate,length(bucket)),
            "confidence",
            real_text(confidence,4L)
        )
    )
  }
  lines <- c(lines,paste("ece",real_text(run$ece,4L)))
  for (l in seq_len(length(run$network_data$layout$layers)-1L)) {
    layer <- run$network_data$layout$layers[[l]]
    summary <- run$hidden_summary[[l]]
    lines <- c(lines,paste("hidden",l,layer$activation,"units",layer$outputs))
    for (klass in seq_len(classes)-1L) {
      values <- summary$means[[klass+1L]]
      text <- if (is.null(values)) "-" else paste(vapply(values,real_text,character(1),4L),collapse=" ")
      lines <- c(lines,paste("class",klass,"mean",text))
    }
    lines <- c(lines,paste("preferred",paste(summary$preferred,collapse=" ")))
    if (layer$activation == "RELU") lines <- c(
        lines,
        paste("zero_counts",paste(summary$zero_counts,collapse=" "))
    )
  }
  lines <- c(lines,"pruning")
  for (item in run$pruning) lines <- c(
      lines,
      paste(
          "prune",
          item$percent,
          "removed",
          item$removed,
          "correct",
          item$correct,
          "test_acc",
          ratio(item$correct,n),
          "test_loss",
          real_text(item$loss,6L)
      )
  )
  lines <- c(lines,"noise")
  for (item in run$noise_results) lines <- c(
      lines,
      paste("noise",item$percent,"correct",item$correct,"test_acc",ratio(item$correct,n))
  )
  ids <- vapply(run$misclassified,function(item) item$id,character(1))
  c(lines,paste0("misclassified ",length(ids),if (length(ids)) paste0(" ",paste(ids,collapse=" ")) else ""))
}
ensembles <- function(runs,ranking,test) {
  classes <- runs[[1L]]$network_data$architecture$classes
  soft_runs <- Filter(
      function(run) tail(run$network_data$architecture$layers,1L)[[1L]]$activation == "SOFTMAX",
      runs
  )
  majority <- soft <- integer()
  for (i in seq_along(test)) {
    votes <- integer(classes)
    for (run in runs) {
      predicted <- run$test$outcomes[[i]]$predicted
      votes[predicted+1L] <- votes[predicted+1L]+1L
    }
    highest <- max(votes)
    for (index in ranking) {
      predicted <- runs[[index]]$test$outcomes[[i]]$predicted
      if (votes[predicted+1L] == highest) {
        majority <- c(majority,predicted)
        break
      }
    }
    if (length(soft_runs)) {
      means <- vapply(
          seq_len(classes),
          function(k) ordered_sum(vapply(
              soft_runs,
              function(run) run$test$outcomes[[i]]$scores[k],
              numeric(1)
          ))/length(soft_runs),
          numeric(1)
      )
      soft <- c(soft,which.max(means)-1L)
    }
  }
  list(majority=majority,soft=soft,soft_count=length(soft_runs))
}
saliency_lines <- function(top,test) {
  network <- top$network_data
  architecture <- network$architecture
  size <- architecture$width*architecture$height
  maps <- lapply(seq_len(architecture$classes)-1L,function(klass) {
    chosen <- Filter(function(image) image$label == klass,test)
    values <- numeric(size)
    for (image in chosen) {
      inputs <- gradient(network$layout,top$best_theta,image,TRUE)$input_gradient
      for (i in seq_along(inputs)) values[i] <- values[i]+abs(inputs[i])
    }
    if (length(chosen)) values <- values/length(chosen)
    largest <- max(values)
    if (largest > 0) as.integer(pmin(9L,floor(10*values/largest))) else integer(size)
  })
  c(
      paste("saliency",top$name),
      paste("classes",paste(seq_len(architecture$classes)-1L,collapse=" ")),
      level_maps(maps,architecture$width,architecture$height)
  )
}
hardest_examples_lines <- function(top,training) {
  outcomes <- evaluate_network(top$network_data$layout,top$best_theta,training)$outcomes
  order <- head(order(-vapply(outcomes,function(item) item$loss,numeric(1)),seq_along(training)),5L)
  lines <- paste("hardest_training_examples",top$name)
  for (i in order) lines <- c(
      lines,
      paste(
          training[[i]]$id,
          "label",
          training[[i]]$label,
          "predicted",
          outcomes[[i]]$predicted,
          "loss",
          real_text(outcomes[[i]]$loss,6L)
      )
  )
  lines
}
misclassified_examples_lines <- function(top,runs,test,all_train,majority) {
  width <- top$network_data$architecture$width
  lines <- paste("misclassified_examples",top$name)
  for (i in seq_along(test)) {
    image <- test[[i]]
    outcome <- top$test$outcomes[[i]]
    if (outcome$predicted == image$label) next
    predictions <- vapply(runs,function(run) run$test$outcomes[[i]]$predicted,integer(1))
    pixels <- strsplit(image$pixels,"",fixed=TRUE)[[1L]]
    distances <- vapply(
        all_train,
        function(candidate) sum(pixels != strsplit(candidate$pixels,"",fixed=TRUE)[[1L]]),
        integer(1)
    )
    nearest_index <- which.min(distances)
    nearest <- all_train[[nearest_index]]
    lines <- c(lines,paste(image$id,"label",image$label,"predicted",outcome$predicted,"confidence",real_text(outcome$confidence,4L),"true_score",real_text(outcome$scores[image$label+1L],4L),
      "runs",paste(predictions,collapse=" "),"ensemble",majority[i]),paste(
          "nearest",
          nearest$id,
          "label",
          nearest$label,
          "distance",
          distances[nearest_index]
      ),ascii_image(image$pixels,width))
  }
  lines
}
comparison_lines <- function(runs,training,all_train,test,settings) {
  ranking <- order(
      -vapply(runs,function(run) run$test$correct,integer(1)),
      vapply(runs,function(run) run$best_val_loss,numeric(1)),
      seq_along(runs)
  )
  top <- runs[[ranking[1L]]]
  n <- length(test)
  ensemble <- ensembles(runs,ranking,test)
  majority <- ensemble$majority
  lines <- "comparison"
  for (rank in seq_along(ranking)) {
    run <- runs[[ranking[rank]]]
    lines <- c(lines,paste("rank",rank,run$name,"correct",run$test$correct,"test_acc",ratio(run$test$correct,n),"best_val_loss",real_text(run$best_val_loss,6L),
      "test_loss",real_text(
          run$test$loss,
          6L
      ),"best_epoch",run$best_epoch,"epochs",length(run$epochs),"updates",run$updates))
  }
  lines <- c(lines,"agreement")
  for (a in runs) {
    predictions <- vapply(a$test$outcomes,function(item) item$predicted,integer(1))
    agreement <- vapply(
        runs,
        function(b) sum(predictions == vapply(b$test$outcomes,function(item) item$predicted,integer(1))),
        integer(1)
    )
    lines <- c(lines,paste(a$name,paste(agreement,collapse=" ")))
  }
  lines <- c(lines,paste("mcnemar",top$name))
  top_correct <- vapply(top$test$outcomes,function(item) item$predicted == item$label,logical(1))
  for (index in ranking[-1L]) {
    run <- runs[[index]]
    other_correct <- vapply(run$test$outcomes,function(item) item$predicted == item$label,logical(1))
    b <- sum(top_correct & !other_correct)
    c <- sum(!top_correct & other_correct)
    difference <- max(abs(b-c)-1L,0L)
    numerator <- difference*difference
    denominator <- b+c
    chi <- if (denominator == 0L) "0.0000" else ratio(numerator,denominator)
    lines <- c(
        lines,
        paste(
            "vs",
            run$name,
            "b",
            b,
            "c",
            c,
            "chi2",
            chi,
            "significant",
            if (numerator*1000L > 3841L*denominator) "yes" else "no"
        )
    )
  }
  labels <- vapply(test,function(image) image$label,integer(1))
  correct <- sum(majority == labels)
  fixed <- sum(majority == labels & !top_correct)
  broken <- sum(majority != labels & top_correct)
  lines <- c(
      lines,
      paste(
          "ensemble correct",
          paste0(correct,"/",n),
          "test_acc",
          ratio(correct,n),
          "fixed",
          fixed,
          "broken",
          broken
      )
  )
  if (ensemble$soft_count > 0L) {
    correct <- sum(ensemble$soft == labels)
    lines <- c(
        lines,
        paste(
            "soft_ensemble runs",
            ensemble$soft_count,
            "correct",
            paste0(correct,"/",n),
            "test_acc",
            ratio(correct,n)
        )
    )
  } else lines <- c(lines,"soft_ensemble none")
  for (item in runs[[1L]]$noise_results) lines <- c(lines,paste("noise",item$percent,"flipped",item$flipped))
  classes <- top$network_data$architecture$classes
  total <- matrix(0L,classes,classes)
  for (run in runs) total <- total+run$confusion
  pairs <- list()
  for (y in seq_len(classes)-1L) for (p in seq_len(classes)-1L) if (y != p && total[
      y+1L,
      p+1L
  ] > 0L) pairs[[length(pairs)+1L]] <- c(y,p)
  if (length(pairs)) {
    ordered <- order(-vapply(pairs,function(pair) total[pair[1L]+1L,pair[2L]+1L],integer(1)),vapply(pairs,`[`,integer(1),1L),vapply(pairs,`[`,integer(1),2L))
    pairs <- pairs[head(ordered,5L)]
  }
  lines <- c(lines,"confused_pairs")
  for (pair in pairs) lines <- c(lines,paste(pair[1L],"as",pair[2L],"count",total[pair[1L]+1L,pair[2L]+1L]))
  c(
      lines,
      "",
      saliency_lines(top,test),
      "",
      hardest_examples_lines(top,training),
      "",
      misclassified_examples_lines(top,runs,test,all_train,majority)
  )
}
evaluation_lines <- function(runs,training,validation,test,data) {
  lines <- c(data_summary_lines(training,validation,test,data$networks[[1L]]),"")
  for (run in runs) lines <- c(lines,run_evaluation_lines(run,validation,test,data$settings),"")
  c(lines,comparison_lines(runs,training,data$train,test,data$settings))
}
write_output <- function(name,lines) {
  dir.create("output",showWarnings=FALSE)
  writeLines(lines,file.path("output",name),useBytes=TRUE)
}
main <- function() {
  data <- load_inputs()
  nv <- length(data$train) %/% 5L
  split <- length(data$train)-nv
  training <- data$train[seq_len(split)]
  validation <- data$train[seq.int(split+1L,length(data$train))]
  catalog <- network_catalog(data)
  checks <- gradient_check_lines(catalog,data$networks,training,data$settings)
  noise <- noisy_data(data$test,data$settings)
  runs <- lapply(data$settings$runs,function(definition) {
    run <- train_run(definition,catalog[[definition$network]],training,validation,data$settings)
    prepare_run_evaluation(run,training,data$test,data$settings,noise)
  })
  write_output("gradient_check.txt",checks)
  write_output("training_log.csv",training_log_lines(runs,length(training),length(validation)))
  write_output("final_weights.txt",final_weight_lines(runs))
  write_output("predictions.csv",prediction_lines(runs))
  write_output("evaluation.txt",evaluation_lines(runs,training,validation,data$test,data))
}
main()
