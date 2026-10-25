module RasterCanvas
export Point, Rect, Color, RGB, Layer, round_ratio, effective_alpha, paint!, erase!, color_at, alpha_at, composite
const Point = NTuple{2,Int}
const Rect = NTuple{4,Int}
const Color = NTuple{4,Int}
const RGB = NTuple{3,Int}
function round_ratio(n, d)
    d < 0 && ((n, d) = (-n, -d))
    fld(2n+d, 2d)
end
effective_alpha(alpha, opacity) = round_ratio(alpha*opacity, 255)
struct Layer
    width::Int
    height::Int
    opacity::Int
    mode::String
    colors::Matrix{Union{Nothing,Color}}
    lines::Matrix{Int}
end
Layer(w, h, opacity, mode) = Layer(w, h, opacity, mode, fill!(Matrix{Union{Nothing,Color}}(undef, h, w), nothing), zeros(Int, h, w))
function paint!(layer, x, y, color, line)
    layer.colors[y+1, x+1] = color
    layer.lines[y+1, x+1] = line
end
function erase!(layer, x, y)
    painted = layer.colors[y+1, x+1] !== nothing
    layer.colors[y+1, x+1] = nothing
    painted
end
color_at(layer, x, y) = layer.colors[y+1, x+1]
function alpha_at(layer, x, y)
    color = color_at(layer, x, y)
    color === nothing ? 0 : effective_alpha(color[4], layer.opacity)
end
function blend_component(mode, source, value)
    mode == "multiply" && return round_ratio(source*value, 255)
    mode == "screen" && return 255-round_ratio((255-source)*(255-value), 255)
    source
end
function composite(layers, background, width, height)
    image = Matrix{RGB}(undef, height, width)
    for y in 0:height-1, x in 0:width-1
        current = background[1:3]
        for layer in layers
            color = color_at(layer, x, y)
            color === nothing && continue
            alpha = effective_alpha(color[4], layer.opacity)
            current = ntuple(c -> round_ratio(alpha*blend_component(layer.mode, color[c], current[c])+(255-alpha)*current[c], 255), 3)
        end
        image[y+1, x+1] = current
    end
    image
end
end
