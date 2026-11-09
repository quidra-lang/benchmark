function sequential_sum(values)
    total = 0.0
    for value in values
        total += value
    end
    total
end
clip(value) = value<1 ? 1.0 : value>5 ? 5.0 : value
rmse(errors) = isempty(errors) ? nothing : sqrt(sequential_sum(e*e for e in errors)/length(errors))
mae(errors) = isempty(errors) ? nothing : sequential_sum(abs(e) for e in errors)/length(errors)
training_rmse(
    training,
    predict
) = sqrt(sequential_sum((r.rating-predict(r.u,r.i))^2 for r in training)/length(training))
rank_weight(rank) = 1/log2(rank+1)
function ranking_metrics(ranked,relevant,cutoff)
    hits = 0
    dcg = average_precision = reciprocal_rank = 0.0
    for (rank,item) in enumerate(ranked[1:cutoff])
        item in relevant || continue
        hits += 1
        dcg += rank_weight(rank)
        average_precision += hits/rank
        reciprocal_rank==0 && (reciprocal_rank=1/rank)
    end
    ideal = min(cutoff,length(relevant))
    ideal_dcg = sequential_sum(rank_weight(rank) for rank in 1:ideal)
    (hits=hits,recall=hits/length(relevant),ndcg=dcg/ideal_dcg,ap=average_precision/ideal,rr=reciprocal_rank)
end
