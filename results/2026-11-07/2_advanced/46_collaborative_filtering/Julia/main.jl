include("ratings.jl")
include("evaluation.jl")
include("neighborhood.jl")
include("factorization.jl")
include("report.jl")
const METHODS = ("GLOBAL","BASELINE","USER_KNN","ITEM_KNN","SLOPE_ONE","SVD","ALS")
const RANKINGS = ("POPULAR",METHODS[2:end]...)
const KNN_METHODS = ("USER_KNN","ITEM_KNN")
prediction(value;fallback=false,neighbors=0,similarity=0.0,top=0) = (
    value=value,
    fallback=fallback,
    neighbors=neighbors,
    similarity=similarity,
    top=top
)
baseline(r,u,i) = (r.data.mean+r.user_bias[u])+r.item_bias[i]
function train(data)
    params = data.params
    user_bias,item_bias = zeros(length(data.users)),zeros(length(data.items))
    base(u,i) = (data.mean+user_bias[u])+item_bias[i]
    log = Tuple{String,Int,Float64}[]
    errors = Dict("GLOBAL"=>training_rmse(data.training,(u,i)->data.mean))
    for sweep in 1:10
        for i in eachindex(data.items)
            value = sequential_sum(data.ratings[u,i]-data.mean-user_bias[u] for u in data.by_item[i])
            item_bias[i] = value/(params["BIAS_REG"][1]+data.item_counts[i])
        end
        for u in eachindex(data.users)
            value = sequential_sum(data.ratings[u,i]-data.mean-item_bias[i] for i in data.by_user[u])
            user_bias[u] = value/(params["BIAS_REG"][2]+data.user_counts[u])
        end
        push!(log,("BASELINE",sweep,training_rmse(data.training,base)))
    end
    errors["BASELINE"] = log[end][3]
    svd,svd_log = train_svd(data)
    als,als_log = train_als(data,user_bias,item_bias)
    append!(log,svd_log)
    append!(log,als_log)
    errors["SVD"],errors["ALS"] = svd_log[end][3],als_log[end][3]
    popularity = sort(collect(eachindex(data.items));by=i->(
        -data.item_counts[i],
        -data.item_means[i],
        data.items[i]
    ))
    head = length(data.items)÷5
    (data=data,params=params,user_bias=user_bias,item_bias=item_bias,log=log,train_errors=errors,svd=svd,als=als,
     neighborhood=build_neighborhood(
         data,
         Int(params["SHRINKAGE"][1])
     ),popularity=popularity,head=head,popular=Set(popularity[1:head]),
     predictions=Dict(name=>Any[] for name in METHODS),clipped=Dict(name=>Float64[] for name in METHODS),
     errors=Dict(name=>Float64[] for name in METHODS),metrics=Dict{String,Any}(),relevant=Dict{Int,Set{Int}}(),
     rankings=Dict{Int,Any}(),ranking_predictions=Dict{Int,Any}())
end
function predict(r,method,u,i,k=Int(r.params["NEIGHBORS"][1]))
    data,n = r.data,r.neighborhood
    method=="GLOBAL" && return prediction(data.mean)
    method=="BASELINE" && return prediction(baseline(r,u,i))
    method=="SVD" && return prediction(factor_prediction(r.svd,u,i))
    method=="ALS" && return prediction(factor_prediction(r.als,u,i))
    if method=="SLOPE_ONE"
        numerator = 0.0
        denominator = 0
        for other in data.by_user[u]
            common = n.counts[i,other]
            common==0 && continue
            numerator += (deviation(n,i,other)+data.ratings[u,other])*common
            denominator += common
        end
        return denominator==0 ? prediction(baseline(r,u,i);fallback=true) : prediction(numerator/denominator)
    end
    is_user = method=="USER_KNN"
    candidates = Tuple{Int,Float64}[]
    for other in (is_user ? data.by_item[i] : data.by_user[u])
        similarity = is_user ? n.user[u,other] : n.item[i,other]
        !isnan(similarity) && similarity>r.params["MIN_SIMILARITY"][1] && push!(candidates,(other,similarity))
    end
    selected = largest_neighbors(candidates,k)
    isempty(selected) && return prediction(baseline(r,u,i);fallback=true)
    numerator = denominator = 0.0
    for (other,similarity) in selected
        residual = is_user ? data.ratings[other,i]-data.user_means[other] : data.ratings[
            u,
            other
        ]-data.item_means[other]
        numerator += similarity*residual
        denominator += similarity
    end
    mean = is_user ? data.user_means[u] : data.item_means[i]
    prediction(
        mean+numerator/denominator;neighbors=length(selected),
        similarity=denominator/length(selected),
        top=selected[1][1]
    )
end
function predict_tests!(r)
    lines = ["user,item,actual,"*join(METHODS,",")]
    for row in r.data.test
        fields = string.([r.data.users[row.u],r.data.items[row.i],row.rating])
        for method in METHODS
            p = predict(r,method,row.u,row.i)
            q = clip(p.value)
            push!(r.predictions[method],p)
            push!(r.clipped[method],q)
            push!(r.errors[method],q-row.rating)
            push!(fields,real_text(q))
        end
        push!(lines,join(fields,","))
    end
    for method in METHODS
        predictions = r.predictions[method]
        r.metrics[method] = (rmse=rmse(r.errors[method]),mae=mae(r.errors[method]),
            clipped=count(p->p.value<1 || p.value>5,predictions),fallback=count(p->p.fallback,predictions))
    end
    lines
end
function prepare_rankings!(r)
    data = r.data
    for row in data.test
        row.rating>=4 && push!(get!(r.relevant,row.u,Set{Int}()),row.i)
    end
    requested = [data.user_index[id] for id in Int.(r.params["RECOMMEND_USERS"]) if haskey(
        data.user_index,
        id
    )]
    users = sort(unique(vcat(collect(keys(r.relevant)),requested)))
    for u in users
        candidates = [i for i in eachindex(data.items) if data.ratings[u,i]==0]
        lists = Dict{String,Vector{Int}}("POPULAR"=>[i for i in r.popularity if data.ratings[u,i]==0])
        predictions = Dict{String,Any}()
        for method in METHODS[2:end]
            values = Dict(i=>predict(r,method,u,i) for i in candidates)
            predictions[method] = values
            lists[method] = sort(candidates;by=i->(-values[i].value,data.items[i]))
        end
        r.rankings[u],r.ranking_predictions[u] = lists,predictions
    end
end
function count_summary(counts)
    ordered = sort(counts)
    n = length(ordered)
    median = isodd(n) ? ordered[n÷2+1] : (ordered[n÷2]+ordered[n÷2+1])/2
    "min $(ordered[1]) median $(real_text(median)) max $(ordered[end])"
end
function errors_for(r,indices,metric=rmse)
    join(["$method $(real_text(metric(r.errors[method][indices])))" for method in METHODS]," ")
end
group_number(value,bounds) = count(bound->value>=bound,bounds)+1
function evaluation_sections(r)
    data,params,n = r.data,r.params,r.neighborhood
    m = length(data.test)
    theta = params["MIN_SIMILARITY"][1]
    first_time,last_time = extrema(row.time for row in data.training)
    histogram = [count(row->row.rating==rating,data.training) for rating in 1:5]
    user_pairs = count(i->!isnan(n.user[i]),eachindex(n.user))÷2
    item_pairs = count(i->!isnan(n.item[i]),eachindex(n.item))÷2
    user_usable = count(value->!isnan(value) && value>theta,n.user)÷2
    item_usable = count(value->!isnan(value) && value>theta,n.item)÷2
    slope_pairs = count(>(0),n.counts)÷2
    sections = [["data users $(length(data.users)) items $(length(data.items)) catalog $(data.catalog) ratings $(length(data.training)) test $m",
      "density $(real_text(length(data.training)/(length(data.users)*length(data.items)))) global_mean $(real_text(data.mean))",
      "histogram "*join(
          histogram,
          " "
      ),"user_ratings "*count_summary(data.user_counts),"item_ratings "*count_summary(data.item_counts),
      "timestamps first $first_time last $last_time","cold_items $(data.catalog-length(data.items))",
      "similarities user_pairs $user_pairs usable $user_usable item_pairs $item_pairs usable $item_usable slope_pairs $slope_pairs"]]
    lines = ["genre_stats"]
    genres = sort(unique([genre for genres in data.genres for genre in genres]))
    for genre in genres
        items = [i for i in eachindex(data.items) if genre in data.genres[i]]
        ratings = sum(data.item_counts[items])
        high = count(row->row.i in items && row.rating>=4,data.training)
        push!(lines,"genre $genre items $(length(items)) ratings $ratings high $high")
    end
    push!(sections,lines)
    buckets = Int(params["TIME_BUCKETS"][1])
    counts,totals = zeros(Int,buckets),zeros(Int,buckets)
    users = [Set{Int}() for _ in 1:buckets]
    for row in data.training
        bucket = fld((row.time-first_time)*buckets,last_time-first_time+1)+1
        counts[bucket] += 1
        totals[bucket] += row.rating
        push!(users[bucket],row.u)
    end
    lines = ["time_buckets $buckets"]
    for b in 1:buckets
        mean = counts[b]==0 ? nothing : totals[b]/counts[b]
        push!(lines,"bucket $b ratings $(counts[b]) users $(length(users[b])) mean $(real_text(mean))")
    end
    push!(sections,lines)
    lines = ["rating_metrics"]
    for method in METHODS
        metric = r.metrics[method]
        push!(
            lines,
            "$method rmse $(real_text(metric.rmse)) mae $(real_text(metric.mae)) clipped $(metric.clipped) fallback $(metric.fallback)"
        )
    end
    push!(sections,lines)
    lines = ["generalization"]
    for method in ("GLOBAL","BASELINE","SVD","ALS")
        train_error,test_error = r.train_errors[method],r.metrics[method].rmse
        push!(
            lines,
            "$method train $(real_text(train_error)) test $(real_text(test_error)) gap $(real_text(test_error-train_error))"
        )
    end
    push!(sections,lines)
    lines = ["neighborhoods k $(Int(params["NEIGHBORS"][1]))"]
    for method in KNN_METHODS
        used = [p for p in r.predictions[method] if !p.fallback]
        w = length(used)
        mean_neighbors = w==0 ? nothing : sum(p.neighbors for p in used)/w
        mean_similarity = w==0 ? nothing : sequential_sum(p.similarity for p in used)/w
        push!(
            lines,
            "$method predictions $m with_neighbors $w mean_neighbors $(real_text(mean_neighbors)) mean_similarity $(real_text(mean_similarity))"
        )
    end
    push!(sections,lines)
    actual = [row.rating for row in data.test]
    actual_mean = sum(actual)/m
    actual_variation = sequential_sum((value-actual_mean)*(value-actual_mean) for value in actual)
    lines = ["prediction_stats actual mean $(real_text(actual_mean)) std $(real_text(sqrt(actual_variation/m)))"]
    for method in METHODS
        values = r.clipped[method]
        mean = sequential_sum(values)/m
        variation = sequential_sum((v-mean)*(v-mean) for v in values)
        correlation = nothing
        if minimum(values)!=maximum(values) && minimum(actual)!=maximum(actual)
            cross = sequential_sum((values[i]-mean)*(actual[i]-actual_mean) for i in 1:m)
            correlation = cross/sqrt(variation*actual_variation)
        end
        push!(
            lines,
            "$method mean $(real_text(mean)) std $(real_text(sqrt(variation/m))) correlation $(real_text(correlation))"
        )
    end
    push!(sections,lines)
    lines = ["error_bins edges 0.5 1.0 1.5 2.0"]
    for method in METHODS
        bins = zeros(Int,5)
        for error in r.errors[method]
            bins[count(edge->abs(error)>=edge,(0.5,1.0,1.5,2.0))+1] += 1
        end
        push!(lines,method*" "*join(bins," "))
    end
    push!(sections,lines)
    lines = ["comparison"]
    for a in 1:6,b in a+1:7
        left,right = abs.(r.errors[METHODS[a]]),abs.(r.errors[METHODS[b]])
        wins,ties = count(left.<right),count(left.==right)
        push!(lines,"$(METHODS[a]) $(METHODS[b]) wins $wins ties $ties losses $(m-wins-ties)")
    end
    push!(sections,lines)
    for kind in ("user","item")
        bounds = Int.(params[kind=="user" ? "USER_GROUPS" : "ITEM_GROUPS"])
        counts = kind=="user" ? data.user_counts : data.item_counts
        grouped = [Int[] for _ in 1:length(bounds)+1]
        for (i,row) in enumerate(data.test)
            index = kind=="user" ? row.u : row.i
            push!(grouped[group_number(counts[index],bounds)],i)
        end
        lines = [kind*"_groups bounds "*join(bounds," ")]
        for (g,indices) in enumerate(grouped)
            lower = g==1 ? 1 : bounds[g-1]
            upper = g<=length(bounds) ? string(bounds[g]-1) : "-"
            push!(lines,"group $g from $lower to $upper pairs $(length(indices)) "*errors_for(r,indices))
        end
        push!(sections,lines)
    end
    lines = ["by_rating"]
    for rating in 1:5
        indices = [i for i in 1:m if data.test[i].rating==rating]
        push!(lines,"rating $rating pairs $(length(indices)) "*errors_for(r,indices,mae))
    end
    push!(sections,lines)
    genres = sort(unique([genre for row in data.test for genre in data.genres[row.i]]))
    lines = ["genres"]
    for genre in genres
        indices = [i for i in 1:m if genre in data.genres[data.test[i].i]]
        push!(lines,"genre $genre pairs $(length(indices)) "*errors_for(r,indices))
    end
    push!(sections,lines)
    evaluated = sort(collect(keys(r.relevant)))
    e = length(evaluated)
    relevant_count = sum(length(r.relevant[u]) for u in evaluated)
    lines = ["ranking users $e relevant $relevant_count"]
    for cutoff in Int.(params["CUTOFFS"])
        push!(lines,"cutoff $cutoff")
        for method in RANKINGS
            metrics = [ranking_metrics(r.rankings[u][method],r.relevant[u],cutoff) for u in evaluated]
            precision = sum(metric.hits for metric in metrics)/(cutoff*e)
            recall = sequential_sum(metric.recall for metric in metrics)/e
            ndcg = sequential_sum(metric.ndcg for metric in metrics)/e
            map = sequential_sum(metric.ap for metric in metrics)/e
            mrr = sequential_sum(metric.rr for metric in metrics)/e
            hit_rate = count(metric->metric.hits>=1,metrics)/e
            push!(
                lines,
                "  $method precision $(real_text(precision)) recall $(real_text(recall)) ndcg $(real_text(ndcg)) map $(real_text(map)) mrr $(real_text(mrr)) hit_rate $(real_text(hit_rate))"
            )
        end
    end
    push!(sections,lines)
    size = Int(params["TOP_N"][1])
    pair_count = size*(size-1)÷2
    lines = ["beyond_accuracy top_n $size head $(r.head)"]
    for method in RANKINGS
        distinct = Set{Int}()
        diversity = popularity = long_tail = 0
        novelty = similarity = 0.0
        for u in evaluated
            ranked = r.rankings[u][method][1:size]
            union!(distinct,ranked)
            diversity += length(unique([genre for i in ranked for genre in data.genres[i]]))
            novelty += sequential_sum(log2(length(data.users)/data.item_counts[i]) for i in ranked)/size
            popularity += sum(data.item_counts[ranked])
            long_tail += count(i->!(i in r.popular),ranked)
            pair_similarity = 0.0
            for a in 1:size-1,b in a+1:size
                value = n.item[ranked[a],ranked[b]]
                pair_similarity += isnan(value) ? 0.0 : value
            end
            similarity += pair_similarity/pair_count
        end
        push!(
            lines,
            "$method coverage $(real_text(length(distinct)/length(data.items))) diversity $(real_text(diversity/e)) novelty $(real_text(novelty/e)) popularity $(real_text(popularity/(size*e))) long_tail $(real_text(long_tail/(size*e))) similarity $(real_text(similarity/e))"
        )
    end
    push!(sections,lines)
    bounds = Int.(params["USER_GROUPS"])
    lines = ["ranking_groups top_n $size bounds "*join(bounds," ")]
    for g in 1:length(bounds)+1
        users = [u for u in evaluated if group_number(data.user_counts[u],bounds)==g]
        fields = ["group $g users $(length(users))"]
        for method in RANKINGS
            value = isempty(users) ? nothing : sequential_sum(ranking_metrics(
                r.rankings[u][method],
                r.relevant[u],
                size
            ).ndcg for u in users)/length(users)
            push!(fields,"$method $(real_text(value))")
        end
        push!(lines,join(fields," "))
    end
    push!(sections,lines)
    lines = ["agreement top_n $size"]
    for a in 1:6,b in a+1:7
        total = 0.0
        for u in evaluated
            left,right = Set(r.rankings[u][RANKINGS[a]][1:size]),Set(r.rankings[u][RANKINGS[b]][1:size])
            total += length(intersect(left,right))/length(union(left,right))
        end
        push!(lines,"$(RANKINGS[a]) $(RANKINGS[b]) jaccard $(real_text(total/e))")
    end
    push!(sections,lines)
    lines = ["neighbor_grid"]
    grid = Int.(params["NEIGHBOR_GRID"])
    errors = zeros(length(grid),2)
    for (index,k) in enumerate(grid)
        fields = ["k $k"]
        for (j,method) in enumerate(KNN_METHODS)
            errors[index,j] = rmse([clip(predict(
                r,
                method,
                row.u,
                row.i,
                k
            ).value)-row.rating for row in data.test])
            push!(fields,"$method $(real_text(errors[index,j]))")
        end
        push!(lines,join(fields," "))
    end
    push!(lines,"best USER_KNN $(grid[argmin(errors[:,1])]) ITEM_KNN $(grid[argmin(errors[:,2])])")
    push!(sections,lines)
    lines = ["biases"]
    list_size = Int(params["LIST_SIZE"][1])
    for kind in ("item","user")
        ids = kind=="item" ? data.items : data.users
        biases = kind=="item" ? r.item_bias : r.user_bias
        counts = kind=="item" ? data.item_counts : data.user_counts
        means = kind=="item" ? data.item_means : data.user_means
        for (label,sign) in (("high",-1),("low",1))
            order = sort(collect(eachindex(ids));by=i->(sign*biases[i],ids[i]))[1:list_size]
            for i in order
                line = "$(kind)_$label $(ids[i]) bias $(real_text(biases[i])) count $(counts[i]) mean $(real_text(means[i]))"
                kind=="item" && (line*=" "*data.titles[i])
                push!(lines,line)
            end
        end
    end
    push!(sections,lines)
    sections
end
function preferred_genres(r,u,liked)
    counts = Dict{String,Int}()
    for i in r.data.by_user[u]
        rating = r.data.ratings[u,i]
        (liked ? rating>=4 : rating<=2) || continue
        for genre in r.data.genres[i]
            counts[genre] = get(counts,genre,0)+1
        end
    end
    order = sort(collect(keys(counts));by=genre->(-counts[genre],genre))
    [(genre,counts[genre]) for genre in order[1:min(3,length(order))]]
end
popularity_line(
    r,
    rank,
    i
) = "  $rank $(r.data.items[i]) count $(r.data.item_counts[i]) mean $(real_text(r.data.item_means[i])) $(r.data.titles[i])"
function recommendation_sections(r)
    data = r.data
    size,list_size = Int(r.params["TOP_N"][1]),Int(r.params["LIST_SIZE"][1])
    sections = Vector{String}[]
    for id in Int.(r.params["RECOMMEND_USERS"])
        if !haskey(data.user_index,id)
            push!(
                sections,
                vcat(
                    ["user $id unknown","list POPULAR"],
                    [popularity_line(r,rank,i) for (rank,i) in enumerate(r.popularity[1:size])]
                )
            )
            continue
        end
        u = data.user_index[id]
        lines = ["user $id ratings $(data.user_counts[u]) mean $(real_text(data.user_means[u])) bias $(real_text(r.user_bias[u]))"]
        liked,disliked = preferred_genres(r,u,true),preferred_genres(r,u,false)
        for (label,genres) in (("liked_genres",liked),("disliked_genres",disliked))
            push!(
                lines,
                label*" "*(isempty(genres) ? "-" : join(["$genre $count" for (genre,count) in genres]," "))
            )
        end
        recent = sort([row for row in data.training if row.u==u];by=row->(-row.time,data.items[row.i]))
        push!(
            lines,
            "recent "*join(
                ["$(data.items[row.i]) $(row.rating)" for row in recent[1:min(3,length(recent))]],
                " "
            )
        )
        candidates = [(
            v,
            r.neighborhood.user[u,v]
        ) for v in eachindex(data.users) if !isnan(r.neighborhood.user[u,v]) && r.neighborhood.user[
            u,
            v
        ]>r.params["MIN_SIMILARITY"][1]]
        for (v,similarity) in largest_neighbors(candidates,list_size)
            push!(
                lines,
                "neighbor $(data.users[v]) similarity $(real_text(similarity)) common $(r.neighborhood.user_common[u,v])"
            )
        end
        for (index,row) in enumerate(data.test)
            row.u==u || continue
            values = [real_text(r.clipped[method][index]) for method in METHODS]
            push!(lines,"heldout $(data.items[row.i]) actual $(row.rating) "*join(values," "))
        end
        liked_names = Set(genre for (genre,_) in liked)
        for method in RANKINGS
            ranked = r.rankings[u][method][1:size]
            matches = count(i->any(genre in liked_names for genre in data.genres[i]),ranked)
            push!(lines,"list $method genre_match $matches")
            for (rank,i) in enumerate(ranked)
                if method=="POPULAR"
                    push!(lines,popularity_line(r,rank,i))
                else
                    p = r.ranking_predictions[u][method][i]
                    line = "  $rank $(data.items[i]) $(real_text(p.value))"
                    if method in KNN_METHODS
                        top = p.top==0 ? "-" : string(method=="USER_KNN" ? data.users[p.top] : data.items[p.top])
                        line *= " via $top"
                    end
                    push!(lines,line*" "*data.titles[i])
                end
            end
        end
        push!(sections,lines)
    end
    sections
end
function similar_sections(r)
    data,n = r.data,r.neighborhood
    size = Int(r.params["LIST_SIZE"][1])
    factors = r.svd.items
    norms = [dot_product(factors[i,:],factors[i,:]) for i in eachindex(data.items)]
    sections = Vector{String}[]
    for id in Int.(r.params["SIMILAR_ITEMS"])
        i = data.item_index[id]
        lines = [
            "item $id ratings $(data.item_counts[i]) mean $(real_text(data.item_means[i])) bias $(real_text(r.item_bias[i])) genres $(data.genre_text[i]) title $(data.titles[i])",
            "cosine"
        ]
        candidates = [(j,n.item[i,j]) for j in eachindex(data.items) if !isnan(n.item[i,j])]
        for (rank,(j,similarity)) in enumerate(largest_neighbors(candidates,size))
            push!(
                lines,
                "  $rank $(data.items[j]) similarity $(real_text(similarity)) common $(n.counts[i,j]) $(data.titles[j])"
            )
        end
        push!(lines,"factors")
        candidates = [(
            j,
            dot_product(factors[i,:],factors[j,:])/sqrt(norms[i]*norms[j])
        ) for j in eachindex(data.items) if j!=i]
        for (rank,(j,similarity)) in enumerate(largest_neighbors(candidates,size))
            push!(lines,"  $rank $(data.items[j]) similarity $(real_text(similarity)) $(data.titles[j])")
        end
        common_items = [j for j in eachindex(data.items) if n.counts[i,j]>=1]
        ordered = sort(common_items;by=j->(-n.counts[i,j],data.items[j]))
        push!(lines,"co_rated")
        for (rank,j) in enumerate(ordered[1:min(size,length(ordered))])
            push!(lines,"  $rank $(data.items[j]) common $(n.counts[i,j]) $(data.titles[j])")
        end
        ordered = sort(common_items;by=j->(-deviation(n,j,i),-n.counts[j,i],data.items[j]))
        push!(lines,"slope_one")
        for (rank,j) in enumerate(ordered[1:min(size,length(ordered))])
            push!(
                lines,
                "  $rank $(data.items[j]) difference $(n.differences[j,i]) common $(n.counts[j,i]) $(data.titles[j])"
            )
        end
        push!(sections,lines)
    end
    sections
end
function separate_sections(sections)
    lines = String[]
    for section in sections
        isempty(lines) || push!(lines,"")
        append!(lines,section)
    end
    lines
end
function main()
    recommender = train(read_inputs())
    predictions = predict_tests!(recommender)
    prepare_rankings!(recommender)
    write_lines("predictions.csv",predictions)
    write_lines("evaluation.txt",separate_sections(evaluation_sections(recommender)))
    write_lines("recommendations.txt",separate_sections(recommendation_sections(recommender)))
    write_lines("similar_items.txt",separate_sections(similar_sections(recommender)))
    write_lines(
        "training_log.csv",
        vcat(
            ["method,epoch,train_rmse"],
            ["$method,$epoch,$(real_text(error))" for (method,epoch,error) in recommender.log]
        )
    )
end
main()
