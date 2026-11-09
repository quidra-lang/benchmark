bit_at(index) = 1 << (index - 1)
has_item(mask, index) = mask & bit_at(index) != 0
function lex_less(a, b)
    for i in 1:min(length(a), length(b))
        a[i] != b[i] && return a[i] < b[i]
    end
    return length(a) < length(b)
end
function bid_shares(items, reserves, bids, decided=0)
    result = Any[]
    for i in eachindex(items)
        has_item(decided, i) && continue
        share, source = reserves[items[i]] // 1, 0
        for bid in bids
            if has_item(bid.bundle, i)
                candidate = bid.amount // count_ones(bid.bundle)
                if candidate > share
                    share, source = candidate, bid.number
                end
            end
        end
        push!(result, (item=items[i], share=share, source=source))
    end
    return result
end
function solve_wdp(items, reserves, bids)
    ordered = sort(bids; by=b -> b.number)
    shares = bid_shares(items, reserves, ordered)
    root_bound = sum((record.share for record in shares); init=0//1)
    nodes, pruned, leaves = 0, 0, 0
    best_welfare = nothing
    best_numbers = Int[]
    improvements = Any[]
    complete = (1 << length(items)) - 1
    function visit(decided, used, welfare, chosen)
        nodes += 1
        if decided == complete
            leaves += 1
            numbers = sort([b.number for b in chosen])
            if best_welfare === nothing || welfare > best_welfare || (welfare == best_welfare && lex_less(
                numbers,
                best_numbers
            ))
                best_welfare, best_numbers = welfare, numbers
                push!(improvements, (nodes=nodes, welfare=welfare, numbers=copy(numbers)))
            end
            return
        end
        usable = [b for b in ordered if b.bundle & decided == 0 && !(b.xor && has_item(used, b.bidder))]
        bound = welfare + sum((record.share for record in bid_shares(
            items,
            reserves,
            usable,
            decided
        )); init=0//1)
        if best_welfare !== nothing && bound < best_welfare
            pruned += 1
            return
        end
        first_item = findfirst(i -> !has_item(decided, i), eachindex(items))
        for bid in usable
            if has_item(bid.bundle, first_item)
                next_used = bid.xor ? used | bit_at(bid.bidder) : used
                visit(decided | bid.bundle, next_used, welfare + bid.amount, [chosen; bid])
            end
        end
        visit(decided | bit_at(first_item), used, welfare + reserves[items[first_item]], chosen)
    end
    visit(0, 0, 0, Bid[])
    winning = [b for b in ordered if b.number in best_numbers]
    return (welfare=best_welfare, numbers=best_numbers, winning=winning, nodes=nodes, pruned=pruned,
            leaves=leaves, improvements=improvements, shares=shares, bound=root_bound)
end
function greedy_order(bids)
    return sort(bids; lt=(a,b) -> begin
        left = a.amount * a.amount * count_ones(b.bundle)
        right = b.amount * b.amount * count_ones(a.bundle)
        left == right ? a.number < b.number : left > right
    end)
end
function greedy_select(bids)
    occupied, used = 0, 0
    chosen = Bid[]
    for bid in bids
        if bid.bundle & occupied != 0 || (bid.xor && has_item(used, bid.bidder))
            continue
        end
        push!(chosen, bid)
        occupied |= bid.bundle
        bid.xor && (used |= bit_at(bid.bidder))
    end
    return chosen
end
