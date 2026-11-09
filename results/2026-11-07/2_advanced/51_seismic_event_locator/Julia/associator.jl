function associate(picks,window,minimum)
    candidates = NamedTuple[]
    for (index,first_pick) in enumerate(picks)
        first_pick.assigned && continue
        chosen = Pick[]
        seen = Set{Int}()
        for pick in picks[index:end]
            pick.sample>first_pick.sample+window && break
            (pick.assigned || pick.station in seen) && continue
            push!(chosen,pick)
            push!(seen,pick.station)
        end
        length(chosen)<minimum && continue
        for pick in chosen
            pick.assigned = true
        end
        push!(candidates,(number=length(candidates)+1,first=first_pick,picks=chosen))
    end
    candidates
end
