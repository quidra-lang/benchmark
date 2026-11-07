include("pgm_reader.jl")
include("threshold.jl")
include("morphology.jl")
include("labeling.jl")
include("report.jl")

const SYMBOLS = collect("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
const ORIENTATIONS = ["none", "horizontal", "vertical", "falling", "rising"]
const FOUR = [(1, 0), (0, -1), (-1, 0), (0, 1)]
const EIGHT = [(1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1), (0, 1), (1, 1)]
const CSV_HEADER = "image,label,class,flags,area,x0,y0,x1,y1,cx,cy,mean,variance,min,max,contrast,border,perimeter,chain,straight,diagonal,turns,compactness,runs,holes,hole_area,euler,parent,depth,var_x,var_y,cov_xy,hu1,orientation,anisotropy,extent,mirror_lr,mirror_tb,hull_area,solidity,feret2,width2,elongation,bays,bay_area,skeleton,endpoints,branches,neighbor,distance2,codes"

struct Setting
    connectivity::Int
    threshold::String
    polarity::String
    operations::Vector{String}
end

method_name(setting) = setting.threshold in ("otsu", "isodata") ? setting.threshold : "fixed"
parse_rational(text) = occursin('/', text) ? parse(Int, split(text, '/')[1]) // parse(Int, split(text, '/')[2]) : parse(Int, text) // 1

struct Parameters
    otsu_top::Int
    sweep_step::Int
    isotropy::Rational{Int}
    bay_min::Int
    elements::Dict{String,Vector{Pixel}}
    settings::Dict{String,Setting}
end

function read_parameters(path)
    entries = split.(readlines(path))
    otsu_top, sweep_step, bay_min = 0, 0, 0
    isotropy = 0 // 1
    elements, settings = Dict{String,Vector{Pixel}}(), Dict{String,Setting}()
    for words in entries
        keyword = words[1]
        if keyword == "otsu_top"
            otsu_top = parse(Int, words[2])
        elseif keyword == "sweep"
            sweep_step = parse(Int, words[2])
        elseif keyword == "isotropy"
            isotropy = parse_rational(words[2])
        elseif keyword == "bay_min"
            bay_min = parse(Int, words[2])
        elseif keyword == "element"
            ox, oy = parse.(Int, words[5:6])
            offsets = Pixel[]
            for (row, text) in enumerate(words[7:end]), (column, symbol) in enumerate(text)
                symbol == '#' && push!(offsets, (column - 1 - ox, row - 1 - oy))
            end
            elements[words[2]] = offsets
        elseif keyword == "image"
            settings[words[2]] = Setting(parse(Int, words[3]), words[4], words[5], String.(words[6:end]))
        end
    end
    Parameters(otsu_top, sweep_step, isotropy, bay_min, elements, settings)
end

struct RegionCondition
    feature::String
    comparison::String
    text::String
    value::Rational{Int}
end

RegionCondition(words) = RegionCondition(words[1], words[2], words[3], words[1] == "orientation" ? 0 // 1 : parse_rational(words[3]))

function condition_holds(condition, region)
    if condition.feature == "orientation"
        return condition.comparison == "=" ? region.orientation == condition.text : region.orientation != condition.text
    end
    own, value = region.features[condition.feature], condition.value
    operator = condition.comparison
    operator == "<" && return own < value
    operator == "<=" && return own <= value
    operator == ">" && return own > value
    operator == ">=" && return own >= value
    operator == "=" ? own == value : own != value
end

struct Rule
    name::String
    conditions::Vector{RegionCondition}
end

rule_matches(rule, region) = all(condition_holds(condition, region) for condition in rule.conditions)

struct Rules
    filters::Vector{RegionCondition}
    classes::Vector{Rule}
    flags::Vector{Rule}
end

function read_rules(path)
    filters, classes, flags = RegionCondition[], Rule[], Rule[]
    for line in readlines(path)
        words = split(line)
        if words[1] == "filter"
            push!(filters, RegionCondition(words[2:end]))
        else
            rule = Rule(words[2], [RegionCondition(words[index:index+2]) for index in 3:3:length(words)])
            push!(words[1] == "class" ? classes : flags, rule)
        end
    end
    Rules(filters, classes, flags)
end

function class_names(rules)
    names = String[]
    for rule in rules.classes
        !(rule.name in names) && push!(names, rule.name)
    end
    push!(names, "other")
end

struct Hole
    number::Int
    pixels::Vector{Pixel}
    owner::Int
end

Base.@kwdef mutable struct Region
    number::Int
    pixels::Vector{Pixel}
    features::Dict{String,Rational{Int}} = Dict{String,Rational{Int}}()
    orientation::String = "none"
    codes::Vector{Int} = Int[]
    skeleton::Set{Pixel} = Set{Pixel}()
    hull_doubled::Int = 0
    parent::Union{Nothing,Int} = nothing
    depth::Int = 0
    children::Vector{Int} = Int[]
    kept::Bool = false
    dropped_by::Union{Nothing,Int} = nothing
    class_name::String = "other"
    flags::Vector{String} = String[]
    neighbor::Union{Nothing,Int} = nothing
    distance::Int = 0
end

integer(region, name) = Int(region.features[name])
directions(connectivity) = connectivity == 4 ? FOUR : EIGHT

function group_pixels(labels, region_count)
    groups = [Pixel[] for _ in 0:region_count]
    for y in axes(labels, 1), x in axes(labels, 2)
        push!(groups[labels[y, x] + 1], (x - 1, y - 1))
    end
    groups
end

function enclosed_components(mask, connectivity)
    components = label_components(.!mask, connectivity)
    height, width = size(mask)
    [pixels for pixels in group_pixels(components.labels, components.count)[2:end]
        if !any(x == 0 || y == 0 || x == width - 1 || y == height - 1 for (x, y) in pixels)]
end

function fill_holes(mask, connectivity)
    filled = copy(mask)
    for pixels in enclosed_components(mask, connectivity), (x, y) in pixels
        filled[y + 1, x + 1] = true
    end
    filled
end

cross(a, b, p) = (b[1] - a[1]) * (p[2] - a[2]) - (b[2] - a[2]) * (p[1] - a[1])
squared_distance(a, b) = (a[1] - b[1])^2 + (a[2] - b[2])^2

function half_hull(points)
    chain = Pixel[]
    for point in points
        while length(chain) >= 2 && cross(chain[end - 1], chain[end], point) <= 0
            pop!(chain)
        end
        push!(chain, point)
    end
    chain
end

function convex_hull(pixels)
    corners = Set{Pixel}()
    for (x, y) in pixels
        union!(corners, [(x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)])
    end
    ordered = sort(collect(corners))
    vcat(half_hull(ordered)[1:end-1], half_hull(reverse(ordered))[1:end-1])
end

hull_edges(hull) = [(hull[index], hull[mod1(index + 1, length(hull))]) for index in eachindex(hull)]
contains_center(hull, x, y) = all(cross((2 * a[1], 2 * a[2]), (2 * b[1], 2 * b[2]), (2 * x + 1, 2 * y + 1)) >= 0 for (a, b) in hull_edges(hull))
box_bounds(pixels) = (minimum(first, pixels), minimum(last, pixels), maximum(first, pixels), maximum(last, pixels))

function box_distance(first, second)
    dx = integer(first, "x0") + integer(first, "x1") - integer(second, "x0") - integer(second, "x1")
    dy = integer(first, "y0") + integer(first, "y1") - integer(second, "y0") - integer(second, "y1")
    dx^2 + dy^2
end

mean_text(total, amount) = amount == 0 ? "-" : decimal_text(total // amount, 2)
orientation_line(regions) = "orientations " * join(["$name $(count(region -> region.orientation == name, regions))" for name in ORIENTATIONS], " ")
label_at(a, x, y) = 0 <= x < a.image.width && 0 <= y < a.image.height ? a.labels[y + 1, x + 1] : -1

function chain_code(a, region)
    steps = directions(a.setting.connectivity)
    visited, codes = [region.pixels[1]], Int[]
    heading = length(steps) - 1
    while true
        x, y = visited[end]
        start = length(steps) == 4 ? mod(heading + 3, 4) : mod(heading + (iseven(heading) ? 7 : 6), 8)
        chosen = nothing
        for offset in 0:length(steps)-1
            direction = mod(start + offset, length(steps))
            dx, dy = steps[direction + 1]
            if label_at(a, x + dx, y + dy) == region.number
                chosen = direction
                break
            end
        end
        isnothing(chosen) && return Int[]
        dx, dy = steps[chosen + 1]
        push!(visited, (x + dx, y + dy))
        push!(codes, chosen)
        heading = chosen
        moves = length(codes)
        if moves >= 2 && visited[moves + 1] == visited[2] && visited[moves] == visited[1]
            return codes[1:end-1]
        end
    end
end

function measure!(a, region, parameters)
    f, pixels = region.features, region.pixels
    area = length(pixels)
    x0, y0, x1, y1 = box_bounds(pixels)
    for (name, value) in [("area", area), ("x0", x0), ("y0", y0), ("x1", x1), ("y1", y1),
        ("width", x1 - x0 + 1), ("height", y1 - y0 + 1)]
        f[name] = value // 1
    end
    f["border"] = Int(x0 == 0 || y0 == 0 || x1 == a.image.width - 1 || y1 == a.image.height - 1) // 1
    values = [a.image.pixels[y + 1, x + 1] for (x, y) in pixels]
    sum_values, sum_squares = sum(values), sum(value^2 for value in values)
    f["mean"], f["variance"] = sum_values // area, (area * sum_squares - sum_values^2) // area^2
    f["min"], f["max"] = minimum(values) // 1, maximum(values) // 1
    surrounding = Set{Pixel}()
    for (x, y) in pixels, (dx, dy) in EIGHT
        label_at(a, x + dx, y + dy) == 0 && push!(surrounding, (x + dx, y + dy))
    end
    amount = length(surrounding)
    sum_surrounding = sum((a.image.pixels[y + 1, x + 1] for (x, y) in surrounding); init=0)
    f["contrast"] = amount == 0 ? 0 // 1 : (sum_values * amount - sum_surrounding * area) // (area * amount)
    f["perimeter"] = count(point -> any(label_at(a, point[1] + dx, point[2] + dy) != region.number for (dx, dy) in directions(12 - a.setting.connectivity)), pixels) // 1
    region.codes = chain_code(a, region)
    straight = a.setting.connectivity == 4 ? length(region.codes) : count(iseven, region.codes)
    diagonal = length(region.codes) - straight
    turns = count(index -> region.codes[index] != region.codes[mod1(index - 1, length(region.codes))], eachindex(region.codes))
    for (name, value) in [("chain", length(region.codes)), ("straight", straight), ("diagonal", diagonal), ("turns", turns)]
        f[name] = value // 1
    end
    f["compactness"] = (5 * straight + 7 * diagonal)^2 // (25 * area)
    f["runs"] = count(point -> label_at(a, point[1] - 1, point[2]) != region.number, pixels) // 1
    owned = [hole for hole in a.holes if hole.owner == region.number]
    f["holes"], f["hole_area"] = length(owned) // 1, sum((length(hole.pixels) for hole in owned); init=0) // 1
    f["euler"], f["depth"] = (1 - length(owned)) // 1, region.depth // 1
    sx, sy = sum(first, pixels), sum(last, pixels)
    m20 = area * sum(x * x for (x, _) in pixels) - sx^2
    m02 = area * sum(y * y for (_, y) in pixels) - sy^2
    m11 = area * sum(x * y for (x, y) in pixels) - sx * sy
    f["cx"], f["cy"] = sx // area, sy // area
    f["var_x"], f["var_y"], f["cov_xy"] = m20 // area^2, m02 // area^2, m11 // area^2
    f["hu1"] = (m20 + m02) // area^3
    anisotropy = m20 + m02 > 0 ? (abs(m20 - m02) + 2 * abs(m11)) // (m20 + m02) : 0 // 1
    f["anisotropy"] = anisotropy
    u, v = m20 - m02, 2 * m11
    region.orientation = anisotropy <= parameters.isotropy ? "none" : abs(v) >= abs(u) ? (v > 0 ? "falling" : "rising") : (u > 0 ? "horizontal" : "vertical")
    f["extent"] = area // ((x1 - x0 + 1) * (y1 - y0 + 1))
    f["mirror_lr"] = count(point -> label_at(a, x0 + x1 - point[1], point[2]) == region.number, pixels) // area
    f["mirror_tb"] = count(point -> label_at(a, point[1], y0 + y1 - point[2]) == region.number, pixels) // area
    hull = convex_hull(pixels)
    region.hull_doubled = abs(sum(p[1] * q[2] - q[1] * p[2] for (p, q) in hull_edges(hull)))
    feret2 = maximum(squared_distance(p, q) for p in hull for q in hull)
    width2 = minimum((maximum(abs(cross(p, q, v)) for v in hull)^2) // squared_distance(p, q) for (p, q) in hull_edges(hull))
    f["solidity"], f["feret2"], f["width2"] = (2 * area) // region.hull_doubled, feret2 // 1, width2
    f["elongation"] = (feret2 // 1) / width2
    bay_mask = [a.labels[y + 1, x + 1] == 0 && a.hole_of[y + 1, x + 1] == 0 && contains_center(hull, x, y) for y in y0:y1, x in x0:x1]
    bays = label_components(bay_mask, 12 - a.setting.connectivity)
    sizes = length.(group_pixels(bays.labels, bays.count)[2:end])
    f["bays"], f["bay_area"] = count(size -> size >= parameters.bay_min, sizes) // 1, sum(sizes; init=0) // 1
    region.skeleton = thin(pixels)
    crossings = [crossing_number(region.skeleton, point) for point in region.skeleton]
    f["skeleton"], f["endpoints"], f["branches"] = length(region.skeleton) // 1, count(==(1), crossings) // 1, count(>=(3), crossings) // 1
end

function analyze_image(image, setting, parameters)
    histogram = Histogram(image)
    otsu_result = otsu(histogram)
    isodata_cutoff, isodata_iterations = isodata(histogram)
    cutoff = setting.threshold == "otsu" ? otsu_result.cutoff : setting.threshold == "isodata" ? isodata_cutoff : parse(Int, setting.threshold)
    binarize(t) = [setting.polarity == "bright" ? image.pixels[y, x] > t : image.pixels[y, x] <= t for y in 1:image.height, x in 1:image.width]
    initial = binarize(cutoff)
    final_mask = copy(initial)
    morph_counts = Int[]
    for operation in setting.operations
        if operation == "fill"
            final_mask = fill_holes(final_mask, 12 - setting.connectivity)
        else
            kind, name = split(operation, ':')
            offsets = parameters.elements[name]
            final_mask = kind == "erode" ? erode(final_mask, offsets) : kind == "dilate" ? dilate(final_mask, offsets) : kind == "open" ? opening(final_mask, offsets) : closing(final_mask, offsets)
        end
        push!(morph_counts, count(final_mask))
    end
    sweep = Tuple{Int,Int,Int}[]
    for t in parameters.sweep_step:parameters.sweep_step:image.maxval-1
        mask = binarize(t)
        push!(sweep, (t, count(mask), label_components(mask, setting.connectivity).count))
    end
    labeled = label_components(final_mask, setting.connectivity)
    labels, provisional = labeled.labels, labeled.provisional
    groups = group_pixels(labels, labeled.count)
    regions = [Region(; number, pixels=groups[number + 1]) for number in 1:labeled.count]
    four_components, eight_components = label_components(final_mask, 4).count, label_components(final_mask, 8).count
    bit_quad = bit_quad_euler(final_mask, setting.connectivity)
    holes, hole_of = Hole[], zeros(Int, image.height, image.width)
    for pixels in enclosed_components(final_mask, 12 - setting.connectivity)
        x, y = pixels[1]
        number, owner = length(holes) + 1, labels[y, x + 1]
        for (px, py) in pixels
            hole_of[py + 1, px + 1] = number
        end
        push!(holes, Hole(number, pixels, owner))
    end
    for region in regions
        x, y = region.pixels[1]
        if y >= 1 && hole_of[y, x + 1] > 0
            owner = holes[hole_of[y, x + 1]].owner
            region.parent = owner
            region.depth = regions[owner].depth + 1
            push!(regions[owner].children, region.number)
        end
    end
    result = (; image, setting, histogram, otsu_result, isodata_cutoff, isodata_iterations, cutoff, initial,
        final_mask, morph_counts, sweep, labels, provisional, regions, four_components, eight_components, bit_quad, holes, hole_of)
    for region in regions
        measure!(result, region, parameters)
    end
    result
end

function apply_rules!(a, rules)
    for region in a.regions
        region.dropped_by = findfirst(condition -> !condition_holds(condition, region), rules.filters)
        !isnothing(region.dropped_by) && continue
        region.kept = true
        first_class = findfirst(rule -> rule_matches(rule, region), rules.classes)
        !isnothing(first_class) && (region.class_name = rules.classes[first_class].name)
        region.flags = [rule.name for rule in rules.flags if rule_matches(rule, region)]
    end
    kept = kept_regions(a)
    for region in kept
        others = [(box_distance(region, other), other.number) for other in kept if other.number != region.number]
        if !isempty(others)
            region.distance, region.neighbor = minimum(others)
        end
    end
end

kept_regions(a) = [region for region in a.regions if region.kept]

function tree_text(a, number)
    region = a.regions[number]
    isempty(region.children) && return string(number)
    "$number(" * join([tree_text(a, child) for child in region.children], " ") * ")"
end

function threshold_lines(a, top)
    image, h = a.image, a.histogram
    lines = ["image $(image.name) size $(image.width) $(image.height) maxval $(image.maxval)",
        "histogram pixels $(h.pixels) min $(h.minimum) max $(h.maximum) mean $(mean_text(h.total, h.pixels)) median $(h.median) mode $(h.mode) levels $(h.levels)",
        "bins " * join(vcat(h.bin_width, h.bins), " "), "otsu threshold $(a.otsu_result.cutoff) upper $(a.otsu_result.upper) candidates $(length(a.otsu_result.candidates))"]
    for (rank, candidate) in enumerate(a.otsu_result.candidates[1:min(end, top)])
        c = candidate
        gap = (c.sum_above * c.below - c.sum_below * c.above) // (c.below * c.above)
        push!(lines, "rank $rank t $(c.cutoff) below $(c.below) above $(c.above) mean_below $(mean_text(c.sum_below, c.below)) mean_above $(mean_text(c.sum_above, c.above)) gap $(decimal_text(gap, 2))")
    end
    push!(lines, "isodata threshold $(a.isodata_cutoff) iterations $(a.isodata_iterations)",
        "threshold $(a.cutoff) $(method_name(a.setting)) $(a.setting.polarity) foreground $(count(a.initial))")
    for (operation, amount) in zip(a.setting.operations, a.morph_counts)
        push!(lines, "morph $operation foreground $amount")
    end
    for (cutoff, foreground, regions) in a.sweep
        push!(lines, "sweep $cutoff foreground $foreground regions $regions")
    end
    lines
end

function region_symbol(a, x, y, skeleton_only)
    label = a.labels[y + 1, x + 1]
    label == 0 && return a.hole_of[y + 1, x + 1] > 0 ? ':' : '.'
    region = a.regions[label]
    skeleton_only && !((x, y) in region.skeleton) && return '+'
    region.kept ? SYMBOLS[mod(label, length(SYMBOLS)) + 1] : '#'
end

function map_lines(a)
    size_text = "$(a.image.name) $(a.image.width) $(a.image.height)"
    lines = ["morphology $size_text"]
    for y in 1:a.image.height
        row = [a.initial[y, x] ? (a.final_mask[y, x] ? '#' : '-') : (a.final_mask[y, x] ? '+' : '.') for x in 1:a.image.width]
        push!(lines, join(row))
    end
    for (heading, skeleton_only) in [("labels", false), ("skeleton", true)]
        push!(lines, "$heading $size_text")
        for y in 0:a.image.height-1
            push!(lines, join([region_symbol(a, x, y, skeleton_only) for x in 0:a.image.width-1]))
        end
    end
    lines
end

function csv_row(a, region)
    f = region.features
    fields = [a.image.name, string(region.number), region.class_name, isempty(region.flags) ? "-" : join(region.flags, '+')]
    append!(fields, [string(integer(region, name)) for name in ["area", "x0", "y0", "x1", "y1"]])
    append!(fields, [decimal_text(f[name], digits) for (name, digits) in [("cx", 3), ("cy", 3), ("mean", 2), ("variance", 2)]])
    append!(fields, [string(integer(region, "min")), string(integer(region, "max")), decimal_text(f["contrast"], 2)])
    append!(fields, [string(integer(region, name)) for name in ["border", "perimeter", "chain", "straight", "diagonal", "turns"]])
    push!(fields, decimal_text(f["compactness"], 3))
    append!(fields, [string(integer(region, name)) for name in ["runs", "holes", "hole_area", "euler"]])
    push!(fields, isnothing(region.parent) ? "-" : string(region.parent), string(region.depth))
    append!(fields, [decimal_text(f[name], digits) for (name, digits) in [("var_x", 3), ("var_y", 3), ("cov_xy", 3), ("hu1", 4)]])
    push!(fields, region.orientation)
    append!(fields, [decimal_text(f[name], 3) for name in ["anisotropy", "extent", "mirror_lr", "mirror_tb"]])
    append!(fields, [hull_area_text(region.hull_doubled), decimal_text(f["solidity"], 3), string(integer(region, "feret2")),
        decimal_text(f["width2"], 3), decimal_text(f["elongation"], 3)])
    append!(fields, [string(integer(region, name)) for name in ["bays", "bay_area", "skeleton", "endpoints", "branches"]])
    push!(fields, isnothing(region.neighbor) ? "-" : string(region.neighbor), isnothing(region.neighbor) ? "-" : decimal_text(region.distance // 4, 2),
        isempty(region.codes) ? "-" : join(region.codes))
    join(fields, ',')
end

function intensity_text(a, foreground)
    values = [a.image.pixels[y, x] for y in 1:a.image.height for x in 1:a.image.width if a.final_mask[y, x] == foreground]
    mean_text(sum(values; init=0), length(values))
end

function area_line(a)
    kept = kept_regions(a)
    isempty(kept) && return "area total 0 mean - largest - smallest -"
    area = sum(integer(region, "area") for region in kept)
    largest = first(sort(kept; by=region -> (-integer(region, "area"), region.number)))
    smallest = first(sort(kept; by=region -> (integer(region, "area"), region.number)))
    "area total $area mean $(mean_text(area, length(kept))) largest $(largest.number) $(integer(largest, "area")) smallest $(smallest.number) $(integer(smallest, "area"))"
end

function summary_lines(a, rules)
    kept = kept_regions(a)
    region_count, hole_count = length(a.regions), length(a.holes)
    hole_pixels = sum((length(hole.pixels) for hole in a.holes); init=0)
    lines = ["image $(a.image.name)", "threshold $(a.cutoff) $(method_name(a.setting)) $(a.setting.polarity) conn $(a.setting.connectivity)",
        "foreground $(count(a.initial)) $(count(a.final_mask))", "regions $region_count provisional $(a.provisional) kept $(length(kept)) dropped $(region_count - length(kept))",
        "connectivity four $(a.four_components) eight $(a.eight_components)", "holes $hole_count hole_pixels $hole_pixels euler $(region_count - hole_count) bitquad $(a.bit_quad)"]
    for hole in a.holes
        x0, y0, x1, y1 = box_bounds(hole.pixels)
        push!(lines, "hole $(hole.number) owner $(hole.owner) area $(length(hole.pixels)) box $x0 $y0 $x1 $y1")
    end
    push!(lines, "depth_max $(maximum((region.depth for region in a.regions); init=0))")
    trees = [tree_text(a, region.number) for region in a.regions if isnothing(region.parent)]
    push!(lines, join(vcat(["tree"], trees), " "), "intensity foreground $(intensity_text(a, true)) background $(intensity_text(a, false))", area_line(a))
    classes = ["$name $(count(region -> region.class_name == name, kept))" for name in class_names(rules)]
    push!(lines, "classes " * join(classes, " "), orientation_line(kept))
    flags = ["$(rule.name) $(count(region -> rule.name in region.flags, kept))" for rule in rules.flags]
    push!(lines, join(vcat(["flags"], flags), " "))
    lines
end

function overall_lines(analyses, rules)
    regions = [region for a in analyses for region in a.regions]
    kept = [region for region in regions if region.kept]
    holes = sum(length(a.holes) for a in analyses)
    lines = ["overall", "images $(length(analyses))", "regions $(length(regions)) kept $(length(kept)) dropped $(length(regions) - length(kept))",
        "holes $holes euler $(length(regions) - holes)"]
    for (index, condition) in enumerate(rules.filters)
        dropped = count(region -> region.dropped_by == index, regions)
        push!(lines, "filter $index $(condition.feature) $(condition.comparison) $(condition.text) dropped $dropped")
    end
    for name in class_names(rules)
        members = [region for region in kept if region.class_name == name]
        area = sum((integer(region, "area") for region in members); init=0)
        push!(lines, "class $name count $(length(members)) area $area mean $(mean_text(area, length(members)))")
    end
    for rule in rules.flags
        push!(lines, "flag $(rule.name) count $(count(region -> rule.name in region.flags, kept))")
    end
    push!(lines, orientation_line(kept))
    largest = nothing
    for a in analyses, region in kept_regions(a)
        if isnothing(largest) || integer(region, "area") > integer(largest[2], "area")
            largest = (a.image.name, region)
        end
    end
    push!(lines, isnothing(largest) ? "largest -" : "largest $(largest[1]) $(largest[2].number) $(integer(largest[2], "area"))")
    lines
end

function main()
    parameters = read_parameters(joinpath("input", "params.txt"))
    rules = read_rules(joinpath("input", "rules.txt"))
    analyses = [analyze_image(image, parameters.settings[image.name], parameters) for image in read_images(joinpath("input", "images.txt"))]
    thresholds, maps, rows, summary = String[], String[], [CSV_HEADER], String[]
    for a in analyses
        apply_rules!(a, rules)
        append!(thresholds, threshold_lines(a, parameters.otsu_top))
        append!(maps, map_lines(a))
        append!(rows, [csv_row(a, region) for region in kept_regions(a)])
        append!(summary, summary_lines(a, rules))
    end
    append!(summary, overall_lines(analyses, rules))
    write_files("output", [("thresholds.txt", thresholds), ("labels.txt", maps), ("regions.csv", rows), ("summary.txt", summary)])
end

main()
