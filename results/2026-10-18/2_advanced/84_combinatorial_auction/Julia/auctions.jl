function enumerate_candidates(bids, xor)
    result = Any[]
    for number in 1:((1 << length(bids)) - 1)
        xor && count_ones(number) != 1 && continue
        bundle, value, feasible = 0, 0, true
        for (i, bid) in enumerate(bids)
            has_item(number, i) || continue
            if bundle & bid.bundle != 0
                feasible = false
                break
            end
            bundle |= bid.bundle
            value += bid.amount
        end
        feasible && push!(result, (number=number, bundle=bundle, value=value))
    end
    return result
end
value_of(candidates, items) = maximum((c.value for c in candidates if c.bundle & items == c.bundle); init=0)
function english_auction(participants, reserve, increment)
    price, steps, winner, paid = reserve, 0, 0, 0
    remaining = findall(p -> p.value >= price, participants)
    while length(remaining) >= 2
        previous = remaining
        price += increment
        steps += 1
        remaining = findall(p -> p.value >= price, participants)
        if isempty(remaining)
            winner, paid = previous[1], price - increment
            break
        end
    end
    if winner == 0 && !isempty(remaining)
        winner, paid = remaining[1], price
    end
    drops = [begin
        drop = p.value < reserve ? reserve : reserve + ((p.value-reserve) ÷ increment + 1) * increment
        drop <= price ? string(drop) : "-"
    end for p in participants]
    return (winner=winner, price=paid, steps=steps, drops=drops)
end
function dutch_auction(participants, reserve, start, decrement)
    price, steps = start, 0
    while price >= reserve
        eligible = findall(p -> p.bid >= price, participants)
        if !isempty(eligible)
            winner = eligible[argmax([participants[i].bid for i in eligible])]
            return (winner=winner, price=price, steps=steps)
        end
        price -= decrement
        steps += 1
    end
    return (winner=0, price=0, steps=steps)
end
