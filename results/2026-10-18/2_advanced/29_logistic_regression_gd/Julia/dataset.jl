function read_examples(path)
    lines = readlines(path)
    names = String.(split(lines[1],',')[2:end-1])
    rows = map(lines[2:end]) do line
        fields = split(line,',')
        (id=String(fields[1]),values=parse.(Float64,fields[2:end-1]),label=parse(Int,fields[end]))
    end
    names,rows
end
function read_inputs()
    names,train = read_examples("input/train.csv")
    _,test = read_examples("input/test.csv")
    entries = Dict{String,Vector{String}}()
    for line in readlines("input/params.txt")
        fields = String.(split(line))
        entries[fields[1]] = fields[2:end]
    end
    integer(key,i=1) = parse(Int,entries[key][i])
    real(key,i=1) = parse(Float64,entries[key][i])
    settings = (
        positive=integer("POSITIVE"),
        degree=integer("DEGREE"),
        threshold=real("THRESHOLD"),
        lambdas=parse.(Float64,entries["LAMBDAS"]),
        gd_rate=real("GD"),
        gd_iterations=integer("GD",2),
        sgd_rate=real("SGD"),
        batch_size=integer("SGD",2),
        epochs=integer("SGD",3),
        sgd_seed=integer("SGD",4),
        softmax_rate=real("SOFTMAX"),
        softmax_iterations=integer("SOFTMAX",2),
        softmax_lambda=real("SOFTMAX",3),
        bootstrap_count=integer("BOOTSTRAP"),
        bootstrap_seed=integer("BOOTSTRAP",2),
        permutation_count=integer("PERMUTATION"),
        permutation_seed=integer("PERMUTATION",2),
        map_width=integer("MAP"),
        map_height=integer("MAP",2),
        cost_fp=integer("COST"),
        cost_fn=integer("COST",2)
    )
    names,train,test,settings
end
function expansion_tuples(base_count,degree)
    tuples = Vector{Int}[]
    function append_tuples(prefix,remaining,first)
        if remaining == 0
            push!(tuples,copy(prefix))
        else
            for index in first:base_count
                push!(prefix,index)
                append_tuples(prefix,remaining-1,index)
                pop!(prefix)
            end
        end
    end
    for k in 1:degree
        append_tuples(Int[],k,1)
    end
    tuples
end
expanded_names(names,tuples) = [join(names[indices],'*') for indices in tuples]
function expanded_values(tuples,values)
    map(tuples) do indices
        product = values[indices[1]]
        for index in indices[2:end]
            product *= values[index]
        end
        product
    end
end
function compute_statistics(rows,count)
    means,deviations = Float64[],Float64[]
    for j in 1:count
        total = 0.0
        for row in rows
            total += row[j]
        end
        mean = total/length(rows)
        squares = 0.0
        for row in rows
            squares += (row[j]-mean)*(row[j]-mean)
        end
        push!(means,mean)
        push!(deviations,sqrt(squares/(length(rows)-1)))
    end
    (means=means,deviations=deviations)
end
standardize(values,statistics,count) = vcat(
    [1.0],
    [(values[j]-statistics.means[j])/statistics.deviations[j] for j in 1:count]
)
