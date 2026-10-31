using Printf

const PATTERNS = Dict(
    "NEW" => "iiii", "OUTPUT" => "", "INVERT" => "", "BRIGHTNESS" => "i",
    "CONTRAST" => "ii", "THRESHOLD" => "i", "LEVELS" => "ii",
    "POSTERIZE" => "i", "MAXVAL" => "i", "FLIPH" => "", "FLIPV" => "",
    "ROTATE" => "i", "CROP" => "iiii", "PAD" => "ii", "SCALE" => "ii",
    "SHIFT" => "iii", "TILE" => "ii", "BLUR" => "", "GAUSS" => "",
    "SHARPEN" => "", "CONVOLVE" => "iiiiiiiiii", "SOBEL" => "",
    "MEDIAN" => "", "ERODE" => "", "DILATE" => "", "OPEN" => "",
    "CLOSE" => "", "GRADIENT" => "", "LINE" => "iiiii",
    "RECT" => "iiiii", "CIRCLE" => "iiii", "FLOOD" => "iii",
    "HISTOGRAM" => "", "EQUALIZE" => "", "LABEL" => "i",
    "DISTANCE" => "i", "STATS" => "", "REGION" => "iiii",
    "DITHER" => "", "ASCIIART" => "", "STORE" => "n",
    "RECALL" => "n", "DROP" => "n", "BLEND" => "nii",
    "DIFF" => "n", "PASTE" => "nii", "SLOTS" => "",
    "INFO" => "", "UNDO" => "", "REDO" => ""
)
const IMAGELESS = ("NEW", "RECALL", "DROP", "SLOTS", "INFO", "UNDO", "REDO")
const NEED_SLOT = ("RECALL", "DROP", "BLEND", "DIFF", "PASTE")
const SHADES = collect("@#*+=~-:,.")
const KERNELS = Dict(
    "BLUR" => ([1, 1, 1, 1, 1, 1, 1, 1, 1], 9),
    "GAUSS" => ([1, 2, 1, 2, 4, 2, 1, 2, 1], 16),
    "SHARPEN" => ([0, -1, 0, -1, 5, -1, 0, -1, 0], 1)
)
const NEIGHBORS4 = [(0, -1), (-1, 0), (1, 0), (0, 1)]
const NEIGHBORS8 = [(dx, dy) for dy in -1:1 for dx in -1:1
                    if dx != 0 || dy != 0]
const Point = Tuple{Int,Int}

struct CommandError <: Exception
    reason::String
end
check(condition, reason="bad value") = condition || throw(CommandError(reason))

struct GrayImage
    width::Int
    height::Int
    maxval::Int
    pixels::Vector{Int}
end

pixel(image::GrayImage, x::Int, y::Int) = image.pixels[y*image.width + x + 1]
contains(image::GrayImage, x::Int, y::Int) =
    0 <= x < image.width && 0 <= y < image.height
row(image::GrayImage, y::Int) =
    image.pixels[(y*image.width + 1):((y + 1)*image.width)]
with_pixels(image::GrayImage, pixels::Vector{Int}) =
    GrayImage(image.width, image.height, image.maxval, pixels)
limit(image::GrayImage, value::Int) = clamp(value, 0, image.maxval)

function neighborhood(image::GrayImage, x::Int, y::Int)
    [pixel(image, clamp(x + dx, 0, image.width - 1),
                 clamp(y + dy, 0, image.height - 1))
     for dy in -1:1 for dx in -1:1]
end

function summary(image::GrayImage)
    checksum = sum(i*p for (i, p) in enumerate(image.pixels))
    "$(image.width)x$(image.height) maxval $(image.maxval) checksum $checksum"
end

function read_pgm(lines::Vector{String})
    words = String[]
    for line in lines
        append!(words, split(strip(first(split(line, "#"; limit=2)))))
    end
    check(!isempty(words) && words[1] == "P2", "bad magic")
    function header(i, upper, message)
        check(i <= length(words), "truncated header")
        check(occursin(r"^[0-9]+$", words[i]), "bad number")
        number = parse(Int, words[i])
        check(1 <= number <= upper, message)
        number
    end
    width = header(2, 64, "bad size")
    height = header(3, 64, "bad size")
    maxval = header(4, 255, "bad maxval")
    values = words[5:end]
    pixels = Int[]
    needed = width * height
    for i in 0:(needed - 1)
        x, y = i % width, i ÷ width
        check(i + 1 <= length(values),
              "too few pixels ($(length(values)) of $needed)")
        word = values[i + 1]
        check(occursin(r"^[0-9]+$", word), "bad pixel at $x,$y")
        value = parse(Int, word)
        check(value <= maxval, "pixel out of range at $x,$y")
        push!(pixels, value)
    end
    check(length(values) == needed,
          "too many pixels ($(length(values)) of $needed)")
    GrayImage(width, height, maxval, pixels)
end

function transform(image::GrayImage, width::Int, height::Int, f)
    values = [f(x, y) for y in 0:(height - 1) for x in 0:(width - 1)]
    GrayImage(width, height, image.maxval, values)
end
transform(image::GrayImage, f) = transform(image, image.width, image.height, f)
transform(f, image::GrayImage) = transform(image, f)
transform(f, image::GrayImage, width::Int, height::Int) = transform(image, width, height, f)

function convolve(image::GrayImage, kernel::Vector{Int}, divisor::Int)
    transform(image) do x, y
        q = neighborhood(image, x, y)
        limit(image, fld(sum(k*v for (k, v) in zip(kernel, q)), divisor))
    end
end

function rank_filter(image::GrayImage, rank::Int)
    transform(image) do x, y
        sort(neighborhood(image, x, y))[rank + 1]
    end
end

function sobel(image::GrayImage)
    transform(image) do x, y
        q = neighborhood(image, x, y)
        gx = (q[3] + 2q[6] + q[9]) - (q[1] + 2q[4] + q[7])
        gy = (q[7] + 2q[8] + q[9]) - (q[1] + 2q[2] + q[3])
        limit(image, abs(gx) + abs(gy))
    end
end

function line_points(x::Int, y::Int, dest_x::Int, dest_y::Int)
    dx = abs(dest_x - x)
    dy = -abs(dest_y - y)
    sx = x < dest_x ? 1 : -1
    sy = y < dest_y ? 1 : -1
    error = dx + dy
    points = Point[]
    while true
        push!(points, (x, y))
        x == dest_x && y == dest_y && break
        twice = 2error
        if twice >= dy
            error += dy
            x += sx
        end
        if twice <= dx
            error += dx
            y += sy
        end
    end
    points
end

function rectangle_points(image::GrayImage, x::Int, y::Int, width::Int, height::Int, fill::Bool)
    right, bottom = x + width - 1, y + height - 1
    points = Point[]
    for j in max(0, y):min(bottom, image.height - 1)
        for i in max(0, x):min(right, image.width - 1)
            (fill || i == x || i == right || j == y || j == bottom) &&
                push!(points, (i, j))
        end
    end
    points
end

function circle_points(cx::Int, cy::Int, radius::Int)
    a, b, error = radius, 0, 1 - radius
    points = Point[]
    while a >= b
        append!(points, [
            (cx + a, cy + b), (cx + b, cy + a),
            (cx - b, cy + a), (cx - a, cy + b),
            (cx - a, cy - b), (cx - b, cy - a),
            (cx + b, cy - a), (cx + a, cy - b)
        ])
        b += 1
        if error < 0
            error += 2b + 1
        else
            a -= 1
            error += 2(b - a) + 1
        end
    end
    points
end

function filled_circle(image::GrayImage, points::Vector{Point})
    rows = Dict{Int,Tuple{Int,Int}}()
    for (x, y) in points
        if haskey(rows, y)
            lo, hi = rows[y]
            rows[y] = (min(lo, x), max(hi, x))
        else
            rows[y] = (x, x)
        end
    end
    result = Point[]
    for (y, (lo, hi)) in rows
        0 <= y < image.height || continue
        append!(result, [(x, y) for x in max(0, lo):min(hi, image.width - 1)])
    end
    result
end

function flood_points(image::GrayImage, x::Int, y::Int)
    target = pixel(image, x, y)
    stack = Point[(x, y)]
    visited = Set([y*image.width + x])
    points = Point[]
    while !isempty(stack)
        cx, cy = pop!(stack)
        push!(points, (cx, cy))
        for (dx, dy) in NEIGHBORS4
            nx, ny = cx + dx, cy + dy
            contains(image, nx, ny) && pixel(image, nx, ny) == target || continue
            index = ny*image.width + nx
            if !(index in visited)
                push!(visited, index)
                push!(stack, (nx, ny))
            end
        end
    end
    points
end

function equalize(image::GrayImage)
    counts = zeros(Int, image.maxval + 1)
    for p in image.pixels
        counts[p + 1] += 1
    end
    cdf = cumsum(counts)
    cmin = cdf[minimum(image.pixels) + 1]
    size = length(image.pixels)
    cmin == size && return with_pixels(image, copy(image.pixels))
    span = size - cmin
    with_pixels(image, [fld(2(cdf[p + 1] - cmin)*image.maxval + span, 2span)
                        for p in image.pixels])
end

function components(image::GrayImage, threshold::Int)
    visited = falses(length(image.pixels))
    groups = Vector{Point}[]
    for start in eachindex(image.pixels)
        (visited[start] || image.pixels[start] < threshold) && continue
        visited[start] = true
        stack = Point[((start - 1) % image.width, (start - 1) ÷ image.width)]
        group = Point[]
        while !isempty(stack)
            x, y = pop!(stack)
            push!(group, (x, y))
            for (dx, dy) in NEIGHBORS8
                nx, ny = x + dx, y + dy
                contains(image, nx, ny) || continue
                index = ny*image.width + nx + 1
                if !visited[index] && image.pixels[index] >= threshold
                    visited[index] = true
                    push!(stack, (nx, ny))
                end
            end
        end
        push!(groups, group)
    end
    groups
end

function component_text(image::GrayImage, threshold::Int, group::Vector{Point})
    xs = first.(group)
    ys = last.(group)
    perimeter = 0
    for (x, y) in group
        if any(!contains(image, x + dx, y + dy) ||
               pixel(image, x + dx, y + dy) < threshold
               for (dx, dy) in NEIGHBORS4)
            perimeter += 1
        end
    end
    area = length(group)
    "area $area perimeter $perimeter box $(minimum(xs)) $(minimum(ys)) " *
    "$(maximum(xs)) $(maximum(ys)) center $(sum(xs) ÷ area) $(sum(ys) ÷ area)"
end

function distance_map(image::GrayImage, threshold::Int)
    w, h = image.width, image.height
    any(p -> p < threshold, image.pixels) ||
        return with_pixels(image, fill(image.maxval, w*h))
    distances = [p < threshold ? 0 : w + h for p in image.pixels]
    for y in 0:(h - 1), x in 0:(w - 1)
        i = y*w + x + 1
        x > 0 && (distances[i] = min(distances[i], distances[i - 1] + 1))
        y > 0 && (distances[i] = min(distances[i], distances[i - w] + 1))
    end
    for y in (h - 1):-1:0, x in (w - 1):-1:0
        i = y*w + x + 1
        x < w - 1 && (distances[i] = min(distances[i], distances[i + 1] + 1))
        y < h - 1 && (distances[i] = min(distances[i], distances[i + w] + 1))
    end
    with_pixels(image, [min(n, image.maxval) for n in distances])
end

function statistics(pixels::Vector{Int}, maxval::Int)
    sorted = sort(pixels)
    counts = zeros(Int, maxval + 1)
    for pixel in pixels
        counts[pixel + 1] += 1
    end
    size = length(pixels)
    "min $(first(sorted)) max $(last(sorted)) mean $(sum(pixels) ÷ size) " *
        "median $(sorted[fld(size - 1, 2) + 1]) mode $(argmax(counts) - 1)"
end

function dither(image::GrayImage)
    errors = copy(image.pixels)
    pixels = zeros(Int, length(errors))
    diffusion = ((1, 0, 7), (-1, 1, 3), (0, 1, 5), (1, 1, 1))
    for y in 0:(image.height - 1), x in 0:(image.width - 1)
        index = y*image.width + x + 1
        old = errors[index]
        new_pixel = 2old >= image.maxval ? image.maxval : 0
        pixels[index] = new_pixel
        error = old - new_pixel
        for (dx, dy, weight) in diffusion
            nx, ny = x + dx, y + dy
            if contains(image, nx, ny)
                errors[ny*image.width + nx + 1] += fld(error*weight, 16)
            end
        end
    end
    with_pixels(image, pixels)
end

mutable struct ImageEditor
    current::Union{Nothing,GrayImage}
    undo::Vector{GrayImage}
    redo::Vector{GrayImage}
    slots::Dict{String,GrayImage}
    output::Vector{String}
end
ImageEditor() = ImageEditor(nothing, GrayImage[], GrayImage[],
                            Dict{String,GrayImage}(), String[])
emit!(editor::ImageEditor, line::String) = push!(editor.output, line)

function parse_command(words::Vector{String})
    name = words[1]
    check(haskey(PATTERNS, name), "unknown command $name")
    pattern = PATTERNS[name]
    args = words[2:end]
    fill = name in ("RECT", "CIRCLE") && length(args) == length(pattern) + 1 &&
           last(args) == "FILL"
    fill && pop!(args)
    check(length(args) == length(pattern), "bad arguments")
    numbers = Int[]
    slot = ""
    for (kind, word) in zip(pattern, args)
        if kind == 'i'
            check(occursin(r"^(?:0|-?[1-9][0-9]{0,6})$", word), "bad arguments")
            push!(numbers, parse(Int, word))
        else
            check(occursin(r"^[a-z]{1,8}$", word), "bad arguments")
            slot = word
        end
    end
    (name, numbers, slot, fill)
end

function replace!(editor::ImageEditor, image::GrayImage, label::String)
    editor.current = image
    empty!(editor.undo)
    empty!(editor.redo)
    emit!(editor, "$label $(summary(image))")
end

function commit!(editor::ImageEditor, image::GrayImage; painted=nothing)
    push!(editor.undo, editor.current)
    empty!(editor.redo)
    editor.current = image
    suffix = isnothing(painted) ? "" : " painted $painted"
    emit!(editor, "ok $(summary(image))$suffix")
end

function paint!(editor::ImageEditor, points::Vector{Point}, value::Int)
    image = editor.current
    positions = Set{Int}()
    for (x, y) in points
        contains(image, x, y) && push!(positions, y*image.width + x + 1)
    end
    pixels = copy(image.pixels)
    for index in positions
        pixels[index] = value
    end
    commit!(editor, with_pixels(image, pixels); painted=length(positions))
end

function crop_area(image::GrayImage, args::Vector{Int})
    x, y, w, h = args
    check(x >= 0 && y >= 0 && w >= 1 && h >= 1)
    check(x + w <= image.width && y + h <= image.height)
    x, y, w, h
end

function matching_slot(editor::ImageEditor, name::String)
    image = editor.current
    other = editor.slots[name]
    check(other.width == image.width && other.height == image.height,
          "size mismatch")
    check(other.maxval == image.maxval, "maxval mismatch")
    other
end

function run!(editor::ImageEditor, name::String, a::Vector{Int}, slot::String, fill_shape::Bool)
    image = editor.current
    w = isnothing(image) ? 0 : image.width
    h = isnothing(image) ? 0 : image.height
    m = isnothing(image) ? 0 : image.maxval
    if name == "NEW"
        width, height, maxval, value = a
        check(1 <= width <= 64 && 1 <= height <= 64)
        check(1 <= maxval <= 255 && 0 <= value <= maxval)
        replace!(editor, GrayImage(width, height, maxval,
                                   fill(value, width*height)), "created")
    elseif name == "OUTPUT"
        emit!(editor, "P2")
        emit!(editor, "$w $h")
        emit!(editor, string(m))
        for y in 0:(h - 1)
            emit!(editor, join(row(image, y), " "))
        end
    elseif name == "INVERT"
        commit!(editor, with_pixels(image, [m - p for p in image.pixels]))
    elseif name == "BRIGHTNESS"
        check(-255 <= a[1] <= 255)
        commit!(editor, with_pixels(image, [limit(image, p + a[1])
                                           for p in image.pixels]))
    elseif name == "CONTRAST"
        num, den = a
        check(0 <= num <= 100 && 1 <= den <= 100)
        center = (m + 1) ÷ 2
        commit!(editor, with_pixels(image, [
            limit(image, center + fld((p - center)*num, den)) for p in image.pixels
        ]))
    elseif name == "THRESHOLD"
        check(0 <= a[1] <= m)
        commit!(editor, with_pixels(image, [p >= a[1] ? m : 0
                                           for p in image.pixels]))
    elseif name == "LEVELS"
        lo, hi = a
        check(0 <= lo < hi <= m)
        commit!(editor, with_pixels(image, [
            limit(image, fld((p - lo)*m, hi - lo)) for p in image.pixels
        ]))
    elseif name == "POSTERIZE"
        levels = a[1]
        check(2 <= levels <= m + 1)
        commit!(editor, with_pixels(image, [
            fld(fld(p*levels, m + 1)*m, levels - 1) for p in image.pixels
        ]))
    elseif name == "MAXVAL"
        new_max = a[1]
        check(1 <= new_max <= 255)
        values = [fld(2p*new_max + m, 2m) for p in image.pixels]
        commit!(editor, GrayImage(w, h, new_max, values))
    elseif name == "FLIPH"
        commit!(editor, transform(image, (x, y) -> pixel(image, w - 1 - x, y)))
    elseif name == "FLIPV"
        commit!(editor, transform(image, (x, y) -> pixel(image, x, h - 1 - y)))
    elseif name == "ROTATE"
        angle = a[1]
        check(angle in (90, 180, 270))
        if angle == 90
            result = transform(image, h, w, (x, y) -> pixel(image, y, h - 1 - x))
        elseif angle == 180
            result = transform(image, (x, y) -> pixel(image, w - 1 - x, h - 1 - y))
        else
            result = transform(image, h, w, (x, y) -> pixel(image, w - 1 - y, x))
        end
        commit!(editor, result)
    elseif name == "CROP"
        x, y, width, height = crop_area(image, a)
        commit!(editor, transform(image, width, height,
                                  (i, j) -> pixel(image, x + i, y + j)))
    elseif name == "PAD"
        n, value = a
        check(n >= 1 && 0 <= value <= m)
        check(w + 2n <= 64 && h + 2n <= 64, "too large")
        commit!(editor, transform(image, w + 2n, h + 2n) do x, y
            contains(image, x - n, y - n) ? pixel(image, x - n, y - n) : value
        end)
    elseif name == "SCALE"
        num, den = a
        check(1 <= num <= 16 && 1 <= den <= 16)
        width, height = fld(w*num, den), fld(h*num, den)
        check(width >= 1 && height >= 1, "too small")
        check(width <= 64 && height <= 64, "too large")
        commit!(editor, transform(image, width, height, (x, y) ->
            pixel(image, fld((2x + 1)*den, 2num), fld((2y + 1)*den, 2num))))
    elseif name == "SHIFT"
        dx, dy, value = a
        check(-1000 <= dx <= 1000 && -1000 <= dy <= 1000 && 0 <= value <= m)
        commit!(editor, transform(image, (x, y) ->
            contains(image, x - dx, y - dy) ? pixel(image, x - dx, y - dy) : value))
    elseif name == "TILE"
        nx, ny = a
        check(nx >= 1 && ny >= 1)
        check(w*nx <= 64 && h*ny <= 64, "too large")
        commit!(editor, transform(image, w*nx, h*ny,
                                  (x, y) -> pixel(image, x % w, y % h)))
    elseif haskey(KERNELS, name)
        kernel, divisor = KERNELS[name]
        commit!(editor, convolve(image, kernel, divisor))
    elseif name == "CONVOLVE"
        check(all(n -> -16 <= n <= 16, a[1:9]) && 1 <= a[10] <= 256)
        commit!(editor, convolve(image, a[1:9], a[10]))
    elseif name == "SOBEL"
        commit!(editor, sobel(image))
    elseif name == "MEDIAN"
        commit!(editor, rank_filter(image, 4))
    elseif name == "ERODE"
        commit!(editor, rank_filter(image, 0))
    elseif name == "DILATE"
        commit!(editor, rank_filter(image, 8))
    elseif name == "OPEN"
        commit!(editor, rank_filter(rank_filter(image, 0), 8))
    elseif name == "CLOSE"
        commit!(editor, rank_filter(rank_filter(image, 8), 0))
    elseif name == "GRADIENT"
        low = rank_filter(image, 0).pixels
        high = rank_filter(image, 8).pixels
        commit!(editor, with_pixels(image, high .- low))
    elseif name == "LINE"
        x0, y0, x1, y1, value = a
        check(all(n -> -1000 <= n <= 1000, a[1:4]) && 0 <= value <= m)
        paint!(editor, line_points(x0, y0, x1, y1), value)
    elseif name == "RECT"
        x, y, width, height, value = a
        check(-1000 <= x <= 1000 && -1000 <= y <= 1000)
        check(1 <= width <= 1000 && 1 <= height <= 1000 && 0 <= value <= m)
        paint!(editor, rectangle_points(image, x, y, width, height, fill_shape), value)
    elseif name == "CIRCLE"
        cx, cy, radius, value = a
        check(-1000 <= cx <= 1000 && -1000 <= cy <= 1000)
        check(0 <= radius <= 1000 && 0 <= value <= m)
        outline = circle_points(cx, cy, radius)
        paint!(editor, fill_shape ? filled_circle(image, outline) : outline, value)
    elseif name == "FLOOD"
        x, y, value = a
        check(contains(image, x, y) && 0 <= value <= m)
        paint!(editor, flood_points(image, x, y), value)
    elseif name == "HISTOGRAM"
        lows = Union{Nothing,Int}[nothing for _ in 1:16]
        highs = zeros(Int, 16)
        counts = zeros(Int, 16)
        for value in 0:m
            index = fld(value*16, m + 1) + 1
            isnothing(lows[index]) && (lows[index] = value)
            highs[index] = value
        end
        for p in image.pixels
            counts[fld(p*16, m + 1) + 1] += 1
        end
        top = maximum(counts)
        for i in 1:16
            isnothing(lows[i]) && continue
            emit!(editor, @sprintf("%3d-%3d %4d |%s", lows[i], highs[i], counts[i],
                                   repeat("#", fld(counts[i]*32, top))))
        end
    elseif name == "EQUALIZE"
        commit!(editor, equalize(image))
    elseif name == "LABEL"
        check(0 <= a[1] <= m)
        groups = components(image, a[1])
        emit!(editor, "labels $(length(groups))")
        for (index, group) in enumerate(groups)
            emit!(editor, "label $index $(component_text(image, a[1], group))")
        end
    elseif name == "DISTANCE"
        check(0 <= a[1] <= m)
        commit!(editor, distance_map(image, a[1]))
    elseif name == "STATS"
        emit!(editor, statistics(image.pixels, m))
    elseif name == "REGION"
        x, y, width, height = crop_area(image, a)
        region = transform(image, width, height, (i, j) -> pixel(image, x + i, y + j))
        emit!(editor, statistics(region.pixels, m))
    elseif name == "DITHER"
        commit!(editor, dither(image))
    elseif name == "ASCIIART"
        for y in 0:(h - 1)
            emit!(editor, join([SHADES[fld(p*10, m + 1) + 1] for p in row(image, y)]))
        end
    elseif name == "STORE"
        editor.slots[slot] = image
        emit!(editor, "stored $slot $(summary(image))")
    elseif name == "RECALL"
        replace!(editor, editor.slots[slot], "recalled $slot")
    elseif name == "DROP"
        delete!(editor.slots, slot)
        emit!(editor, "dropped $slot")
    elseif name == "BLEND"
        num, den = a
        check(0 <= num <= den && 1 <= den <= 100)
        other = matching_slot(editor, slot)
        pixels = [fld(p*(den - num) + q*num, den)
                  for (p, q) in zip(image.pixels, other.pixels)]
        commit!(editor, with_pixels(image, pixels))
    elseif name == "DIFF"
        other = matching_slot(editor, slot)
        commit!(editor, with_pixels(image, abs.(image.pixels .- other.pixels)))
    elseif name == "PASTE"
        x, y = a
        check(-1000 <= x <= 1000 && -1000 <= y <= 1000)
        other = editor.slots[slot]
        check(other.maxval == m, "maxval mismatch")
        pixels = copy(image.pixels)
        painted = 0
        for j in 0:(other.height - 1), i in 0:(other.width - 1)
            if contains(image, x + i, y + j)
                pixels[(y + j)*w + x + i + 1] = pixel(other, i, j)
                painted += 1
            end
        end
        commit!(editor, with_pixels(image, pixels); painted=painted)
    elseif name == "SLOTS"
        isempty(editor.slots) && emit!(editor, "no slots")
        for key in sort(collect(keys(editor.slots)))
            emit!(editor, "$key $(summary(editor.slots[key]))")
        end
    elseif name == "INFO"
        description = isnothing(image) ? "none" : summary(image)
        emit!(editor, "image $description undo $(length(editor.undo)) " *
                      "redo $(length(editor.redo)) slots $(length(editor.slots))")
    elseif name == "UNDO"
        check(!isempty(editor.undo), "nothing to undo")
        push!(editor.redo, image)
        editor.current = pop!(editor.undo)
        emit!(editor, "undo $(summary(editor.current))")
    elseif name == "REDO"
        check(!isempty(editor.redo), "nothing to redo")
        push!(editor.undo, image)
        editor.current = pop!(editor.redo)
        emit!(editor, "redo $(summary(editor.current))")
    end
end

function execute!(editor::ImageEditor, words::Vector{String})
    try
        name, a, slot, fill_shape = parse_command(words)
        name in IMAGELESS || check(!isnothing(editor.current), "no image")
        name in NEED_SLOT && check(haskey(editor.slots, slot), "no slot $slot")
        run!(editor, name, a, slot, fill_shape)
    catch e
        e isa CommandError || rethrow()
        emit!(editor, "error: $(e.reason)")
    end
end

function load!(editor::ImageEditor, lines::Vector{String})
    try
        replace!(editor, read_pgm(lines), "loaded")
    catch e
        e isa CommandError || rethrow()
        emit!(editor, "error: load: $(e.reason)")
    end
end

function main()
    lines = readlines(stdin)
    count = parse(Int, lines[1])
    index = 2
    editor = ImageEditor()
    for _ in 1:count
        words = String.(split(lines[index], ' '))
        index += 1
        if words[1] == "LOAD"
            amount = parse(Int, words[2])
            load!(editor, lines[index:(index + amount - 1)])
            index += amount
        else
            execute!(editor, words)
        end
    end
    for line in editor.output
        println(line)
    end
end

main()
