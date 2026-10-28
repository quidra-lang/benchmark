function symbol_lines(symbol)
    return [join(value == 1 ? '#' : '.' for value in symbol[y, :]) for y in axes(symbol, 1)]
end

function pbm_text(symbol, quiet, scale)
    side = size(symbol, 1)
    width = (side + 2 * quiet) * scale
    margin = repeat("0", quiet * scale)
    empty_row = repeat("0", width)
    lines = ["P1", "$width $width"]
    append!(lines, fill(empty_row, quiet * scale))
    for y in 1:side
        pixels = margin * join(repeat(string(value), scale) for value in symbol[y, :]) * margin
        append!(lines, fill(pixels, scale))
    end
    append!(lines, fill(empty_row, quiet * scale))
    return join(lines, "\n") * "\n"
end
