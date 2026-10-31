include("pgm_io.jl")
include("costs.jl")
include("aggregation.jl")
include("refinement.jl")
include("evaluation.jl")

const METHODS = ("sad","ssd","census","sgm","fusion","wta_final","sgm_final")
const SELECTION_METHODS = METHODS[1:4]
const REASONS = (("textureless",50),("nonunique",100),("outside",150),("mismatch",200),("occluded",255))
const SOURCES = ("kept","median","background","interpolated","none")
words(args...) = join(string.(args)," ")
lower_median(values) = sort(values)[(length(values)+1)÷2]
function neighbors4(p,width,height)
    y,x = divrem(p-1,width)
    [yy*width+xx+1 for (xx,yy) in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)) if 0<=xx<width && 0<=yy<height]
end
function select_disparities(volume,strengths,width,height,params)
    dmin,dmax = params["disparity_min"],params["disparity_max"]
    candidates = dmin:dmax
    right = zeros(Int,size(volume,1))
    for y in 0:height-1,x in 0:width-1
        p = y*width+x+1
        available = [d for d in candidates if x+d<width]
        !isempty(available) && (right[p]=argmin(d->(volume[p+d,d-dmin+1],d),available))
    end
    image,reasons,margins,lr,bounds = zeros(Int,size(volume,1)),zeros(Int,size(volume,1)),zeros(
        Int,
        size(volume,1)
    ),zeros(Int,4),0
    for y in 0:height-1,x in 0:width-1
        p = y*width+x+1
        costs = volume[p,:]
        best = argmin(costs)+dmin-1
        first = costs[best-dmin+1]
        second = minimum(costs[d-dmin+1] for d in candidates if abs(d-best)>=2)
        bounds += best==dmin || best==dmax
        consistent(d) = x>=d && abs(d-right[p-d])<=params["lr_max_diff"]
        if strengths[p]<params["texture_threshold"]
            reason = 50
        elseif 100second<=(100+params["uniqueness"])*first
            reason = 100
        elseif x<best
            reason = 150
        elseif !consistent(best)
            reason = any(consistent,candidates) ? 200 : 255
        else
            reason = 0
            image[p],margins[p] = best,second-first
        end
        reasons[p] = reason
        if reason in (0,200,255)
            lr[min(abs(best-right[p-best]),3)+1] += 1
        end
    end
    (image=image,reasons=reasons,margins=margins,lr=lr,bounds=bounds)
end
function connected_regions(image,width,height,maximum_difference)
    visited,components = falses(length(image)),Vector{Int}[]
    for start in eachindex(image)
        (image[start]==0 || visited[start]) && continue
        visited[start] = true
        stack,component = [start],Int[]
        while !isempty(stack)
            p = pop!(stack)
            push!(component,p)
            for q in neighbors4(p,width,height)
                if image[q]!=0 && !visited[q] && abs(image[q]-image[p])<=maximum_difference
                    visited[q] = true
                    push!(stack,q)
                end
            end
        end
        push!(components,component)
    end
    components
end
function ray_values(image,width,height,x,y,directions)
    values = Int[]
    for (dx,dy) in directions
        xx,yy = x+dx,y+dy
        while 0<=xx<width && 0<=yy<height
            value = image[yy*width+xx+1]
            if value!=0
                push!(values,value)
                break
            end
            xx,yy = xx+dx,yy+dy
        end
    end
    values
end
function postprocess(selection,width,height,params)
    original,filtered = selection.image,copy(selection.image)
    removed = [part for part in connected_regions(
        original,
        width,
        height,
        params["speckle_range"]
    ) if length(part)<params["speckle_size"]]
    for part in removed
        filtered[part] .= 0
    end
    medians = zeros(Int,length(original))
    for y in 0:height-1,x in 0:width-1
        p = y*width+x+1
        filtered[p]==0 && continue
        values = [filtered[yy*width+xx+1] for yy in max(0,y-1):min(
            height-1,
            y+1
        ) for xx in max(0,x-1):min(width-1,x+1) if filtered[yy*width+xx+1]!=0]
        medians[p] = lower_median(values)
    end
    result,sources = copy(medians),fill("none",length(original))
    for y in 0:height-1,x in 0:width-1
        p = y*width+x+1
        if medians[p]!=0
            sources[p] = medians[p]==original[p] ? "kept" : "median"
        elseif selection.reasons[p] in (150,255)
            values = ray_values(medians,width,height,x,y,((-1,0),(1,0)))
            if !isempty(values)
                result[p],sources[p] = minimum(values),"background"
            end
        else
            values = ray_values(medians,width,height,x,y,DIRECTIONS)
            if !isempty(values)
                result[p],sources[p] = lower_median(values),"interpolated"
            end
        end
    end
    (
        image=result,
        sources=sources,
        speckles=length(removed),
        speckle_pixels=sum(length,removed;init=0),
        median_changed=count(pair->pair[1]!=pair[2],zip(filtered,medians)),
        background=count(==("background"),sources),
        interpolated=count(==("interpolated"),sources),
        unfilled=count(==("none"),sources)
    )
end
function fuse(methods,minimum_votes)
    result,votes = zeros(Int,length(methods["sad"].image)),zeros(Int,5)
    for p in eachindex(result)
        candidates = [methods[name].image[p] for name in SELECTION_METHODS if methods[name].image[p]!=0]
        votes[length(candidates)+1] += 1
        if !isempty(candidates)
            median = lower_median(candidates)
            count(value->abs(value-median)<=1,candidates)>=minimum_votes && (result[p]=median)
        end
    end
    (image=result,votes=votes)
end
function extract_objects(image,truth,width,height,params)
    layers = sort!(unique(filter(!=(0),truth)))
    counts = Dict(layer=>count(==(layer),truth) for layer in layers)
    objects,small = NamedTuple[],0
    for component in connected_regions(image,width,height,params["object_range"])
        if length(component)<params["object_min_size"]
            small += 1
            continue
        end
        xs,ys = [(p-1)%width for p in component],[(p-1)÷width for p in component]
        disparities,n = image[component],length(component)
        median,total = lower_median(disparities),sum(disparities)
        box = (minimum(xs),minimum(ys),maximum(xs),maximum(ys))
        known = filter(!=(0),truth[component])
        layer = isempty(known) ? nothing : argmin(g->(-count(==(g),known),g),unique(known))
        hits = isnothing(layer) ? 0 : count(==(layer),known)
        union_count = isnothing(layer) ? 0 : n+counts[layer]-hits
        push!(
            objects,
            (
                pixels=n,
                box=box,
                minimum=minimum(disparities),
                maximum=maximum(disparities),
                median=median,
                mean=two_decimals(total,n),
                depth=two_decimals(params["focal_length"]*params["baseline"]*n,total),
                width=two_decimals((box[3]-box[1]+1)*params["baseline"],median),
                height=two_decimals((box[4]-box[2]+1)*params["baseline"],median),
                truth=layer,
                hits=hits,
                union_count=union_count,
                first=minimum(component)
            )
        )
    end
    sort!(objects;by=o->(-o.median,-o.pixels,o.first))
    detected = Set(o.truth for o in objects if !isnothing(o.truth) && 2*o.hits>o.union_count)
    lines = [words("objects",length(objects),"small",small,"pixels",sum((o.pixels for o in objects);init=0))]
    for (number,o) in enumerate(objects)
        truth_text = isnothing(o.truth) ? "truth - iou -" : words(
            "truth",
            o.truth,
            "iou",
            ratio(o.hits,o.union_count)
        )
        push!(
            lines,
            words(
                "object",
                number,
                "pixels",
                o.pixels,
                "box",
                o.box...,
                "disparity",
                o.minimum,
                o.maximum,
                "median",
                o.median,
                "mean",
                o.mean,
                "depth",
                o.depth,
                "size",
                o.width,
                o.height,
                truth_text
            )
        )
    end
    missed = [g for g in layers if !(g in detected)]
    push!(
        lines,
        words(
            "layers",
            length(layers),
            "detected",
            length(detected),
            "missed",
            isempty(missed) ? "-" : join(missed," ")
        )
    )
    lines
end
function sample_lines(methods,costs,truth,width,params)
    lines = ["x,y,sad,ssd,census,sgm,disparity,source,subpixel,depth,truth,truth_depth"]
    focal,baseline = params["focal_length"],params["baseline"]
    for (x,y) in params["sample_pixels"]
        p = y*width+x+1
        values = [string(x),string(y)]
        append!(
            values,
            [methods[name].image[p]==0 ? "-" : string(methods[name].image[p]) for name in SELECTION_METHODS]
        )
        d = methods["sgm_final"].image[p]
        if d!=0
            refined,depth = subpixel(
                d,
                costs[p,:],
                params["disparity_min"],
                params["disparity_max"],
                focal,
                baseline
            )
            append!(values,[string(d),methods["sgm_final"].sources[p],refined,depth])
        else
            append!(values,["-","none","-","-"])
        end
        append!(values,truth[p]==0 ? ["-","-"] : [string(truth[p]),two_decimals(focal*baseline,truth[p])])
        push!(lines,join(values,","))
    end
    lines
end
function method_lines(name,method,truth,width,height,regions,scores,params)
    image = method.image
    values = filter(!=(0),image)
    lines = [words("method",name,"valid",length(values),"invalid",length(image)-length(values))]
    push!(
        lines,
        isempty(values) ? "disparity min - max - median - distinct 0" : words(
            "disparity min",
            minimum(values),
            "max",
            maximum(values),
            "median",
            lower_median(values),
            "distinct",
            length(unique(values))
        )
    )
    horizontal,vertical = 0,0
    for y in 0:height-1,x in 0:width-1
        p = y*width+x+1
        image[p]==0 && continue
        horizontal += x+1<width && image[p+1]!=0 && abs(image[p]-image[p+1])>=2
        vertical += y+1<height && image[p+width]!=0 && abs(image[p]-image[p+width])>=2
    end
    push!(lines,words("jumps horizontal",horizontal,"vertical",vertical))
    if name in SELECTION_METHODS
        push!(lines,words("window",method.window,"bounds",method.bounds))
        push!(
            lines,
            "reasons "*join((words(reason,count(==(code),method.reasons)) for (reason,code) in REASONS)," ")
        )
        push!(lines,words("lr 0",method.lr[1],"1",method.lr[2],"2",method.lr[3],"3+",method.lr[4]))
    elseif name=="fusion"
        push!(lines,"votes "*join((words(n,method.votes[n+1]) for n in 0:4)," "))
    else
        push!(
            lines,
            words(
                "postprocess speckles",
                method.speckles,
                method.speckle_pixels,
                "median",
                method.median_changed,
                "background",
                method.background,
                "interpolated",
                method.interpolated,
                "unfilled",
                method.unfilled
            )
        )
        for source in SOURCES
            region = [p for p in regions["all"] if method.sources[p]==source]
            score = evaluate(image,truth,region)
            push!(lines,words("source",source,"pixels",score.pixels,"bad1",ratio(score.bad1,score.pixels)))
        end
    end
    for region in REGION_ORDER
        score = scores[region]
        push!(
            lines,
            words(
                "region",
                region,
                "pixels",
                score.pixels,
                "valid",
                score.valid,
                "bad1",
                ratio(score.bad1,score.pixels),
                "bad2",
                ratio(score.bad2,score.pixels),
                "mae",
                score.mae,
                "exact",
                score.exact
            )
        )
    end
    focal,baseline = params["focal_length"],params["baseline"]
    errors = [abs(depth_hundredths(image[p],focal,baseline)-depth_hundredths(
        truth[p],
        focal,
        baseline
    )) for p in regions["nonocc"] if image[p]!=0]
    push!(
        lines,
        isempty(errors) ? "depth_error pixels 0 mean - max -" : words(
            "depth_error pixels",
            length(errors),
            "mean",
            two_decimals(sum(errors),100*length(errors)),
            "max",
            two_decimals(maximum(errors),100)
        )
    )
    bins = zeros(Int,5)
    invalid = 0
    for p in regions["all"]
        if image[p]==0
            invalid += 1
        else
            bins[min(abs(image[p]-truth[p]),4)+1] += 1
        end
    end
    push!(lines,words("errors 0",bins[1],"1",bins[2],"2",bins[3],"3",bins[4],"4+",bins[5],"invalid",invalid))
    lines
end
function evaluation_lines(s,methods,sweeps,progress)
    width,height,left,right,truth,strengths,regions,params = s.width,s.height,s.left,s.right,s.truth,s.strengths,s.regions,s.params
    scores = Dict(name=>Dict(region=>evaluate(
        methods[name].image,
        truth,
        regions[region]
    ) for region in REGION_ORDER) for name in METHODS)
    delta = [right[p-truth[p]]-left[p] for p in regions["nonocc"]]
    bias_sum = sum(delta)
    bias = two_decimals(abs(bias_sum),length(delta))
    bias_sum<0 && bias!="0.00" && (bias="-"*bias)
    lines = [words("image",width,height),words("disparities",params["disparity_min"],params["disparity_max"])]
    for (name,image) in (("left",left),("right",right))
        push!(
            lines,
            words(
                name,
                "mean",
                two_decimals(sum(image),length(image)),
                "min",
                minimum(image),
                "max",
                maximum(image)
            )
        )
    end
    push!(
        lines,
        words(
            "texture mean",
            two_decimals(sum(strengths),width*height),
            "textureless",
            count(<(params["texture_threshold"]),strengths)
        )
    )
    push!(
        lines,
        words(
            "ground_truth known",
            length(regions["all"]),
            "nonocc",
            length(regions["nonocc"]),
            "occluded",
            length(regions["occluded"]),
            "disc",
            length(regions["disc"]),
            "unknown",
            width*height-length(regions["all"])
        )
    )
    push!(
        lines,
        words(
            "photometric pixels",
            length(delta),
            "mean_abs",
            two_decimals(sum(abs,delta),length(delta)),
            "bias",
            bias
        )
    )
    for sweep in sweeps
        score = sweep.metrics
        push!(
            lines,
            words(
                "sweep",
                sweep.kind,
                "window",
                sweep.window,
                "valid",
                sweep.valid,
                "bad1",
                ratio(score.bad1,score.pixels),
                "bad2",
                ratio(score.bad2,score.pixels)
            )
        )
    end
    for item in progress
        score = item.metrics
        push!(
            lines,
            words(
                "paths",
                item.number,
                "valid",
                item.valid,
                "bad1",
                ratio(score.bad1,score.pixels),
                "bad2",
                ratio(score.bad2,score.pixels)
            )
        )
    end
    for name in METHODS
        append!(lines,method_lines(name,methods[name],truth,width,height,regions,scores[name],params))
    end
    for region in REGION_ORDER
        function rank_key(index)
            score = scores[METHODS[index]][region]
            (score.bad1,score.bad2,score.valid==0,score.error_sum//max(1,score.valid),index)
        end
        ranking = sort!(collect(eachindex(METHODS));by=rank_key)
        push!(lines,words("ranking",region,join([METHODS[i] for i in ranking]," ")))
    end
    for name in SELECTION_METHODS
        method = methods[name]
        tp = count(p->method.reasons[p] in (150,255),regions["occluded"])
        fp = count(p->method.reasons[p] in (150,255),regions["nonocc"])
        fn = length(regions["occluded"])-tp
        push!(
            lines,
            words(
                "occlusion",
                name,
                "tp",
                tp,
                "fp",
                fp,
                "fn",
                fn,
                "precision",
                ratio(tp,tp+fp),
                "recall",
                ratio(tp,tp+fn)
            )
        )
    end
    for name in SELECTION_METHODS
        method = methods[name]
        pixels = sort!([p for p in regions["nonocc"] if method.image[p]!=0];by=p->(-method.margins[p],p))
        for percentage in (25,50,75,100)
            n = (length(pixels)*percentage+99)÷100
            bad = count(p->abs(method.image[p]-truth[p])>1,pixels[1:n])
            push!(
                lines,
                words(
                    "confidence",
                    name,
                    percentage,
                    "pixels",
                    n,
                    "margin",
                    n==0 ? "-" : method.margins[pixels[n]],
                    "bad1",
                    ratio(bad,n)
                )
            )
        end
    end
    for layer in sort!(unique(filter(!=(0),truth)))
        region = [p for p in regions["nonocc"] if truth[p]==layer]
        errors = [evaluate(methods[name].image,truth,region).bad1 for name in METHODS]
        push!(
            lines,
            words(
                "layer",
                layer,
                "pixels",
                count(==(layer),truth),
                "nonocc",
                length(region),
                "bad1",
                join(errors," ")
            )
        )
    end
    for d in params["disparity_min"]:params["disparity_max"]
        push!(lines,words("histogram",d,count(==(d),methods["sgm_final"].image)))
    end
    lines
end
function main()
    image = read_pgm("input/left.pgm")
    width,height,left = image.width,image.height,image.pixels
    right,truth,params = read_pgm("input/right.pgm").pixels,read_pgm("input/ground_truth.pgm").pixels,read_parameters()
    regions = truth_regions(truth,width,height)
    strengths = texture(left,width,height,params["texture_window"])
    cl,cr = census(left,width,height),census(right,width,height)
    volume(kind,window) = cost_volume(
        left,
        right,
        cl,
        cr,
        width,
        height,
        kind,
        window,
        params["disparity_min"],
        params["disparity_max"]
    )
    methods,sweeps = Dict{String,NamedTuple}(),NamedTuple[]
    for kind in METHODS[1:3]
        best = (typemax(Int),typemax(Int))
        for window in params[kind*"_windows"]
            selection = (
                ;select_disparities(volume(kind,window),strengths,width,height,params)...,
                window=window
            )
            metrics = evaluate(selection.image,truth,regions["nonocc"])
            push!(sweeps,(kind=kind,window=window,metrics=metrics,valid=count(!=(0),selection.image)))
            if (metrics.bad1,metrics.bad2)<best
                best,methods[kind] = (metrics.bad1,metrics.bad2),selection
            end
        end
    end
    stages = cumulative_costs(
        volume(params["sgm_cost"],params["sgm_window"]),
        left,
        width,
        height,
        params["sgm_paths"],
        params["p1"],
        params["p2"],
        params["p2_gamma"]
    )
    progress = NamedTuple[]
    for (number,costs) in enumerate(stages)
        selection = select_disparities(costs,strengths,width,height,params)
        push!(
            progress,
            (
                number=number,
                metrics=evaluate(selection.image,truth,regions["nonocc"]),
                valid=count(!=(0),selection.image)
            )
        )
        methods["sgm"] = (;selection...,window=params["sgm_window"])
    end
    methods["fusion"] = fuse(methods,params["fusion_min_votes"])
    methods["wta_final"] = postprocess(methods[params["wta_cost"]],width,height,params)
    methods["sgm_final"] = postprocess(methods["sgm"],width,height,params)
    mkpath("output")
    write_pgm("output/disparity_wta.pgm",width,height,8 .* methods["wta_final"].image)
    write_pgm("output/disparity_sgm.pgm",width,height,8 .* methods["sgm_final"].image)
    write_pgm("output/occlusion.pgm",width,height,methods["sgm"].reasons)
    error_image = [truth[p]==0 ? 0 : methods["sgm_final"].image[p]==0 ? 255 : 50*(min(
        abs(methods["sgm_final"].image[p]-truth[p]),
        3
    )+1) for p in eachindex(truth)]
    write_pgm("output/error_sgm.pgm",width,height,error_image)
    s = (
        width=width,
        height=height,
        left=left,
        right=right,
        truth=truth,
        strengths=strengths,
        regions=regions,
        params=params
    )
    outputs = [
        "depth.csv"=>sample_lines(methods,stages[end],truth,width,params),
        "evaluation.txt"=>evaluation_lines(s,methods,sweeps,progress),
        "objects.txt"=>extract_objects(methods["sgm_final"].image,truth,width,height,params)
    ]
    for (name,lines) in outputs
        open(joinpath("output",name),"w") do io
            for line in lines
                println(io,line)
            end
        end
    end
end
main()
