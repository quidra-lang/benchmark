for (module in c("dataset","gaussian","em","kmeans","report")) source(paste0(module,".R"))
rounded_four <- function(value) as.numeric(dec(value))
parameter_count <- function(k,type) switch(type,FULL=6L*k-1L,TIED=3L*k+2L,DIAG=5L*k-1L,SPHERICAL=4L*k-1L)
point_entropy <- function(r) -ordered_sum(r[r > 0]*log(r[r > 0]))
summarize_run <- function(run,k,type,type_index,n,tolerance) {
  p <- parameter_count(k,type)
  bic <- -2*run$loglik+p*log(n)
  aic <- -2*run$loglik+2*p
  assignment <- vapply(run$records,function(row) which.max(row$responsibilities),integer(1))
  entropy <- ordered_sum(vapply(run$records,function(row) point_entropy(row$responsibilities),numeric(1)))
  trace <- run$trace
  settled <- 0L
  while (!all(abs(trace[seq.int(
      settled+1L,
      length(trace)
  )]-tail(trace,1L)) <= tolerance)) settled <- settled+1L
  increases <- diff(trace)
  largest <- which.max(increases)
  violations <- which(tail(trace,-1L) < head(trace,-1L)-0.000001*abs(head(trace,-1L)))
  run$k <- k
  run$type <- type
  run$type_index <- type_index
  run$parameter_count <- p
  run$bic <- bic
  run$aic <- aic
  run$icl <- bic+2*entropy
  run$entropy <- entropy
  run$mean_entropy <- entropy/n
  run$assignment <- assignment
  run$sizes <- vapply(seq_len(k),function(j) sum(assignment == j),integer(1))
  run$settled_at <- settled
  run$largest_t <- largest
  run$largest_increase <- increases[largest]
  run$violations <- violations
  run
}
ranking <- function(models,criterion) {
  indices <- order(vapply(models,function(m) rounded_four(m[[criterion]]),numeric(1)),vapply(models,function(m) m$parameter_count,integer(1)),
    vapply(models,function(m) m$k,integer(1)),vapply(models,function(m) m$type_index,integer(1)))
  models[indices]
}
contingency <- function(left,right,rows,columns) {
  table <- matrix(0L,rows,columns)
  for (i in seq_along(left)) table[left[i],right[i]] <- table[left[i],right[i]]+1L
  table
}
choose2 <- function(n) {
  n <- as.numeric(n)
  (n*(n-1)) %/% 2
}
adjusted_rand <- function(left,right,rows,columns) {
  table <- contingency(left,right,rows,columns)
  shared <- sum(choose2(table))
  a <- sum(choose2(rowSums(table)))
  b <- sum(choose2(colSums(table)))
  z <- choose2(length(left))
  numerator <- 2*(z*shared-a*b)
  denominator <- z*(a+b)-2*a*b
  if (denominator == 0) return(c(1,1))
  first <- abs(numerator)
  second <- abs(denominator)
  while (second != 0) {
    remainder <- first %% second
    first <- second
    second <- remainder
  }
  numerator <- numerator %/% first
  denominator <- denominator %/% first
  if (denominator < 0) c(-numerator,-denominator) else c(numerator,denominator)
}
ari_text <- function(pair) paste0(
    sprintf("%.0f",pair[1L]),
    "/",
    sprintf("%.0f",pair[2L]),
    " ",
    dec(pair[1L]/pair[2L])
)
partition_metrics <- function(points,labels,k) {
  n <- length(points)
  clusters <- lapply(seq_len(k),function(j) which(labels == j))
  occupied <- which(lengths(clusters) > 0L)
  g <- length(occupied)
  if (g < 2L) return(list(silhouette=NULL,cluster_silhouettes=list(),ch=NULL,db=NULL))
  centers <- lapply(clusters,function(indices) if (length(indices)) c(ordered_sum(vapply(points[indices],function(p) p$x,numeric(1)))/length(indices),
    ordered_sum(vapply(points[indices],function(p) p$y,numeric(1)))/length(indices)) else NULL)
  distances <- matrix(0,n,n)
  for (i in seq_len(n)) for (j in seq_len(n)) distances[i,j] <- distance(
      point_xy(points[[i]]),
      point_xy(points[[j]])
  )
  silhouette <- numeric(n)
  for (i in seq_len(n)) {
    members <- clusters[[labels[i]]]
    if (length(members) == 1L) next
    own <- ordered_sum(distances[i,members[members != i]])/(length(members)-1L)
    other <- min(vapply(
        occupied[occupied != labels[i]],
        function(c) ordered_sum(distances[i,clusters[[c]]])/length(clusters[[c]]),
        numeric(1)
    ))
    silhouette[i] <- (other-own)/max(own,other)
  }
  center <- c(
      ordered_sum(vapply(points,function(p) p$x,numeric(1)))/n,
      ordered_sum(vapply(points,function(p) p$y,numeric(1)))/n
  )
  between <- ordered_sum(vapply(
      occupied,
      function(c) length(clusters[[c]])*squared_distance(centers[[c]],center),
      numeric(1)
  ))
  within <- ordered_sum(vapply(
      seq_len(n),
      function(i) squared_distance(point_xy(points[[i]]),centers[[labels[i]]]),
      numeric(1)
  ))
  ch <- (between/(g-1L))/(within/(n-g))
  scatter <- vapply(
      seq_len(k),
      function(c) if (length(clusters[[c]])) ordered_sum(vapply(
          clusters[[c]],
          function(i) distance(point_xy(points[[i]]),centers[[c]]),
          numeric(1)
      ))/length(clusters[[c]]) else 0,
      numeric(1)
  )
  db <- ordered_sum(vapply(
      occupied,
      function(c) max(vapply(
          occupied[occupied != c],
          function(d) (scatter[c]+scatter[d])/distance(centers[[c]],centers[[d]]),
          numeric(1)
      )),
      numeric(1)
  ))/g
  local <- setNames(
      lapply(occupied,function(c) ordered_sum(silhouette[clusters[[c]]])/length(clusters[[c]])),
      as.character(occupied)
  )
  list(silhouette=ordered_sum(silhouette)/n,cluster_silhouettes=local,ch=ch,db=db)
}
all_permutations <- function(k) {
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
best_matching <- function(left,right,k) {
  table <- contingency(left,right,k,k)
  permutations <- all_permutations(k)
  counts <- vapply(
      permutations,
      function(p) sum(vapply(seq_len(k),function(j) table[p[j],j],integer(1))),
      integer(1)
  )
  best <- which.max(counts)
  list(matching=permutations[[best]],agreement=counts[best],table=table)
}
component_details <- function(model,points,edges,metrics) {
  result <- list()
  mixture <- model$model
  for (k in seq_len(model$k)) {
    members <- which(model$assignment == k)
    cov <- mixture$covariances[[k]]
    mean <- mixture$means[[k]]
    squared <- vapply(points,function(point) mahalanobis(point_xy(point),mean,cov),numeric(1))
    distances <- sqrt(squared[members])
    boundaries <- c(0,edges,Inf)
    observed <- integer(length(boundaries)-1L)
    expected <- numeric(length(observed))
    for (i in seq_along(observed)) {
      low <- boundaries[i]
      high <- boundaries[i+1L]
      observed[i] <- sum(distances >= low & distances < high)
      probability <- exp(-low*low/2)-if (is.infinite(high)) 0 else exp(-high*high/2)
      expected[i] <- length(members)*probability
    }
    chi <- ordered_sum((observed-expected)*(observed-expected)/expected)
    result[[k]] <- list(number=k,weight=mixture$weights[k],mean=mean,cov=cov,size=length(members),
      soft_size=ordered_sum(vapply(
          model$records,
          function(row) row$responsibilities[k],
          numeric(1)
      )),inside_one=sum(squared[members] <= 1),inside_two=sum(squared[members] <= 4),
      silhouette=metrics$cluster_silhouettes[[as.character(k)]],observed=observed,expected=expected,chi=chi,geometry=eigen_data(cov))
  }
  result
}
cluster_entropy <- function(clusters,records) {
  total <- 0
  for (record in records) {
    probabilities <- vapply(
        clusters,
        function(cluster) ordered_sum(record$responsibilities[cluster]),
        numeric(1)
    )
    total <- total+point_entropy(probabilities)
  }
  total
}
merging_block <- function(model) {
  clusters <- lapply(seq_len(model$k),function(k) k)
  lines <- c("merging",paste("start entropy",dec(cluster_entropy(clusters,model$records))))
  step <- 0L
  while (length(clusters) > 1L) {
    candidates <- list()
    for (i in seq_len(length(clusters)-1L)) for (j in seq.int(i+1L,length(clusters))) {
      proposed <- clusters
      proposed[[i]] <- sort(c(proposed[[i]],proposed[[j]]))
      proposed <- proposed[-j]
      proposed <- proposed[order(vapply(proposed,`[`,integer(1),1L))]
      entropy <- cluster_entropy(proposed,model$records)
      candidates[[length(candidates)+1L]] <- list(i=i,j=j,entropy=entropy,clusters=proposed)
    }
    ordering <- order(
        vapply(candidates,function(c) rounded_four(c$entropy),numeric(1)),
        vapply(candidates,function(c) c$i,integer(1)),
        vapply(candidates,function(c) c$j,integer(1))
    )
    chosen <- candidates[[ordering[1L]]]
    assigned <- vapply(
        model$records,
        function(row) which.max(vapply(
            chosen$clusters,
            function(cluster) ordered_sum(row$responsibilities[cluster]),
            numeric(1)
        )),
        integer(1)
    )
    sizes <- vapply(seq_along(chosen$clusters),function(j) sum(assigned == j),integer(1))
    step <- step+1L
    lines <- c(
        lines,
        paste(
            "step",
            step,
            "merge",
            paste(clusters[[chosen$i]],collapse="+"),
            paste(clusters[[chosen$j]],collapse="+"),
            "entropy",
            dec(chosen$entropy),
            "sizes",
            integer_values(sizes)
        )
    )
    clusters <- chosen$clusters
  }
  lines
}
refit_from_kmeans <- function(model,kmeans,points,settings) {
  weights <- numeric(model$k)
  means <- covariances <- list()
  for (j in seq_len(model$k)) {
    members <- points[kmeans$assignment == j]
    center <- kmeans$centers[[j]]
    n <- length(members)
    weights[j] <- n/length(points)
    means[[j]] <- center
    a <- ordered_sum(vapply(members,function(p) (p$x-center[1L])^2,numeric(1)))/n
    b <- ordered_sum(vapply(members,function(p) (p$x-center[1L])*(p$y-center[2L]),numeric(1)))/n
    c <- ordered_sum(vapply(members,function(p) (p$y-center[2L])^2,numeric(1)))/n
    covariances[[j]] <- c(a+settings$epsilon,b,c+settings$epsilon)
  }
  initial <- list(weights=weights,means=means,covariances=covariances,type="")
  run <- run_em(points,initial,model$type,settings$iterations,settings$epsilon)
  summarize_run(run,model$k,model$type,model$type_index,length(points),settings$settle)
}
model_blocks <- function(models) {
  blocks <- list()
  for (model in models) {
    lines <- c(paste0("model K=",model$k," type=",model$type),paste("parameters",model$parameter_count),paste("loglik",dec(model$loglik)),paste("bic",dec(model$bic)),paste("aic",dec(model$aic)),paste("icl",dec(model$icl)),
      paste("mean_entropy",dec(model$mean_entropy)),paste("settled_at",model$settled_at),paste(
          "largest_increase iteration",
          model$largest_t,
          "value",
          dec(model$largest_increase)
      ),paste("violations",length(model$violations)),paste("sizes",integer_values(model$sizes)))
    for (j in seq_len(model$k)) {
      geometry <- eigen_data(model$model$covariances[[j]])
      lines <- c(
          lines,
          paste(
              "component",
              j,
              "weight",
              dec(model$model$weights[j]),
              "mean",
              real_values(model$model$means[[j]]),
              "cov",
              real_values(model$model$covariances[[j]]),
              "axes",
              real_values(geometry$axes),
              "angle",
              dec(geometry$angle)
          )
      )
    }
    blocks[[length(blocks)+1L]] <- lines
  }
  blocks
}
selection_blocks <- function(models,selected,kmeans,points,initial,settings) {
  ranked <- setNames(lapply(c("bic","aic","icl"),function(key) ranking(models,key)),c("bic","aic","icl"))
  model_key <- function(model) paste(model$k,model$type,sep=",")
  ranks <- lapply(ranked,function(rows) setNames(seq_along(rows),vapply(rows,model_key,character(1))))
  lines <- c("ranking by bic","rank K type parameters loglik bic delta_bic aic aic_rank icl icl_rank")
  for (rank in seq_along(ranked$bic)) {
    model <- ranked$bic[[rank]]
    delta <- rounded_four(model$bic)-rounded_four(selected$bic)
    lines <- c(
        lines,
        paste(
            rank,
            model$k,
            model$type,
            model$parameter_count,
            dec(model$loglik),
            dec(model$bic),
            dec(delta),
            dec(model$aic),
            ranks$aic[[model_key(model)]],
            dec(model$icl),
            ranks$icl[[model_key(model)]]
        )
    )
  }
  for (label in c("selected","best_aic","best_icl")) {
    key <- switch(label,selected="bic",best_aic="aic",best_icl="icl")
    model <- ranked[[key]][[1L]]
    lines <- c(lines,paste0(label," K=",model$k," type=",model$type))
  }
  blocks <- list(lines)
  lines <- "best K per type"
  for (type in settings$types) {
    same <- Filter(function(model) model$type == type,models)
    lines <- c(
        lines,
        paste(
            type,
            "bic",
            ranking(same,"bic")[[1L]]$k,
            "aic",
            ranking(same,"aic")[[1L]]$k,
            "icl",
            ranking(same,"icl")[[1L]]$k
        )
    )
  }
  blocks[[length(blocks)+1L]] <- lines
  previous <- NULL
  for (k in settings$ks) {
    model <- ranking(Filter(function(m) m$k == k,models),"bic")[[1L]]
    km <- kmeans[[as.character(k)]]
    gm <- partition_metrics(points,model$assignment,k)
    ks <- partition_metrics(points,km$assignment,k)
    lines <- c(paste0("K=",k," type=",model$type," bic ",dec(model$bic)),paste("  kmeans iterations",km$iterations,"inertia",dec(km$inertia)),
      paste("  ari",ari_text(adjusted_rand(model$assignment,km$assignment,k,k))),paste(
          "  silhouette gmm",
          optional(gm$silhouette),
          "kmeans",
          optional(ks$silhouette)
      ),
      paste(
          "  calinski_harabasz gmm",
          optional(gm$ch),
          "kmeans",
          optional(ks$ch)
      ),paste("  davies_bouldin gmm",optional(gm$db),"kmeans",optional(ks$db)))
    if (!is.null(previous)) {
      table <- contingency(previous$assignment,model$assignment,previous$k,k)
      parents <- character(k)
      shared <- integer(k)
      for (j in seq_len(k)) {
        counts <- table[,j]
        parent <- which.max(counts)
        parents[j] <- if (sum(counts) == 0L) "-" else as.character(parent)
        shared[j] <- if (sum(counts) == 0L) 0L else counts[parent]
      }
      lines <- c(
          lines,
          paste0("  parents K=",previous$k," ",paste(parents,collapse=" ")," shared ",integer_values(shared))
      )
    }
    blocks[[length(blocks)+1L]] <- lines
    previous <- model
  }
  lines <- "violations"
  for (model in models) for (t in model$violations) lines <- c(
      lines,
      paste0(
          "K=",
          model$k,
          " type=",
          model$type,
          " iteration ",
          t,
          " previous ",
          dec(model$trace[t]),
          " current ",
          dec(model$trace[t+1L])
      )
  )
  if (length(lines) == 1L) lines <- c(lines,"none")
  blocks[[length(blocks)+1L]] <- lines
  metrics <- partition_metrics(points,selected$assignment,selected$k)
  details <- component_details(selected,points,settings$gof_edges,metrics)
  lines <- "selected components"
  for (component in details) {
    geometry <- component$geometry
    sx <- geometry$axes[1L]
    sy <- geometry$axes[2L]
    lines <- c(lines,paste("component",component$number,"weight",dec(component$weight),"size",component$size,"soft_size",dec(component$soft_size),"mean",real_values(component$mean)),
      paste("  cov",real_values(component$cov),"corr",dec(geometry$correlation)),paste(
          "  eigen",
          dec(geometry$leading),
          dec(geometry$trailing),
          "direction",
          real_values(geometry$direction),
          "angle",
          dec(geometry$angle)
      ),
      paste("  axes_1sigma",dec(sx),dec(sy),"axes_2sigma",dec(2*sx),dec(2*sy)),paste(
          "  inside_1sigma",
          component$inside_one,
          "inside_2sigma",
          component$inside_two,
          "area_1sigma",
          dec(geometry$area)
      ),
      paste("  silhouette",optional(component$silhouette)),paste(
          "  gof observed",
          integer_values(component$observed),
          "expected",
          real_values(component$expected),
          "chi2",
          dec(component$chi)
      ))
  }
  blocks[[length(blocks)+1L]] <- lines
  lines <- "overlap"
  mixture <- selected$model
  k <- selected$k
  if (k > 1L) for (a in seq_len(k-1L)) for (b in seq.int(a+1L,k)) {
    overlap <- bhattacharyya(
        mixture$means[[a]],
        mixture$covariances[[a]],
        mixture$means[[b]],
        mixture$covariances[[b]]
    )
    shared <- ordered_sum(vapply(
        selected$records,
        function(row) row$responsibilities[a]*row$responsibilities[b],
        numeric(1)
    ))
    lines <- c(
        lines,
        paste0(
            a,
            "-",
            b,
            " bhattacharyya ",
            dec(overlap$distance),
            " coefficient ",
            dec(overlap$coefficient),
            " shared ",
            dec(shared)
        )
    )
  }
  if (length(lines) == 1L) lines <- c(lines,"none")
  blocks <- c(blocks,list(lines,merging_block(selected)))
  km <- kmeans[[as.character(k)]]
  matched <- best_matching(selected$assignment,km$assignment,k)
  matching <- matched$matching
  agreement <- matched$agreement
  table <- matched$table
  lines <- c(
      paste0("kmeans K=",k),
      paste("iterations",km$iterations),
      paste("inertia",dec(km$inertia)),
      paste("sizes",integer_values(km$sizes))
  )
  for (j in seq_along(km$centers)) lines <- c(lines,paste("center",j,real_values(km$centers[[j]])))
  lines <- c(lines,"contingency",vapply(seq_len(k),function(j) integer_values(table[j,]),character(1)),paste("ari",ari_text(adjusted_rand(selected$assignment,km$assignment,k,k))),
    paste("matching",integer_values(matching)),paste0(
        "agreement ",
        agreement,
        "/",
        length(points),
        " ",
        dec(agreement/length(points))
    ))
  disagree <- 0L
  for (i in seq_along(points)) {
    component <- selected$assignment[i]
    cluster <- km$assignment[i]
    if (matching[cluster] != component) {
      disagree <- disagree+1L
      lines <- c(
          lines,
          paste(
              "disagree",
              points[[i]]$id,
              "gmm",
              component,
              "kmeans",
              cluster,
              "max",
              dec(max(selected$records[[i]]$responsibilities))
          )
      )
    }
  }
  lines <- c(lines,paste("disagreements",disagree))
  blocks[[length(blocks)+1L]] <- lines
  refit <- refit_from_kmeans(selected,km,points,settings)
  blocks[[length(blocks)+1L]] <- c(paste0("refit_from_kmeans K=",k," type=",selected$type),paste("loglik",dec(refit$loglik),"bic",dec(refit$bic),"settled_at",refit$settled_at),
    paste("sizes",integer_values(refit$sizes)),paste(
        "ari_vs_selected",
        ari_text(adjusted_rand(selected$assignment,refit$assignment,k,k))
    ))
  folds <- settings$cv_folds
  lines <- paste0("cross_validation K=",k," type=",selected$type," folds ",folds)
  scores <- numeric(folds)
  assignment <- (seq_along(points)-1L) %% folds
  for (f in seq_len(folds)-1L) {
    training <- points[assignment != f]
    testing <- points[assignment == f]
    fitted <- run_em(training,initial[[as.character(k)]],selected$type,settings$iterations,settings$epsilon)
    test <- responsibilities(testing,fitted$model)
    scores[f+1L] <- test$loglik/length(testing)
    lines <- c(
        lines,
        paste(
            "fold",
            f+1L,
            "train",
            length(training),
            "test",
            length(testing),
            "train_loglik",
            dec(fitted$loglik/length(training)),
            "test_loglik",
            dec(scores[f+1L])
        )
    )
  }
  lines <- c(lines,paste("mean_test_loglik",dec(ordered_sum(scores)/folds)))
  blocks[[length(blocks)+1L]] <- lines
  maxima <- vapply(selected$records,function(row) max(row$responsibilities),numeric(1))
  uncertain <- which(maxima < settings$uncertain)
  uncertain <- uncertain[order(vapply(maxima[uncertain],rounded_four,numeric(1)),uncertain)]
  lines <- paste("uncertain threshold",dec(settings$uncertain))
  for (i in uncertain) lines <- c(
      lines,
      paste(
          points[[i]]$id,
          "component",
          selected$assignment[i],
          "max",
          dec(maxima[i]),
          "responsibilities",
          real_values(selected$records[[i]]$responsibilities)
      )
  )
  lines <- c(lines,paste("count",length(uncertain)))
  blocks[[length(blocks)+1L]] <- lines
  log_density <- vapply(selected$records,function(row) row$log_density,numeric(1))
  outliers <- which(log_density < settings$low_density)
  outliers <- outliers[order(vapply(log_density[outliers],rounded_four,numeric(1)),outliers)]
  lines <- paste("outliers threshold",dec(settings$low_density))
  for (i in outliers) {
    component <- selected$assignment[i]
    q <- mahalanobis(point_xy(points[[i]]),mixture$means[[component]],mixture$covariances[[component]])
    lines <- c(lines,paste(points[[i]]$id,"component",component,"log_density",dec(log_density[i]),"q",dec(q)))
  }
  lines <- c(lines,paste("count",length(outliers)))
  blocks[[length(blocks)+1L]] <- lines
  blocks
}
plot_maps <- function(model,points,settings) {
  xmin <- settings$map_x[1L]
  xmax <- settings$map_x[2L]
  ymin <- settings$map_y[1L]
  ymax <- settings$map_y[2L]
  width <- settings$map_size[1L]
  height <- settings$map_size[2L]
  dx <- (xmax-xmin)/width
  dy <- (ymax-ymin)/height
  center <- function(row,column) c(xmin+(column-0.5)*dx,ymax-(row-0.5)*dy)
  mixture <- model$model
  k <- model$k
  densities <- matrix(0,height,width)
  regions <- uncertainty <- point_map <- matrix(" ",height,width)
  for (r in seq_len(height)) for (column in seq_len(width)) {
    coordinates <- center(r,column)
    scores <- vapply(
        seq_len(k),
        function(j) weighted_log_density(
            coordinates,
            mixture$weights[j],
            mixture$means[[j]],
            mixture$covariances[[j]]
        ),
        numeric(1)
    )
    densities[r,column] <- ordered_sum(exp(scores))
    regions[r,column] <- as.character(which.max(scores))
    if (k > 1L) {
      exponentials <- exp(scores-max(scores))
      probabilities <- exponentials/ordered_sum(exponentials)
      level <- min(9L,max(0L,floor(10*point_entropy(probabilities)/log(k))))
      uncertainty[r,column] <- LEVELS[level+1L]
    }
  }
  maximum_density <- max(densities)
  density_map <- matrix(" ",height,width)
  counts <- integer(10L)
  mass <- 0
  for (r in seq_len(height)) for (column in seq_len(width)) {
    level <- min(9L,floor(10*densities[r,column]/maximum_density))
    counts[level+1L] <- counts[level+1L]+1L
    density_map[r,column] <- LEVELS[level+1L]
    mass <- mass+densities[r,column]
  }
  mass <- mass*dx*dy
  cell <- function(point) c(floor((point[1L]-xmin)/dx)+1L,floor((ymax-point[2L])/dy)+1L)
  for (j in seq_along(mixture$means)) {
    position <- cell(mixture$means[[j]])
    column <- position[1L]
    r <- position[2L]
    if (column >= 1L && column <= width && r >= 1L && r <= height) density_map[r,column] <- as.character(j)
  }
  bins <- matrix(0L,height,width)
  outside <- 0L
  for (i in seq_along(points)) {
    position <- cell(point_xy(points[[i]]))
    column <- position[1L]
    r <- position[2L]
    label <- model$assignment[i]
    if (column >= 1L && column <= width && r >= 1L && r <= height) {
      if (bins[r,column] == 0L) bins[r,column] <- label else if (bins[r,column] != label) bins[
          r,
          column
      ] <- -1L
    } else outside <- outside+1L
  }
  for (r in seq_len(height)) for (column in seq_len(width)) {
    if (bins[r,column] != 0L) {
      point_map[r,column] <- if (bins[r,column] == -1L) "*" else as.character(bins[r,column])
      next
    }
    contour <- FALSE
    for (j in seq_len(k)) {
      if (mahalanobis(center(r,column),mixture$means[[j]],mixture$covariances[[j]]) > 4) next
      neighbors <- list(c(r-1L,column),c(r+1L,column),c(r,column-1L),c(r,column+1L))
      for (neighbor in neighbors) {
        rr <- neighbor[1L]
        cc <- neighbor[2L]
        if (rr >= 1L && rr <= height && cc >= 1L && cc <= width && mahalanobis(
            center(rr,cc),
            mixture$means[[j]],
            mixture$covariances[[j]]
        ) > 4) {
          contour <- TRUE
          break
        }
      }
      if (contour) break
    }
    point_map[r,column] <- if (contour) "." else " "
  }
  lines <- c(paste0("density K=",k," type=",model$type),paste("x",dec(xmin),dec(xmax),"y",dec(ymin),dec(ymax),"grid",paste0(width,"x",height)),
    paste("max_density",dec(maximum_density,6L),"mass_in_map",dec(mass)),framed(density_map))
  for (level in seq_len(10L)-1L) lines <- c(
      lines,
      paste0(
          "level ",
          level,
          ' "',
          LEVELS[level+1L],
          '" from ',
          dec(level*maximum_density/10,6L),
          " cells ",
          counts[level+1L]
      )
  )
  c(
      lines,
      "",
      "regions",
      framed(regions),
      "",
      "uncertainty",
      framed(uncertainty),
      "",
      "points",
      framed(point_map),
      paste("outside",outside)
  )
}
main <- function() {
  inputs <- read_all()
  points <- inputs$points
  initial <- inputs$initial
  settings <- inputs$settings
  models <- list()
  for (k in settings$ks) for (type_index in seq_along(settings$types)) {
    type <- settings$types[type_index]
    run <- run_em(points,initial[[as.character(k)]],type,settings$iterations,settings$epsilon)
    models[[length(models)+1L]] <- summarize_run(run,k,type,type_index,length(points),settings$settle)
  }
  selected <- ranking(models,"bic")[[1L]]
  kmeans <- setNames(
      lapply(
          settings$ks,
          function(k) run_kmeans(points,initial[[as.character(k)]]$means,settings$kmeans_iterations)
      ),
      as.character(settings$ks)
  )
  trace <- "K,type,iteration,loglik"
  for (model in models) for (t in seq_along(model$trace)) trace <- c(
      trace,
      paste(model$k,model$type,t-1L,dec(model$trace[t]),sep=",")
  )
  assignments_text <- "id,component,max_responsibility,log_density,kmeans_cluster"
  for (i in seq_along(points)) {
    row <- selected$records[[i]]
    assignments_text <- c(
        assignments_text,
        paste(
            points[[i]]$id,
            selected$assignment[i],
            dec(max(row$responsibilities)),
            dec(row$log_density),
            kmeans[[as.character(selected$k)]]$assignment[i],
            sep=","
        )
    )
  }
  write_blocks("models.txt",model_blocks(models))
  write_lines("loglik_trace.csv",trace)
  write_lines("assignments.csv",assignments_text)
  write_blocks("selection.txt",selection_blocks(models,selected,kmeans,points,initial,settings))
  write_lines("density_map.txt",plot_maps(selected,points,settings))
}
main()
