for (module in c("ratings","evaluation","neighborhood","factorization","report")) source(paste0(module,".R"))
METHODS <- c("GLOBAL","BASELINE","USER_KNN","ITEM_KNN","SLOPE_ONE","SVD","ALS")
RANKINGS <- c("POPULAR",METHODS[-1L])
KNN_METHODS <- c("USER_KNN","ITEM_KNN")
integer_text <- function(value) sprintf("%.0f",value)
fmt <- function(pattern,...) {
  arguments <- lapply(list(...),function(value) if (is.numeric(value)) integer_text(value) else value)
  do.call(sprintf,c(list(pattern),arguments))
}
prediction <- function(value,fallback=FALSE,neighbors=0L,similarity=0,top=0L)
  list(value=value,fallback=fallback,neighbors=neighbors,similarity=similarity,top=top)
baseline <- function(r,u,i) (r$data$mean+r$user_bias[u])+r$item_bias[i]
train <- function(data) {
  params <- data$params
  user_bias <- numeric(length(data$users))
  item_bias <- numeric(length(data$items))
  base <- function(u,i) (data$mean+user_bias[u])+item_bias[i]
  log <- list()
  errors <- list(GLOBAL=training_rmse(data$training,function(u,i) data$mean))
  for (sweep in seq_len(10L)) {
    for (i in seq_along(data$items)) {
      value <- sequential_sum(data$ratings[data$by_item[[i]],i]-data$mean-user_bias[data$by_item[[i]]])
      item_bias[i] <- value/(params$BIAS_REG[1L]+data$item_counts[i])
    }
    for (u in seq_along(data$users)) {
      value <- sequential_sum(data$ratings[u,data$by_user[[u]]]-data$mean-item_bias[data$by_user[[u]]])
      user_bias[u] <- value/(params$BIAS_REG[2L]+data$user_counts[u])
    }
    log[[length(log)+1L]] <- list(method="BASELINE",epoch=sweep,error=training_rmse(data$training,base))
  }
  errors$BASELINE <- tail(log,1L)[[1L]]$error
  svd <- train_svd(data)
  als <- train_als(data,user_bias,item_bias)
  log <- c(log,svd$log,als$log)
  errors$SVD <- tail(svd$log,1L)[[1L]]$error
  errors$ALS <- tail(als$log,1L)[[1L]]$error
  popularity <- order(-data$item_counts,-data$item_means,data$items)
  head_count <- length(data$items) %/% 5L
  list2env(list(data=data,params=params,user_bias=user_bias,item_bias=item_bias,log=log,train_errors=errors,
    svd=svd$model,als=als$model,neighborhood=build_neighborhood(data,params$SHRINKAGE[1L]),
    popularity=popularity,head=head_count,popular=popularity[seq_len(head_count)],
    predictions=setNames(rep(list(list()),length(METHODS)),METHODS),
    clipped=setNames(rep(list(numeric()),length(METHODS)),METHODS),errors=setNames(
        rep(list(numeric()),length(METHODS)),
        METHODS
    ),
    metrics=list(),relevant=vector("list",length(data$users)),evaluated=integer(),
    rankings=vector("list",length(data$users)),ranking_predictions=vector(
        "list",
        length(data$users)
    )),parent=emptyenv())
}
predict_rating <- function(r,method,u,i,k=r$params$NEIGHBORS[1L]) {
  data <- r$data
  n <- r$neighborhood
  if (method == "GLOBAL") return(prediction(data$mean))
  if (method == "BASELINE") return(prediction(baseline(r,u,i)))
  if (method == "SVD") return(prediction(factor_prediction(r$svd,u,i)))
  if (method == "ALS") return(prediction(factor_prediction(r$als,u,i)))
  if (method == "SLOPE_ONE") {
    numerator <- 0
    denominator <- 0L
    for (other in data$by_user[[u]]) {
      common <- n$counts[i,other]
      if (!common) next
      numerator <- numerator+(deviation(n,i,other)+data$ratings[u,other])*common
      denominator <- denominator+common
    }
    if (!denominator) return(prediction(baseline(r,u,i),fallback=TRUE))
    return(prediction(numerator/denominator))
  }
  is_user <- method == "USER_KNN"
  candidates <- list()
  for (other in if (is_user) data$by_item[[i]] else data$by_user[[u]]) {
    similarity <- if (is_user) n$user[u,other] else n$item[i,other]
    if (!is.na(similarity) && similarity > r$params$MIN_SIMILARITY[1L]) candidates[[length(candidates)+1L]] <- c(
        other,
        similarity
    )
  }
  selected <- largest_neighbors(candidates,k)
  if (!length(selected)) return(prediction(baseline(r,u,i),fallback=TRUE))
  numerator <- denominator <- 0
  for (neighbor in selected) {
    other <- neighbor[1L]
    similarity <- neighbor[2L]
    residual <- if (is_user) data$ratings[other,i]-data$user_means[other] else data$ratings[
        u,
        other
    ]-data$item_means[other]
    numerator <- numerator+similarity*residual
    denominator <- denominator+similarity
  }
  mean <- if (is_user) data$user_means[u] else data$item_means[i]
  prediction(
      mean+numerator/denominator,
      neighbors=length(selected),
      similarity=denominator/length(selected),
      top=selected[[1L]][1L]
  )
}
predict_tests <- function(r) {
  lines <- paste0("user,item,actual,",paste(METHODS,collapse=","))
  for (row in r$data$test) {
    fields <- integer_text(c(r$data$users[row$u],r$data$items[row$i],row$rating))
    for (method in METHODS) {
      p <- predict_rating(r,method,row$u,row$i)
      q <- clip(p$value)
      r$predictions[[method]][[length(r$predictions[[method]])+1L]] <- p
      r$clipped[[method]] <- c(r$clipped[[method]],q)
      r$errors[[method]] <- c(r$errors[[method]],q-row$rating)
      fields <- c(fields,real_text(q))
    }
    lines <- c(lines,paste(fields,collapse=","))
  }
  for (method in METHODS) {
    predictions <- r$predictions[[method]]
    r$metrics[[method]] <- list(rmse=rmse(r$errors[[method]]),mae=mae(r$errors[[method]]),
      clipped=sum(vapply(predictions,function(p) p$value < 1 || p$value > 5,logical(1))),
      fallback=sum(vapply(predictions,`[[`,logical(1),"fallback")))
  }
  lines
}
prepare_rankings <- function(r) {
  data <- r$data
  for (row in data$test) if (row$rating >= 4L) r$relevant[[row$u]] <- unique(c(r$relevant[[row$u]],row$i))
  r$evaluated <- which(lengths(r$relevant) > 0L)
  requested <- match(r$params$RECOMMEND_USERS,data$users)
  users <- sort(unique(c(r$evaluated,requested[!is.na(requested)])))
  for (u in users) {
    candidates <- which(data$ratings[u,] == 0)
    lists <- list(POPULAR=r$popularity[data$ratings[u,r$popularity] == 0])
    predictions <- list()
    for (method in METHODS[-1L]) {
      values <- setNames(lapply(candidates,function(i) predict_rating(r,method,u,i)),as.character(candidates))
      predictions[[method]] <- values
      lists[[method]] <- candidates[order(-vapply(values,`[[`,numeric(1),"value"),data$items[candidates])]
    }
    r$rankings[[u]] <- lists
    r$ranking_predictions[[u]] <- predictions
  }
}
count_summary <- function(counts) {
  ordered <- sort(counts)
  n <- length(ordered)
  median <- if (n %% 2L) ordered[n %/% 2L+1L] else (ordered[n %/% 2L]+ordered[n %/% 2L+1L])/2
  fmt("min %s median %s max %s",ordered[1L],real_text(median),tail(ordered,1L))
}
errors_for <- function(r,indices,metric=rmse) paste(vapply(METHODS,function(method)
  paste(method,real_text(metric(r$errors[[method]][indices]))),character(1)),collapse=" ")
group_number <- function(value,bounds) sum(value >= bounds)+1L
evaluation_sections <- function(r) {
  data <- r$data
  params <- r$params
  n <- r$neighborhood
  m <- length(data$test)
  theta <- params$MIN_SIMILARITY[1L]
  times <- vapply(data$training,`[[`,numeric(1),"time")
  first_time <- min(times)
  last_time <- max(times)
  histogram <- vapply(
      seq_len(5L),
      function(rating) sum(vapply(data$training,function(row) row$rating == rating,logical(1))),
      numeric(1)
  )
  user_pairs <- sum(!is.na(n$user)) %/% 2L
  item_pairs <- sum(!is.na(n$item)) %/% 2L
  user_usable <- sum(n$user > theta,na.rm=TRUE) %/% 2L
  item_usable <- sum(n$item > theta,na.rm=TRUE) %/% 2L
  slope_pairs <- sum(n$counts > 0L) %/% 2L
  sections <- list(c(fmt("data users %s items %s catalog %s ratings %s test %s",length(data$users),length(data$items),data$catalog,length(data$training),m),
    fmt(
        "density %s global_mean %s",
        real_text(length(data$training)/(length(data$users)*length(data$items))),
        real_text(data$mean)
    ),
    paste("histogram",paste(histogram,collapse=" ")),paste(
        "user_ratings",
        count_summary(data$user_counts)
    ),paste(
        "item_ratings",
        count_summary(data$item_counts)
    ),
    fmt(
        "timestamps first %s last %s",
        first_time,
        last_time
    ),fmt("cold_items %s",data$catalog-length(data$items)),
    fmt(
        "similarities user_pairs %s usable %s item_pairs %s usable %s slope_pairs %s",
        user_pairs,
        user_usable,
        item_pairs,
        item_usable,
        slope_pairs
    )))
  lines <- "genre_stats"
  genres <- sort(unique(unlist(data$genres,use.names=FALSE)),method="radix")
  for (genre in genres) {
    items <- which(vapply(data$genres,function(genres) genre %in% genres,logical(1)))
    ratings <- sum(data$item_counts[items])
    high <- sum(vapply(data$training,function(row) row$i %in% items && row$rating >= 4L,logical(1)))
    lines <- c(lines,fmt("genre %s items %s ratings %s high %s",genre,length(items),ratings,high))
  }
  sections[[length(sections)+1L]] <- lines
  buckets <- params$TIME_BUCKETS[1L]
  counts <- totals <- numeric(buckets)
  users <- rep(list(integer()),buckets)
  for (row in data$training) {
    bucket <- ((row$time-first_time)*buckets) %/% (last_time-first_time+1)+1L
    counts[bucket] <- counts[bucket]+1L
    totals[bucket] <- totals[bucket]+row$rating
    users[[bucket]] <- unique(c(users[[bucket]],row$u))
  }
  lines <- fmt("time_buckets %s",buckets)
  for (b in seq_len(buckets)) lines <- c(
      lines,
      fmt(
          "bucket %s ratings %s users %s mean %s",
          b,
          counts[b],
          length(users[[b]]),
          real_text(if (counts[b]) totals[b]/counts[b] else NULL)
      )
  )
  sections[[length(sections)+1L]] <- lines
  lines <- "rating_metrics"
  for (method in METHODS) {
    metric <- r$metrics[[method]]
    lines <- c(
        lines,
        fmt(
            "%s rmse %s mae %s clipped %s fallback %s",
            method,
            real_text(metric$rmse),
            real_text(metric$mae),
            metric$clipped,
            metric$fallback
        )
    )
  }
  sections[[length(sections)+1L]] <- lines
  lines <- "generalization"
  for (method in c("GLOBAL","BASELINE","SVD","ALS")) {
    train_error <- r$train_errors[[method]]
    test_error <- r$metrics[[method]]$rmse
    lines <- c(
        lines,
        fmt(
            "%s train %s test %s gap %s",
            method,
            real_text(train_error),
            real_text(test_error),
            real_text(test_error-train_error)
        )
    )
  }
  sections[[length(sections)+1L]] <- lines
  lines <- fmt("neighborhoods k %s",params$NEIGHBORS[1L])
  for (method in KNN_METHODS) {
    used <- Filter(function(p) !p$fallback,r$predictions[[method]])
    w <- length(used)
    mean_neighbors <- if (w) sum(vapply(used,`[[`,numeric(1),"neighbors"))/w else NULL
    mean_similarity <- if (w) sequential_sum(vapply(used,`[[`,numeric(1),"similarity"))/w else NULL
    lines <- c(
        lines,
        fmt(
            "%s predictions %s with_neighbors %s mean_neighbors %s mean_similarity %s",
            method,
            m,
            w,
            real_text(mean_neighbors),
            real_text(mean_similarity)
        )
    )
  }
  sections[[length(sections)+1L]] <- lines
  actual <- vapply(data$test,`[[`,numeric(1),"rating")
  actual_mean <- sum(actual)/m
  actual_variation <- sequential_sum((actual-actual_mean)*(actual-actual_mean))
  lines <- fmt(
      "prediction_stats actual mean %s std %s",
      real_text(actual_mean),
      real_text(sqrt(actual_variation/m))
  )
  for (method in METHODS) {
    values <- r$clipped[[method]]
    mean <- sequential_sum(values)/m
    variation <- sequential_sum((values-mean)*(values-mean))
    correlation <- if (min(values) != max(values) && min(actual) != max(actual))
      sequential_sum((values-mean)*(actual-actual_mean))/sqrt(variation*actual_variation) else NULL
    lines <- c(
        lines,
        fmt(
            "%s mean %s std %s correlation %s",
            method,
            real_text(mean),
            real_text(sqrt(variation/m)),
            real_text(correlation)
        )
    )
  }
  sections[[length(sections)+1L]] <- lines
  lines <- "error_bins edges 0.5 1.0 1.5 2.0"
  for (method in METHODS) {
    bins <- integer(5L)
    for (error in r$errors[[method]]) {
      bin <- sum(abs(error) >= c(0.5,1,1.5,2))+1L
      bins[bin] <- bins[bin]+1L
    }
    lines <- c(lines,paste(method,paste(bins,collapse=" ")))
  }
  sections[[length(sections)+1L]] <- lines
  lines <- "comparison"
  for (a in seq_len(6L)) for (b in seq.int(a+1L,7L)) {
    left <- abs(r$errors[[METHODS[a]]])
    right <- abs(r$errors[[METHODS[b]]])
    wins <- sum(left < right)
    ties <- sum(left == right)
    lines <- c(lines,fmt("%s %s wins %s ties %s losses %s",METHODS[a],METHODS[b],wins,ties,m-wins-ties))
  }
  sections[[length(sections)+1L]] <- lines
  for (kind in c("user","item")) {
    bounds <- params[[if (kind == "user") "USER_GROUPS" else "ITEM_GROUPS"]]
    counts <- if (kind == "user") data$user_counts else data$item_counts
    grouped <- rep(list(integer()),length(bounds)+1L)
    for (i in seq_along(data$test)) {
      row <- data$test[[i]]
      index <- if (kind == "user") row$u else row$i
      g <- group_number(counts[index],bounds)
      grouped[[g]] <- c(grouped[[g]],i)
    }
    lines <- paste0(kind,"_groups bounds ",paste(integer_text(bounds),collapse=" "))
    for (g in seq_along(grouped)) {
      indices <- grouped[[g]]
      lower <- if (g == 1L) 1L else bounds[g-1L]
      upper <- if (g <= length(bounds)) integer_text(bounds[g]-1L) else "-"
      lines <- c(
          lines,
          fmt("group %s from %s to %s pairs %s %s",g,lower,upper,length(indices),errors_for(r,indices))
      )
    }
    sections[[length(sections)+1L]] <- lines
  }
  lines <- "by_rating"
  for (rating in seq_len(5L)) {
    indices <- which(actual == rating)
    lines <- c(lines,fmt("rating %s pairs %s %s",rating,length(indices),errors_for(r,indices,mae)))
  }
  sections[[length(sections)+1L]] <- lines
  genres <- sort(
      unique(unlist(lapply(data$test,function(row) data$genres[[row$i]]),use.names=FALSE)),
      method="radix"
  )
  lines <- "genres"
  for (genre in genres) {
    indices <- which(vapply(data$test,function(row) genre %in% data$genres[[row$i]],logical(1)))
    lines <- c(lines,fmt("genre %s pairs %s %s",genre,length(indices),errors_for(r,indices)))
  }
  sections[[length(sections)+1L]] <- lines
  evaluated <- r$evaluated
  e <- length(evaluated)
  relevant_count <- sum(lengths(r$relevant[evaluated]))
  lines <- fmt("ranking users %s relevant %s",e,relevant_count)
  for (cutoff in params$CUTOFFS) {
    lines <- c(lines,fmt("cutoff %s",cutoff))
    for (method in RANKINGS) {
      metrics <- lapply(
          evaluated,
          function(u) ranking_metrics(r$rankings[[u]][[method]],r$relevant[[u]],cutoff)
      )
      precision <- sum(vapply(metrics,`[[`,numeric(1),"hits"))/(cutoff*e)
      recall <- sequential_sum(vapply(metrics,`[[`,numeric(1),"recall"))/e
      ndcg <- sequential_sum(vapply(metrics,`[[`,numeric(1),"ndcg"))/e
      map <- sequential_sum(vapply(metrics,`[[`,numeric(1),"ap"))/e
      mrr <- sequential_sum(vapply(metrics,`[[`,numeric(1),"rr"))/e
      hit_rate <- sum(vapply(metrics,function(metric) metric$hits >= 1L,logical(1)))/e
      lines <- c(lines,fmt("  %s precision %s recall %s ndcg %s map %s mrr %s hit_rate %s",method,real_text(precision),real_text(recall),
        real_text(ndcg),real_text(map),real_text(mrr),real_text(hit_rate)))
    }
  }
  sections[[length(sections)+1L]] <- lines
  size <- params$TOP_N[1L]
  pair_count <- (size*(size-1L)) %/% 2L
  lines <- fmt("beyond_accuracy top_n %s head %s",size,r$head)
  for (method in RANKINGS) {
    distinct <- integer()
    diversity <- popularity <- long_tail <- 0L
    novelty <- similarity <- 0
    for (u in evaluated) {
      ranked <- r$rankings[[u]][[method]][seq_len(size)]
      distinct <- union(distinct,ranked)
      diversity <- diversity+length(unique(unlist(data$genres[ranked],use.names=FALSE)))
      novelty <- novelty+sequential_sum(log2(length(data$users)/data$item_counts[ranked]))/size
      popularity <- popularity+sum(data$item_counts[ranked])
      long_tail <- long_tail+sum(!(ranked %in% r$popular))
      pair_similarity <- 0
      for (a in seq_len(size-1L)) for (b in seq.int(a+1L,size)) {
        value <- n$item[ranked[a],ranked[b]]
        pair_similarity <- pair_similarity+(if (is.na(value)) 0 else value)
      }
      similarity <- similarity+pair_similarity/pair_count
    }
    lines <- c(lines,fmt("%s coverage %s diversity %s novelty %s popularity %s long_tail %s similarity %s",method,
      real_text(length(distinct)/length(data$items)),real_text(diversity/e),real_text(novelty/e),real_text(popularity/(size*e)),
      real_text(long_tail/(size*e)),real_text(similarity/e)))
  }
  sections[[length(sections)+1L]] <- lines
  bounds <- params$USER_GROUPS
  lines <- fmt("ranking_groups top_n %s bounds %s",size,paste(integer_text(bounds),collapse=" "))
  for (g in seq_len(length(bounds)+1L)) {
    users <- evaluated[vapply(evaluated,function(u) group_number(data$user_counts[u],bounds) == g,logical(1))]
    fields <- fmt("group %s users %s",g,length(users))
    for (method in RANKINGS) {
      value <- if (length(users)) sequential_sum(vapply(users,function(u)
        ranking_metrics(
            r$rankings[[u]][[method]],
            r$relevant[[u]],
            size
        )$ndcg,numeric(1)))/length(users) else NULL
      fields <- c(fields,paste(method,real_text(value)))
    }
    lines <- c(lines,paste(fields,collapse=" "))
  }
  sections[[length(sections)+1L]] <- lines
  lines <- fmt("agreement top_n %s",size)
  for (a in seq_len(6L)) for (b in seq.int(a+1L,7L)) {
    total <- 0
    for (u in evaluated) {
      left <- r$rankings[[u]][[RANKINGS[a]]][seq_len(size)]
      right <- r$rankings[[u]][[RANKINGS[b]]][seq_len(size)]
      total <- total+length(intersect(left,right))/length(union(left,right))
    }
    lines <- c(lines,fmt("%s %s jaccard %s",RANKINGS[a],RANKINGS[b],real_text(total/e)))
  }
  sections[[length(sections)+1L]] <- lines
  lines <- "neighbor_grid"
  grid <- params$NEIGHBOR_GRID
  errors <- matrix(0,length(grid),2L)
  for (index in seq_along(grid)) {
    k <- grid[index]
    fields <- fmt("k %s",k)
    for (j in seq_along(KNN_METHODS)) {
      method <- KNN_METHODS[j]
      errors[index,j] <- rmse(vapply(
          data$test,
          function(row) clip(predict_rating(r,method,row$u,row$i,k)$value)-row$rating,
          numeric(1)
      ))
      fields <- c(fields,paste(method,real_text(errors[index,j])))
    }
    lines <- c(lines,paste(fields,collapse=" "))
  }
  sections[[length(sections)+1L]] <- c(
      lines,
      fmt("best USER_KNN %s ITEM_KNN %s",grid[which.min(errors[,1L])],grid[which.min(errors[,2L])])
  )
  lines <- "biases"
  list_size <- params$LIST_SIZE[1L]
  for (kind in c("item","user")) {
    ids <- if (kind == "item") data$items else data$users
    biases <- if (kind == "item") r$item_bias else r$user_bias
    counts <- if (kind == "item") data$item_counts else data$user_counts
    means <- if (kind == "item") data$item_means else data$user_means
    for (label in c("high","low")) {
      sign <- if (label == "high") -1L else 1L
      ordered <- head(order(sign*biases,ids),list_size)
      for (i in ordered) {
        line <- fmt(
            "%s_%s %s bias %s count %s mean %s",
            kind,
            label,
            ids[i],
            real_text(biases[i]),
            counts[i],
            real_text(means[i])
        )
        if (kind == "item") line <- paste(line,data$titles[i])
        lines <- c(lines,line)
      }
    }
  }
  sections[[length(sections)+1L]] <- lines
  sections
}
preferred_genres <- function(r,u,liked) {
  counts <- list()
  for (i in r$data$by_user[[u]]) {
    rating <- r$data$ratings[u,i]
    if (!(if (liked) rating >= 4 else rating <= 2)) next
    for (genre in r$data$genres[[i]]) counts[[genre]] <- if (is.null(counts[[genre]])) 1L else counts[[genre]]+1L
  }
  if (!length(counts)) return(list())
  ordered <- head(order(-unlist(counts,use.names=FALSE),names(counts),method="radix"),3L)
  lapply(ordered,function(i) list(genre=names(counts)[i],count=counts[[i]]))
}
popularity_line <- function(r,rank,i) fmt(
    "  %s %s count %s mean %s %s",
    rank,
    r$data$items[i],
    r$data$item_counts[i],
    real_text(r$data$item_means[i]),
    r$data$titles[i]
)
recommendation_sections <- function(r) {
  data <- r$data
  size <- r$params$TOP_N[1L]
  list_size <- r$params$LIST_SIZE[1L]
  sections <- list()
  for (id in r$params$RECOMMEND_USERS) {
    u <- match(id,data$users)
    if (is.na(u)) {
      sections[[length(sections)+1L]] <- c(fmt("user %s unknown",id),"list POPULAR",vapply(seq_len(size),function(rank)
        popularity_line(r,rank,r$popularity[rank]),character(1)))
      next
    }
    lines <- fmt(
        "user %s ratings %s mean %s bias %s",
        id,
        data$user_counts[u],
        real_text(data$user_means[u]),
        real_text(r$user_bias[u])
    )
    liked <- preferred_genres(r,u,TRUE)
    disliked <- preferred_genres(r,u,FALSE)
    for (label in c("liked_genres","disliked_genres")) {
      genres <- if (label == "liked_genres") liked else disliked
      values <- if (!length(genres)) "-" else paste(
          vapply(genres,function(g) fmt("%s %s",g$genre,g$count),character(1)),
          collapse=" "
      )
      lines <- c(lines,paste(label,values))
    }
    recent <- Filter(function(row) row$u == u,data$training)
    recent <- head(recent[order(-vapply(recent,`[[`,numeric(1),"time"),vapply(recent,function(row) data$items[row$i],numeric(1)))],3L)
    lines <- c(
        lines,
        paste(
            "recent",
            paste(
                vapply(recent,function(row) fmt("%s %s",data$items[row$i],row$rating),character(1)),
                collapse=" "
            )
        )
    )
    candidates <- list()
    for (v in seq_along(data$users)) {
      similarity <- r$neighborhood$user[u,v]
      if (!is.na(similarity) && similarity > r$params$MIN_SIMILARITY[1L]) candidates[[length(candidates)+1L]] <- c(
          v,
          similarity
      )
    }
    for (neighbor in largest_neighbors(candidates,list_size)) {
      v <- neighbor[1L]
      lines <- c(
          lines,
          fmt(
              "neighbor %s similarity %s common %s",
              data$users[v],
              real_text(neighbor[2L]),
              r$neighborhood$user_common[u,v]
          )
      )
    }
    for (index in seq_along(data$test)) {
      row <- data$test[[index]]
      if (row$u != u) next
      values <- vapply(METHODS,function(method) real_text(r$clipped[[method]][index]),character(1))
      lines <- c(lines,fmt("heldout %s actual %s %s",data$items[row$i],row$rating,paste(values,collapse=" ")))
    }
    liked_names <- vapply(liked,`[[`,character(1),"genre")
    for (method in RANKINGS) {
      ranked <- r$rankings[[u]][[method]][seq_len(size)]
      matches <- sum(vapply(data$genres[ranked],function(genres) any(genres %in% liked_names),logical(1)))
      lines <- c(lines,fmt("list %s genre_match %s",method,matches))
      for (rank in seq_along(ranked)) {
        i <- ranked[rank]
        if (method == "POPULAR") lines <- c(lines,popularity_line(r,rank,i)) else {
          p <- r$ranking_predictions[[u]][[method]][[as.character(i)]]
          line <- fmt("  %s %s %s",rank,data$items[i],real_text(p$value))
          if (method %in% KNN_METHODS) {
            top <- if (!p$top) "-" else integer_text(if (method == "USER_KNN") data$users[p$top] else data$items[p$top])
            line <- paste(line,"via",top)
          }
          lines <- c(lines,paste(line,data$titles[i]))
        }
      }
    }
    sections[[length(sections)+1L]] <- lines
  }
  sections
}
similar_sections <- function(r) {
  data <- r$data
  n <- r$neighborhood
  size <- r$params$LIST_SIZE[1L]
  factors <- r$svd$items
  norms <- vapply(seq_along(data$items),function(i) dot_product(factors[i,],factors[i,]),numeric(1))
  sections <- list()
  for (id in r$params$SIMILAR_ITEMS) {
    i <- match(id,data$items)
    lines <- c(
        fmt(
            "item %s ratings %s mean %s bias %s genres %s title %s",
            id,
            data$item_counts[i],
            real_text(data$item_means[i]),
            real_text(r$item_bias[i]),
            data$genre_text[i],
            data$titles[i]
        ),
        "cosine"
    )
    candidates <- lapply(which(!is.na(n$item[i,])),function(j) c(j,n$item[i,j]))
    selected <- largest_neighbors(candidates,size)
    for (rank in seq_along(selected)) {
      j <- selected[[rank]][1L]
      lines <- c(
          lines,
          fmt(
              "  %s %s similarity %s common %s %s",
              rank,
              data$items[j],
              real_text(selected[[rank]][2L]),
              n$counts[i,j],
              data$titles[j]
          )
      )
    }
    lines <- c(lines,"factors")
    candidates <- lapply(
        setdiff(seq_along(data$items),i),
        function(j) c(j,dot_product(factors[i,],factors[j,])/sqrt(norms[i]*norms[j]))
    )
    selected <- largest_neighbors(candidates,size)
    for (rank in seq_along(selected)) {
      j <- selected[[rank]][1L]
      lines <- c(
          lines,
          fmt("  %s %s similarity %s %s",rank,data$items[j],real_text(selected[[rank]][2L]),data$titles[j])
      )
    }
    common_items <- which(n$counts[i,] >= 1L)
    ordered <- head(common_items[order(-n$counts[i,common_items],data$items[common_items])],size)
    lines <- c(lines,"co_rated")
    for (rank in seq_along(ordered)) {
      j <- ordered[rank]
      lines <- c(lines,fmt("  %s %s common %s %s",rank,data$items[j],n$counts[i,j],data$titles[j]))
    }
    differences <- vapply(common_items,function(j) deviation(n,j,i),numeric(1))
    ordered <- head(common_items[order(-differences,-n$counts[common_items,i],data$items[common_items])],size)
    lines <- c(lines,"slope_one")
    for (rank in seq_along(ordered)) {
      j <- ordered[rank]
      lines <- c(
          lines,
          fmt(
              "  %s %s difference %s common %s %s",
              rank,
              data$items[j],
              n$differences[j,i],
              n$counts[j,i],
              data$titles[j]
          )
      )
    }
    sections[[length(sections)+1L]] <- lines
  }
  sections
}
separate_sections <- function(sections) {
  lines <- character()
  for (section in sections) {
    if (length(lines)) lines <- c(lines,"")
    lines <- c(lines,section)
  }
  lines
}
main <- function() {
  recommender <- train(read_inputs())
  predictions <- predict_tests(recommender)
  prepare_rankings(recommender)
  write_lines("predictions.csv",predictions)
  write_lines("evaluation.txt",separate_sections(evaluation_sections(recommender)))
  write_lines("recommendations.txt",separate_sections(recommendation_sections(recommender)))
  write_lines("similar_items.txt",separate_sections(similar_sections(recommender)))
  log <- vapply(
      recommender$log,
      function(entry) paste(entry$method,integer_text(entry$epoch),real_text(entry$error),sep=","),
      character(1)
  )
  write_lines("training_log.csv",c("method,epoch,train_rmse",log))
}
main()
