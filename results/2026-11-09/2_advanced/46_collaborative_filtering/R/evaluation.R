sequential_sum <- function(values) {
  total <- 0
  for (value in values) total <- total+value
  total
}
clip <- function(value) if (value < 1) 1 else if (value > 5) 5 else value
rmse <- function(errors) if (!length(errors)) NULL else sqrt(sequential_sum(errors*errors)/length(errors))
mae <- function(errors) if (!length(errors)) NULL else sequential_sum(abs(errors))/length(errors)
training_rmse <- function(training,predict) {
  errors <- vapply(training,function(r) r$rating-predict(r$u,r$i),numeric(1))
  sqrt(sequential_sum(errors*errors)/length(training))
}
rank_weight <- function(rank) 1/log2(rank+1L)
ranking_metrics <- function(ranked,relevant,cutoff) {
  hits <- 0L
  dcg <- average_precision <- reciprocal_rank <- 0
  for (rank in seq_len(cutoff)) {
    if (!(ranked[rank] %in% relevant)) next
    hits <- hits+1L
    dcg <- dcg+rank_weight(rank)
    average_precision <- average_precision+hits/rank
    if (reciprocal_rank == 0) reciprocal_rank <- 1/rank
  }
  ideal <- min(cutoff,length(relevant))
  ideal_dcg <- sequential_sum(vapply(seq_len(ideal),rank_weight,numeric(1)))
  list(
      hits=hits,
      recall=hits/length(relevant),
      ndcg=dcg/ideal_dcg,
      ap=average_precision/ideal,
      rr=reciprocal_rank
  )
}
