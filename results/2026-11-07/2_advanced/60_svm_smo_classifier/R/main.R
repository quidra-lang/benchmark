for (module in c("evaluation","kernels","dataset","smo","multiclass")) source(paste0(module,".R"))
support_counts <- function(model) {
  total <- sum(model$alpha > 0)
  bound <- sum(model$alpha > 0 & model$alpha == model$C)
  c(total,bound,total-bound)
}
support_text <- function(model) {
  counts <- support_counts(model)
  paste("support_vectors",counts[1L],"bound",counts[2L],"free",counts[3L])
}
run_info <- function(model) paste(
    "passes",
    passes(model),
    "steps",
    model$steps,
    "converged",
    if (model$converged) "yes" else "no"
)
objectives <- function(model,alpha=model$alpha) {
  scores <- vapply(seq_along(alpha),function(i) {
    total <- 0
    for (j in seq_along(alpha)) if (alpha[j] > 0) total <- total+alpha[j]*model$labels[j]*model$matrix[i,j]
    total
  },numeric(1))
  quadratic <- total <- 0
  for (i in seq_along(alpha)) {
    quadratic <- quadratic+alpha[i]*model$labels[i]*scores[i]
    total <- total+alpha[i]
  }
  c(quadratic,total-quadratic/2)
}
rank_results <- function(results) results[order(
    -vapply(results,function(result) result$correct,integer(1)),
    vapply(results,function(result) result$C,numeric(1)),
    vapply(results,function(result) result$kernel_index,integer(1))
)]
cross_validate <- function(training,settings) {
  points <- lapply(training,function(example) example$point)
  labels <- vapply(training,function(example) example$label,integer(1))
  partitions <- folds(length(training),settings$folds)
  matrices <- combinations <- best <- list()
  for (ki in seq_along(settings$kernels)) {
    kernel <- settings$kernels[[ki]]
    matrix <- kernel_matrix(kernel,points)
    matrices[[ki]] <- matrix
    candidates <- list()
    for (C in settings$c_grid) {
      values <- numeric(length(training))
      fold_results <- list()
      correct <- support <- pass_count <- steps <- 0L
      for (partition in partitions) {
        fitting <- partition$train
        testing <- partition$test
        model <- train_model(points[fitting],labels[fitting],kernel,submatrix(matrix,fitting),C,settings)
        fold_correct <- 0L
        for (i in testing) {
          values[i] <- decision(model,points[[i]])
          fold_correct <- fold_correct+as.integer(svm_sign(values[i]) == labels[i])
        }
        sv <- support_counts(model)[1L]
        fold_results[[length(fold_results)+1L]] <- list(
            train=length(fitting),
            test=length(testing),
            correct=fold_correct,
            support=sv,
            model=model
        )
        correct <- correct+fold_correct
        support <- support+sv
        pass_count <- pass_count+passes(model)
        steps <- steps+model$steps
      }
      result <- list(
          kernel=kernel,
          kernel_index=ki,
          C=C,
          values=values,
          folds=fold_results,
          correct=correct,
          support=support,
          passes=pass_count,
          steps=steps
      )
      candidates[[length(candidates)+1L]] <- result
      combinations[[length(combinations)+1L]] <- result
    }
    best[[ki]] <- rank_results(candidates)[[1L]]
  }
  list(
      matrices=matrices,
      combinations=combinations,
      best=best,
      selected=rank_results(best)[[1L]],
      ranking=rank_results(combinations)
  )
}
cross_validation_lines <- function(n,k,best,selected,ranking) {
  lines <- paste("cross_validation folds",k,"examples",n)
  for (result in best) lines <- c(
      lines,
      paste(
          "best",
          result$kernel$name,
          "C",
          fixed_text(result$C),
          "correct",
          paste0(result$correct,"/",n),
          "accuracy",
          ratio(result$correct,n)
      )
  )
  lines <- c(lines,paste("selected",selected$kernel$name,"C",fixed_text(selected$C)),"ranking")
  for (rank in seq_along(ranking)) {
    result <- ranking[[rank]]
    lines <- c(
        lines,
        paste(rank,result$kernel$name,"C",fixed_text(result$C),"correct",paste0(result$correct,"/",n))
    )
  }
  lines <- c(lines,paste("cv_detail",selected$kernel$name,"C",fixed_text(selected$C)))
  for (f in seq_along(selected$folds)) {
    result <- selected$folds[[f]]
    lines <- c(
        lines,
        paste(
            "fold",
            f,
            "train",
            result$train,
            "test",
            result$test,
            "correct",
            result$correct,
            "support_vectors",
            result$support,
            run_info(result$model)
        )
    )
  }
  lines
}
evaluate_final <- function(model,training,testing,tolerance) {
  n <- length(training)
  m <- length(testing)
  train_values <- training_decisions(model)
  test_values <- vapply(testing,function(example) decision(model,example$point),numeric(1))
  test_labels <- vapply(testing,function(example) example$label,integer(1))
  objective <- objectives(model)
  quadratic <- objective[1L]
  dual <- objective[2L]
  label_alignment <- matrix_squares <- 0
  for (i in seq_len(n)) for (j in seq_len(n)) {
    value <- model$matrix[i,j]
    label_alignment <- label_alignment+model$labels[i]*model$labels[j]*value
    matrix_squares <- matrix_squares+value*value
  }
  alignment <- label_alignment/(n*sqrt(matrix_squares))
  equality <- w1 <- w2 <- 0
  class_counts <- matrix(0L,2L,2L)
  for (i in seq_along(training)) {
    example <- training[[i]]
    alpha <- model$alpha[i]
    equality <- equality+alpha*example$label
    if (model$kernel$kind == "linear") {
      w1 <- w1+alpha*example$label*example$point[1L]
      w2 <- w2+alpha*example$label*example$point[2L]
    }
    if (alpha > 0) {
      row <- if (example$label == 1L) 1L else 2L
      column <- if (alpha == model$C) 1L else 2L
      class_counts[row,column] <- class_counts[row,column]+1L
    }
  }
  norm_value <- sqrt(quadratic)
  radius <- max(diag(model$matrix))-min(model$matrix)
  hinge_total <- largest <- 0
  violations <- estimated <- 0L
  for (i in seq_along(model$alpha)) {
    alpha <- model$alpha[i]
    label <- model$labels[i]
    value <- train_values[i]
    hinge <- max(0,1-label*value)
    hinge_total <- hinge_total+hinge
    residual <- label*value-1
    violation <- if (alpha == 0) max(
        0,
        -residual
    ) else if (alpha == model$C) max(0,residual) else abs(residual)
    violations <- violations+as.integer(violation > tolerance)
    largest <- max(largest,violation)
    estimated <- estimated+as.integer(2*alpha*radius+hinge >= 1)
  }
  primal <- quadratic/2+model$C*hinge_total
  train_correct <- correct_count(model$labels,train_values)
  counts <- binary_counts(test_labels,test_values)
  tp <- counts[1L]
  fp <- counts[2L]
  tn <- counts[3L]
  fn <- counts[4L]
  inside <- sum(abs(test_values) < 1)
  positive <- ordered_sum(test_values[test_labels == 1L])/(tp+fn)
  negative <- ordered_sum(test_values[test_labels == -1L])/(fp+tn)
  lines <- c(paste("model",model$kernel$name),paste("kernel",kernel_description(model$kernel)),paste("C",fixed_text(model$C)),paste("alignment",fixed_text(alignment,6L)),
    paste(
        "passes",
        passes(model),
        "full",
        model$full_passes,
        "nonbound",
        model$nonbound_passes,
        "converged",
        if (model$converged) "yes" else "no"
    ),
    paste("examined",model$examined,"steps",model$steps),paste(
        "choice heuristic",
        model$choices[1L],
        "nonbound_loop",
        model$choices[2L],
        "full_loop",
        model$choices[3L]
    ),
    paste(
        "clipping none",
        model$clipping[1L],
        "lower",
        model$clipping[2L],
        "upper",
        model$clipping[3L]
    ),support_text(model),paste("b",fixed_text(model$b,6L)),paste("equality",fixed_text(equality,6L)))
  if (model$kernel$kind == "linear") lines <- c(lines,paste("w",fixed_text(w1,6L),fixed_text(w2,6L)))
  lines <- c(lines,paste("sv_by_class positive bound",class_counts[1L,1L],"free",class_counts[1L,2L],"negative bound",class_counts[2L,1L],"free",class_counts[2L,2L]),
    paste(
        "norm",
        fixed_text(norm_value,6L),
        "margin",
        fixed_text(2/norm_value,6L)
    ),paste("dual_objective",fixed_text(dual,6L)),paste("primal_objective",fixed_text(primal,6L)),
    paste("duality_gap",fixed_text(primal-dual,6L)),paste(
        "kkt_violations",
        violations,
        "max",
        fixed_text(largest,6L)
    ),
    paste(
        "xi_alpha radius",
        fixed_text(radius,6L),
        "errors",
        paste0(estimated,"/",n),
        "accuracy",
        ratio(n-estimated,n)
    ),
    paste("train correct",paste0(train_correct,"/",n),"accuracy",ratio(train_correct,n)),paste(
        "test correct",
        paste0(tp+tn,"/",m),
        "accuracy",
        ratio(tp+tn,m),
        "tp",
        tp,
        "fp",
        fp,
        "tn",
        tn,
        "fn",
        fn
    ),
    paste(
        "test precision",
        ratio(tp,tp+fp),
        "recall",
        ratio(tp,tp+fn),
        "f1",
        ratio(2L*tp,2L*tp+fp+fn),
        "auc",
        fixed_text(auc(test_labels,test_values))
    ),
    paste("test inside_margin",inside),paste(
        "test mean_decision positive",
        fixed_text(positive),
        "negative",
        fixed_text(negative)
    ))
  for (i in seq_along(training)) if (model$alpha[i] > 0) lines <- c(lines,paste("sv",training[[i]]$id,"y",training[[i]]$label,"alpha",fixed_text(model$alpha[i],6L),
    "f",fixed_text(train_values[i]),if (model$alpha[i] == model$C) "bound" else "free"))
  list(model=model,train_values=train_values,test_values=test_values,weights=c(w1,w2),lines=lines)
}
training_log <- function(model) {
  lines <- paste("training_log",model$kernel$name)
  i <- 1L
  while (i <= length(model$records)) {
    record <- model$records[[i]]
    if (record$full) {
      dual <- objectives(model,record$alpha)[2L]
      lines <- c(
          lines,
          paste(
              "pass",
              i,
              "full examined",
              record$examined,
              "changed",
              record$changed,
              "dual_objective",
              fixed_text(dual,6L)
          )
      )
      i <- i+1L
    } else {
      first <- i
      examined <- changed <- 0L
      while (i <= length(model$records) && !model$records[[i]]$full) {
        examined <- examined+model$records[[i]]$examined
        changed <- changed+model$records[[i]]$changed
        i <- i+1L
      }
      lines <- c(lines,paste("passes",paste0(first,"-",i-1L),"nonbound examined",examined,"changed",changed))
    }
  }
  lines
}
additional_training_lines <- function(training,testing,selected,matrix,settings,learning=FALSE) {
  kernel <- selected$kernel
  C <- selected$C
  points <- lapply(training,function(e) e$point)
  labels <- vapply(training,function(e) e$label,integer(1))
  test_labels <- vapply(testing,function(e) e$label,integer(1))
  lines <- if (learning) paste(
      "learning_curve",
      kernel$name,
      "C",
      fixed_text(C)
  ) else paste("c_path",kernel$name)
  candidates <- if (learning) settings$learning_curve else settings$c_grid
  for (candidate in candidates) {
    size <- if (learning) (length(training)*candidate) %/% 100L else length(training)
    coefficient <- if (learning) C else candidate
    indices <- seq_len(size)
    model <- train_model(
        points[indices],
        labels[indices],
        kernel,
        submatrix(matrix,indices),
        coefficient,
        settings
    )
    train_correct <- correct_count(labels[indices],training_decisions(model))
    test_correct <- correct_count(test_labels,vapply(testing,function(e) decision(model,e$point),numeric(1)))
    if (learning) lines <- c(
        lines,
        paste(
            "size",
            size,
            "support_vectors",
            support_counts(model)[1L],
            "train",
            paste0(train_correct,"/",size),
            "test",
            paste0(test_correct,"/",length(testing)),
            run_info(model)
        )
    ) else
      lines <- c(
          lines,
          paste(
              "C",
              fixed_text(coefficient),
              support_text(model),
              "dual_objective",
              fixed_text(objectives(model)[2L],6L),
              "train",
              paste0(train_correct,"/",size),
              "test",
              paste0(test_correct,"/",length(testing)),
              run_info(model)
          )
      )
  }
  lines
}
probability <- function(value,A,B) 1/(1+exp(A*value+B))
negative_log_likelihood <- function(values,targets,A,B) {
  total <- 0
  for (i in seq_along(values)) {
    p <- probability(values[i],A,B)
    total <- total+(targets[i]*log(p)+(1-targets[i])*log(1-p))
  }
  -total
}
calibrate <- function(training,testing,selected,test_values,iterations) {
  positive <- sum(vapply(training,function(e) e$label == 1L,logical(1)))
  negative <- length(training)-positive
  targets <- vapply(
      training,
      function(e) if (e$label == 1L) (positive+1L)/(positive+2L) else 1/(negative+2L),
      numeric(1)
  )
  values <- selected$values
  A <- 0
  B <- log((negative+1L)/(positive+1L))
  lines <- c(paste("calibration",selected$kernel$name,"C",fixed_text(selected$C),"positives",positive,"negatives",negative),
    paste(
        "start A",
        fixed_text(A,6L),
        "B",
        fixed_text(B,6L),
        "nll",
        fixed_text(negative_log_likelihood(values,targets,A,B),6L)
    ))
  for (iteration in seq_len(iterations)) {
    g1 <- g2 <- h11 <- h21 <- h22 <- 0
    for (i in seq_along(values)) {
      value <- values[i]
      target <- targets[i]
      p <- probability(value,A,B)
      g1 <- g1+value*(target-p)
      g2 <- g2+(target-p)
      h11 <- h11+value*value*p*(1-p)
      h21 <- h21+value*p*(1-p)
      h22 <- h22+p*(1-p)
    }
    determinant <- h11*h22-h21*h21
    A <- A-(h22*g1-h21*g2)/determinant
    B <- B-(h11*g2-h21*g1)/determinant
    lines <- c(
        lines,
        paste(
            "iteration",
            iteration,
            "A",
            fixed_text(A,6L),
            "B",
            fixed_text(B,6L),
            "nll",
            fixed_text(negative_log_likelihood(values,targets,A,B),6L)
        )
    )
  }
  probabilities <- vapply(test_values,function(value) probability(value,A,B),numeric(1))
  totals <- numeric(5L)
  counts <- positives <- integer(5L)
  log_total <- brier <- 0
  for (i in seq_along(testing)) {
    p <- probabilities[i]
    actual <- testing[[i]]$label == 1L
    log_total <- log_total+(if (actual) log(p) else log(1-p))
    difference <- p-as.integer(actual)
    brier <- brier+difference*difference
    bin <- min(4L,floor(5*p))+1L
    counts[bin] <- counts[bin]+1L
    totals[bin] <- totals[bin]+p
    positives[bin] <- positives[bin]+as.integer(actual)
  }
  lines <- c(
      lines,
      paste(
          "test log_loss",
          fixed_text(-log_total/length(testing),6L),
          "brier",
          fixed_text(brier/length(testing),6L)
      )
  )
  ranges <- c("0.0-0.2","0.2-0.4","0.4-0.6","0.6-0.8","0.8-1.0")
  for (bin in seq_len(5L)) {
    mean <- if (counts[bin] == 0L) "-" else fixed_text(totals[bin]/counts[bin])
    lines <- c(
        lines,
        paste(
            "bin",
            ranges[bin],
            "count",
            counts[bin],
            "mean_probability",
            mean,
            "positive_rate",
            ratio(positives[bin],counts[bin])
        )
    )
  }
  closest <- head(order(abs(test_values),seq_along(testing)),5L)
  for (i in closest) lines <- c(
      lines,
      paste(
          "closest",
          testing[[i]]$id,
          "label",
          testing[[i]]$label,
          "decision",
          fixed_text(test_values[i]),
          "probability",
          fixed_text(probabilities[i])
      )
  )
  list(A=A,B=B,probabilities=probabilities,lines=lines)
}
linear_decision <- function(weights,point) weights[1L]*point[1L]+weights[2L]*point[2L]+weights[3L]
pegasos <- function(training,testing,parameters,comparison) {
  lambda <- parameters[[1L]]
  iterations <- parameters[[2L]]
  seed <- parameters[[3L]]
  state <- as.numeric(seed)
  updates <- 0L
  w1 <- w2 <- bias <- sum1 <- sum2 <- sum_bias <- 0
  n <- length(training)
  m <- length(testing)
  labels <- vapply(training,function(e) e$label,integer(1))
  test_labels <- vapply(testing,function(e) e$label,integer(1))
  lines <- paste("pegasos lambda",fixed_text(lambda),"iterations",iterations,"seed",seed)
  for (t in seq_len(iterations)) {
    state <- (48271*state) %% 2147483647
    example <- training[[as.integer(state %% n)+1L]]
    eta <- 1/(lambda*t)
    sigma <- 1-eta*lambda
    if (example$label*linear_decision(c(w1,w2,bias),example$point) < 1) {
      w1 <- sigma*w1+eta*example$label*example$point[1L]
      w2 <- sigma*w2+eta*example$label*example$point[2L]
      bias <- sigma*bias+eta*example$label
      updates <- updates+1L
    } else {
      w1 <- sigma*w1
      w2 <- sigma*w2
      bias <- sigma*bias
    }
    sum1 <- sum1+w1
    sum2 <- sum2+w2
    sum_bias <- sum_bias+bias
    if (t %% (iterations %/% 10L) == 0L) {
      values <- vapply(training,function(e) linear_decision(c(w1,w2,bias),e$point),numeric(1))
      hinge <- ordered_sum(pmax(0,1-labels*values))
      objective <- lambda/2*(w1*w1+w2*w2+bias*bias)+hinge/n
      lines <- c(
          lines,
          paste(
              "checkpoint",
              t,
              "objective",
              fixed_text(objective,6L),
              "train",
              paste0(correct_count(labels,values),"/",n)
          )
      )
    }
  }
  weights <- c(w1,w2,bias)
  average <- c(sum1/iterations,sum2/iterations,sum_bias/iterations)
  train_values <- vapply(training,function(e) linear_decision(weights,e$point),numeric(1))
  test_values <- vapply(testing,function(e) linear_decision(weights,e$point),numeric(1))
  average_values <- vapply(testing,function(e) linear_decision(average,e$point),numeric(1))
  train_correct <- correct_count(labels,train_values)
  test_correct <- correct_count(test_labels,test_values)
  average_correct <- correct_count(test_labels,average_values)
  v1 <- comparison$weights[1L]
  v2 <- comparison$weights[2L]
  cosine <- (w1*v1+w2*v2)/(sqrt(w1*w1+w2*w2)*sqrt(v1*v1+v2*v2))
  agreement <- sum(svm_sign(test_values) == svm_sign(comparison$test_values))
  lines <- c(lines,paste("updates",updates),paste("w",fixed_text(w1,6L),fixed_text(w2,6L),"bias",fixed_text(bias,6L)),
    paste(
        "train correct",
        paste0(train_correct,"/",n),
        "accuracy",
        ratio(train_correct,n)
    ),paste("test correct",paste0(test_correct,"/",m),"accuracy",ratio(test_correct,m)),
    paste(
        "average w",
        fixed_text(average[1L],6L),
        fixed_text(average[2L],6L),
        "bias",
        fixed_text(average[3L],6L),
        "test correct",
        paste0(average_correct,"/",m)
    ),
    paste(
        "compare",
        comparison$model$kernel$name,
        "cosine",
        fixed_text(cosine,6L),
        "test_agreement",
        paste0(agreement,"/",m)
    ))
  list(values=test_values,lines=lines)
}
mcnemar_lines <- function(testing,results,pegasos_values) {
  names <- c(vapply(results,function(result) result$model$kernel$name,character(1)),"pegasos")
  values <- c(lapply(results,function(result) result$test_values),list(pegasos_values))
  labels <- vapply(testing,function(e) e$label,integer(1))
  correctness <- lapply(values,function(decisions) svm_sign(decisions) == labels)
  lines <- "mcnemar"
  for (a in seq_len(length(names)-1L)) for (b in seq.int(a+1L,length(names))) {
    first <- sum(correctness[[a]] & !correctness[[b]])
    second <- sum(correctness[[b]] & !correctness[[a]])
    difference <- abs(first-second)-1L
    chi2 <- if (first+second == 0L) "-" else fixed_text((difference*difference)/(first+second))
    lines <- c(lines,paste(names[a],names[b],"only_first",first,"only_second",second,"chi2",chi2))
  }
  lines
}
multiclass_summary <- function(role,examples,results) {
  classes <- vapply(examples,function(e) e$class_number,integer(1))
  rest <- sum(classes == vapply(results,function(r) r$ovr,integer(1)))
  pair <- sum(classes == vapply(results,function(r) r$ovo,integer(1)))
  agreement <- sum(vapply(results,function(r) r$ovr == r$ovo,logical(1)))
  ties <- sum(vapply(results,function(r) r$tied,logical(1)))
  n <- length(examples)
  paste(
      role,
      "ovr",
      paste0(rest,"/",n),
      ratio(rest,n),
      "ovo",
      paste0(pair,"/",n),
      ratio(pair,n),
      "agreement",
      paste0(agreement,"/",n),
      "vote_ties",
      ties
  )
}
multiclass_lines <- function(training,testing,models) {
  train_results <- lapply(training,function(e) classify(models,e$point))
  test_results <- lapply(testing,function(e) classify(models,e$point))
  n <- length(training)
  m <- length(testing)
  lines <- c(
      paste("multiclass kernel",models$kernel$name,"C",fixed_text(models$C),"classes 3 train",n,"test",m),
      "ovr"
  )
  for (k in seq_len(3L)) {
    model <- models$ovr[[k]]
    correct <- sum(vapply(
        seq_along(testing),
        function(j) svm_sign(test_results[[j]]$ovr_values[k]) == (if (testing[[j]]$class_number == k) 1L else -1L),
        logical(1)
    ))
    lines <- c(
        lines,
        paste(
            "model",
            paste0(k,"-rest"),
            "examples",
            n,
            "positives",
            sum(model$labels == 1L),
            support_text(model),
            "b",
            fixed_text(model$b,6L),
            run_info(model),
            "test",
            paste0(correct,"/",m)
        )
    )
  }
  lines <- c(lines,"ovo")
  for (i in seq_along(CLASS_PAIRS)) {
    pair <- CLASS_PAIRS[[i]]
    model <- models$ovo[[i]]
    indices <- which(vapply(testing,function(e) e$class_number %in% pair,logical(1)))
    correct <- sum(vapply(
        indices,
        function(j) svm_sign(test_results[[j]]$ovo_values[i]) == (if (testing[[j]]$class_number == pair[1L]) 1L else -1L),
        logical(1)
    ))
    lines <- c(
        lines,
        paste(
            "model",
            paste(pair,collapse="-"),
            "examples",
            length(model$points),
            "positives",
            sum(model$labels == 1L),
            support_text(model),
            "b",
            fixed_text(model$b,6L),
            run_info(model),
            "test",
            paste0(correct,"/",length(indices))
        )
    )
  }
  lines <- c(lines,"predictions")
  for (i in seq_along(testing)) {
    e <- testing[[i]]
    r <- test_results[[i]]
    rest <- paste(vapply(r$ovr_values,fixed_text,character(1)),collapse=" ")
    pair <- paste(vapply(r$ovo_values,fixed_text,character(1)),collapse=" ")
    lines <- c(
        lines,
        paste(
            e$id,
            "class",
            e$class_number,
            "ovr",
            rest,
            "pred",
            r$ovr,
            "ovo",
            pair,
            "votes",
            paste(r$votes,collapse=" "),
            "pred",
            r$ovo
        )
    )
  }
  lines <- c(
      lines,
      multiclass_summary("train",training,train_results),
      multiclass_summary("test",testing,test_results)
  )
  classes <- vapply(testing,function(e) e$class_number,integer(1))
  for (decoder in c("ovr","ovo")) {
    predictions <- vapply(test_results,function(r) r[[decoder]],integer(1))
    lines <- c(lines,paste("confusion",decoder),confusion_lines(confusion_matrix(classes,predictions)))
  }
  lines
}
framed_plot <- function(cells,width,height) {
  border <- paste0("+",strrep("-",width),"+")
  c(
      border,
      vapply(
          seq_len(height)-1L,
          function(r) paste0("|",paste(cells[seq.int(r*width+1L,(r+1L)*width)],collapse=""),"|"),
          character(1)
      ),
      border
  )
}
plot_cell <- function(point,xmin,ymax,dx,dy,width,height) {
  column <- as.integer(floor((point[1L]-xmin)/dx))
  row <- as.integer(floor((ymax-point[2L])/dy))
  if (column >= 0L && column < width && row >= 0L && row < height) row*width+column+1L else 0L
}
decision_plots <- function(training,multi_training,results,selected,A,B,multi,settings) {
  width <- settings$plot_size[1L]
  height <- settings$plot_size[2L]
  xmin <- settings$plot_x[1L]
  xmax <- settings$plot_x[2L]
  ymin <- settings$plot_y[1L]
  ymax <- settings$plot_y[2L]
  dx <- (xmax-xmin)/width
  dy <- (ymax-ymin)/height
  ncell <- width*height
  model <- results[[selected$kernel_index]]$model
  binary <- probabilities <- multicells <- character(ncell)
  signs <- matrix(0L,ncell,length(results))
  levels <- integer(10L)
  for (r in seq_len(height)-1L) for (c in seq_len(width)-1L) {
    p <- r*width+c+1L
    point <- c(xmin+(c+0.5)*dx,ymax-(r+0.5)*dy)
    values <- vapply(results,function(result) decision(result$model,point),numeric(1))
    value <- values[selected$kernel_index]
    binary[p] <- if (value >= 1) "+" else if (value > 0) "." else if (value > -1) "-" else " "
    level <- min(9L,floor(10*probability(value,A,B)))
    probabilities[p] <- as.character(level)
    levels[level+1L] <- levels[level+1L]+1L
    signs[p,] <- svm_sign(values)
    result <- classify(multi,point)
    multicells[p] <- if (result$ovr != result$ovo) "?" else c(" ",".",":")[result$ovr]
  }
  assignments <- integer(ncell)
  outside <- 0L
  for (i in seq_along(training)) {
    p <- plot_cell(training[[i]]$point,xmin,ymax,dx,dy,width,height)
    if (p == 0L) outside <- outside+1L else if (assignments[p] == 0L || (model$alpha[i] > 0 && model$alpha[assignments[p]] <= 0)) assignments[p] <- i
  }
  for (p in seq_along(assignments)) {
    i <- assignments[p]
    if (i == 0L) next
    support <- model$alpha[i] > 0
    binary[p] <- if (training[[i]]$label == 1L) { if (support) "X" else "x" } else if (support) "O" else "o"
  }
  multi_assignments <- integer(ncell)
  multi_outside <- 0L
  for (i in seq_along(multi_training)) {
    p <- plot_cell(multi_training[[i]]$point,xmin,ymax,dx,dy,width,height)
    if (p == 0L) multi_outside <- multi_outside+1L else if (multi_assignments[p] == 0L) multi_assignments[p] <- i
  }
  for (p in seq_along(multi_assignments)) if (multi_assignments[p] != 0L) multicells[p] <- as.character(multi_training[[multi_assignments[p]]]$class_number)
  lines <- c(paste("binary",model$kernel$name,"C",fixed_text(model$C)),paste("x",fixed_text(xmin),fixed_text(xmax),"y",fixed_text(ymin),fixed_text(ymax),"grid",paste0(width,"x",height)),
    framed_plot(binary,width,height),paste(
        "cells outer_positive",
        sum(binary == "+"),
        "inner_positive",
        sum(binary == "."),
        "inner_negative",
        sum(binary == "-"),
        "outer_negative",
        sum(binary == " "),
        "points",
        sum(assignments != 0L),
        "outside",
        outside
    ),
    "",paste(
        "probability",
        model$kernel$name,
        "A",
        fixed_text(A,6L),
        "B",
        fixed_text(B,6L)
    ),framed_plot(probabilities,width,height),paste("levels",paste(levels,collapse=" ")),"","grid_agreement")
  if (length(results) > 1L) for (a in seq_len(length(results)-1L)) for (b in seq.int(a+1L,length(results))) {
    agreement <- sum(signs[,a] == signs[,b])
    lines <- c(
        lines,
        paste(
            results[[a]]$model$kernel$name,
            results[[b]]$model$kernel$name,
            paste0(agreement,"/",ncell),
            "positive",
            sum(signs[,a] == 1L),
            sum(signs[,b] == 1L)
        )
    )
  }
  c(lines,"",paste("multiclass",multi$kernel$name,"C",fixed_text(multi$C)),framed_plot(multicells,width,height),
    paste(
        "cells class1",
        sum(multicells == " "),
        "class2",
        sum(multicells == "."),
        "class3",
        sum(multicells == ":"),
        "disagree",
        sum(multicells == "?"),
        "points",
        sum(multi_assignments != 0L),
        "outside",
        multi_outside
    ))
}
cv_grid_lines <- function(combinations,k,n) {
  header <- c("kernel","C",paste0("fold",seq_len(k)),"correct","accuracy","support_vectors","passes","steps")
  lines <- paste(header,collapse=",")
  for (result in combinations) {
    row <- c(
        result$kernel$name,
        fixed_text(result$C),
        vapply(result$folds,function(fold) fold$correct,integer(1)),
        result$correct,
        ratio(result$correct,n),
        result$support,
        result$passes,
        result$steps
    )
    lines <- c(lines,paste(row,collapse=","))
  }
  lines
}
prediction_lines <- function(testing,results,selected,pegasos_values,probabilities) {
  header <- c(
      "id",
      "label",
      vapply(results,function(result) result$model$kernel$name,character(1)),
      "pegasos",
      "predicted",
      "probability"
  )
  lines <- paste(header,collapse=",")
  selected_values <- results[[selected$kernel_index]]$test_values
  for (i in seq_along(testing)) {
    e <- testing[[i]]
    row <- c(
        e$id,
        e$label,
        vapply(results,function(result) fixed_text(result$test_values[i]),character(1)),
        fixed_text(pegasos_values[i]),
        svm_sign(selected_values[i]),
        fixed_text(probabilities[i])
    )
    lines <- c(lines,paste(row,collapse=","))
  }
  lines
}
main <- function() {
  inputs <- read_inputs()
  training <- inputs$training
  testing <- inputs$testing
  settings <- inputs$settings
  cv <- cross_validate(training,settings)
  points <- lapply(training,function(e) e$point)
  labels <- vapply(training,function(e) e$label,integer(1))
  results <- lapply(seq_along(cv$best),function(i) {
    result <- cv$best[[i]]
    model <- train_model(points,labels,result$kernel,cv$matrices[[i]],result$C,settings)
    evaluate_final(model,training,testing,settings$tolerance)
  })
  selected <- cv$selected
  chosen <- results[[selected$kernel_index]]
  matrix <- cv$matrices[[selected$kernel_index]]
  sections <- c(list(cross_validation_lines(length(training),settings$folds,cv$best,selected,cv$ranking)),lapply(results,function(result) result$lines),
    list(
        training_log(chosen$model),
        additional_training_lines(training,testing,selected,matrix,settings),
        additional_training_lines(training,testing,selected,matrix,settings,TRUE)
    ))
  calibration <- calibrate(training,testing,selected,chosen$test_values,settings$newton_iterations)
  sections[[length(sections)+1L]] <- calibration$lines
  comparison <- Filter(function(result) result$model$kernel$kind == "linear",results)[[1L]]
  pegasos_result <- pegasos(training,testing,settings$pegasos,comparison)
  sections <- c(sections,list(pegasos_result$lines,mcnemar_lines(testing,results,pegasos_result$values)))
  multi_kernel <- Filter(function(kernel) kernel$name == settings$multiclass[[1L]],settings$kernels)[[1L]]
  multi <- train_multiclass(inputs$multi_training,multi_kernel,settings$multiclass[[2L]],settings)
  model_lines <- character()
  for (section in sections) {
    if (length(model_lines)) model_lines <- c(model_lines,"")
    model_lines <- c(model_lines,section)
  }
  write_lines("model.txt",model_lines)
  write_lines("cv_grid.csv",cv_grid_lines(cv$combinations,settings$folds,length(training)))
  write_lines(
      "predictions.csv",
      prediction_lines(testing,results,selected,pegasos_result$values,calibration$probabilities)
  )
  write_lines("multiclass.txt",multiclass_lines(inputs$multi_training,inputs$multi_testing,multi))
  write_lines(
      "decision_plot.txt",
      decision_plots(
          training,
          inputs$multi_training,
          results,
          selected,
          calibration$A,
          calibration$B,
          multi,
          settings
      )
  )
}
main()
