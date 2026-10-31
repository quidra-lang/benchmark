function read_inputs()
    training = [parse.(Int,split(line,',')) for line in readlines("input/ratings.csv")[2:end]]
    tests = [parse.(Int,split(line,',')) for line in readlines("input/test.csv")[2:end]]
    users = sort(unique(row[1] for row in training))
    items = sort(unique(row[2] for row in training))
    user_index = Dict(id=>i for (i,id) in enumerate(users))
    item_index = Dict(id=>i for (i,id) in enumerate(items))
    train = [(u=user_index[r[1]],i=item_index[r[2]],rating=r[3],time=r[4]) for r in training]
    test = [(u=user_index[r[1]],i=item_index[r[2]],rating=r[3]) for r in tests]
    catalog = Dict{Int,Any}()
    for row in split.(readlines("input/items.csv")[2:end],',')
        catalog[parse(Int,row[1])] = (
            title=String(row[2]),
            genre_text=String(row[3]),
            genres=String.(split(row[3],'|'))
        )
    end
    ratings = zeros(Int,length(users),length(items))
    for r in train
        ratings[r.u,r.i] = r.rating
    end
    by_user = [findall(>(0),ratings[u,:]) for u in eachindex(users)]
    by_item = [findall(>(0),ratings[:,i]) for i in eachindex(items)]
    user_counts,item_counts = length.(by_user),length.(by_item)
    user_means = [sum(ratings[u,by_user[u]])/user_counts[u] for u in eachindex(users)]
    item_means = [sum(ratings[by_item[i],i])/item_counts[i] for i in eachindex(items)]
    params = Dict(String(words[1])=>parse.(
        Float64,
        words[2:end]
    ) for words in split.(readlines("input/params.txt")))
    (users=users,items=items,user_index=user_index,item_index=item_index,training=train,test=test,catalog=length(catalog),
     titles=[catalog[id].title for id in items],genre_text=[catalog[id].genre_text for id in items],
     genres=[catalog[id].genres for id in items],ratings=ratings,by_user=by_user,by_item=by_item,
     user_counts=user_counts,item_counts=item_counts,user_means=user_means,item_means=item_means,
     mean=sum(r.rating for r in train)/length(train),params=params)
end
