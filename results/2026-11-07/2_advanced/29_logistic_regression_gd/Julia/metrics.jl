using Printf
function fixed(value,places=4)
    text = Printf.format(Printf.Format("%.$(places)f"),value)
    startswith(text,"-") && parse(Float64,text) == 0 ? text[2:end] : text
end
function ratio(a,b)
    b == 0 && return "-"
    q = (20000a+b)÷(2b)
    "$(q÷10000).$(lpad(string(q%10000),4,'0'))"
end
function fraction(a,b)
    divisor = gcd(a,b)
    "$(a÷divisor)/$(b÷divisor) $(ratio(a,b))"
end
fraction(value::Tuple) = fraction(value...)
function confusion(predictions,targets)
    (
        tp=count(i->predictions[i] == 1 && targets[i] == 1,eachindex(targets)),
        fp=count(i->predictions[i] == 1 && targets[i] == 0,eachindex(targets)),
        tn=count(i->predictions[i] == 0 && targets[i] == 0,eachindex(targets)),
        fn=count(i->predictions[i] == 0 && targets[i] == 1,eachindex(targets))
    )
end
function auc(scores,targets)
    order = sortperm(scores)
    positives = sum(targets)
    rank_sum,start = 0,1
    while start <= length(order)
        stop = start
        while stop < length(order) && scores[order[stop+1]] == scores[order[start]]
            stop += 1
        end
        for position in start:stop
            targets[order[position]] == 1 && (rank_sum+=start+stop)
        end
        start = stop+1
    end
    rank_sum-positives*(positives+1),2*positives*(length(targets)-positives)
end
function roc_points(probabilities,targets)
    order = sortperm(eachindex(probabilities),by=i->(-probabilities[i],i))
    points = NamedTuple[]
    tp,fp = 0,0
    for (position,i) in enumerate(order)
        targets[i] == 1 ? (tp+=1) : (fp+=1)
        if position == length(order) || probabilities[order[position+1]] != probabilities[i]
            push!(points,(threshold=probabilities[i],tp=tp,fp=fp))
        end
    end
    points
end
