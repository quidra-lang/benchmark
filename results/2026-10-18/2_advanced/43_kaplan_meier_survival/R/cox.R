evaluate_cox <- function(subjects,vectors,beta) {
  p <- length(beta)
  predictors <- vapply(vectors,function(x) total(beta*x),numeric(1))
  risks <- exp(predictors)
  order <- order(-vapply(subjects,`[[`,integer(1),"time"),vapply(subjects,`[[`,integer(1),"id"))
  s0 <- likelihood <- 0
  s1 <- score <- numeric(p)
  s2 <- information <- matrix(0,p,p)
  event_sums <- list()
  position <- 1L
  while (position <= length(order)) {
    time <- subjects[[order[position]]]$time
    stop <- position
    while (stop <= length(order) && subjects[[order[stop]]]$time == time) stop <- stop+1L
    indices <- order[seq.int(position,stop-1L)]
    for (i in indices) {
      risk <- risks[i]
      x <- vectors[[i]]
      s0 <- s0+risk
      for (c in seq_len(p)) {
        s1[c] <- s1[c]+risk*x[c]
        for (d in seq_len(p)) s2[c,d] <- s2[c,d]+risk*x[c]*x[d]
      }
    }
    events <- indices[vapply(indices,function(i) subjects[[i]]$event == 1L,logical(1))]
    if (length(events)) {
      n <- length(events)
      likelihood <- likelihood+(total(predictors[events])-n*log(s0))
      for (c in seq_len(p)) {
        score[c] <- score[c]+(sum(vapply(events,function(i) vectors[[i]][c],integer(1)))-n*s1[c]/s0)
        for (d in seq_len(p)) information[c,d] <- information[c,d]+n*(s2[c,d]/s0-(s1[c]/s0)*(s1[d]/s0))
      }
      event_sums[[as.character(time)]] <- list(s0=s0,s1=s1,events=n)
    }
    position <- stop
  }
  list(loglik=likelihood,score=score,information=information,predictors=predictors,event_sums=event_sums)
}
fit_cox <- function(subjects,vectors) {
  beta <- numeric(length(vectors[[1L]]))
  null <- evaluate_cox(subjects,vectors,beta)
  current <- null
  iterations <- list()
  for (iteration in seq_len(25L)) {
    change <- solve_system(current$information,current$score)
    beta <- beta+change
    iterations[[iteration]] <- list(number=iteration,loglik=current$loglik,beta=beta)
    current <- evaluate_cox(subjects,vectors,beta)
  }
  list(beta=beta,null=null,final=current,iterations=iterations)
}
