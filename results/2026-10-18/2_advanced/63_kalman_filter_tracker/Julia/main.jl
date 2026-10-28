include("matrix.jl")
include("kalman.jl")
include("association.jl")
include("imm.jl")
include("evaluation.jl")

const FILTERS = ("cv","ca","abg","imm","rts")
words(values...) = join(string.(values)," ")
optional(value) = isnothing(value) ? "-" : string(value)
function listed(keyword,items)
    values = join(string.(collect(items))," ")
    keyword*" "*(isempty(values) ? "none" : values)
end
function segments(items)
    result = Tuple{Int,Int,Int}[]
    for (scan,label) in items
        if !isempty(result) && result[end][2]+1==scan && result[end][3]==label
            result[end] = (result[end][1],scan,label)
        else
            push!(result,(scan,scan,label))
        end
    end
    result
end
path_length(positions) = ordered_total(distance(positions[i-1],positions[i]) for i in 2:length(positions))
rmse(errors) = sqrt(ordered_total(errors)/length(errors))
function filter_scores(values)
    best = argmin(name->parse(Float64,real_text(values[name])),FILTERS)
    join(("$name $(real_text(values[name]))" for name in FILTERS)," ")*" best "*best
end
function framed(grid)
    border = "+"*repeat("-",size(grid,2))*"+"
    [border;["|"*join(grid[row,:])*"|" for row in axes(grid,1)];border]
end
function read_inputs()
    measurements,times,truth,params = Vector{Vector{Float64}}[],Float64[],Dict{Int,Dict{Int,Vector{Float64}}}(),Dict{String,Any}()
    for line in readlines("input/measurements.csv")[2:end]
        fields = split(line,',')
        scan = parse(Int,fields[1])
        while length(measurements)<scan
            push!(measurements,Vector{Float64}[])
            push!(times,parse(Float64,fields[2]))
        end
        push!(measurements[scan],parse.(Float64,fields[3:4]))
    end
    for line in readlines("input/truth.csv")[2:end]
        fields = split(line,',')
        target,scan = parse.(Int,fields[1:2])
        get!(truth,target,Dict{Int,Vector{Float64}}())[scan] = parse.(Float64,fields[3:4])
    end
    for line in readlines("input/params.txt")
        fields = String.(split(line))
        name = fields[1]
        params[name] = name=="MODEL" ? fields[2] : name in (
            "CONFIRM",
            "DELETE",
            "PLOT_SIZE"
        ) ? parse.(Int,fields[2:end]) : parse.(Float64,fields[2:end])
    end
    (measurements=measurements,times=times,truth=truth,params=params)
end
Base.@kwdef mutable struct TargetTrack
    number::Int
    birth::Int
    last_hit::Int
    kalman::KalmanFilter
    confirmed::Union{Nothing,Int} = nothing
    deleted::Union{Nothing,Int} = nothing
    status::String = "tentative"
    hits::Int = 1
    consecutive_misses::Int = 0
    observations::Dict{Int,Union{Nothing,Vector{Float64}}} = Dict()
    nis::Dict{Int,Float64} = Dict()
    target::Union{Nothing,Int} = nothing
    primary_matches::Dict{Int,Int} = Dict()
    span::Vector{Int} = Int[]
    estimates::Dict{String,Dict{Int,Vector{Float64}}} = Dict()
    model_logs::Dict{String,Float64} = Dict()
    primary_covariances::Dict{Int,Matrix{Float64}} = Dict()
    high::Dict{Int,Float64} = Dict()
    nis_values::Vector{Float64} = Float64[]
    longest_gap::Int = 0
    path::Float64 = 0.0
    common::Vector{Int} = Int[]
    mean_distance::Float64 = 0.0
end
parameter(s,name) = s.params[name][1]
function make_kalman(s,model,measurement)
    KalmanFilter(
        model,
        parameter(s,"Q_"*model),
        parameter(s,"SIGMA"),
        parameter(s,"INIT_VELOCITY_VARIANCE"),
        parameter(s,"INIT_ACCELERATION_VARIANCE"),
        measurement
    )
end
function track_all_scans(s)
    required_hits,window = s.params["CONFIRM"]
    for scan in 1:s.scans
        live = [track for track in s.tracks if track.status!="deleted"]
        measurements = s.measurements[scan]
        if scan>1
            for track in live
                predict!(track.kalman,s.times[scan]-s.times[scan-1])
            end
        end
        usable,innovations = Dict{Tuple{Int,Int},Float64}(),Dict{Tuple{Int,Int},NamedTuple}()
        row_gates,column_gates = zeros(Int,length(live)),zeros(Int,length(measurements))
        for (row,track) in enumerate(live),(column,measurement) in enumerate(measurements)
            info = innovation(track.kalman,measurement)
            if info.distance2<=parameter(s,"GATE")
                usable[(row,column)],innovations[(row,column)] = info.distance2,info
                row_gates[row] += 1
                column_gates[column] += 1
            end
        end
        assigned = optimal_assignment(length(live),length(measurements),usable)
        greedy,used_rows,used_columns = Tuple{Int,Int}[],Set{Int}(),Set{Int}()
        for (row,column) in sort!(collect(keys(usable));by=pair->(usable[pair],live[pair[1]].number,pair[2]))
            if !(row in used_rows) && !(column in used_columns)
                push!(greedy,(row,column))
                push!(used_rows,row)
                push!(used_columns,column)
            end
        end
        sort!(greedy)
        s.counters[3] += assigned!=greedy
        matches = Dict(assigned)
        missed,confirmed,deleted = Int[],Int[],Int[]
        for (row,track) in enumerate(live)
            if haskey(matches,row)
                column = matches[row]
                measurement = measurements[column]
                update!(track.kalman,measurement,innovations[(row,column)])
                track.observations[scan],track.nis[scan] = measurement,usable[(row,column)]
                track.last_hit,track.hits,track.consecutive_misses = scan,track.hits+1,0
            else
                track.observations[scan] = nothing
                track.consecutive_misses += 1
                push!(missed,track.number)
            end
            if track.status=="confirmed"
                if track.consecutive_misses>=parameter(s,"DELETE")
                    track.status,track.deleted = "deleted",scan
                    push!(deleted,track.number)
                end
            elseif track.hits>=required_hits
                track.status,track.confirmed = "confirmed",scan
                push!(confirmed,track.number)
            elseif scan-track.birth+1>=window
                track.status,track.deleted = "deleted",scan
                push!(deleted,track.number)
            end
        end
        used_columns = Set(column for (_,column) in assigned)
        new = Tuple{TargetTrack,Int}[]
        for (column,measurement) in enumerate(measurements)
            column in used_columns && continue
            track = TargetTrack(
                number=length(s.tracks)+1,
                birth=scan,
                last_hit=scan,
                kalman=make_kalman(s,s.params["MODEL"],measurement)
            )
            track.observations[scan] = measurement
            push!(s.tracks,track)
            push!(new,(track,column))
        end
        conflicts_m,conflicts_t = count(>=(2),column_gates),count(>=(2),row_gates)
        s.counters[1] += conflicts_m
        s.counters[2] += conflicts_t
        append!(s.log,[words("scan",scan,"tracks",length(live),"measurements",length(measurements)),
            listed(
                "gate",
                ("$(live[row].number):$column=$(real_text(usable[(row,column)]))" for (
                    row,
                    column
                ) in sort!(collect(keys(usable))))
            ),
            listed("assign",("$(live[row].number):$column" for (row,column) in assigned)),
            listed(
                "greedy",
                ("$(live[row].number):$column" for (row,column) in greedy)
            ),listed("missed",missed),
            listed(
                "new",
                ("$(track.number):$column" for (track,column) in new)
            ),listed("confirmed",confirmed),listed("deleted",deleted),
            words(
                "status tentative",
                count(t->t.status=="tentative",s.tracks),
                "confirmed",
                count(t->t.status=="confirmed",s.tracks)
            ),
            words("conflicts measurements",conflicts_m,"tracks",conflicts_t)])
        for track in [live;[track for (track,_) in new]]
            push!(
                s.track_rows,
                join([string(track.number),string(scan),real_text.(track.kalman.x[1:4])...,track.status],",")
            )
        end
    end
    (;s...,evaluated=[track for track in s.tracks if !isnothing(track.confirmed)])
end
function abg_estimates(s,track)
    alpha,beta,gamma = s.params["ABG"]
    state = [track.observations[track.birth];zeros(4)]
    estimates = Dict{Int,Vector{Float64}}()
    for scan in track.span
        if scan>track.birth
            t = s.times[scan]-s.times[scan-1]
            measurement = track.observations[scan]
            for axis in 1:2
                position,velocity,acceleration = state[axis],state[axis+2],state[axis+4]
                position = position+t*velocity+t*t*acceleration/2
                velocity = velocity+t*acceleration
                if !isnothing(measurement)
                    residual = measurement[axis]-position
                    position += alpha*residual
                    velocity += beta*residual/t
                    acceleration += 2*gamma*residual/(t*t)
                end
                state[axis],state[axis+2],state[axis+4] = position,velocity,acceleration
            end
        end
        estimates[scan] = state[1:4]
    end
    estimates
end
function compare_filters!(s)
    for track in s.evaluated
        track.span = collect(track.birth:track.last_hit)
        track.estimates = Dict(name=>Dict{Int,Vector{Float64}}() for name in FILTERS)
        histories = Dict{String,Vector{NamedTuple}}()
        for name in ("cv","ca")
            filter = make_kalman(s,uppercase(name),track.observations[track.birth])
            history,likelihood = NamedTuple[],0.0
            for scan in track.span
                if scan>track.birth
                    predict!(filter,s.times[scan]-s.times[scan-1])
                    measurement = track.observations[scan]
                    !isnothing(measurement) && (likelihood+=update!(filter,measurement).likelihood)
                end
                track.estimates[name][scan] = filter.x[1:4]
                push!(history,filter_snapshot(filter))
            end
            histories[name],track.model_logs[name] = history,likelihood
        end
        track.estimates["abg"] = abg_estimates(s,track)
        history = histories[s.primary]
        track.primary_covariances = Dict(scan=>state.p for (scan,state) in zip(track.span,history))
        track.estimates["rts"] = Dict(scan=>state[1:4] for (scan,state) in zip(track.span,smooth(history)))
        imm = IMMFilter(
            s.params["IMM_Q"],
            s.params["IMM_TRANSITION"],
            s.params["IMM_INITIAL"],
            parameter(s,"SIGMA"),
            parameter(s,"INIT_VELOCITY_VARIANCE"),
            track.observations[track.birth]
        )
        for scan in track.span
            scan>track.birth && imm_step!(imm,s.times[scan]-s.times[scan-1],track.observations[scan])
            track.estimates["imm"][scan],track.high[scan] = imm_estimate(imm),imm.probabilities[2]
        end
        track.nis_values = [track.nis[scan] for scan in track.span if haskey(track.nis,scan)]
        gap = 0
        for scan in track.span
            gap = isnothing(track.observations[scan]) ? gap+1 : 0
            track.longest_gap = max(track.longest_gap,gap)
        end
        track.path = path_length([track.estimates["rts"][scan] for scan in track.span])
    end
end
function evaluate_scans(s)
    labels = Dict(name=>Dict(target=>zeros(Int,s.scans) for target in s.targets) for name in FILTERS)
    ospa_values = Dict(name=>Float64[] for name in FILTERS)
    scan_sizes = Tuple{Int,Int}[]
    for scan in 1:s.scans
        tracks = [track for track in s.evaluated if track.birth<=scan<=track.last_hit]
        targets = [target for target in s.targets if haskey(s.truth[target],scan)]
        push!(scan_sizes,(length(targets),length(tracks)))
        positions = [s.truth[target][scan] for target in targets]
        for name in FILTERS
            estimates = [track.estimates[name][scan] for track in tracks]
            usable = Dict{Tuple{Int,Int},Float64}()
            for (row,estimate) in enumerate(estimates),(column,point) in enumerate(positions)
                value = distance(estimate,point)
                value<=parameter(s,"MATCH_DISTANCE") && (usable[(row,column)]=value)
            end
            for (row,column) in optimal_assignment(length(tracks),length(targets),usable)
                track,target = tracks[row],targets[column]
                labels[name][target][scan] = track.number
                name==s.primary && (track.primary_matches[scan]=target)
            end
            push!(ospa_values[name],ospa(estimates,positions,parameter(s,"OSPA_CUTOFF")))
        end
    end
    continuities = Dict(name=>Dict(target=>continuity(labels[name][target][sort!(collect(keys(s.truth[target])))]) for target in s.targets) for name in FILTERS)
    (;s...,labels=labels,ospa_values=ospa_values,scan_sizes=scan_sizes,continuities=continuities)
end
function match_tracks(s)
    usable,details = Dict{Tuple{Int,Int},Float64}(),Dict{Tuple{Int,Int},Vector{Int}}()
    cutoff = parameter(s,"OSPA_CUTOFF")
    for (row,track) in enumerate(s.evaluated),(column,target) in enumerate(s.targets)
        positions = s.truth[target]
        common = [scan for scan in track.span if haskey(positions,scan)]
        isempty(common) && continue
        distances = Dict(scan=>distance(track.estimates[s.primary][scan],positions[scan]) for scan in common)
        any(<(cutoff),values(distances)) || continue
        union_scans = sort!(collect(union(Set(track.span),Set(keys(positions)))))
        cost = ordered_total(haskey(distances,scan) ? min(
            cutoff,
            distances[scan]
        ) : cutoff for scan in union_scans)/length(union_scans)
        usable[(row,column)],details[(row,column)] = cost,common
    end
    matched = Dict{Int,TargetTrack}()
    for (row,column) in optimal_assignment(length(s.evaluated),length(s.targets),usable)
        track,target = s.evaluated[row],s.targets[column]
        track.target,track.common,track.mean_distance = target,details[(row,column)],usable[(row,column)]
        matched[target] = track
    end
    (;s...,matched_tracks=matched)
end
function evaluate_errors(s)
    results = Dict{Int,NamedTuple}()
    overall_position,overall_velocity = Dict(name=>Float64[] for name in FILTERS),Dict(name=>Float64[] for name in FILTERS)
    for target in s.targets
        haskey(s.matched_tracks,target) || continue
        track,positions = s.matched_tracks[target],s.truth[target]
        velocities = Dict{Int,Vector{Float64}}()
        for scan in track.common
            if haskey(positions,scan-1) && haskey(positions,scan+1)
                velocities[scan] = (positions[scan+1]-positions[scan-1])/(s.times[scan+1]-s.times[scan-1])
            end
        end
        position_scores,velocity_scores = Dict{String,Float64}(),Dict{String,Float64}()
        for name in FILTERS
            pe = [squared_distance(track.estimates[name][scan],positions[scan]) for scan in track.common]
            ve = [squared_distance(
                track.estimates[name][scan][3:4],
                velocities[scan]
            ) for scan in sort!(collect(keys(velocities)))]
            position_scores[name],velocity_scores[name] = rmse(pe),rmse(ve)
            append!(overall_position[name],pe)
            append!(overall_velocity[name],ve)
        end
        nees = [quadratic2(
            track.estimates[s.primary][scan][1:2]-positions[scan],
            matrix_inverse(track.primary_covariances[scan][1:2,1:2])
        ) for scan in track.common]
        results[target] = (
            track=track,
            position=position_scores,
            velocity=velocity_scores,
            velocity_count=length(velocities),
            nees=nees
        )
    end
    (
        ;s...,
        target_results=results,
        overall_position=Dict(name=>rmse(overall_position[name]) for name in FILTERS),
        overall_velocity=Dict(name=>rmse(overall_velocity[name]) for name in FILTERS)
    )
end
function evaluation_lines(s)
    lines = [
        "summary",
        words("scans",s.scans),
        words("measurements",sum(length,s.measurements)),
        words("targets",length(s.targets)),
        words("tracks_created",length(s.tracks)),
        words("tracks_confirmed",length(s.evaluated)),
        words("false_tracks",count(t->isempty(t.primary_matches),s.evaluated)),
        words("missed_targets",length(s.targets)-length(s.matched_tracks)),
        words("measurements_used",sum(t.hits for t in s.evaluated)),
        words("conflict_measurements",s.counters[1]),
        words("conflict_tracks",s.counters[2]),
        words("greedy_differences",s.counters[3]),
        "",
        "targets"
    ]
    for target in s.targets
        scans = sort!(collect(keys(s.truth[target])))
        path = path_length([s.truth[target][scan] for scan in scans])
        push!(
            lines,
            words(
                "target",
                target,
                "first",
                scans[1],
                "last",
                scans[end],
                "scans",
                length(scans),
                "path",
                real_text(path),
                "mean_speed",
                real_text(path/(s.times[scans[end]]-s.times[scans[1]]))
            )
        )
    end
    append!(lines,["","tracks"])
    bound = parameter(s,"CONSISTENCY_BOUND")
    for track in s.evaluated
        n = length(track.nis_values)
        push!(
            lines,
            words(
                "track",
                track.number,
                "birth",
                track.birth,
                "confirmed",
                track.confirmed,
                "end",
                track.last_hit,
                "deleted",
                optional(track.deleted),
                "hits",
                track.hits,
                "misses",
                length(track.span)-track.hits,
                "longest_gap",
                track.longest_gap,
                "path",
                real_text(track.path),
                "nis",
                real_text(ordered_total(track.nis_values)/n),
                "nis_inside",
                "$(count(<=(bound),track.nis_values))/$n"
            )
        )
    end
    append!(lines,["","matching"])
    for track in s.evaluated
        text = words("track",track.number,"target",optional(track.target))
        !isnothing(track.target) && (text*=words(
            " common",
            length(track.common),
            "mean_distance",
            real_text(track.mean_distance)
        ))
        ranges = segments(sort!(collect(track.primary_matches);by=first))
        push!(
            lines,
            text*words(
                " matched_scans",
                length(track.primary_matches),
                listed("segments",("$first-$last:$target" for (first,last,target) in ranges))
            )
        )
    end
    append!(lines,["","rmse"])
    for target in s.targets
        if !haskey(s.target_results,target)
            push!(lines,words("target",target,"track -"))
        else
            result = s.target_results[target]
            push!(
                lines,
                words(
                    "target",
                    target,
                    "track",
                    result.track.number,
                    "common",
                    length(result.track.common),
                    filter_scores(result.position)
                )
            )
            push!(
                lines,
                words("target",target,"velocity",result.velocity_count,filter_scores(result.velocity))
            )
        end
    end
    append!(
        lines,
        [
            "overall position "*filter_scores(s.overall_position),
            "overall velocity "*filter_scores(s.overall_velocity),
            "",
            "consistency"
        ]
    )
    for target in s.targets
        if !haskey(s.target_results,target)
            push!(lines,words("target",target,"track -"))
        else
            result = s.target_results[target]
            push!(
                lines,
                words(
                    "target",
                    target,
                    "track",
                    result.track.number,
                    "nees",
                    real_text(ordered_total(result.nees)/length(result.nees)),
                    "inside",
                    "$(count(<=(bound),result.nees))/$(length(result.nees))"
                )
            )
        end
    end
    nis = [value for track in s.evaluated for value in track.nis_values]
    edges = s.params["NIS_EDGES"]
    observed = zeros(Int,length(edges)+1)
    for value in nis
        observed[searchsortedlast(edges,value)+1] += 1
    end
    expected,lower = Float64[],0.0
    for upper in [edges;Inf]
        push!(expected,length(nis)*(exp(-lower/2)-(isinf(upper) ? 0.0 : exp(-upper/2))))
        lower = upper
    end
    push!(
        lines,
        words(
            "nis_histogram total",
            length(nis),
            "observed",
            join(observed," "),
            "expected",
            join(real_text.(expected)," ")
        )
    )
    append!(lines,["","models"])
    for track in s.evaluated
        cv,ca = track.model_logs["cv"],track.model_logs["ca"]
        push!(
            lines,
            words(
                "track",
                track.number,
                "updates",
                length(track.nis_values),
                "cv",
                real_text(cv),
                "ca",
                real_text(ca),
                "better",
                cv>=ca ? "cv" : "ca"
            )
        )
    end
    append!(
        lines,
        [
            "",
            words("ospa cutoff",real_text(parameter(s,"OSPA_CUTOFF")),"order 2"),
            "scan targets tracks cv ca abg imm rts"
        ]
    )
    for scan in 1:s.scans
        push!(
            lines,
            words(
                scan,
                s.scan_sizes[scan]...,
                join((real_text(s.ospa_values[name][scan]) for name in FILTERS)," ")
            )
        )
    end
    push!(lines,"mean "*join((real_text(ordered_total(s.ospa_values[name])/s.scans) for name in FILTERS)," "))
    append!(lines,["","continuity"])
    for name in FILTERS
        values = s.continuities[name]
        push!(
            lines,
            words(
                name,
                "covered",
                sum(values[target].covered for target in s.targets),
                "breaks",
                sum(values[target].breaks for target in s.targets),
                "swaps",
                sum(values[target].swaps for target in s.targets)
            )
        )
        for target in s.targets
            result = values[target]
            push!(
                lines,
                words(
                    "  target",
                    target,
                    "scans",
                    length(s.truth[target]),
                    "covered",
                    result.covered,
                    "breaks",
                    result.breaks,
                    "swaps",
                    result.swaps,
                    "delay",
                    optional(result.delay)
                )
            )
        end
    end
    append!(lines,["","imm"])
    for track in s.evaluated
        high = [track.high[scan] for scan in track.span]
        index = argmax(high)
        ranges = segments((scan,1) for scan in track.span if track.high[scan]>0.5)
        push!(
            lines,
            words(
                "track",
                track.number,
                "mean_high",
                real_text(ordered_total(high)/length(high)),
                "max_high",
                real_text(high[index]),
                "at",
                track.span[index],
                "high_scans",
                count(>(0.5),high),
                listed("segments",("$first-$last" for (first,last,_) in ranges))
            )
        )
    end
    lines
end
function plot_cell(s,point)
    xmin,xmax = s.params["PLOT_X"]
    ymin,ymax = s.params["PLOT_Y"]
    width,height = s.params["PLOT_SIZE"]
    column = floor(Int,(point[1]-xmin)/((xmax-xmin)/width))
    row = floor(Int,(ymax-point[2])/((ymax-ymin)/height))
    0<=column<width && 0<=row<height ? (row+1,column+1) : nothing
end
function plot_lines(s)
    width,height = s.params["PLOT_SIZE"]
    xmin,xmax = s.params["PLOT_X"]
    ymin,ymax = s.params["PLOT_Y"]
    characters = Dict(track.number=>(i<=26 ? Char(Int('A')+i-1) : Char(Int('a')+i-27)) for (
        i,
        track
    ) in enumerate(s.evaluated))
    trajectory = fill(' ',height,width)
    for target in s.targets,scan in sort!(collect(keys(s.truth[target])))
        cell = plot_cell(s,s.truth[target][scan])
        !isnothing(cell) && (trajectory[cell...]='.')
    end
    for track in s.evaluated,scan in track.span
        cell = plot_cell(s,track.estimates["rts"][scan])
        !isnothing(cell) && (trajectory[cell...]=characters[track.number])
    end
    lines = [words(
        "tracks x",
        real_text(xmin),
        real_text(xmax),
        "y",
        real_text(ymin),
        real_text(ymax),
        "size",
        width,
        height
    )]
    append!(lines,framed(trajectory))
    for track in s.evaluated
        push!(lines,words(characters[track.number],"track",track.number,"target",optional(track.target)))
    end
    counts = zeros(Int,height,width)
    for measurements in s.measurements,measurement in measurements
        cell = plot_cell(s,measurement)
        !isnothing(cell) && (counts[cell...]+=1)
    end
    density = [
        counts[row,column]==0 ? ' ' : counts[row,column]<10 ? Char(Int('0')+counts[
            row,
            column
        ]) : '#' for row in 1:height,
        column in 1:width
    ]
    append!(lines,["","measurements"])
    append!(lines,framed(density))
    append!(lines,["","timeline"])
    for target in s.targets
        timeline = [!haskey(
            s.truth[target],
            scan
        ) ? ' ' : s.labels[s.primary][target][scan]==0 ? '.' : characters[s.labels[s.primary][target][scan]] for scan in 1:s.scans]
        push!(lines,"$target |$(join(timeline))|")
    end
    heights = [floor(Int,10*value/parameter(s,"OSPA_CUTOFF")) for value in s.ospa_values[s.primary]]
    bars = [heights[column]>=11-row ? '#' : ' ' for row in 1:10,column in 1:s.scans]
    append!(lines,["","ospa "*s.primary])
    append!(lines,framed(bars))
    lines
end
function main()
    data = read_inputs()
    s = (
        ;data...,
        scans=length(data.measurements),
        targets=sort!(collect(keys(data.truth))),
        primary=lowercase(data.params["MODEL"]),
        tracks=TargetTrack[],
        track_rows=["track,scan,x,y,vx,vy,status"],
        log=String[],
        counters=zeros(Int,3)
    )
    s = track_all_scans(s)
    compare_filters!(s)
    s = evaluate_scans(s)
    s = match_tracks(s)
    s = evaluate_errors(s)
    smoothed = ["track,scan,x,y,vx,vy"]
    for track in s.evaluated,scan in track.span
        push!(
            smoothed,
            join([string(track.number),string(scan),real_text.(track.estimates["rts"][scan])...],",")
        )
    end
    mkpath("output")
    for (name,lines) in [
        "tracks.csv"=>s.track_rows,
        "smoothed.csv"=>smoothed,
        "association_log.txt"=>s.log,
        "evaluation.txt"=>evaluation_lines(s),
        "track_plot.txt"=>plot_lines(s)
    ]
        open(joinpath("output",name),"w") do io
            for line in lines
                println(io,line)
            end
        end
    end
end
main()
