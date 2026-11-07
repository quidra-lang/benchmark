for (module in c("dataset","linalg","gaussian_models","evaluation","plot")) source(paste0(module,".R"))
fit <- function(data,name,features=seq_along(data$features),rows=data$train,prior=data$params$PRIOR,
                epsilon=data$params$VAR_SMOOTHING[1L],gamma=data$params$QDA_GAMMA[1L]) {
  train_model(rows,features,length(data$classes),name,prior,epsilon,gamma)
}
cross_validate <- function(analysis,name,features=seq_along(analysis$data$features),
                           epsilon=analysis$data$params$VAR_SMOOTHING[1L],gamma=analysis$data$params$QDA_GAMMA[1L]) {
  data <- analysis$data
  key <- paste(name,paste(features,collapse=","),sprintf("%.17g",epsilon),sprintf("%.17g",gamma),sep="|")
  if (exists(key,analysis$cache,inherits=FALSE)) return(get(key,analysis$cache,inherits=FALSE))
  predictions <- integer(length(data$train))
  counts <- integer()
  folds <- data$params$CV_FOLDS[1L]
  for (fold in seq_len(folds)-1L) {
    model <- fit(
        data,
        name,
        features,
        Filter(function(r) r$id %% folds != fold,data$train),
        epsilon=epsilon,
        gamma=gamma
    )
    correct <- 0L
    for (i in seq_along(data$train)) {
      row <- data$train[[i]]
      if (row$id %% folds != fold) next
      predictions[i] <- predict_class(model,row$x)
      correct <- correct+(predictions[i] == row$y)
    }
    counts <- c(counts,correct)
  }
  result <- list(predictions=predictions,counts=counts,correct=sum(counts))
  assign(key,result,analysis$cache)
  result
}
confusion_lines <- function(classes,matrix) vapply(seq_along(classes),function(k)
  paste("confusion",classes[k],paste(matrix[k,],collapse=" ")),character(1))
comparison_lines <- function(title,names,predictions,actual) {
  lines <- title
  for (a in seq_len(length(names)-1L)) for (b in seq.int(a+1L,length(names))) {
    result <- mcnemar(actual,predictions[[a]],predictions[[b]])
    lines <- c(lines,sprintf("%s %s b01 %d b10 %d chi2 %s significant %s",names[a],names[b],
      result$b01,result$b10,real_text(result$chi2),if (result$significant) "yes" else "no"))
  }
  lines
}
point_grid <- function(points,actual,letters,limits,dimensions) {
  xmin <- limits[1L]
  xmax <- limits[2L]
  ymin <- limits[3L]
  ymax <- limits[4L]
  width <- dimensions[1L]
  height <- dimensions[2L]
  grid <- matrix(" ",height,width)
  for (i in seq_along(points)) {
    point <- points[[i]]
    column <- cell(point[1L],xmin,xmax,width)+1L
    row <- height-cell(point[2L],ymin,ymax,height)
    letter <- letters[actual[i]]
    grid[row,column] <- if (grid[row,column] %in% c(" ",letter)) letter else "*"
  }
  grid
}
model_sections <- function(analysis) {
  data <- analysis$data
  nb <- analysis$models[[1L]]
  lda <- analysis$models[[2L]]
  qda <- analysis$models[[3L]]
  classes <- data$classes
  features <- data$features
  d <- length(features)
  sections <- list()
  lines <- c(
      paste("features",paste(features,collapse=" ")),
      paste("classes",paste(classes,collapse=" ")),
      paste("prior_mode",data$params$PRIOR)
  )
  for (k in seq_along(classes)) lines <- c(lines,sprintf("class %s letter %s count %d prior %s mean %s",
    classes[k],toupper(substr(classes[k],1L,1L)),nb$counts[k],real_text(nb$priors[k]),reals(nb$means[[k]])))
  sections[[length(sections)+1L]] <- lines
  lines <- c(
      "model NB",
      sprintf(
          "smoothing epsilon %s max_variance %s added %s",
          real_text(nb$epsilon),
          real_text(nb$max_variance),
          real_text(nb$added)
      )
  )
  for (k in seq_along(classes)) lines <- c(
      lines,
      sprintf(
          "class %s variance %s log_det %s",
          classes[k],
          reals(diag(nb$covariance[[k]])),
          real_text(nb$determinants[k])
      )
  )
  sections[[length(sections)+1L]] <- lines
  lower <- lda$factors[[1L]]
  lines <- c(
      "model LDA",
      paste("log_det",real_text(lda$determinants[1L])),
      vapply(seq_len(d),function(i) paste0("  ",reals(lda$pooled[i,])),character(1))
  )
  for (k in seq_along(classes)) {
    coef <- backward(lower,forward(lower,lda$means[[k]]))
    intercept <- log(lda$priors[k])-dot_product(lda$means[[k]],coef)/2
    lines <- c(lines,sprintf("class %s intercept %s coef %s",classes[k],real_text(intercept),reals(coef)))
  }
  sections[[length(sections)+1L]] <- lines
  lines <- paste("model QDA gamma",real_text(qda$gamma))
  for (k in seq_along(classes)) {
    eigenvalues <- sort(jacobi(qda$covariance[[k]])$values,decreasing=TRUE)
    lines <- c(lines,sprintf("class %s log_det %s eigenvalues %s condition %s",classes[k],real_text(qda$determinants[k]),
      reals(eigenvalues),real_text(eigenvalues[1L]/tail(eigenvalues,1L))),
      vapply(seq_len(d),function(i) paste0("  ",reals(qda$covariance[[k]][i,])),character(1)))
  }
  sections[[length(sections)+1L]] <- lines
  lines <- "separation"
  for (a in seq_len(length(classes)-1L)) for (b in seq.int(a+1L,length(classes))) {
    difference <- nb$means[[a]]-nb$means[[b]]
    mahalanobis <- sqrt(quadratic_form(lower,difference))
    average <- (qda$covariance[[a]]+qda$covariance[[b]])/2
    factor <- cholesky_factor(average)
    bhattacharyya <- quadratic_form(
        factor,
        difference
    )/8+(log_determinant(factor)-(qda$determinants[a]+qda$determinants[b])/2)/2
    lines <- c(
        lines,
        sprintf(
            "%s %s mahalanobis %s bhattacharyya %s",
            classes[a],
            classes[b],
            real_text(mahalanobis),
            real_text(bhattacharyya)
        )
    )
  }
  sections[[length(sections)+1L]] <- lines
  outlier_distances <- vapply(data$train,function(row) distances(qda,row$x)[row$y],numeric(1))
  indices <- which(outlier_distances > data$params$OUTLIER_THRESHOLD[1L])
  indices <- indices[order(-outlier_distances[indices],indices)]
  lines <- paste("outliers threshold",real_text(data$params$OUTLIER_THRESHOLD[1L]))
  for (i in indices) {
    row <- data$train[[i]]
    lines <- c(lines,sprintf("%d %s q %s",row$id,row$label,real_text(outlier_distances[i])))
  }
  sections[[length(sections)+1L]] <- c(lines,sprintf("count %d",length(indices)))
  sections
}
prediction_lines <- function(analysis) {
  data <- analysis$data
  lines <- paste0("id,model,actual,predicted,decision,",paste(data$classes,collapse=","))
  for (i in seq_along(data$test)) for (k in seq_len(3L)) {
    row <- data$test[[i]]
    result <- analysis$results[[k]][[i]]
    lines <- c(lines,paste(c(row$id,MODEL_NAMES[k],row$label,data$classes[result$predicted],
      data$classes[result$decision],real_text(result$posterior)),collapse=","))
  }
  lines
}
model_evaluation <- function(analysis,k) {
  data <- analysis$data
  results <- analysis$results[[k]]
  predictions <- analysis$predictions[[k]]
  actual <- vapply(data$test,`[[`,integer(1),"y")
  m <- length(actual)
  metrics <- measures(actual,predictions,length(data$classes))
  lines <- c(paste("model",MODEL_NAMES[k]),confusion_lines(data$classes,metrics$matrix))
  for (key in c("accuracy","balanced_accuracy","kappa")) lines <- c(
      lines,
      paste(key,fraction_text(metrics[[key]]))
  )
  for (j in seq_along(data$classes)) lines <- c(lines,sprintf("class %s support %d recall %s precision %s f1 %s",
    data$classes[j],metrics$support[j],fraction_text(metrics$recall[[j]]),fraction_text(metrics$precision[[j]]),fraction_text(metrics$f1[[j]])))
  loss <- -ordered_sum(vapply(seq_len(m),function(i) results[[i]]$log_posterior[actual[i]],numeric(1)))/m
  lines <- c(lines,paste("macro_f1",real_text(metrics$macro_f1)),paste("log_loss",real_text(loss)))
  errors <- which(predictions != actual)
  lines <- c(lines,sprintf("errors %d",length(errors)))
  for (i in errors) {
    row <- data$test[[i]]
    result <- results[[i]]
    lines <- c(
        lines,
        sprintf(
            "error %d actual %s predicted %s confidence %s",
            row$id,
            row$label,
            data$classes[result$predicted],
            real_text(result$confidence)
        )
    )
  }
  edges <- c(0,data$params$CALIBRATION_EDGES,1)
  confidences <- vapply(results,`[[`,numeric(1),"confidence")
  calibration_error <- 0
  for (j in seq_len(length(edges)-1L)) {
    lo <- edges[j]
    hi <- edges[j+1L]
    indices <- which(confidences >= lo & (confidences < hi | (j == length(edges)-1L & confidences == hi)))
    n <- length(indices)
    confidence_sum <- ordered_sum(confidences[indices])
    correct <- sum(predictions[indices] == actual[indices])
    confidence <- if (n) real_text(confidence_sum/n) else "-"
    lines <- c(
        lines,
        sprintf(
            "bin %s %s count %d confidence %s accuracy %s",
            real_text(lo),
            real_text(hi),
            n,
            confidence,
            ratio_text(correct,n)
        )
    )
    calibration_error <- calibration_error+abs(correct-confidence_sum)
  }
  lines <- c(lines,paste("ece",real_text(calibration_error/m)))
  for (threshold in data$params$REJECT_THRESHOLDS) {
    selected <- which(confidences >= threshold)
    correct <- sum(predictions[selected] == actual[selected])
    lines <- c(lines,sprintf("reject %s accepted %d coverage %s accuracy %s",real_text(threshold),length(selected),
      ratio_text(length(selected),m),ratio_text(correct,length(selected))))
  }
  lines
}
evaluation_sections <- function(analysis) {
  data <- analysis$data
  n <- length(data$train)
  m <- length(data$test)
  classes <- length(data$classes)
  actual <- vapply(data$test,`[[`,integer(1),"y")
  train_actual <- vapply(data$train,`[[`,integer(1),"y")
  features <- seq_along(data$features)
  sections <- c(list(sprintf("test rows %d",m)),lapply(seq_len(3L),function(k) model_evaluation(analysis,k)))
  ensemble <- vapply(seq_len(m),function(i) which.max(vapply(seq_len(classes),function(j)
    ordered_sum(vapply(
        seq_len(3L),
        function(k) analysis$results[[k]][[i]]$posterior[j],
        numeric(1)
    ))/3,numeric(1))),integer(1))
  metrics <- measures(actual,ensemble,classes)
  sections[[length(sections)+1L]] <- c("ensemble soft_vote",sprintf("accuracy %s balanced_accuracy %s kappa %s",
    fraction_text(metrics$accuracy),fraction_text(metrics$balanced_accuracy),fraction_text(metrics$kappa)))
  sections[[length(sections)+1L]] <- comparison_lines(
      "mcnemar test",
      c(MODEL_NAMES,"ENSEMBLE"),
      c(analysis$predictions,list(ensemble)),
      actual
  )
  lines <- "costs"
  for (k in seq_len(3L)) {
    results <- analysis$results[[k]]
    total <- ordered_sum(vapply(
        seq_len(m),
        function(i) data$costs[actual[i],results[[i]]$predicted],
        numeric(1)
    ))
    decision_total <- ordered_sum(vapply(
        seq_len(m),
        function(i) data$costs[actual[i],results[[i]]$decision],
        numeric(1)
    ))
    changed <- sum(vapply(results,function(r) r$predicted != r$decision,logical(1)))
    correct <- sum(vapply(seq_len(m),function(i) results[[i]]$decision == actual[i],logical(1)))
    lines <- c(lines,sprintf("%s argmax_total %s decision_total %s changed %d decision_accuracy %s",MODEL_NAMES[k],
      real_text(total),real_text(decision_total),changed,ratio_text(correct,m)))
  }
  sections[[length(sections)+1L]] <- lines
  novel <- list()
  for (i in seq_along(data$test)) {
    q <- distances(analysis$models[[3L]],data$test[[i]]$x)
    nearest <- which.min(q)
    if (q[nearest] > data$params$OUTLIER_THRESHOLD[1L]) novel[[length(novel)+1L]] <- list(
        q=q[nearest],
        index=i,
        nearest=nearest
    )
  }
  indices <- order(-vapply(novel,`[[`,numeric(1),"q"),vapply(novel,`[[`,integer(1),"index"))
  lines <- paste("novelty threshold",real_text(data$params$OUTLIER_THRESHOLD[1L]))
  for (item in novel[indices]) lines <- c(
      lines,
      sprintf("%d nearest %s q %s",data$test[[item$index]]$id,data$classes[item$nearest],real_text(item$q))
  )
  sections[[length(sections)+1L]] <- c(lines,sprintf("count %d",length(novel)))
  b <- data$params$BOOTSTRAP[1L]
  seed <- data$params$BOOTSTRAP[2L]
  draw <- random_generator(seed)
  samples <- matrix(0,b,3L)
  for (resample in seq_len(b)) for (unused in seq_len(m)) {
    i <- draw() %% m+1L
    for (k in seq_len(3L)) samples[resample,k] <- samples[
        resample,
        k
    ]+(analysis$predictions[[k]][i] == actual[i])
  }
  lines <- sprintf("bootstrap resamples %d seed %d",b,seed)
  offset <- b %/% 40L
  for (k in seq_len(3L)) {
    ordered <- sort(samples[,k])
    lines <- c(lines,sprintf("%s mean %s interval %s %s",MODEL_NAMES[k],real_text(sum(ordered)/b/m),
      ratio_text(ordered[offset+1L],m),ratio_text(ordered[b-offset],m)))
  }
  for (a in seq_len(2L)) for (j in seq.int(a+1L,3L)) {
    wins <- sum(samples[,a] > samples[,j])
    ties <- sum(samples[,a] == samples[,j])
    lines <- c(
        lines,
        sprintf("%s %s wins %d ties %d losses %d",MODEL_NAMES[a],MODEL_NAMES[j],wins,ties,b-wins-ties)
    )
  }
  sections[[length(sections)+1L]] <- lines
  alternative <- if (data$params$PRIOR == "empirical") "uniform" else "empirical"
  lines <- paste("prior_sensitivity alternative",alternative)
  for (k in seq_len(3L)) {
    model <- fit(data,MODEL_NAMES[k],prior=alternative)
    predictions <- vapply(data$test,function(row) predict_class(model,row$x),integer(1))
    metrics <- measures(actual,predictions,classes)
    changed <- sum(predictions != analysis$predictions[[k]])
    lines <- c(lines,sprintf("%s accuracy %s balanced_accuracy %s changed %d",MODEL_NAMES[k],
      fraction_text(metrics$accuracy),fraction_text(metrics$balanced_accuracy),changed))
  }
  sections[[length(sections)+1L]] <- lines
  lines <- "learning_curve"
  for (size in data$params$CURVE) {
    taken <- integer(classes)
    rows <- list()
    for (row in data$train) {
      taken[row$y] <- taken[row$y]+1L
      if (taken[row$y] <= size) rows[[length(rows)+1L]] <- row
    }
    fields <- sprintf("size %d rows %d",size,length(rows))
    for (name in MODEL_NAMES) {
      model <- fit(data,name,features,rows)
      correct <- sum(vapply(data$test,function(row) predict_class(model,row$x) == row$y,logical(1)))
      fields <- c(fields,paste(name,ratio_text(correct,m)))
    }
    lines <- c(lines,paste(fields,collapse=" "))
  }
  sections[[length(sections)+1L]] <- lines
  folds <- data$params$CV_FOLDS[1L]
  fold_sizes <- vapply(
      seq_len(folds)-1L,
      function(fold) sum(vapply(data$train,function(row) row$id %% folds == fold,logical(1))),
      numeric(1)
  )
  lines <- c(sprintf("cross_validation folds %d",folds),paste("fold_sizes",paste(fold_sizes,collapse=" ")))
  best <- NULL
  for (s in seq_along(data$subsets)) {
    subset <- data$subsets[[s]]
    lines <- c(
        lines,
        paste("subset",subset$name,"features",paste(data$features[subset$features],collapse=" "))
    )
    for (k in seq_len(3L)) {
      cv <- cross_validate(analysis,MODEL_NAMES[k],subset$features)
      lines <- c(
          lines,
          sprintf(
              "  %s fold_correct %s correct %d accuracy %s",
              MODEL_NAMES[k],
              paste(cv$counts,collapse=" "),
              cv$correct,
              ratio_text(cv$correct,n)
          )
      )
      if (is.null(best) || cv$correct > best$correct || (cv$correct == best$correct && length(subset$features) < length(best$features)))
        best <- list(name=subset$name,features=subset$features,kind=MODEL_NAMES[k],correct=cv$correct)
    }
  }
  lines <- c(
      lines,
      sprintf(
          "best subset %s model %s correct %d accuracy %s",
          best$name,
          best$kind,
          best$correct,
          ratio_text(best$correct,n)
      )
  )
  model <- fit(data,best$kind,best$features)
  correct <- sum(vapply(data$test,function(row) predict_class(model,row$x) == row$y,logical(1)))
  sections[[length(sections)+1L]] <- c(
      lines,
      sprintf("refit_test correct %d accuracy %s",correct,ratio_text(correct,m))
  )
  cvs <- lapply(MODEL_NAMES,function(name) cross_validate(analysis,name))
  sections[[length(sections)+1L]] <- comparison_lines("mcnemar cross_validation",MODEL_NAMES,lapply(cvs,`[[`,"predictions"),train_actual)
  for (k in seq_len(3L)) {
    metrics <- measures(train_actual,cvs[[k]]$predictions,classes)
    sections[[length(sections)+1L]] <- c(paste("cv_confusion model",MODEL_NAMES[k]),confusion_lines(data$classes,metrics$matrix),
      sprintf(
          "balanced_accuracy %s kappa %s",
          fraction_text(metrics$balanced_accuracy),
          fraction_text(metrics$kappa)
      ))
  }
  lines <- "leave_one_out"
  for (name in MODEL_NAMES) {
    correct <- 0L
    for (i in seq_along(data$train)) {
      row <- data$train[[i]]
      model <- fit(data,name,features,data$train[-i])
      correct <- correct+(predict_class(model,row$x) == row$y)
    }
    lines <- c(lines,sprintf("%s correct %d accuracy %s",name,correct,ratio_text(correct,n)))
  }
  sections[[length(sections)+1L]] <- lines
  for (name in MODEL_NAMES) {
    lines <- paste("forward_selection model",name)
    selected <- integer()
    best_step <- 0L
    best_correct <- -1L
    for (step in features) {
      candidates <- setdiff(features,selected)
      scores <- vapply(candidates,function(j) cross_validate(analysis,name,c(selected,j))$correct,numeric(1))
      winner <- which.max(scores)
      added <- candidates[winner]
      correct <- scores[winner]
      selected <- c(selected,added)
      lines <- c(
          lines,
          sprintf(
              "step %d add %s correct %d accuracy %s",
              step,
              data$features[added],
              correct,
              ratio_text(correct,n)
          )
      )
      if (correct > best_correct) {
        best_step <- step
        best_correct <- correct
      }
    }
    sections[[length(sections)+1L]] <- c(
        lines,
        sprintf(
            "best_step %d features %s",
            best_step,
            paste(data$features[selected[seq_len(best_step)]],collapse=" ")
        )
    )
  }
  for (name in c("NB","QDA")) {
    values <- if (name == "NB") data$params$SMOOTHING_GRID else data$params$GAMMA_GRID
    lines <- if (name == "NB") "nb_smoothing_path" else "qda_gamma_path"
    best_value <- 0
    best_correct <- -1L
    for (value in values) {
      cv <- if (name == "NB") cross_validate(
          analysis,
          name,
          epsilon=value
      ) else cross_validate(analysis,name,gamma=value)
      lines <- c(
          lines,
          sprintf("value %s correct %d accuracy %s",real_text(value),cv$correct,ratio_text(cv$correct,n))
      )
      if (cv$correct >= best_correct) {
        best_value <- value
        best_correct <- cv$correct
      }
    }
    model <- if (name == "NB") fit(data,name,epsilon=best_value) else fit(data,name,gamma=best_value)
    correct <- sum(vapply(data$test,function(row) predict_class(model,row$x) == row$y,logical(1)))
    sections[[length(sections)+1L]] <- c(
        lines,
        sprintf("best %s test correct %d accuracy %s",real_text(best_value),correct,ratio_text(correct,m))
    )
  }
  sections
}
boundary_sections <- function(analysis) {
  data <- analysis$data
  width <- data$params$MAP_SIZE[1L]
  height <- data$params$MAP_SIZE[2L]
  classes <- length(data$classes)
  upper <- toupper(substr(data$classes,1L,1L))
  lower <- substr(data$classes,1L,1L)
  sections <- list()
  for (features in data$pairs) {
    fx <- features[1L]
    fy <- features[2L]
    xs <- vapply(data$train,function(row) row$x[fx],numeric(1))
    ys <- vapply(data$train,function(row) row$x[fy],numeric(1))
    xmin <- min(xs)
    xmax <- max(xs)
    ymin <- min(ys)
    ymax <- max(ys)
    dx <- (xmax-xmin)/(width-1L)
    dy <- (ymax-ymin)/(height-1L)
    points <- lapply(
        seq_len(height),
        function(row) lapply(seq_len(width),function(column) c(xmin+(column-1L)*dx,ymax-(row-1L)*dy))
    )
    lines <- c(sprintf("pair %s %s",data$features[fx],data$features[fy]),
      sprintf(
          "x %s %s %s y %s %s %s grid %dx%d",
          data$features[fx],
          real_text(xmin),
          real_text(xmax),
          data$features[fy],
          real_text(ymin),
          real_text(ymax),
          width,
          height
      ))
    grids <- list()
    for (name in MODEL_NAMES) {
      model <- fit(data,name,features)
      correct <- sum(vapply(data$train,function(row) predict_class(model,row$x) == row$y,logical(1)))
      cv <- cross_validate(analysis,name,features)
      lines <- c(
          lines,
          sprintf(
              "model %s train_accuracy %s cv_accuracy %s",
              name,
              ratio_text(correct,length(data$train)),
              ratio_text(cv$correct,length(data$train))
          )
      )
      results <- lapply(points,function(row) lapply(row,function(point) infer_vector(model,point)))
      grids[[length(grids)+1L]] <- results
      grid <- matrix(" ",height,width)
      counts <- integer(classes)
      for (row in seq_len(height)) for (column in seq_len(width)) {
        predicted <- results[[row]][[column]]$predicted
        grid[row,column] <- upper[predicted]
        counts[predicted] <- counts[predicted]+1L
      }
      lines <- c(lines,frame(grid),paste("cells",paste(paste(upper,counts),collapse=" ")))
    }
    agreement <- uncertainty <- matrix(" ",height,width)
    disagreements <- 0L
    characters <- strsplit(" .:-=+*#%@","",fixed=TRUE)[[1L]]
    for (row in seq_len(height)) for (column in seq_len(width)) {
      distinct <- length(unique(vapply(grids,function(grid) grid[[row]][[column]]$predicted,integer(1))))
      agreement[row,column] <- if (distinct == 1L) "." else as.character(distinct)
      disagreements <- disagreements+(distinct != 1L)
      u <- (1-grids[[3L]][[row]][[column]]$confidence)/(1-1/classes)
      uncertainty[row,column] <- characters[min(9L,floor(10*u))+1L]
    }
    grid <- point_grid(lapply(data$train,function(row) row$x[features]),vapply(data$train,`[[`,integer(1),"y"),lower,
      c(xmin,xmax,ymin,ymax),c(width,height))
    sections[[length(sections)+1L]] <- c(lines,"agreement",frame(agreement),sprintf("disagreement_cells %d",disagreements),
      "uncertainty QDA",frame(uncertainty),"points",frame(grid))
  }
  sections
}
projection_sections <- function(analysis) {
  data <- analysis$data
  statistics <- analysis$models[[1L]]
  n <- length(data$train)
  classes <- length(data$classes)
  d <- length(data$features)
  center <- statistics$center
  within <- between <- matrix(0,d,d)
  for (a in seq_len(d)) for (b in seq_len(d)) {
    within[a,b] <- ordered_sum(vapply(statistics$scatter,function(s) s[a,b],numeric(1)))
    between[a,b] <- ordered_sum(vapply(seq_len(classes),function(k)
      statistics$counts[k]*(statistics$means[[k]][a]-center[a])*(statistics$means[[k]][b]-center[b]),numeric(1)))
  }
  f_values <- (diag(between)/(classes-1L))/(diag(within)/(n-classes))
  feature_order <- order(-f_values,seq_len(d))
  univariate <- "univariate"
  for (rank in seq_len(d)) {
    j <- feature_order[rank]
    univariate <- c(
        univariate,
        sprintf(
            "rank %d %s f %s between %s within %s",
            rank,
            data$features[j],
            real_text(f_values[j]),
            real_text(between[j,j]),
            real_text(within[j,j])
        )
    )
  }
  lower <- cholesky_factor(within)
  transformed <- matrix(0,d,d)
  for (j in seq_len(d)) transformed[,j] <- forward(lower,between[,j])
  whitened <- matrix(0,d,d)
  for (i in seq_len(d)) whitened[,i] <- forward(lower,transformed[i,])
  symmetric <- (whitened+t(whitened))/2
  eigen <- jacobi(symmetric)
  eigenvalue_order <- order(-eigen$values,seq_len(d))
  total <- ordered_sum(eigen$values)
  directions <- lapply(eigenvalue_order[seq_len(2L)],function(i) {
    direction <- backward(lower,eigen$vectors[,i])
    direction <- direction/sqrt(dot_product(direction,direction))
    if (direction[which.max(abs(direction))] < 0) direction <- -direction
    direction
  })
  project <- function(vector) vapply(
      directions,
      function(direction) ordered_sum(direction*(vector-center)),
      numeric(1)
  )
  train_points <- lapply(data$train,function(row) project(row$x))
  test_points <- lapply(data$test,function(row) project(row$x))
  centroids <- lapply(statistics$means,project)
  fisher <- c(paste("fisher features",paste(data$features,collapse=" ")),paste("center",reals(center)),
    sprintf("sweeps %d",eigen$sweeps),paste("eigenvalues",reals(eigen$values[eigenvalue_order])),paste(
        "ratios",
        reals(eigen$values[eigenvalue_order]/total)
    ))
  for (dimension in seq_len(2L)) {
    standardized <- directions[[dimension]]*sqrt(diag(analysis$models[[2L]]$pooled))
    fisher <- c(
        fisher,
        sprintf("direction %d %s",dimension,reals(directions[[dimension]])),
        sprintf("standardized %d %s",dimension,reals(standardized))
    )
  }
  for (k in seq_len(classes)) {
    spread <- vapply(seq_len(2L),function(dimension) {
      indices <- which(vapply(data$train,function(row) row$y == k,logical(1)))
      sqrt(ordered_sum(vapply(
          indices,
          function(i) (train_points[[i]][dimension]-centroids[[k]][dimension])^2,
          numeric(1)
      ))/statistics$counts[k])
    },numeric(1))
    fisher <- c(
        fisher,
        sprintf("centroid %s %s spread %s",data$classes[k],reals(centroids[[k]]),reals(spread))
    )
  }
  for (dimensions in seq_len(2L)) {
    nearest_correct <- function(points,rows) sum(vapply(seq_along(points),function(i) {
      distance <- vapply(
          centroids,
          function(centroid) ordered_sum((points[[i]][seq_len(dimensions)]-centroid[seq_len(dimensions)])^2),
          numeric(1)
      )
      which.min(distance) == rows[[i]]$y
    },logical(1)))
    fisher <- c(fisher,sprintf("nearest_centroid dims %d train %s test %s",dimensions,
      ratio_text(nearest_correct(train_points,data$train),n),ratio_text(
          nearest_correct(test_points,data$test),
          length(data$test)
      )))
  }
  xs <- vapply(train_points,`[`,numeric(1),1L)
  ys <- vapply(train_points,`[`,numeric(1),2L)
  xmin <- min(xs)
  xmax <- max(xs)
  ymin <- min(ys)
  ymax <- max(ys)
  width <- data$params$PLOT_SIZE[1L]
  height <- data$params$PLOT_SIZE[2L]
  letters <- substr(data$classes,1L,1L)
  grid <- point_grid(train_points,vapply(data$train,`[[`,integer(1),"y"),letters,c(xmin,xmax,ymin,ymax),c(width,height))
  for (k in seq_len(classes)) {
    point <- centroids[[k]]
    grid[height-cell(point[2L],ymin,ymax,height),cell(point[1L],xmin,xmax,width)+1L] <- toupper(letters[k])
  }
  scatter <- c(
      sprintf(
          "plot x %s %s y %s %s size %dx%d",
          real_text(xmin),
          real_text(xmax),
          real_text(ymin),
          real_text(ymax),
          width,
          height
      ),
      frame(grid)
  )
  list(univariate,fisher,scatter)
}
main <- function() {
  data <- read_inputs()
  models <- lapply(MODEL_NAMES,function(name) fit(data,name))
  results <- lapply(models,function(model) lapply(data$test,function(row) infer(model,row$x,data$costs)))
  predictions <- lapply(results,function(rows) vapply(rows,`[[`,integer(1),"predicted"))
  analysis <- list(
      data=data,
      models=models,
      results=results,
      predictions=predictions,
      cache=new.env(parent=emptyenv())
  )
  write_lines("models.txt",join_sections(model_sections(analysis)))
  write_lines("predictions.csv",prediction_lines(analysis))
  write_lines("evaluation.txt",join_sections(evaluation_sections(analysis)))
  write_lines("boundaries.txt",join_sections(boundary_sections(analysis)))
  write_lines("projection.txt",join_sections(projection_sections(analysis)))
}
main()
