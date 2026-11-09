function vcg_payments(items, reserves, bids, optimal, bidder_count)
    details = Dict{Int,Any}()
    for k in 1:bidder_count
        winning = [b for b in optimal.winning if b.bidder == k]
        isempty(winning) && continue
        alternative = solve_wdp(items, reserves, [b for b in bids if b.bidder != k])
        value = sum(b.amount for b in winning)
        details[k] = (paid=alternative.welfare - (optimal.welfare - value), alternative=alternative)
    end
    return details
end
function critical_payments(order, winning, items, reserves)
    result = Dict{Int,Any}()
    for bid in winning
        selected = greedy_select([b for b in order if b.number != bid.number])
        index = findfirst(b -> b.bundle & bid.bundle != 0 || (bid.xor && bid.bidder == b.bidder), selected)
        rival = index === nothing ? nothing : selected[index]
        payment = sum(reserves[items[i]] for i in eachindex(items) if has_item(bid.bundle, i))
        if rival !== nothing
            threshold = rival.amount * rival.amount * count_ones(bid.bundle)
            earlier(t) = t * t * count_ones(rival.bundle) > threshold || (t * t * count_ones(rival.bundle) == threshold && bid.number < rival.number)
            low, high = 1, 1
            while !earlier(high)
                high *= 2
            end
            while low < high
                middle = (low + high) ÷ 2
                if earlier(middle)
                    high = middle
                else
                    low = middle + 1
                end
            end
            payment = max(payment, low)
        end
        result[bid.number] = (paid=payment, rival=rival)
    end
    return result
end
function coalition_welfares(items, reserves, bids, bidder_count)
    masks = collect(0:((1 << bidder_count) - 1))
    positions(mask) = [i for i in 1:bidder_count if has_item(mask, i)]
    sort!(masks; lt=(a,b) -> count_ones(a) == count_ones(b) ? lex_less(
        positions(a),
        positions(b)
    ) : count_ones(a) < count_ones(b))
    result = Any[]
    for mask in masks
        search = solve_wdp(items, reserves, [b for b in bids if has_item(mask, b.bidder)])
        push!(result, (mask=mask, members=positions(mask), welfare=search.welfare, numbers=search.numbers))
    end
    return result
end
function blocking_coalitions(coalitions, seller, utilities)
    blocking, minimal = Any[], Any[]
    for coalition in coalitions
        payoff = seller + sum((utilities[k] for k in coalition.members); init=0)
        if coalition.welfare > payoff
            record = (coalition=coalition, payoff=payoff, deficit=coalition.welfare - payoff)
            if !any(previous.coalition.mask & coalition.mask == previous.coalition.mask for previous in blocking)
                push!(minimal, record)
            end
            push!(blocking, record)
        end
    end
    return blocking, minimal
end
gsp_price(ranking, rank) = rank < length(ranking) ? ranking[rank+1].bid : 0
function slot_vcg_payment(ranking, rates, rank)
    payment = 0//1
    for following in (rank+1):min(length(ranking), length(rates)+1)
        next_rate = following <= length(rates) ? rates[following] : 0//1
        payment += ranking[following].value * (rates[following-1] - next_rate)
    end
    return payment
end
