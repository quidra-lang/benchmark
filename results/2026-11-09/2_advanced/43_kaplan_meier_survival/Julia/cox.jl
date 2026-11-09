function evaluate_cox(subjects,vectors,beta)
    p = length(beta)
    predictors = [total(beta[c]*x[c] for c in 1:p) for x in vectors]
    risks = exp.(predictors)
    order = sort(collect(eachindex(subjects));by=i->(-subjects[i].time,subjects[i].id))
    s0 = likelihood = 0.0
    s1,score = zeros(p),zeros(p)
    s2,information = zeros(p,p),zeros(p,p)
    event_sums = Dict{Int,Any}()
    position = 1
    while position<=length(order)
        time = subjects[order[position]].time
        stop = position
        while stop<=length(order) && subjects[order[stop]].time==time
            stop += 1
        end
        indices = order[position:stop-1]
        for i in indices
            risk,x = risks[i],vectors[i]
            s0 += risk
            for c in 1:p
                s1[c] += risk*x[c]
                for d in 1:p
                    s2[c,d] += risk*x[c]*x[d]
                end
            end
        end
        events = [i for i in indices if subjects[i].event==1]
        if !isempty(events)
            n = length(events)
            likelihood += total(predictors[i] for i in events)-n*log(s0)
            for c in 1:p
                score[c] += sum(vectors[i][c] for i in events)-n*s1[c]/s0
                for d in 1:p
                    information[c,d] += n*(s2[c,d]/s0-(s1[c]/s0)*(s1[d]/s0))
                end
            end
            event_sums[time] = (s0=s0,s1=copy(s1),events=n)
        end
        position = stop
    end
    (loglik=likelihood,score=score,information=information,predictors=predictors,event_sums=event_sums)
end
function fit_cox(subjects,vectors)
    beta = zeros(length(vectors[1]))
    null = evaluate_cox(subjects,vectors,beta)
    current = null
    iterations = []
    for iteration in 1:25
        change = solve_system(current.information,current.score)
        beta = beta.+change
        push!(iterations,(iteration,current.loglik,copy(beta)))
        current = evaluate_cox(subjects,vectors,beta)
    end
    (beta=beta,null=null,final=current,iterations=iterations)
end
