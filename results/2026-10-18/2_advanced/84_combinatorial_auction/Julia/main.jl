include("bids_io.jl")
include("wdp_solver.jl")
include("payments.jl")
include("auctions.jl")
include("report.jl")
line(parts...) = join(string.(parts), " ")
const MECHANISMS = ["vcg", "pay_as_bid", "greedy", "critical", "saa"]
const OUTCOMES = ["vcg", "greedy", "critical", "saa"]
const FORMATS = ["first_price", "second_price", "english", "dutch", "all_pay"]
function allocation(bids, items, reserves)
    winning = sort(bids; by=b -> b.number)
    owners = zeros(Int, length(items))
    for bid in winning, i in eachindex(items)
        has_item(bid.bundle, i) && (owners[i] = bid.bidder)
    end
    unsold = items[owners .== 0]
    accepted = sum((b.amount for b in winning); init=0)
    retained = sum((reserves[item] for item in unsold); init=0)
    return (
        winning=winning,
        owners=owners,
        unsold=unsold,
        accepted=accepted,
        retained=retained,
        welfare=accepted+retained
    )
end
function validate_bids(raw, reserves, parameters)
    bidders, valid, eligible, below, rejected = Any[], Bid[], Bid[], Any[], Any[]
    seen = Set{String}()
    bid_count = 0
    for entry in raw.lines
        error = entry.name in seen ? "duplicate bidder" : !(entry.language in (
            "XOR",
            "OR"
        )) ? "bad language " * entry.language : ""
        push!(seen, entry.name)
        bidder = nothing
        if isempty(error)
            bidder = (name=entry.name, language=entry.language, valid=Bid[], eligible=Bid[])
            push!(bidders, bidder)
        end
        for text in entry.texts
            bid_count += 1
            reason = error
            mask, amount = 0, 0
            if isempty(reason)
                if !occursin(r"^[a-z]+(?:\+[a-z]+)*:(?:0|[1-9][0-9]{0,4})$", text)
                    reason = "malformed bid"
                else
                    bundle_part, amount_part = split(text, ':')
                    names = split(bundle_part, '+')
                    for name in names
                        if !haskey(reserves, name)
                            reason = "unknown item " * name
                        elseif !(name in raw.items)
                            reason = "item not offered " * name
                        else
                            index = findfirst(==(name), raw.items)
                            if has_item(mask, index)
                                reason = "duplicate item " * name
                            else
                                mask |= bit_at(index)
                            end
                        end
                        isempty(reason) || break
                    end
                    if isempty(reason)
                        amount = parse(Int, amount_part)
                        duplicate = findfirst(b -> b.bundle == mask, bidder.valid)
                        if length(names) > parameters["max_bundle_size"]
                            reason = "bundle too large"
                        elseif amount == 0
                            reason = "zero value"
                        elseif duplicate !== nothing
                            reason = "duplicate bundle " * string(bidder.valid[duplicate].number)
                        elseif length(bidder.valid) >= parameters["max_bids_per_bidder"]
                            reason = "too many bids"
                        end
                    end
                end
            end
            if !isempty(reason)
                push!(rejected, (number=bid_count, name=entry.name, reason=reason))
                continue
            end
            bid = Bid(bid_count, length(bidders), mask, amount, entry.language == "XOR")
            push!(valid, bid)
            push!(bidder.valid, bid)
            reserve = sum(reserves[raw.items[i]] for i in eachindex(raw.items) if has_item(mask, i))
            if amount >= reserve
                push!(eligible, bid)
                push!(bidder.eligible, bid)
            else
                push!(below, (bid=bid, reserve=reserve))
            end
        end
    end
    return (
        bidders=bidders,
        valid=valid,
        eligible=eligible,
        below=below,
        rejected=rejected,
        bid_count=bid_count
    )
end
function ascending_auction(a, reserves, parameters)
    items, names = a.items, a.names
    choices = [enumerate_candidates(b.valid, b.language == "XOR") for b in a.bidders]
    eligibility = [maximum((count_ones(c.bundle) for c in options); init=0) for options in choices]
    prices = [reserves[item] for item in items]
    holders, bid_counts, bid_rounds, last_rounds = [zeros(Int, length(items)) for _ in 1:4]
    state = parameters["seed"]
    increment = parameters["saa_increment"]
    lines = [line("AUCTION", a.name, "increment", increment)]
    final_round, reason = 0, "cap"
    for r in 1:parameters["round_cap"]
        final_round = r
        activities, new_by_bidder = zeros(Int, length(names)), zeros(Int, length(names))
        new_by_item = [Int[] for _ in items]
        for k in eachindex(names)
            held = sum((bit_at(i) for i in eachindex(items) if holders[i] == k); init=0)
            chosen, best_surplus = 0, 0
            for candidate in choices[k]
                count_ones(candidate.bundle | held) > eligibility[k] && continue
                asking = sum((prices[i] + (holders[i] != 0 && holders[i] != k ? increment : 0) for i in eachindex(items) if has_item(
                    candidate.bundle,
                    i
                )); init=0)
                surplus = candidate.value - asking
                if surplus > best_surplus
                    chosen, best_surplus = candidate.bundle, surplus
                end
            end
            activities[k] = count_ones(chosen | held)
            new_by_bidder[k] = chosen & ~held
            for i in eachindex(items)
                has_item(new_by_bidder[k], i) && push!(new_by_item[i], k)
            end
        end
        demand = sum(count_ones, new_by_bidder)
        if demand > 0
            suffix = join(
                [string(
                    names[k],
                    ":",
                    bundle_text(new_by_bidder[k], items)
                ) for k in eachindex(names) if new_by_bidder[k] != 0],
                " "
            )
            push!(lines, line("ROUND", r, "demand", demand, suffix))
            for i in eachindex(items)
                new_bidders = new_by_item[i]
                isempty(new_bidders) && continue
                winner = new_bidders[1]
                if length(new_bidders) >= 2
                    state = 48271 * state % 2147483647
                    winner = new_bidders[state % length(new_bidders) + 1]
                end
                holders[i] != 0 && (prices[i] += increment)
                holders[i] = winner
                bid_counts[i] += length(new_bidders)
                bid_rounds[i] += 1
                last_rounds[i] = r
            end
            standing = [string(
                items[i],
                "=",
                prices[i],
                "@",
                holders[i] == 0 ? "-" : names[holders[i]]
            ) for i in eachindex(items)]
            push!(lines, line("STANDING", join(standing, " ")))
        else
            push!(lines, line("ROUND", r, "none"))
        end
        changed = String[]
        for k in eachindex(names)
            if activities[k] < eligibility[k]
                eligibility[k] = activities[k]
                push!(changed, string(names[k], "=", eligibility[k]))
            end
        end
        isempty(changed) || push!(lines, line("ELIGIBILITY", join(changed, " ")))
        if demand == 0
            reason = "quiet"
            break
        end
    end
    push!(lines, line("END rounds", final_round, reason))
    for i in eachindex(items)
        if holders[i] == 0
            push!(lines, line("ITEM", items[i], "unsold reserve", reserves[items[i]]))
        else
            push!(
                lines,
                line(
                    "ITEM",
                    items[i],
                    "price",
                    prices[i],
                    "holder",
                    names[holders[i]],
                    "bids",
                    bid_counts[i],
                    "rounds",
                    bid_rounds[i],
                    "last",
                    last_rounds[i]
                )
            )
        end
    end
    payments, utilities = zeros(Int, length(names)), zeros(Int, length(names))
    values_total, exposure, exposed = 0, 0, 0
    for k in eachindex(names)
        won = sum((bit_at(i) for i in eachindex(items) if holders[i] == k); init=0)
        payments[k] = sum((prices[i] for i in eachindex(items) if holders[i] == k); init=0)
        value = value_of(choices[k], won)
        utilities[k] = value - payments[k]
        values_total += value
        if utilities[k] < 0
            exposure -= utilities[k]
            exposed += 1
        end
        text = line(
            "BIDDER",
            names[k],
            "won",
            bundle_text(won, items),
            "paid",
            payments[k],
            "value",
            value,
            "utility",
            utilities[k],
            "eligibility",
            eligibility[k]
        )
        push!(lines, text * (utilities[k] < 0 ? " exposed" : ""))
    end
    revenue = sum(payments)
    retained = sum((reserves[items[i]] for i in eachindex(items) if holders[i] == 0); init=0)
    welfare = values_total + retained
    push!(
        lines,
        line(
            "TOTAL revenue",
            revenue,
            "welfare",
            welfare,
            "efficiency",
            fraction(welfare//a.exact.welfare),
            "exposure",
            exposure,
            "exposed",
            exposed
        )
    )
    return (
        lines=lines,
        payments=payments,
        utilities=utilities,
        revenue=revenue,
        retained=retained,
        welfare=welfare,
        rounds=final_round,
        reason=reason,
        exposure=exposure,
        exposed=exposed
    )
end
function prepare_auction(raw, reserves, parameters)
    validated = validate_bids(raw, reserves, parameters)
    names = [b.name for b in validated.bidders]
    optimal = solve_wdp(raw.items, reserves, validated.eligible)
    exact = allocation(optimal.winning, raw.items, reserves)
    order = greedy_order(validated.eligible)
    greedy = allocation(greedy_select(order), raw.items, reserves)
    critical = critical_payments(order, greedy.winning, raw.items, reserves)
    details = vcg_payments(raw.items, reserves, validated.eligible, optimal, length(names))
    values = [sum((b.amount for b in exact.winning if b.bidder == k); init=0) for k in eachindex(names)]
    greedy_values = [sum((b.amount for b in greedy.winning if b.bidder == k); init=0) for k in eachindex(names)]
    paid = [haskey(details, k) ? details[k].paid : 0 for k in eachindex(names)]
    critical_paid = [sum((critical[b.number].paid for b in greedy.winning if b.bidder == k); init=0) for k in eachindex(names)]
    a = (; validated..., name=raw.name, items=raw.items, names=names, optimal=optimal, exact=exact, order=order, greedy=greedy, critical=critical,
          details=details, values=values, greedy_values=greedy_values, paid=paid, critical_paid=critical_paid,
          utilities=values-paid, critical_utilities=greedy_values-critical_paid, revenue=sum(paid), critical_revenue=sum(critical_paid))
    return (; a..., saa=ascending_auction(a, reserves, parameters))
end
function wdp_lines(a, reserves)
    lines = [line(
        "AUCTION",
        a.name,
        "items",
        length(a.items),
        "bidders",
        length(a.names),
        "bids",
        a.bid_count,
        "valid",
        length(a.valid),
        "eligible",
        length(a.eligible)
    )]
    for bidder in a.bidders
        push!(
            lines,
            line(
                "BIDDER",
                bidder.name,
                bidder.language,
                "valid",
                length(bidder.valid),
                "eligible",
                length(bidder.eligible)
            )
        )
    end
    for r in a.rejected
        push!(lines, line("REJECT", r.number, r.name, r.reason))
    end
    for r in a.below
        push!(
            lines,
            line(
                "BELOW_RESERVE",
                r.bid.number,
                a.names[r.bid.bidder],
                "value",
                r.bid.amount,
                "reserve",
                r.reserve
            )
        )
    end
    for s in a.optimal.shares
        push!(
            lines,
            line("SHARE", s.item, fraction(s.share), s.source == 0 ? "reserve" : line("bid", s.source))
        )
    end
    push!(lines, line("ROOT_BOUND", fraction(a.optimal.bound)))
    for r in a.optimal.improvements
        push!(lines, line("IMPROVE", r.nodes, "welfare", r.welfare, "bids", number_text(r.numbers)))
    end
    e, g = a.exact, a.greedy
    push!(
        lines,
        line(
            "OPTIMAL welfare",
            e.welfare,
            "accepted",
            e.accepted,
            "retained",
            e.retained,
            "winners",
            length(e.winning)
        )
    )
    for b in e.winning
        push!(lines, line("WIN", b.number, a.names[b.bidder], bundle_text(b.bundle, a.items), b.amount))
    end
    push!(lines, line("UNSOLD", isempty(e.unsold) ? "-" : join(e.unsold, " ")))
    push!(
        lines,
        line(
            "SEARCH nodes",
            a.optimal.nodes,
            "pruned",
            a.optimal.pruned,
            "leaves",
            a.optimal.leaves,
            "improvements",
            length(a.optimal.improvements)
        )
    )
    push!(lines, line("GREEDY_ORDER", isempty(a.order) ? "-" : join([b.number for b in a.order], " ")))
    push!(
        lines,
        line(
            "GREEDY welfare",
            g.welfare,
            "accepted",
            g.accepted,
            "retained",
            g.retained,
            "winners",
            length(g.winning),
            "efficiency",
            fraction(g.welfare//e.welfare)
        )
    )
    for b in g.winning
        c = a.critical[b.number]
        push!(
            lines,
            line(
                "GWIN",
                b.number,
                a.names[b.bidder],
                bundle_text(b.bundle, a.items),
                b.amount,
                "critical",
                c.paid,
                "against",
                c.rival === nothing ? "-" : string(c.rival.number)
            )
        )
    end
    push!(lines, line("GUNSOLD", isempty(g.unsold) ? "-" : join(g.unsold, " ")))
    for i in eachindex(a.items)
        push!(lines, line("ITEM", a.items[i], "reserve", reserves[a.items[i]], "demand", count(b -> has_item(b.bundle, i), a.eligible),
                          "optimal", e.owners[i] == 0 ? "-" : a.names[e.owners[i]], "greedy", g.owners[i] == 0 ? "-" : a.names[g.owners[i]]))
    end
    return lines
end
function vcg_lines(a)
    lines = [line("AUCTION", a.name, "welfare", a.exact.welfare)]
    for k in eachindex(a.names)
        if !haskey(a.details, k)
            push!(lines, line("BIDDER", a.names[k], "lost"))
        else
            alternate = a.details[k].alternative
            won = [b.number for b in a.exact.winning if b.bidder == k]
            push!(lines, line("BIDDER", a.names[k], "won", number_text(won), "value", a.values[k], "without", alternate.welfare,
                              "alternative", number_text(alternate.numbers), "payment", a.paid[k], "utility", a.utilities[k]))
        end
    end
    push!(
        lines,
        line(
            "TOTAL revenue",
            a.revenue,
            "pay_as_bid",
            a.exact.accepted,
            "retained",
            a.exact.retained,
            "seller",
            a.revenue+a.exact.retained,
            "bidders",
            sum(a.utilities)
        )
    )
    for k in eachindex(a.names)
        push!(
            lines,
            line(
                "PAYMENTS",
                a.names[k],
                "vcg",
                a.paid[k],
                "pay_as_bid",
                a.values[k],
                "greedy",
                a.greedy_values[k],
                "critical",
                a.critical_paid[k],
                "saa",
                a.saa.payments[k]
            )
        )
    end
    for k in eachindex(a.names)
        push!(
            lines,
            line(
                "UTILITIES",
                a.names[k],
                "vcg",
                a.utilities[k],
                "critical",
                a.critical_utilities[k],
                "saa",
                a.saa.utilities[k]
            )
        )
    end
    return lines
end
function core_lines(a, reserves, parameters)
    lines = [line("AUCTION", a.name, "bidders", length(a.names))]
    counts = Dict(name => 0 for name in ["checked", "skipped", OUTCOMES...])
    if length(a.names) > parameters["core_max_bidders"]
        push!(lines, "SKIPPED")
        counts["skipped"] = 1
        return lines, counts
    end
    counts["checked"] = 1
    coalitions = coalition_welfares(a.items, reserves, a.eligible, length(a.names))
    push!(lines, line("COALITIONS", length(coalitions)))
    outcomes = [(a.revenue+a.exact.retained, a.utilities), (a.greedy.welfare, zeros(Int, length(a.names))),
                (
                    a.critical_revenue+a.greedy.retained,
                    a.critical_utilities
                ), (a.saa.revenue+a.saa.retained, a.saa.utilities)]
    member_text(c) = isempty(c.members) ? "-" : join(a.names[c.members], "+")
    for (name, (seller, utilities)) in zip(OUTCOMES, outcomes)
        push!(lines, line("OUTCOME", name, "seller", seller, "utilities", join(utilities, " ")))
        blocking, minimal = blocking_coalitions(coalitions, seller, utilities)
        for r in minimal
            c = r.coalition
            push!(
                lines,
                line(
                    "BLOCK",
                    member_text(c),
                    "welfare",
                    c.welfare,
                    "payoff",
                    r.payoff,
                    "deficit",
                    r.deficit,
                    "bids",
                    number_text(c.numbers)
                )
            )
        end
        if isempty(blocking)
            push!(lines, "RESULT core")
            counts[name] += 1
        else
            worst = blocking[argmax([r.deficit for r in blocking])]
            push!(
                lines,
                line(
                    "RESULT blocked",
                    length(blocking),
                    "minimal",
                    length(minimal),
                    "max_deficit",
                    worst.deficit,
                    "by",
                    member_text(worst.coalition)
                )
            )
        end
    end
    return lines, counts
end
function duplicate_name(participants)
    seen = Set{String}()
    for p in participants
        p.name in seen && return p.name
        push!(seen, p.name)
    end
    return ""
end
function lot_lines(group, parameters, summary)
    p = group.participants
    reserve = parse(Int, group.arguments[1])
    eligible = findall(b -> b.bid >= reserve, p)
    first_winner = isempty(eligible) ? 0 : eligible[argmax([p[i].bid for i in eligible])]
    efficient = argmax([b.value for b in p])
    optimum = max(reserve, p[efficient].value)
    p[efficient].value < reserve && (efficient = 0)
    lines = [line(
        "LOT",
        group.name,
        "reserve",
        reserve,
        "bidders",
        length(p),
        "efficient",
        efficient == 0 ? "-" : p[efficient].name,
        "optimum",
        optimum
    )]
    first_price = first_winner == 0 ? 0 : p[first_winner].bid
    second_price = efficient == 0 ? 0 : maximum([reserve; [p[i].value for i in eachindex(p) if i != efficient && p[i].value >= reserve]])
    english = english_auction(p, reserve, parameters["english_increment"])
    dutch = dutch_auction(p, reserve, parameters["dutch_start"], parameters["dutch_decrement"])
    mechanisms = [(first_winner, first_price, nothing), (efficient, second_price, nothing),
                  (
                      english.winner,
                      english.price,
                      english.steps
                  ), (dutch.winner, dutch.price, dutch.steps), (first_winner, first_price, nothing)]
    results = Any[]
    for (name, (winner, price, steps)) in zip(FORMATS, mechanisms)
        utilities = zeros(Int, length(p))
        revenue = price
        if name == "all_pay"
            revenue = sum((p[i].bid for i in eligible); init=0)
            for i in eligible
                utilities[i] = -p[i].bid
            end
        end
        welfare = winner == 0 ? reserve : p[winner].value
        if winner == 0
            text = uppercase(name) * " unsold"
        else
            utilities[winner] = p[winner].value-price
            text = line(
                uppercase(name),
                "winner",
                p[winner].name,
                "price",
                price,
                "utility",
                utilities[winner]
            )
        end
        steps !== nothing && (text *= line(" steps", steps))
        efficiency = welfare//optimum
        push!(lines, text * line(" revenue", revenue, "welfare", welfare, "efficiency", fraction(efficiency)))
        if name == "english"
            push!(
                lines,
                line(
                    "ENGLISH_DROPS",
                    join([string(p[i].name, "=", english.drops[i]) for i in eachindex(p)], " ")
                )
            )
        end
        push!(results, (name=name, utilities=utilities, revenue=revenue))
        push!(summary, string(group.name, "/", name, ",", revenue, ",", welfare, ",", fraction(efficiency)))
    end
    for i in eachindex(p)
        push!(lines, line("UTILITY", p[i].name, join([r.utilities[i] for r in results], " ")))
    end
    ranking = sortperm(eachindex(results); by=i -> (-results[i].revenue, i))
    push!(lines, line("RANKING", join([results[i].name for i in ranking], " ")))
    return lines
end
function slots_lines(group, rates, summary, totals)
    by_bid = sort(group.participants; alg=MergeSort, by=p -> -p.bid)
    by_value = sort(group.participants; alg=MergeSort, by=p -> -p.value)
    n, k = length(by_bid), length(rates)
    lines = [line("SLOTS", group.name, "slots", k, "advertisers", n)]
    gsp_revenue, gsp_welfare, vcg_revenue, optimum = 0//1, 0//1, 0//1, 0//1
    for s in 1:min(n,k)
        p, rate = by_bid[s], rates[s]
        price = gsp_price(by_bid, s)
        payment, utility = rate*price, rate*(p.value-price)
        gsp_revenue += payment
        gsp_welfare += rate*p.value
        optimum += rate*by_value[s].value
        push!(
            lines,
            line(
                "GSP",
                s,
                p.name,
                "ctr",
                fraction(rate),
                "bid",
                p.bid,
                "price",
                price,
                "payment",
                fraction(payment),
                "utility",
                fraction(utility)
            )
        )
    end
    efficiency = gsp_welfare/optimum
    push!(
        lines,
        line(
            "GSP_TOTAL revenue",
            fraction(gsp_revenue),
            "welfare",
            fraction(gsp_welfare),
            "efficiency",
            fraction(efficiency)
        )
    )
    for s in 1:min(n,k)
        p, rate = by_value[s], rates[s]
        payment = slot_vcg_payment(by_value, rates, s)
        vcg_revenue += payment
        push!(
            lines,
            line(
                "VCG",
                s,
                p.name,
                "ctr",
                fraction(rate),
                "value",
                p.value,
                "payment",
                fraction(payment),
                "price",
                fraction(payment/rate),
                "utility",
                fraction(rate*p.value-payment)
            )
        )
    end
    push!(
        lines,
        line("VCG_TOTAL revenue", fraction(vcg_revenue), "welfare", fraction(optimum), "efficiency 1")
    )
    violations, deviations = 0, 0
    for s in 2:min(n,k+1)
        p = by_bid[s]
        rate = s <= k ? rates[s] : 0//1
        stay, swap = rate*(p.value-gsp_price(by_bid,s)), rates[s-1]*(p.value-p.bid)
        violated = stay < swap
        violations += violated
        push!(
            lines,
            line(
                "ENVY",
                s,
                p.name,
                "stay",
                fraction(stay),
                "swap",
                fraction(swap),
                violated ? "violated" : "ok"
            )
        )
    end
    push!(lines, violations == 0 ? "ENVY_FREE yes" : line("ENVY_FREE no violations", violations))
    for s in 1:n
        p = by_bid[s]
        current = (s <= k ? rates[s] : 0//1)*(p.value-gsp_price(by_bid,s))
        for t in 1:k
            t == s && continue
            price = t < s ? (t <= n ? by_bid[t].bid : 0) : gsp_price(by_bid,t)
            payoff = rates[t]*(p.value-price)
            if payoff > current
                deviations += 1
                push!(lines, line("DEVIATE", p.name, "from", s, "to", t, "gain", fraction(payoff-current)))
            end
        end
    end
    push!(lines, deviations == 0 ? "NASH yes" : line("NASH no deviations", deviations))
    equilibrium = violations == 0 && deviations == 0
    push!(lines, line("EQUILIBRIUM", equilibrium ? "yes" : "no"))
    totals["envy_free"] += violations == 0
    totals["nash"] += deviations == 0
    totals["equilibria"] += equilibrium
    push!(
        summary,
        string(
            group.name,
            "/gsp,",
            fraction(gsp_revenue),
            ",",
            fraction(gsp_welfare),
            ",",
            fraction(efficiency)
        )
    )
    push!(summary, string(group.name, "/vcg,", fraction(vcg_revenue), ",", fraction(optimum), ",1"))
    return lines
end
function process_groups(groups, parameters, summary)
    lines = String[]
    totals = Dict(name => 0 for name in ["lots", "slot_groups", "errors", "envy_free", "nash", "equilibria"])
    for group in groups
        totals[group.kind == "lot" ? "lots" : "slot_groups"] += 1
        error, rates = "", Rational{Int}[]
        if group.kind == "slots"
            for text in group.arguments
                if !occursin(r"^[1-9][0-9]*/[1-9][0-9]*$", text)
                    error = "bad ctr " * text
                    break
                end
                numerator_value, denominator_value = parse.(Int, split(text,'/'))
                rate = numerator_value//denominator_value
                if rate > 1 || (!isempty(rates) && rate >= rates[end])
                    error = "bad ctr " * text
                    break
                end
                push!(rates, rate)
            end
        end
        if isempty(error)
            if isempty(group.participants)
                error = group.kind == "lot" ? "no bidders" : "no advertisers"
            else
                duplicate = duplicate_name(group.participants)
                if !isempty(duplicate)
                    error = (group.kind == "lot" ? "duplicate bidder " : "duplicate advertiser ") * duplicate
                elseif group.kind == "lot"
                    index = findfirst(p -> p.bid > p.value, group.participants)
                    index !== nothing && (error = "bid above value " * group.participants[index].name)
                end
            end
        end
        if !isempty(error)
            push!(lines, line(uppercase(group.kind), group.name, "ERROR", error))
            totals["errors"] += 1
        elseif group.kind == "lot"
            append!(lines, lot_lines(group, parameters, summary))
        else
            append!(lines, slots_lines(group, rates, summary, totals))
        end
    end
    push!(
        lines,
        line(
            "SUMMARY lots",
            totals["lots"],
            "slot_groups",
            totals["slot_groups"],
            "errors",
            totals["errors"],
            "envy_free",
            totals["envy_free"],
            "nash",
            totals["nash"],
            "equilibria",
            totals["equilibria"]
        )
    )
    return lines
end
function main()
    reserves, raw, groups, parameters = read_inputs()
    wdp, vcg, core, ascending = String[], String[], String[], String[]
    summary = ["mechanism,revenue,welfare,efficiency"]
    totals = Dict(name => 0 for name in [
        "auctions",
        "bids",
        "valid",
        "eligible",
        "nodes",
        "greedy_optimal",
        "rounds",
        "capped",
        "exposed",
        "exposure"
    ])
    revenues = Dict(name => 0 for name in MECHANISMS)
    core_totals = Dict(name => 0 for name in ["checked", "skipped", OUTCOMES...])
    for name in parameters["run"]
        a = prepare_auction(raw[name], reserves, parameters)
        append!(wdp, wdp_lines(a, reserves))
        append!(vcg, vcg_lines(a))
        check_lines, counts = core_lines(a, reserves, parameters)
        append!(core, check_lines)
        for key in keys(core_totals)
            core_totals[key] += counts[key]
        end
        append!(ascending, a.saa.lines)
        for (
            key,
            value
        ) in [("auctions",1), ("bids",a.bid_count), ("valid",length(a.valid)), ("eligible",length(a.eligible)), ("nodes",a.optimal.nodes),
                            (
                                "greedy_optimal",
                                a.greedy.welfare == a.exact.welfare
                            ), ("rounds",a.saa.rounds), ("capped",a.saa.reason == "cap"), ("exposed",a.saa.exposed), ("exposure",a.saa.exposure)]
            totals[key] += value
        end
        income = [a.revenue, a.exact.accepted, a.greedy.accepted, a.critical_revenue, a.saa.revenue]
        welfare = [a.exact.welfare, a.exact.welfare, a.greedy.welfare, a.greedy.welfare, a.saa.welfare]
        for i in eachindex(MECHANISMS)
            revenues[MECHANISMS[i]] += income[i]
            push!(
                summary,
                string(
                    name,
                    "/",
                    MECHANISMS[i],
                    ",",
                    income[i],
                    ",",
                    welfare[i],
                    ",",
                    fraction(welfare[i]//a.exact.welfare)
                )
            )
        end
    end
    push!(
        wdp,
        line(
            "TOTAL auctions",
            totals["auctions"],
            "bids",
            totals["bids"],
            "valid",
            totals["valid"],
            "eligible",
            totals["eligible"],
            "nodes",
            totals["nodes"],
            "greedy_optimal",
            totals["greedy_optimal"]
        )
    )
    push!(vcg, "OVERALL" * join([line("", name, revenues[name]) for name in MECHANISMS]))
    push!(
        core,
        line(
            "SUMMARY checked",
            core_totals["checked"],
            "skipped",
            core_totals["skipped"]
        ) * join([line("", name, core_totals[name]) for name in OUTCOMES])
    )
    push!(
        ascending,
        line(
            "SUMMARY auctions",
            totals["auctions"],
            "rounds",
            totals["rounds"],
            "capped",
            totals["capped"],
            "exposed",
            totals["exposed"],
            "exposure",
            totals["exposure"]
        )
    )
    single = process_groups(groups, parameters, summary)
    write_reports([
        ("wdp.txt",wdp),
        ("vcg.txt",vcg),
        ("core_check.txt",core),
        ("ascending_log.txt",ascending),
        ("single_item.txt",single),
        ("summary.csv",summary)
    ])
end
main()
