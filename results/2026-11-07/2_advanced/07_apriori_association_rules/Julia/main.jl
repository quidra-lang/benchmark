include("baskets.jl")
include("apriori.jl")
include("fpgrowth.jl")
include("rules.jl")
include("report.jl")
using .Baskets
using .Apriori
using .FPGrowth
using .AssociationRules
using .Report

const SEGMENTS = ("NEW","LOYAL","AT_RISK","REGULAR")
function parsefraction(text)
    a,b = parse.(Int,split(text,'/'))
    a//b
end
function parameters()
    fields = Dict{String,String}()
    for line in eachline("input/params.txt")
        name,value = split(line,' ')
        fields[name] = value
    end
    num(key) = parse(Int,fields[key])
    ratio(key) = parsefraction(fields[key])
    (support=num("min_support"),confidence=ratio("min_confidence"),lift=ratio("min_lift"),maxsize=num("max_size"),categorysupport=num("category_min_support"),sequencesupport=num("sequence_min_support"),split=num("split_day"),trainsupport=num("train_min_support"),testsupport=num("test_min_support"),top=num("recommend_top"),matrix=num("matrix_size"),grouplift=ratio("group_min_lift"),negativelift=ratio("negative_max_lift"),expected=num("negative_min_expected"),threshold=ratio("trend_threshold"))
end
function loaddata()
    errors = String[]
    adopted = Dict{String,Tuple{String,Int}}()
    itemrows = records("items.csv")
    for (line,f) in enumerate(itemrows)
        name,category,price = f[1],f[2],parse(Int,f[3])
        message = haskey(adopted,name) ? "duplicate item $name" : price == 0 ? "bad price $price" : ""
        if isempty(message)
            adopted[name] = (category,price)
        else
            push!(errors,"items.csv line $(line+1): $message")
        end
    end
    productnames = sort!(collect(keys(adopted)))
    categories = sort!(unique([v[1] for v in values(adopted)]))
    products = [Product(name,findfirst(==(adopted[name][1]),categories),adopted[name][2],length(categories)+i) for (i,name) in enumerate(productnames)]
    names = vcat(categories,productnames)
    index = Dict(p.name => i for (i,p) in enumerate(products))
    transactions = Transaction[]
    known = Set{String}()
    transactionrows = records("transactions.csv")
    accepted,rejected,duplicates = 0,0,0
    for (line,f) in enumerate(transactionrows)
        tid,customer,day,item = f[1],f[2],parse(Int,f[3]),f[4]
        message = ""
        if tid in known && tid != transactions[end].tid
            message = "tid $tid not contiguous"
        else
            if tid ∉ known
                push!(known,tid)
                push!(transactions,Transaction(tid,customer,day,zeros(Int,length(products)),UInt128(0)))
            end
            current = transactions[end]
            message = customer != current.customer ? "tid $tid customer $customer differs from $(current.customer)" : day != current.day ? "tid $tid day $day differs from $(current.day)" : !haskey(index,item) ? "unknown item $item" : ""
            if isempty(message)
                p = index[item]
                duplicates += current.units[p] > 0
                current.units[p] += 1
                current.mask |= bit(products[p].code)
                accepted += 1
            end
        end
        if !isempty(message)
            push!(errors,"transactions.csv line $(line+1): $message")
            rejected += 1
        end
    end
    baskets = [b for b in transactions if b.mask != 0]
    (errors=errors,products=products,categories=categories,names=names,baskets=baskets,transactions=length(transactions),itemrows=length(itemrows),transactionrows=length(transactionrows),accepted=accepted,rejected=rejected,duplicates=duplicates)
end
function runapriori(baskets,universe,minimum,maxsize,taxonomy=UInt128[])
    supports = Dict{UInt128,Int}()
    levels = NamedTuple[]
    masks = [bit(code) for code in universe]
    counts = countsupports(baskets,masks)
    singles = copy(counts)
    previous = Dict(mask => counts[mask] for mask in masks if counts[mask] >= minimum)
    merge!(supports,previous)
    push!(levels,(number=1,candidates=length(masks),excluded=0,pruned=0,counted=length(masks),frequent=sort!(collect(keys(previous)),lt=setless)))
    for k in 2:maxsize
        isempty(previous) && break
        generation = candidates(previous,k,taxonomy)
        counts = countsupports(baskets,generation.masks)
        previous = Dict(mask => counts[mask] for mask in generation.masks if counts[mask] >= minimum)
        merge!(supports,previous)
        push!(levels,(number=k,candidates=generation.joined,excluded=generation.excluded,pruned=generation.pruned,counted=length(generation.masks),frequent=sort!(collect(keys(previous)),lt=setless)))
    end
    (supports=supports,singles=singles,levels=levels)
end
function makerules(supports,total,p,required=UInt128(0))
    generated = 0
    kept = Rule[]
    for (z,together) in supports
        count_ones(z) < 2 && continue
        required != 0 && z & required == 0 && continue
        x = (z-1) & z
        while x != 0
            y = z ⊻ x
            generated += 1
            a,b = supports[x],supports[y]
            confidence,lift = together//a,liftvalue(total,together,a,b)
            if meets(confidence,lift,p)
                reference = b//total
                w = (x-1) & x
                while w != 0
                    reference = max(reference,supports[w|y]//supports[w])
                    w = (w-1) & x
                end
                push!(kept,makerule(x,y,together,total,a,b,confidence-reference))
            end
            x = (x-1) & z
        end
    end
    sort!(kept,lt=ruleless)
    (generated=generated,rules=kept,productive=count(r -> r.improvement > 0,kept))
end
function classification(supports,total)
    ordered = sort!(collect(keys(supports)),lt=sizeless)
    closed,maximal,generators = UInt128[],UInt128[],UInt128[]
    for x in ordered
        supersets = [z for z in ordered if z != x && hasitems(z,x)]
        isempty(supersets) && push!(maximal,x)
        all(z -> supports[z] != supports[x],supersets) && push!(closed,x)
        all(code -> get(supports,x ⊻ bit(code),total) > supports[x],members(x)) && push!(generators,x)
    end
    (closed=closed,maximal=maximal,generators=generators)
end
function customers(data)
    result = NamedTuple[]
    for id in sort!(unique([b.customer for b in data.baskets]))
        chosen = [b for b in data.baskets if b.customer == id]
        days = [sort!(unique([b.day for b in chosen if b.units[i] > 0])) for i in eachindex(data.products)]
        all_days = sort!(unique([b.day for b in chosen]))
        units = [sum(b.units[i] for b in chosen) for i in eachindex(data.products)]
        categoryunits = zeros(Int,length(data.categories))
        mask = UInt128(0)
        for (product,quantity) in zip(data.products,units)
            quantity > 0 && (mask |= bit(product.code))
            categoryunits[product.category] += quantity
        end
        revenue = sum(p.price*q for (p,q) in zip(data.products,units))
        push!(result,(id=id,baskets=length(chosen),daycount=length(all_days),first=first(all_days),last=last(all_days),days=days,units=sum(units),revenue=revenue,favorite=argmax(categoryunits),mask=mask))
    end
    result
end
function medianfraction(values)
    ordered = sort(values)
    middle = div(length(ordered),2)+1
    isodd(length(ordered)) ? ordered[middle]//1 : (ordered[middle-1]+ordered[middle])//2
end
function sequenceanalysis(data,history,p)
    buyers = [count(c -> !isempty(c.days[i]),history) for i in eachindex(data.products)]
    pairs = 0
    sequences = NamedTuple[]
    for a in eachindex(data.products), b in eachindex(data.products)
        gaps = Int[]
        for customer in history
            x,y = customer.days[a],customer.days[b]
            (isempty(x) || isempty(y) || first(x) >= last(y)) && continue
            gap = minimum(later-earlier for earlier in x for later in y if earlier < later)
            push!(gaps,gap)
        end
        isempty(gaps) && continue
        pairs += 1
        if length(gaps) >= p.sequencesupport
            q = length(gaps)
            push!(sequences,(a=a,b=b,count=q,base=buyers[a],confidence=q//buyers[a],lift=liftvalue(length(history),q,buyers[a],buyers[b]),gap=medianfraction(gaps)))
        end
    end
    sort!(sequences,by=x -> (-x.count,-x.confidence,x.a,x.b))
    repeats = NamedTuple[]
    for i in eachindex(data.products)
        intervals = Int[]
        countcustomers = 0
        for customer in history
            days = customer.days[i]
            if length(days) >= 2
                countcustomers += 1
                append!(intervals,diff(days))
            end
        end
        isempty(intervals) || push!(repeats,(item=i,customers=countcustomers,count=length(intervals),low=minimum(intervals),high=maximum(intervals),mean=sum(intervals)//length(intervals),median=medianfraction(intervals)))
    end
    sort!(repeats,by=x -> (x.mean,x.item))
    lines = String[]
    for (rank,x) in enumerate(sequences)
        push!(lines,"SEQ $rank $(data.products[x.a].name) -> $(data.products[x.b].name) customers $(x.count) base $(x.base) confidence $(fractiontext(x.confidence)) lift $(fractiontext(x.lift)) gap $(fractiontext(x.gap))")
    end
    for x in repeats
        push!(lines,"REPEAT $(data.products[x.item].name) customers $(x.customers) intervals $(x.count) min $(x.low) max $(x.high) mean $(fractiontext(x.mean)) median $(fractiontext(x.median))")
    end
    (buyers=buyers,pairs=pairs,count=length(sequences),lines=lines)
end
function recommend(held,candidates,limit)
    result = Int[]
    for code in candidates
        if !hasitems(held,bit(code)) && code ∉ result
            push!(result,code)
            length(result) == limit && break
        end
    end
    result
end
rulecandidates(rules,held) = [only(members(r.y)) for r in rules if count_ones(r.y) == 1 && hasitems(held,r.x)]
function validation(data,p,universe)
    train = [b.mask for b in data.baskets if b.day <= p.split]
    test = [b.mask for b in data.baskets if b.day > p.split]
    training = runapriori(train,universe,p.trainsupport,p.maxsize)
    testing = runapriori(test,universe,p.testsupport,p.maxsize)
    rules = makerules(training.supports,length(train),p).rules
    testrules = makerules(testing.supports,length(test),p).rules
    cache = Dict{UInt128,Int}()
    support(mask) = get!(cache,mask) do
        count(b -> hasitems(b,mask),test)
    end
    lines = String[]
    verdicts = zeros(Int,3)
    for (rank,r) in enumerate(rules)
        a,b,c = support(r.x),support(r.y),support(r.x|r.y)
        confidence,lift = "-","-"
        verdict = 3
        if a > 0 && b > 0
            conf,l = c//a,liftvalue(length(test),c,a,b)
            confidence,lift = fractiontext(conf),fractiontext(l)
            verdict = meets(conf,l,p) ? 1 : 2
        end
        verdicts[verdict] += 1
        push!(lines,"RULE $rank $(arrow(r,data.names)) train $(r.count) confidence $(fractiontext(r.confidence)) lift $(fractiontext(r.lift)) test $c of $a confidence $confidence lift $lift $(("HOLD","FAIL","UNSEEN")[verdict])")
    end
    known = Set((r.x,r.y) for r in rules)
    emerging = 0
    for (rank,r) in enumerate(testrules)
        (r.x,r.y) in known && continue
        emerging += 1
        push!(lines,"EMERGING $rank $(arrow(r,data.names)) test $(r.count) confidence $(fractiontext(r.confidence)) lift $(fractiontext(r.lift))")
    end
    push!(lines,"VALIDATION train $(length(train)) test $(length(test)) itemsets $(length(training.supports)) rules $(length(rules)) hold $(verdicts[1]) fail $(verdicts[2]) unseen $(verdicts[3]) emerging $emerging")
    popularity = sort!(collect(universe),by=i -> (-training.singles[bit(i)],i))
    suggestions = Dict{UInt128,Vector{Int}}()
    baselines = Dict{UInt128,Vector{Int}}()
    tallies = Dict{Int,Vector{Int}}()
    heldout,hits = zeros(Int,length(data.products)),zeros(Int,length(data.products))
    for basket in test
        size = count_ones(basket)
        size < 2 && continue
        tally = get!(tallies,size,zeros(Int,5))
        for h in members(basket)
            held = basket ⊻ bit(h)
            suggestion = get!(suggestions,held) do
                recommend(held,rulecandidates(rules,held),p.top)
            end
            baseline = get!(baselines,held) do
                recommend(held,popularity,p.top)
            end
            hit = h in suggestion
            tally .+= [1,!isempty(suggestion),!isempty(suggestion) && suggestion[1] == h,hit,h in baseline]
            index = h-length(data.categories)
            heldout[index] += 1
            hits[index] += hit
        end
    end
    total = zeros(Int,5)
    describe(t) = "cases $(t[1]) covered $(t[2]) hit1 $(t[3]) hit $(t[4]) rate $(fractiontext(t[4]//t[1])) baseline $(t[5]) rate $(fractiontext(t[5]//t[1]))"
    for size in sort!(collect(keys(tallies)))
        tally = tallies[size]
        total .+= tally
        push!(lines,"RECOMMEND size $size $(describe(tally))")
    end
    push!(lines,"RECOMMEND total $(describe(total))")
    (lines=lines,heldout=heldout,hits=hits)
end
function summarylines(data,history,a,classified,fp,mainrules,category,categoryrules,sequences)
    baskets = data.baskets
    n = length(baskets)
    sizes = count_ones.([b.mask for b in baskets])
    lines = ["ERROR $error" for error in data.errors]
    push!(lines,"ITEMS rows $(data.itemrows) adopted $(length(data.products)) categories $(length(data.categories))")
    push!(lines,"TRANSACTIONS lines $(data.transactionrows) adopted $(data.accepted) rejected $(data.rejected) duplicates $(data.duplicates) transactions $(data.transactions) empty $(data.transactions-n)")
    push!(lines,"BASKETS count $n customers $(length(history)) first_day $(minimum(b.day for b in baskets)) last_day $(maximum(b.day for b in baskets)) average_size $(fractiontext(sum(sizes)//n)) largest $(maximum(sizes))")
    for k in 1:maximum(sizes)
        countbaskets = count(==(k),sizes)
        push!(lines,"SIZE $k baskets $countbaskets share $(percenttext(countbaskets,n))")
    end
    push!(lines,"FREQUENT itemsets $(length(a.supports)) closed $(length(classified.closed)) maximal $(length(classified.maximal)) generators $(length(classified.generators)) levels $(length(a.levels))")
    match = a.supports == fp.supports
    push!(lines,"FPGROWTH header $(fp.header) nodes $(fp.nodes) conditional_trees $(fp.trees) conditional_nodes $(fp.conditionalnodes) itemsets $(length(fp.supports)) $(match ? "MATCH" : "MISMATCH")")
    if !match
        for (label,first,second) in (("ONLY_APRIORI",a.supports,fp.supports),("ONLY_FPGROWTH",fp.supports,a.supports))
            for mask in sort!([mask for mask in keys(first) if get(second,mask,-1) != first[mask]],lt=sizeless)
                push!(lines,"$label $(itemtext(mask,data.names)) $(first[mask])")
            end
        end
    end
    push!(lines,"RULES generated $(mainrules.generated) passed $(length(mainrules.rules)) productive $(mainrules.productive)")
    for level in category.levels
        push!(lines,"CATEGORY_LEVEL $(level.number) candidates $(level.candidates) taxonomy $(level.excluded) pruned $(level.pruned) counted $(level.counted) frequent $(length(level.frequent))")
    end
    push!(lines,"CATEGORY_RULES itemsets $(length(category.supports)) generated $(categoryrules.generated) passed $(length(categoryrules.rules)) productive $(categoryrules.productive)")
    push!(lines,"SEQUENCES customers $(length(history)) multi_day $(count(c -> c.daycount >= 2,history)) pairs $(sequences.pairs) frequent $(sequences.count)")
    lines
end
function itemsetlines(a,names)
    lines = String[]
    for level in a.levels
        push!(lines,"LEVEL $(level.number) candidates $(level.candidates) pruned $(level.pruned) counted $(level.counted) frequent $(length(level.frequent))")
        append!(lines,["$(itemtext(mask,names)) $(a.supports[mask])" for mask in level.frequent])
    end
    lines
end
function itemslines(data,p,a,mainrules,sequence,evaluation,extendedbaskets)
    products,names,categories = data.products,data.names,data.categories
    n = length(data.baskets)
    units = [sum(b.units[i] for b in data.baskets) for i in eachindex(products)]
    revenue = [product.price*q for (product,q) in zip(products,units)]
    totalrevenue = sum(revenue)
    supports = a.singles
    cache = Dict{UInt128,Int}()
    together(mask) = get!(cache,mask) do
        count(b -> hasitems(b.mask,mask),data.baskets)
    end
    pairs = [mask for mask in keys(a.supports) if count_ones(mask) == 2]
    adjacency = fill(UInt128(0),length(products))
    for mask in pairs
        codes = members(mask)
        first,second = codes[1]-length(categories),codes[2]-length(categories)
        lift = liftvalue(n,a.supports[mask],supports[bit(codes[1])],supports[bit(codes[2])])
        if lift >= p.grouplift
            adjacency[first] |= bit(codes[2])
            adjacency[second] |= bit(codes[1])
        end
    end
    lines = String[]
    order = sort!(collect(eachindex(products)),by=i -> (-revenue[i],products[i].name))
    for (rank,i) in enumerate(order)
        product = products[i]
        chosen = [(mask=mask,other=only(members(mask ⊻ bit(product.code))),count=a.supports[mask],lift=liftvalue(n,a.supports[mask],supports[bit(members(mask)[1])],supports[bit(members(mask)[2])])) for mask in pairs if hasitems(mask,bit(product.code))]
        sort!(chosen,by=x -> (-x.lift,-x.count,x.other))
        partner = isempty(chosen) ? "none" : "$(names[chosen[1].other]) $(fractiontext(chosen[1].lift))"
        bestindex = findfirst(r -> hasitems(r.x|r.y,bit(product.code)),mainrules.rules)
        best = bestindex === nothing ? "none" : "$bestindex $(arrow(mainrules.rules[bestindex],names))"
        countsets = count(mask -> hasitems(mask,bit(product.code)),keys(a.supports))
        baskets = supports[bit(product.code)]
        push!(lines,"ITEM $rank $(product.name) $(categories[product.category]) price $(moneytext(product.price)) units $(units[i]) revenue $(moneytext(revenue[i])) share $(percenttext(revenue[i],totalrevenue)) baskets $baskets support $(fractiontext(baskets//n)) customers $(sequence.buyers[i]) itemsets $countsets heldout $(evaluation.heldout[i]) hits $(evaluation.hits[i]) partner $partner best $best")
    end
    categoryunits = [sum((units[i] for i in eachindex(products) if products[i].category == c);init=0) for c in eachindex(categories)]
    categoryrevenue = [sum((revenue[i] for i in eachindex(products) if products[i].category == c);init=0) for c in eachindex(categories)]
    categorycounts = [count(b -> hasitems(b,bit(c)),extendedbaskets) for c in eachindex(categories)]
    for c in sort!(collect(eachindex(categories)),by=c -> (-categoryrevenue[c],categories[c]))
        push!(lines,"CATEGORY $(categories[c]) items $(count(product -> product.category == c,products)) units $(categoryunits[c]) revenue $(moneytext(categoryrevenue[c])) share $(percenttext(categoryrevenue[c],totalrevenue)) baskets $(categorycounts[c]) support $(fractiontext(categorycounts[c]//n))")
    end
    push!(lines,"TOTAL items $(length(products)) units $(sum(units)) revenue $(moneytext(totalrevenue)) baskets $n customers $(length(unique([b.customer for b in data.baskets])))")
    visited = falses(length(products))
    groups = Vector{Int}[]
    for i in eachindex(products)
        visited[i] && continue
        stack = [i]
        group = Int[]
        visited[i] = true
        while !isempty(stack)
            j = pop!(stack)
            push!(group,j)
            for code in members(adjacency[j])
                child = code-length(categories)
                if !visited[child]
                    visited[child] = true
                    push!(stack,child)
                end
            end
        end
        length(group) >= 2 && push!(groups,sort!(group))
    end
    sort!(groups,by=g -> (-length(g),g[1]))
    for (number,group) in enumerate(groups)
        edges = div(sum(count_ones(adjacency[i]) for i in group),2)
        core = sort(group,by=i -> (-count_ones(adjacency[i]),-supports[bit(products[i].code)],i))[1]
        amount = sum(revenue[group])
        members_text = join([products[i].name for i in group],"+")
        push!(lines,"GROUP $number items $(length(group)) edges $edges core $(products[core].name) revenue $(moneytext(amount)) share $(percenttext(amount,totalrevenue)) members $members_text")
    end
    frequent = [i for i in eachindex(products) if haskey(a.supports,bit(products[i].code))]
    substitutes = NamedTuple[]
    for ai in eachindex(frequent), bi in ai+1:length(frequent)
        i,j = frequent[ai],frequent[bi]
        first,second = bit(products[i].code),bit(products[j].code)
        expected = supports[first]*supports[second]//n
        expected < p.expected && continue
        countpair = together(first|second)
        lift = liftvalue(n,countpair,supports[first],supports[second])
        lift <= p.negativelift && push!(substitutes,(a=i,b=j,count=countpair,expected=expected,lift=lift))
    end
    sort!(substitutes,by=x -> (x.lift,-x.expected,x.a,x.b))
    for x in substitutes
        push!(lines,"SUBSTITUTE $(products[x.a].name) $(products[x.b].name) count $(x.count) expected $(fractiontext(x.expected)) lift $(fractiontext(x.lift))")
    end
    matrixproducts = sort!(collect(eachindex(products)),by=i -> (-supports[bit(products[i].code)],i))[1:p.matrix]
    matrixcategories = sort!(collect(eachindex(categories)),by=c -> (-categorycounts[c],c))
    for (label,codes,baskets) in (("MATRIX",[products[i].code for i in matrixproducts],[b.mask for b in data.baskets]),("CATEGORY_MATRIX",matrixcategories,extendedbaskets))
        counts = [count(b -> hasitems(b,bit(code)),baskets) for code in codes]
        for (index,code) in enumerate(codes)
            push!(lines,"$label $index $(names[code]) baskets $(counts[index])")
        end
        push!(lines,"    "*join([lpad(i,7) for i in eachindex(codes)]))
        for i in eachindex(codes)
            cells = String[]
            for j in eachindex(codes)
                value = i == j ? "-" : string(div(100*n*count(b -> hasitems(b,bit(codes[i])|bit(codes[j])),baskets),counts[i]*counts[j]))
                push!(cells,lpad(value,7))
            end
            push!(lines,lpad(i,4)*join(cells))
        end
    end
    lines,totalrevenue
end
function trendlines(data,p)
    weeks = div(maximum(b.day for b in data.baskets)-1,7)+1
    baskets = zeros(Int,weeks)
    units = zeros(Int,weeks)
    customers = [Set{String}() for _ in 1:weeks]
    series = [zeros(Int,weeks) for _ in data.names]
    for basket in data.baskets
        week = div(basket.day-1,7)+1
        baskets[week] += 1
        push!(customers[week],basket.customer)
        for (product,quantity) in zip(data.products,basket.units)
            units[week] += quantity
            series[product.code][week] += quantity
            series[product.category][week] += quantity
        end
    end
    row(label,values) = rpad(label,17)*join([lpad(value,6) for value in values])
    lines = [row("WEEK",1:weeks),row("BASKETS",baskets),row("UNITS",units),row("CUSTOMERS",length.(customers))]
    append!(lines,[row(name,values) for (name,values) in zip(data.names,series)])
    week_sum = sum(1:weeks)
    square_sum = sum(w*w for w in 1:weeks)
    trends = NamedTuple[]
    for (name,values) in zip(data.names,series)
        total = sum(values)
        slope = (weeks*sum(w*v for (w,v) in enumerate(values))-week_sum*total)//(weeks*square_sum-week_sum*week_sum)
        relative = total == 0 ? nothing : slope*(weeks//total)
        verdict = relative === nothing ? "NONE" : relative >= p.threshold ? "RISING" : relative <= -p.threshold ? "FALLING" : "FLAT"
        push!(trends,(name=name,units=total,slope=slope,relative=relative,verdict=verdict))
    end
    function trendless(a,b)
        a.relative === nothing && return b.relative === nothing && a.name < b.name
        b.relative === nothing && return true
        a.relative == b.relative ? a.name < b.name : a.relative > b.relative
    end
    sort!(trends,lt=trendless)
    for t in trends
        push!(lines,"TREND $(t.name) units $(t.units) slope $(fractiontext(t.slope)) relative $(t.relative === nothing ? "-" : fractiontext(t.relative)) $(t.verdict)")
    end
    lines
end
function customerlines(data,p,history,rules,totalrevenue)
    lines = String[]
    lastday = maximum(b.day for b in data.baskets)
    counts,revenues = zeros(Int,4),zeros(Int,4)
    for c in history
        segment = c.first > lastday-28 ? 1 : c.baskets >= 4 && lastday-c.last <= 14 ? 2 : lastday-c.last > 28 ? 3 : 4
        counts[segment] += 1
        revenues[segment] += c.revenue
        offers = recommend(c.mask,rulecandidates(rules,c.mask),p.top)
        offer = isempty(offers) ? "none" : join(data.names[offers],"+")
        push!(lines,"CUSTOMER $(c.id) baskets $(c.baskets) days $(c.daycount) first $(c.first) last $(c.last) items $(count_ones(c.mask)) units $(c.units) revenue $(moneytext(c.revenue)) average $(moneytext(div(c.revenue,c.baskets))) favorite $(data.categories[c.favorite]) segment $(SEGMENTS[segment]) offer $offer")
    end
    for i in 1:4
        push!(lines,"SEGMENT $(SEGMENTS[i]) customers $(counts[i]) revenue $(moneytext(revenues[i])) share $(percenttext(revenues[i],totalrevenue))")
    end
    lines
end
function main()
    p,data = parameters(),loaddata()
    universe = [product.code for product in data.products]
    masks = [b.mask for b in data.baskets]
    a = runapriori(masks,universe,p.support,p.maxsize)
    fp = growth(masks,p.support,p.maxsize)
    classified = classification(a.supports,length(masks))
    mainrules = makerules(a.supports,length(masks),p)
    extendedbaskets = [extended(b,data.products) for b in data.baskets]
    taxonomy = [bit(product.category)|bit(product.code) for product in data.products]
    category = runapriori(extendedbaskets,1:length(data.names),p.categorysupport,p.maxsize,taxonomy)
    categorymask = bit(length(data.categories)+1)-1
    categoryrules = makerules(category.supports,length(masks),p,categorymask)
    history = customers(data)
    sequences = sequenceanalysis(data,history,p)
    evaluation = validation(data,p,universe)
    closedlines = String[]
    for (label,sets) in (("CLOSED",classified.closed),("MAXIMAL",classified.maximal),("GENERATOR",classified.generators))
        append!(closedlines,["$label $(itemtext(mask,data.names)) $(a.supports[mask])" for mask in sets])
    end
    item_lines,totalrevenue = itemslines(data,p,a,mainrules,sequences,evaluation,extendedbaskets)
    outputs = [("summary.txt",summarylines(data,history,a,classified,fp,mainrules,category,categoryrules,sequences)),("itemsets.txt",itemsetlines(a,data.names)),("closed_maximal.txt",closedlines),("rules.csv",rulecsv(mainrules.rules,data.names)),("category_rules.csv",rulecsv(categoryrules.rules,data.names)),("sequences.txt",sequences.lines),("validation.txt",evaluation.lines),("items_report.txt",item_lines),("trends.txt",trendlines(data,p)),("customers.txt",customerlines(data,p,history,mainrules.rules,totalrevenue))]
    for (name,lines) in outputs
        writereport(name,lines)
    end
end
main()
