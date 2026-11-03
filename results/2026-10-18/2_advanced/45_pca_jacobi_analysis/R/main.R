for (module in c("dataset","matrix","eigen","pca","plot")) source(paste0(module,".R"))
CRITERIA <- c("kaiser","broken_stick","parallel","cumulative")
real_text <- function(value,digits=4L) {
  text <- sprintf(paste0("%.",digits,"f"),value)
  text[as.numeric(text) == 0] <- sub("^-","",text[as.numeric(text) == 0])
  text
}
reals <- function(values) real_text(values)
component_names <- function(prefix,n) paste0(prefix,seq_len(n))
top_indices <- function(values,n) head(order(-values,seq_along(values)),n)
congruence <- function(a,b) dot_product(a,b)/sqrt(dot_product(a,a)*dot_product(b,b))
cumulative_ratios <- function(values) {
  result <- numeric(length(values))
  running <- 0
  for (i in seq_along(values)) {
    running <- running+values[i]
    result[i] <- running
  }
  result
}
analysis_data <- function(table,strategy,observed_means) {
  indices <- which(if (strategy == "listwise") rowSums(is.na(table$values)) == 0L else rep(
      TRUE,
      length(table$ids)
  ))
  values <- table$values[indices,,drop=FALSE]
  for (j in seq_along(observed_means)) values[is.na(values[,j]),j] <- observed_means[j]
  list(ids=table$ids[indices],values=values)
}
decompose <- function(data,scaling) {
  means <- column_means(data$values)
  covariance <- covariance_matrix(data$values,means)
  deviations <- standard_deviations(covariance)
  correlation <- correlation_matrix(covariance,deviations)
  matrix <- if (scaling == "covariance") covariance else correlation
  scales <- if (scaling == "covariance") rep(1,length(means)) else deviations
  list(
      data=data,
      means=means,
      covariance=covariance,
      correlation=correlation,
      matrix=matrix,
      scales=scales,
      eigen=jacobi(matrix)
  )
}
adequacy <- function(correlation,n) {
  p <- nrow(correlation)
  inverse_result <- gauss_jordan(correlation)
  inverse <- inverse_result$inverse
  determinant <- inverse_result$determinant
  partial <- matrix(0,p,p)
  for (j in seq_len(p)) for (k in seq_len(p)) if (j != k) partial[j,k] <- -inverse[
      j,
      k
  ]/sqrt(inverse[j,j]*inverse[
      k,
      k
  ])
  rr <- vapply(seq_len(p),function(j) sequential_sum(correlation[j,-j]*correlation[j,-j]),numeric(1))
  pp <- vapply(seq_len(p),function(j) sequential_sum(partial[j,-j]*partial[j,-j]),numeric(1))
  msa <- rr/(rr+pp)
  total_rr <- sequential_sum(rr)
  total_pp <- sequential_sum(pp)
  list(msa=msa,kmo=total_rr/(total_rr+total_pp),determinant=determinant,
    bartlett=-(n-1-(2*p+5)/6)*log(determinant),df=(p*(p-1L)) %/% 2L)
}
parallel_analysis <- function(n,p,iterations,seed) {
  state <- seed
  uniform <- function() {
    state <<- (48271*state) %% 2147483647
    state/2147483647
  }
  totals <- numeric(p)
  for (unused in seq_len(iterations)) {
    values <- matrix(0,n,p)
    for (i in seq_len(n)) for (j in seq_len(p)) values[i,j] <- uniform()
    covariance <- covariance_matrix(values,column_means(values))
    eigenvalues <- jacobi(correlation_matrix(covariance,standard_deviations(covariance)))$values
    sum_values <- sequential_sum(eigenvalues)
    for (k in seq_len(p)) totals[k] <- totals[k]+eigenvalues[k]/sum_values
  }
  totals/iterations
}
variance_table <- function(values,n,parallel,target) {
  p <- length(values)
  total <- sequential_sum(values)
  average <- total/p
  ratios <- values/total
  cumulative <- cumulative_ratios(ratios)
  broken <- vapply(seq_len(p),function(k) sequential_sum(1/seq.int(k,p))/p,numeric(1))
  errors <- values*sqrt(2/n)
  separated <- vapply(seq_len(p),function(k) {
    neighbors <- c(k-1L,k+1L)
    neighbors <- neighbors[neighbors >= 1L & neighbors <= p]
    all(abs(values[k]-values[neighbors]) > errors[k])
  },logical(1))
  crossing <- function(thresholds) {
    indices <- which(ratios <= thresholds)
    if (length(indices)) indices[1L]-1L else p
  }
  retention <- c(
      kaiser=sum(values > average),
      broken_stick=crossing(broken),
      parallel=crossing(parallel),
      cumulative=which(cumulative >= target)[1L]
  )
  list(total=total,average=average,ratios=ratios,cumulative=cumulative,broken=broken,parallel=parallel,
    errors=errors,separated=separated,retention=retention)
}
varimax_criterion <- function(g) {
  p <- nrow(g)
  k <- ncol(g)
  value <- 0
  for (c in seq_len(k)) {
    q4 <- sequential_sum((g[,c]*g[,c])*(g[,c]*g[,c]))
    q2 <- sequential_sum(g[,c]*g[,c])
    value <- value+(q4/p-(q2/p)*(q2/p))
  }
  value
}
varimax_rotation <- function(loadings,k,cycles) {
  p <- nrow(loadings)
  eta <- vapply(
      seq_len(p),
      function(j) sqrt(sequential_sum(loadings[j,seq_len(k)]*loadings[j,seq_len(k)])),
      numeric(1)
  )
  g <- loadings[,seq_len(k),drop=FALSE]/eta
  criteria <- varimax_criterion(g)
  for (unused in seq_len(cycles)) {
    for (a in seq_len(k-1L)) for (b in seq.int(a+1L,k)) {
      phi <- g[,a]*g[,a]-g[,b]*g[,b]
      psi <- 2*g[,a]*g[,b]
      sa <- sequential_sum(phi)
      sb <- sequential_sum(psi)
      sc <- sequential_sum(phi*phi-psi*psi)
      sd <- sequential_sum(2*phi*psi)
      num <- sd-2*sa*sb/p
      den <- sc-(sa*sa-sb*sb)/p
      omega <- sqrt(num*num+den*den)
      if (omega == 0) next
      cos4 <- den/omega
      sin4 <- num/omega
      cos2 <- sqrt((1+cos4)/2)
      sin2 <- if (cos2 == 0) 1 else sin4/(2*cos2)
      cos1 <- sqrt((1+cos2)/2)
      sin1 <- sin2/(2*cos1)
      for (j in seq_len(p)) {
        first_value <- g[j,a]
        second_value <- g[j,b]
        g[j,a] <- cos1*first_value+sin1*second_value
        g[j,b] <- -sin1*first_value+cos1*second_value
      }
    }
    criteria <- c(criteria,varimax_criterion(g))
  }
  columns <- lapply(seq_len(k),function(c) orient(g[,c]*eta))
  squares <- vapply(columns,function(column) dot_product(column,column),numeric(1))
  order <- order(-squares,seq_len(k))
  columns <- columns[order]
  squares <- squares[order]
  closest <- integer()
  congruences <- numeric()
  for (column in columns) {
    values <- vapply(seq_len(k),function(c) abs(congruence(column,loadings[,c])),numeric(1))
    best <- which.max(values)
    closest <- c(closest,best)
    congruences <- c(congruences,values[best])
  }
  list(columns=columns,squares=squares,criteria=criteria,closest=closest,congruences=congruences)
}
observation <- function(id,values,fit,k,settings) {
  z <- standardize(values,fit$means,fit$scales)
  scores <- component_scores(z,fit$eigen$vectors)
  t2 <- hotelling_t2(scores,fit$eigen$values,k)
  errors <- residuals(z,scores,fit$eigen$vectors,k)
  spe <- dot_product(errors,errors)
  flag <- paste0(if (t2 > settings$T2_LIMIT[1L]) "T" else "",if (spe > settings$SPE_LIMIT[1L]) "Q" else "")
  list(id=id,z=z,scores=scores,t2=t2,errors=errors,spe=spe,flag=if (nzchar(flag)) flag else "-")
}
build_report <- function(dataset) {
  data <- dataset$data
  settings <- dataset$settings
  p <- length(data$names)
  summaries <- lapply(seq_len(p),function(j) {
    values <- data$values[!is.na(data$values[,j]),j]
    observed <- length(values)
    mean <- sequential_sum(values)/observed
    sd <- sqrt(sequential_sum((values-mean)*(values-mean))/(observed-1L))
    list(
        observed=observed,
        missing=length(data$ids)-observed,
        mean=mean,
        sd=sd,
        minimum=min(values),
        maximum=max(values)
    )
  })
  means <- vapply(summaries,`[[`,numeric(1),"mean")
  incomplete <- data$ids[rowSums(is.na(data$values)) > 0L]
  main_data <- analysis_data(data,settings$MISSING,means)
  fit <- decompose(main_data,settings$SCALING)
  n <- length(main_data$ids)
  parallel <- parallel_analysis(n,p,settings$PARALLEL[1L],settings$PARALLEL[2L])
  variance <- variance_table(fit$eigen$values,n,parallel,settings$CUMULATIVE_TARGET[1L])
  rule <- settings$COMPONENTS
  k <- if (rule %in% CRITERIA) max(1L,variance$retention[[rule]]) else as.integer(rule)
  loadings <- matrix(0,p,p)
  for (j in seq_len(p)) for (c in seq_len(p)) loadings[
      j,
      c
  ] <- fit$eigen$vectors[[c]][j]*sqrt(fit$eigen$values[c])
  communalities <- vapply(
      seq_len(p),
      function(j) sequential_sum(loadings[j,seq_len(k)]*loadings[j,seq_len(k)])/fit$matrix[j,j],
      numeric(1)
  )
  circle <- matrix(0,p,2L)
  for (j in seq_len(p)) for (c in seq_len(2L)) circle[j,c] <- loadings[j,c]/sqrt(fit$matrix[j,j])
  observations <- lapply(
      seq_along(main_data$ids),
      function(i) observation(main_data$ids[i],main_data$values[i,],fit,k,settings)
  )
  projections <- lapply(seq_along(dataset$supplementary$ids),function(i)
    observation(dataset$supplementary$ids[i],dataset$supplementary$values[i,],fit,k,settings))
  sensitivities <- list()
  for (strategy in c("listwise","mean")) for (scaling in c("covariance","correlation")) {
    alternative <- decompose(analysis_data(data,strategy,means),scaling)
    eigenvalues <- alternative$eigen$values
    ratios <- eigenvalues/sequential_sum(eigenvalues)
    agreement <- vapply(
        seq_len(k),
        function(c) abs(dot_product(alternative$eigen$vectors[[c]],fit$eigen$vectors[[c]])),
        numeric(1)
    )
    sensitivities[[length(sensitivities)+1L]] <- list(strategy=strategy,scaling=scaling,rows=length(alternative$data$ids),
      sweeps=alternative$eigen$sweeps,eigenvalues=eigenvalues[seq_len(k)],cumulative=cumulative_ratios(ratios)[k],agreement=agreement)
  }
  list(dataset=dataset,settings=settings,names=data$names,p=p,n=n,summaries=summaries,incomplete=incomplete,fit=fit,
    variance=variance,k=k,loadings=loadings,communalities=communalities,circle=circle,adequacy=adequacy(
        fit$correlation,
        n
    ),
    power=power_iteration(fit$matrix,fit$eigen$vectors),varimax=varimax_rotation(
        loadings,
        k,
        settings$VARIMAX_CYCLES[1L]
    ),
    observations=observations,projections=projections,sensitivity=sensitivities)
}
eigen_sections <- function(r) {
  settings <- r$settings
  fit <- r$fit
  v <- r$variance
  incomplete <- if (length(r$incomplete)) paste(
      length(r$incomplete),
      paste(r$incomplete,collapse=" ")
  ) else "0 -"
  sections <- list(c(
      sprintf(
          "pca rows %d used %d variables %d missing %s scaling %s",
          length(r$dataset$data$ids),
          r$n,
          r$p,
          settings$MISSING,
          settings$SCALING
      ),
      paste("incomplete",incomplete)
  ))
  lines <- "variable observed missing mean sd min max msa"
  for (j in seq_along(r$names)) {
    summary <- r$summaries[[j]]
    lines <- c(
        lines,
        paste(
            r$names[j],
            summary$observed,
            summary$missing,
            paste(
                reals(c(summary$mean,summary$sd,summary$minimum,summary$maximum,r$adequacy$msa[j])),
                collapse=" "
            )
        )
    )
  }
  a <- r$adequacy
  sections[[length(sections)+1L]] <- c(
      lines,
      sprintf(
          "adequacy kmo %s determinant %s bartlett %s df %d",
          real_text(a$kmo),
          real_text(a$determinant,6L),
          real_text(a$bartlett),
          a$df
      )
  )
  lines <- paste("matrix",settings$SCALING)
  for (j in seq_along(r$names)) lines <- c(lines,paste(r$names[j],paste(reals(fit$matrix[j,]),collapse=" ")))
  pairs <- list()
  for (j in seq_len(r$p-1L)) for (k in seq.int(j+1L,r$p)) pairs[[length(pairs)+1L]] <- c(j,k)
  strengths <- vapply(pairs,function(pair) abs(fit$correlation[pair[1L],pair[2L]]),numeric(1))
  selected <- top_indices(strengths,settings$TOP_ROWS[1L])
  descriptions <- vapply(
      pairs[selected],
      function(pair) paste0(
          r$names[pair[1L]],
          ":",
          r$names[pair[2L]],
          ":",
          real_text(fit$correlation[pair[1L],pair[2L]])
      ),
      character(1)
  )
  sections[[length(sections)+1L]] <- c(lines,paste("strongest",paste(descriptions,collapse=" ")))
  lines <- c(
      sprintf("jacobi sweeps %d",fit$eigen$sweeps),
      sprintf("eigenvalues total %s average %s",real_text(v$total),real_text(v$average)),
      "k eigenvalue ratio cumulative broken_stick parallel se separated"
  )
  for (k in seq_len(r$p)) lines <- c(
      lines,
      paste(
          k,
          paste(
              reals(c(fit$eigen$values[k],v$ratios[k],v$cumulative[k],v$broken[k],v$parallel[k],v$errors[k])),
              collapse=" "
          ),
          if (v$separated[k]) "yes" else "no"
      )
  )
  sections[[length(sections)+1L]] <- c(
      lines,
      paste(
          "retention",
          paste(paste(CRITERIA,v$retention[CRITERIA]),collapse=" "),
          "target",
          real_text(settings$CUMULATIVE_TARGET[1L])
      ),
      sprintf("components %d rule %s",r$k,settings$COMPONENTS)
  )
  lines <- c("eigenvectors",paste(c("variable",component_names("pc",r$p)),collapse=" "))
  for (j in seq_along(r$names)) lines <- c(lines,paste(r$names[j],paste(reals(vapply(fit$eigen$vectors,`[`,numeric(1),j)),collapse=" ")))
  sections[[length(sections)+1L]] <- lines
  lines <- c("power_iteration iterations 1000","k jacobi power agree_at match")
  matches <- 0L
  for (k in seq_len(r$p)) {
    component <- r$power[[k]]
    match <- abs(component$value-fit$eigen$values[k]) <= 1e-8*fit$eigen$values[1L] && max_difference(
        component$vector,
        fit$eigen$vectors[[k]]
    ) <= 1e-6
    matches <- matches+as.integer(match)
    lines <- c(lines,sprintf("%d %s %s %s %s",k,real_text(fit$eigen$values[k]),real_text(component$value),
      if (is.null(component$agreement)) "-" else as.character(component$agreement),if (match) "yes" else "no"))
  }
  sections[[length(sections)+1L]] <- c(lines,sprintf("cross_check %d/%d",matches,r$p))
  lines <- c("scores","component sd min min_id max max_id contributors")
  for (k in seq_len(r$k)) {
    scores <- vapply(r$observations,function(o) o$scores[k],numeric(1))
    sd <- sqrt(sequential_sum(scores*scores)/(r$n-1L))
    low <- which.min(scores)
    high <- which.max(scores)
    contributions <- scores*scores/((r$n-1L)*fit$eigen$values[k])
    fields <- c(
        paste0("pc",k),
        real_text(sd),
        real_text(scores[low]),
        fit$data$ids[low],
        real_text(scores[high]),
        fit$data$ids[high]
    )
    indices <- top_indices(contributions,settings$TOP_ROWS[1L])
    fields <- c(fields,paste0(fit$data$ids[indices],":",real_text(contributions[indices])))
    lines <- c(lines,paste(fields,collapse=" "))
  }
  sections[[length(sections)+1L]] <- lines
  lines <- sprintf("varimax components %d cycles %d",r$k,settings$VARIMAX_CYCLES[1L])
  for (c in seq_along(r$varimax$criteria)) lines <- c(
      lines,
      sprintf("cycle %d criterion %s",c-1L,real_text(r$varimax$criteria[c],6L))
  )
  for (k in seq_len(r$k)) lines <- c(lines,sprintf("rc%d ss %s ratio %s closest pc%d congruence %s",k,real_text(r$varimax$squares[k]),
    real_text(r$varimax$squares[k]/v$total),r$varimax$closest[k],real_text(r$varimax$congruences[k])))
  sections[[length(sections)+1L]] <- lines
  lines <- c("sensitivity","missing scaling rows sweeps eigenvalues cumulative congruence")
  for (s in r$sensitivity) lines <- c(
      lines,
      paste(
          s$strategy,
          s$scaling,
          s$rows,
          s$sweeps,
          paste(reals(c(s$eigenvalues,s$cumulative,s$agreement)),collapse=" ")
      )
  )
  sections[[length(sections)+1L]] <- lines
  sections
}
csv_files <- function(r) {
  lines <- paste(c("variable",component_names("pc",r$k),"communality",component_names("rc",r$k)),collapse=",")
  for (j in seq_along(r$names)) {
    values <- c(r$loadings[j,seq_len(r$k)],r$communalities[j],vapply(r$varimax$columns,`[`,numeric(1),j))
    lines <- c(lines,paste(c(r$names[j],reals(values)),collapse=","))
  }
  scores <- paste(c("id","set",component_names("pc",r$k)),collapse=",")
  for (set in c("data","supplementary")) {
    observations <- if (set == "data") r$observations else r$projections
    for (o in observations) scores <- c(scores,paste(c(o$id,set,reals(o$scores[seq_len(r$k)])),collapse=","))
  }
  list(loadings=lines,scores=scores)
}
outlier_sections <- function(r) {
  lines <- c(
      sprintf(
          "diagnostics components %d t2_limit %s spe_limit %s",
          r$k,
          real_text(r$settings$T2_LIMIT[1L]),
          real_text(r$settings$SPE_LIMIT[1L])
      ),
      "id t2 spe quality flag"
  )
  for (o in r$observations) {
    quality <- dot_product(o$scores[seq_len(r$k)],o$scores[seq_len(r$k)])/dot_product(o$z,o$z)
    lines <- c(lines,paste(o$id,paste(reals(c(o$t2,o$spe,quality)),collapse=" "),o$flag))
  }
  flags <- vapply(r$observations,`[[`,character(1),"flag")
  sections <- list(c(
      lines,
      sprintf(
          "flagged t2 %d spe %d both %d any %d",
          sum(grepl("T",flags,fixed=TRUE)),
          sum(grepl("Q",flags,fixed=TRUE)),
          sum(flags == "TQ"),
          sum(flags != "-")
      )
  ))
  for (label in c("t2","spe")) {
    values <- vapply(r$observations,function(o) if (label == "t2") o$t2 else o$spe,numeric(1))
    contributions <- lapply(r$observations,function(o) {
      if (label == "spe") return(o$errors*o$errors)
      vapply(seq_len(r$p),function(j) o$z[j]*sequential_sum(vapply(seq_len(r$k),function(k)
        (o$scores[k]/r$fit$eigen$values[k])*r$fit$eigen$vectors[[k]][j],numeric(1))),numeric(1))
    })
    lines <- c(paste("top",label),paste("rank id",label,"variable contribution"))
    indices <- top_indices(values,r$settings$TOP_ROWS[1L])
    for (rank in seq_along(indices)) {
      i <- indices[rank]
      j <- which.max(contributions[[i]])
      lines <- c(
          lines,
          sprintf(
              "%d %s %s %s %s",
              rank,
              r$fit$data$ids[i],
              real_text(values[i]),
              r$names[j],
              real_text(contributions[[i]][j])
          )
      )
    }
    sections[[length(sections)+1L]] <- lines
  }
  lines <- c("reconstruction","k mean_spe max_spe max_id")
  for (k in seq_len(r$p-1L)) {
    errors <- vapply(r$observations,function(o) {
      e <- residuals(o$z,o$scores,r$fit$eigen$vectors,k)
      dot_product(e,e)
    },numeric(1))
    worst <- which.max(errors)
    lines <- c(
        lines,
        sprintf(
            "%d %s %s %s",
            k,
            real_text(sequential_sum(errors)/r$n),
            real_text(errors[worst]),
            r$fit$data$ids[worst]
        )
    )
  }
  sections[[length(sections)+1L]] <- lines
  lines <- c(
      "supplementary",
      paste(c("id",component_names("pc",r$k),"t2","spe","flag","nearest","distance"),collapse=" ")
  )
  for (o in r$projections) {
    distances <- vapply(r$observations,function(a) sequential_sum((o$scores[seq_len(r$k)]-a$scores[seq_len(r$k)])*
      (o$scores[seq_len(r$k)]-a$scores[seq_len(r$k)])),numeric(1))
    nearest <- which.min(distances)
    lines <- c(
        lines,
        paste(
            o$id,
            paste(reals(c(o$scores[seq_len(r$k)],o$t2,o$spe)),collapse=" "),
            o$flag,
            r$fit$data$ids[nearest],
            real_text(sqrt(distances[nearest]))
        )
    )
  }
  sections[[length(sections)+1L]] <- lines
  sections
}
draw_axes <- function(grid,center) {
  row <- center[1L]+1L
  column <- center[2L]+1L
  grid[row,] <- "-"
  grid[,column] <- "|"
  grid[row,column] <- "+"
  grid
}
mark_cells <- function(grid,cells,character) {
  for (cell in cells) grid[cell[1L]+1L,cell[2L]+1L] <- character
  grid
}
draw_points <- function(grid,cells) {
  counts <- matrix(0L,nrow(grid),ncol(grid))
  for (cell in cells) counts[cell[1L]+1L,cell[2L]+1L] <- counts[cell[1L]+1L,cell[2L]+1L]+1L
  for (i in seq_len(nrow(grid))) for (j in seq_len(ncol(grid))) {
    n <- counts[i,j]
    if (n > 0L) grid[i,j] <- if (n == 1L) "." else if (n <= 3L) "o" else "@"
  }
  grid
}
inside_circle <- function(
    row,
    column,
    center,
    radius
) (column-center[2L])^2+(2*(row-center[1L]))^2 <= radius*radius
plot_sections <- function(r) {
  settings <- r$settings
  eigenvalues <- r$fit$eigen$values
  width <- settings$SCREE_WIDTH[1L]
  kaiser <- rounded_position(r$variance$average/eigenvalues[1L],width)
  lines <- sprintf("scree width %d kaiser_column %d",width,kaiser)
  for (k in seq_along(eigenvalues)) {
    value <- eigenvalues[k]
    n <- rounded_position(value/eigenvalues[1L],width)
    broken <- rounded_position(r$variance$broken[k]*r$variance$total/eigenvalues[1L],width)
    lines <- c(lines,paste(scree_line(n,kaiser,broken,width),paste0("pc",k),real_text(value)))
  }
  sections <- list(lines)
  width <- settings$BIPLOT_SIZE[1L]
  height <- settings$BIPLOT_SIZE[2L]
  points <- c(r$observations,r$projections)
  x_limit <- max(vapply(points,function(o) abs(o$scores[1L]),numeric(1)))
  y_limit <- max(vapply(points,function(o) abs(o$scores[2L]),numeric(1)))
  arrow_scale <- 0.9*min(x_limit/max(abs(r$loadings[,1L])),y_limit/max(abs(r$loadings[,2L])))
  origin <- biplot_cell(0,0,x_limit,y_limit,width,height)
  tips <- lapply(
      seq_len(r$p),
      function(j) biplot_cell(
          arrow_scale*r$loadings[j,1L],
          arrow_scale*r$loadings[j,2L],
          x_limit,
          y_limit,
          width,
          height
      )
  )
  cells <- lapply(points,function(o) biplot_cell(o$scores[1L],o$scores[2L],x_limit,y_limit,width,height))
  grid <- draw_axes(new_grid(height,width),origin)
  for (tip in tips) grid <- mark_cells(grid,shaft_cells(origin,tip),shaft_character(origin,tip))
  grid <- draw_points(grid,cells[seq_len(r$n)])
  flagged <- which(vapply(r$observations,function(o) o$flag != "-",logical(1)))
  grid <- mark_cells(grid,cells[flagged],"X")
  grid <- mark_cells(grid,cells[seq.int(r$n+1L,length(cells))],"*")
  for (j in seq_along(tips)) grid <- mark_cells(grid,list(tips[[j]]),LETTERS[j])
  lines <- c(sprintf("biplot pc1 pc2 width %d height %d",width,height),sprintf("x %s %s y %s %s arrow_scale %s",
    real_text(-x_limit),real_text(x_limit),real_text(-y_limit),real_text(y_limit),real_text(arrow_scale)),framed(grid))
  for (j in seq_len(r$p)) lines <- c(
      lines,
      sprintf("%s %s %s %s",LETTERS[j],r$names[j],real_text(r$loadings[j,1L]),real_text(r$loadings[j,2L]))
  )
  sections[[length(sections)+1L]] <- lines
  radius <- settings$CIRCLE_RADIUS[1L]
  center <- c(radius %/% 2L+1L,radius+1L)
  grid <- draw_axes(new_grid(radius+3L,2L*radius+3L),center)
  neighbors <- list(c(-1L,0L),c(1L,0L),c(0L,-1L),c(0L,1L))
  for (row in seq_len(nrow(grid))-1L) for (column in seq_len(ncol(grid))-1L) {
    if (!inside_circle(row,column,center,radius)) next
    if (any(vapply(
        neighbors,
        function(d) !inside_circle(row+d[1L],column+d[2L],center,radius),
        logical(1)
    ))) grid[row+1L,column+1L] <- "."
  }
  for (j in seq_len(r$p)) grid <- mark_cells(
      grid,
      list(circle_cell(r$circle[j,1L],r$circle[j,2L],radius)),
      LETTERS[j]
  )
  lines <- c(sprintf("circle radius %d",radius),framed(grid))
  for (j in seq_len(r$p)) {
    a <- r$circle[j,1L]
    b <- r$circle[j,2L]
    lines <- c(lines,paste(LETTERS[j],r$names[j],paste(reals(c(a,b,a*a+b*b)),collapse=" ")))
  }
  sections[[length(sections)+1L]] <- lines
  width <- settings$DIAGNOSTIC_SIZE[1L]
  height <- settings$DIAGNOSTIC_SIZE[2L]
  x <- 2*settings$T2_LIMIT[1L]
  y <- 2*settings$SPE_LIMIT[1L]
  grid <- draw_axes(new_grid(height,width),diagnostic_cell(x/2,y/2,x,y,width,height))
  grid <- draw_points(grid,lapply(r$observations,function(o) diagnostic_cell(o$t2,o$spe,x,y,width,height)))
  grid <- mark_cells(grid,lapply(r$projections,function(o) diagnostic_cell(o$t2,o$spe,x,y,width,height)),"*")
  sections[[length(sections)+1L]] <- c(
      sprintf("diagnostic width %d height %d t2_max %s spe_max %s",width,height,real_text(x),real_text(y)),
      framed(grid)
  )
  sections
}
join_sections <- function(sections) {
  lines <- character()
  for (section in sections) {
    if (length(lines)) lines <- c(lines,"")
    lines <- c(lines,section)
  }
  lines
}
write_lines <- function(name,lines) writeLines(lines,file.path("output",name),useBytes=TRUE)
main <- function() {
  report <- build_report(load_dataset())
  csv <- csv_files(report)
  dir.create("output",showWarnings=FALSE)
  write_lines("eigen.txt",join_sections(eigen_sections(report)))
  write_lines("loadings.csv",csv$loadings)
  write_lines("scores.csv",csv$scores)
  write_lines("outliers.txt",join_sections(outlier_sections(report)))
  write_lines("plots.txt",join_sections(plot_sections(report)))
}
main()
