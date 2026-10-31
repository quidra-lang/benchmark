struct Point
    id::Int
    x::Int
    y::Int
end
function read_points()
    points = [Point(parse.(Int,split(line,','))...) for line in readlines("input/points.csv")[2:end]]
    sort!(points,by=point->point.id)
end
function read_params()
    values = Dict{String,Vector{String}}()
    for line in readlines("input/params.txt")
        fields = String.(split(line))
        values[fields[1]] = fields[2:end]
    end
    integer(key,i=1) = parse(Int,values[key][i])
    xi_text = only(values["XI"])
    u,v = parse.(Int,split(xi_text,'/'))
    (
        eps_list=parse.(Int,values["EPS"]),
        min_pts=integer("MIN_PTS"),
        max_eps=integer("OPTICS_MAX_EPS"),
        extract_eps=parse.(Int,values["EXTRACT_EPS"]),
        xi_text=xi_text,
        xi_u=u,
        xi_v=v,
        xi_min_size=integer("XI_MIN_SIZE"),
        map_width=integer("MAP_SIZE"),
        map_height=integer("MAP_SIZE",2),
        kdist_width=integer("KDIST_PLOT"),
        kdist_height=integer("KDIST_PLOT",2),
        plot_width=integer("PLOT_WIDTH")
    )
end
