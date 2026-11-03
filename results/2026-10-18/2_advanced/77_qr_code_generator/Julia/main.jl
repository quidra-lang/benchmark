include("bitstream.jl")
include("reed_solomon.jl")
include("matrix.jl")
include("masking.jl")
include("render.jl")

const QR_LEVELS = ("L", "M", "Q", "H")
const QR_MODES = ("NUMERIC", "ALPHANUMERIC", "BYTE")
const QR_INDICATORS = Dict("NUMERIC" => 1, "ALPHANUMERIC" => 2, "BYTE" => 4)
const QR_ERROR_KINDS = ("level", "mode", "version", "mask", "text", "charset", "capacity")

function count_width(mode, version)
    widths = version == 10 ? (12, 11, 16) : (10, 9, 8)
    return widths[findfirst(==(mode), QR_MODES)]
end

function data_width(mode, count)
    mode == "NUMERIC" && return 10 * (count ÷ 3) + (0, 4, 7)[count % 3 + 1]
    mode == "ALPHANUMERIC" && return 11 * (count ÷ 2) + 6 * (count % 2)
    return 8 * count
end

function encodable(mode, character)
    mode == "NUMERIC" && return '0' <= character <= '9'
    mode == "ALPHANUMERIC" && return haskey(QR_ALPHA_VALUES, character)
    return 32 <= Int(character) <= 126
end

segment_width(mode, text, version) = 4 + count_width(mode, version) + data_width(mode, length(text))

function mixed_segments(text, version)
    invalid = Dict(mode => zeros(Int, length(text) + 1) for mode in QR_MODES)
    for (index, character) in enumerate(text), mode in QR_MODES
        invalid[mode][index + 1] = invalid[mode][index] + Int(!encodable(mode, character))
    end
    costs = zeros(Int, length(text) + 1)
    choices = Vector{Tuple{Int,String}}(undef, length(text))
    for stop in 1:length(text)
        best = typemax(Int)
        for start in 0:stop - 1, mode in QR_MODES
            invalid[mode][stop + 1] != invalid[mode][start + 1] && continue
            cost = costs[start + 1] + 4 + count_width(mode, version) + data_width(mode, stop - start)
            if cost < best
                best = cost
                choices[stop] = (start, mode)
            end
        end
        costs[stop + 1] = best
    end
    segments = Tuple{String,String}[]
    stop = length(text)
    while stop > 0
        start, mode = choices[stop]
        push!(segments, (mode, text[start + 1:stop]))
        stop = start
    end
    return reverse(segments), costs[end]
end

function assemble_bits(segments, version)
    writer = QRBitWriter(String[])
    lines = String[]
    for (mode, text) in segments
        indicator = QR_INDICATORS[mode]
        width = count_width(mode, version)
        write_bits!(writer, indicator, 4)
        write_bits!(writer, length(text), width)
        push!(
            lines,
            "segment $mode indicator $(binary_digits(indicator, 4)) count $(length(text)) $(binary_digits(length(text), width))"
        )
        step = mode == "NUMERIC" ? 3 : mode == "ALPHANUMERIC" ? 2 : 1
        for start in 1:step:length(text)
            characters = text[start:min(length(text), start + step - 1)]
            if mode == "NUMERIC"
                value = parse(Int, characters)
                group_width = (0, 4, 7, 10)[length(characters) + 1]
            elseif mode == "ALPHANUMERIC"
                value = QR_ALPHA_VALUES[characters[1]]
                group_width = 6
                if length(characters) == 2
                    value = 45 * value + QR_ALPHA_VALUES[characters[2]]
                    group_width = 11
                end
            else
                value, group_width = Int(characters[1]), 8
            end
            digits = binary_digits(value, group_width)
            write_bits!(writer, value, group_width)
            push!(lines, "group $value $digits \"$characters\"")
        end
    end
    return bit_value(writer), lines
end

function pad_bits(bits, capacity)
    terminator = min(4, capacity - length(bits))
    padded = bits * repeat("0", terminator)
    zero_fill = mod(-length(padded), 8)
    padded *= repeat("0", zero_fill)
    pad_count = (capacity - length(padded)) ÷ 8
    padded *= join(iseven(index) ? "11101100" : "00010001" for index in 0:pad_count - 1)
    return padded, (terminator, zero_fill, pad_count)
end

function block_layout(degree, first_count, first_size, second_count, second_size)
    lengths = vcat(fill(first_size, first_count), fill(second_size, second_count))
    placement = Tuple{Int,Int}[]
    for index in 1:maximum(lengths), block in eachindex(lengths)
        index <= lengths[block] && push!(placement, (block, index))
    end
    for offset in 1:degree, block in eachindex(lengths)
        push!(placement, (block, lengths[block] + offset))
    end
    data = sum(lengths)
    return (
        ; degree,
        lengths,
        placement,
        count=length(lengths),
        data,
        capacity=8 * data,
        total=data + degree * length(lengths)
    )
end

function encode_blocks(data, layout)
    blocks = Vector{Int}[]
    start = 1
    for count in layout.lengths
        words = data[start:start + count - 1]
        push!(blocks, vcat(words, rs_parity(words, layout.degree)))
        start += count
    end
    interleaved = [blocks[block][index] for (block, index) in layout.placement]
    return blocks, interleaved
end

function deinterleave(words, layout)
    blocks = [zeros(Int, count + layout.degree) for count in layout.lengths]
    for (value, (block, index)) in zip(words, layout.placement)
        blocks[block][index] = value
    end
    return blocks
end

mutable struct QRRequest
    identifier::String
    level_token::String
    mode_token::String
    version_token::String
    mask_token::String
    text::String
    splits::Dict{Int,Any}
    mode::String
    version::Int
    level::String
    segments::Vector{Tuple{String,String}}
    bit_count::Int
    boosted::Bool
end

function split_request(request, version)
    category = version == 10 ? 10 : 1
    return get!(request.splits, category) do
        request.mode == "MIXED" ? mixed_segments(request.text, version) : (
            [(request.mode, request.text)],
            segment_width(request.mode, request.text, version)
        )
    end
end

mutable struct QRCodec
    tables::Dict{Tuple{Int,String},Any}
    alignments::Dict{Int,Vector{Int}}
    geometries::Dict{Int,Any}
    formats::Vector{Tuple{Int,String,Int}}
    versions::Vector{Tuple{Int,Int}}
end

function new_codec(tables, alignments)
    formats = [(format_information(level, mask), level, mask) for level in QR_LEVELS for mask in 0:7]
    versions = [(version_information(version), version) for version in 7:40]
    return QRCodec(tables, alignments, Dict{Int,Any}(), formats, versions)
end

function geometry(codec, version)
    return get!(codec.geometries, version) do
        symbol, areas = function_matrix(version, codec.alignments[version])
        order = reading_order(areas)
        indices = Dict(position => index - 1 for (index, position) in enumerate(order))
        side = size(symbol, 1)
        (
            ; symbol,
            areas,
            order,
            indices,
            side,
            data_modules=length(order),
            function_modules=side * side - length(order)
        )
    end
end

function prepare_request!(request, codec)
    request.level_token in (
        QR_LEVELS...,
        (level * "+" for level in QR_LEVELS)...
    ) || return "level $(request.level_token)"
    request.mode_token in (QR_MODES..., "AUTO", "MIXED") || return "mode $(request.mode_token)"
    request.version_token in ("AUTO", string.(1:10)...) || return "version $(request.version_token)"
    request.mask_token in ("AUTO", string.(0:7)...) || return "mask $(request.mask_token)"
    isempty(request.text) && return "text"
    if request.mode_token in ("NUMERIC", "ALPHANUMERIC")
        for (index, character) in enumerate(request.text)
            !encodable(request.mode_token, character) && return "charset position $(index - 1)"
        end
    end
    request.mode = request.mode_token
    if request.mode == "AUTO"
        request.mode = first(mode for mode in QR_MODES if all(
            character -> encodable(mode, character),
            request.text
        ))
    end
    base_level = request.level_token[1:1]
    candidates = request.version_token == "AUTO" ? collect(1:10) : [parse(Int, request.version_token)]
    bits, capacity = 0, 0
    for version in candidates
        bits = split_request(request, version)[2]
        capacity = codec.tables[(version, base_level)].capacity
        if bits <= capacity
            request.version = version
            break
        end
    end
    request.version == 0 && return "capacity bits $bits capacity $capacity"
    request.segments, request.bit_count = split_request(request, request.version)
    request.level = base_level
    if endswith(request.level_token, "+")
        for level in QR_LEVELS[findfirst(==(base_level), QR_LEVELS):end]
            request.bit_count <= codec.tables[(request.version, level)].capacity && (request.level = level)
        end
    end
    request.boosted = request.level != base_level
    return nothing
end

function read_inputs()
    requests = QRRequest[]
    for line in readlines("input/requests.txt")
        header, text = split(line, ':'; limit=2, keepempty=true)
        fields = String.(split(header, ' '))
        push!(
            requests,
            QRRequest(fields..., String(text), Dict{Int,Any}(), "", 0, "", Tuple{String,String}[], 0, false)
        )
    end
    params = Dict{String,Int}()
    for line in readlines("input/params.txt")
        name, value = split(line, ' ')
        params[String(name)] = parse(Int, value)
    end
    tables = Dict{Tuple{Int,String},Any}()
    alignments = Dict{Int,Vector{Int}}()
    for line in readlines("input/tables.txt")
        fields = split(line, ' ')
        version = parse(Int, fields[2])
        if fields[1] == "block"
            tables[(version, String(fields[3]))] = block_layout(parse.(Int, fields[4:end])...)
        else
            alignments[version] = parse.(Int, fields[3:end])
        end
    end
    damage = Dict{String,Vector{Any}}()
    for line in readlines("input/damage.txt")
        fields = split(line, ' ')
        identifier, operation = String(fields[1]), String(fields[2])
        arguments = operation == "fill" ? vcat(
            parse.(Int, fields[3:6]),
            Int(fields[7] == "dark")
        ) : operation == "flip" ? parse.(Int, fields[3:end]) : Int[]
        push!(get!(damage, identifier, Any[]), (operation, arguments))
    end
    lines = readlines("input/scans.txt")
    scans = Tuple{String,Matrix{Int}}[]
    index = 1
    while index <= length(lines)
        name = String(split(lines[index], ' ')[2])
        side = length(lines[index + 1])
        symbol = [Int(lines[index + y][x] == '#') for y in 1:side, x in 1:side]
        push!(scans, (name, symbol))
        index += side + 1
    end
    return requests, params, tables, alignments, damage, scans
end

function encode_request(request, codec)
    layout = geometry(codec, request.version)
    blockspec = codec.tables[(request.version, request.level)]
    raw_bits, trace = assemble_bits(request.segments, request.version)
    padded_bits, padding = pad_bits(raw_bits, blockspec.capacity)
    blocks, codewords = encode_blocks(bits_codewords(padded_bits), blockspec)
    unmasked = copy(layout.symbol)
    for (bit, (x, y)) in zip(codeword_bits(codewords), layout.order)
        unmasked[y + 1, x + 1] = Int(bit == '1')
    end
    candidates, penalties = Matrix{Int}[], NTuple{4,Int}[]
    for mask in 0:7
        symbol = apply_mask(unmasked, layout.order, mask)
        for positions in format_positions(layout.side)
            write_matrix_value!(symbol, positions, format_information(request.level, mask))
        end
        push!(candidates, symbol)
        push!(penalties, mask_penalties(symbol))
    end
    mask = request.mask_token == "AUTO" ? argmin(sum.(penalties)) - 1 : parse(Int, request.mask_token)
    symbol = candidates[mask + 1]
    return (
        ; request,
        layout,
        blockspec,
        raw_bits,
        trace,
        padded_bits,
        padding,
        blocks,
        codewords,
        penalties,
        mask,
        symbol,
        dark=sum(symbol)
    )
end

function codes_lines(encoding, codec)
    request, layout, blocks = encoding.request, encoding.layout, encoding.blockspec
    version, level = request.version, request.level
    lines = ["symbol version $version level $level mask $(encoding.mask) size $(layout.side)"]
    segments = join(("$mode:$(length(text))" for (mode, text) in request.segments), " ")
    push!(lines, "segments $(length(request.segments)) $segments")
    alternatives = String[]
    for mode in QR_MODES
        possible = all(character -> encodable(mode, character), request.text)
        value = possible ? string(segment_width(mode, request.text, version)) : "-"
        push!(alternatives, "$mode $value")
    end
    mixed_bits = request.mode == "MIXED" ? request.bit_count : mixed_segments(request.text, version)[2]
    push!(alternatives, "MIXED $mixed_bits")
    push!(
        lines,
        "bits data $(request.bit_count) capacity $(blocks.capacity) alternatives " * join(alternatives, " ")
    )
    fits = String[]
    for candidate_level in QR_LEVELS
        fitting = "-"
        for candidate in 1:10
            if split_request(request, candidate)[2] <= codec.tables[(candidate, candidate_level)].capacity
                fitting = string(candidate)
                break
            end
        end
        push!(fits, "$candidate_level $fitting")
    end
    push!(lines, "fits " * join(fits, " "))
    remainder = layout.data_modules - 8 * blocks.total
    push!(
        lines,
        "modules function $(layout.function_modules) data $(layout.data_modules) remainder $remainder dark $(encoding.dark)"
    )
    information = binary_digits(format_information(level, encoding.mask), 15)
    version_text = version >= 7 ? binary_digits(version_information(version), 18) : "none"
    push!(lines, "format $information version $version_text")
    for (index, penalty) in enumerate(encoding.penalties)
        n1, n2, n3, n4 = penalty
        push!(lines, "penalty $(index - 1) n1 $n1 n2 $n2 n3 $n3 n4 $n4 total $(sum(penalty))")
    end
    append!(lines, symbol_lines(encoding.symbol))
    return lines
end

function codeword_lines(encoding)
    request, layout = encoding.request, encoding.blockspec
    lines = ["request $(request.identifier) version $(request.version) level $(request.level) blocks $(layout.count) data $(layout.data) ec_per_block $(layout.degree) total $(layout.total)"]
    for (index, words) in enumerate(encoding.blocks)
        count = layout.lengths[index]
        push!(lines, "block $(index - 1) data $(hex_words(words[1:count]))")
        push!(lines, "block $(index - 1) ec $(hex_words(words[count + 1:end]))")
    end
    push!(lines, "interleaved " * hex_words(encoding.codewords))
    return lines
end

function bitstream_lines(encoding)
    request = encoding.request
    lines = ["request $(request.identifier) version $(request.version) bits $(request.bit_count) capacity $(encoding.blockspec.capacity)"]
    append!(lines, encoding.trace)
    terminator, zero_fill, pad_count = encoding.padding
    push!(lines, "terminator $terminator zero_fill $zero_fill pad_bytes $pad_count")
    return lines
end

function read_image(path)
    lines = readlines(path)
    width, height = parse.(Int, split(lines[2], ' '))
    pixels = [Int(lines[y + 2][x] == '1') for y in 1:height, x in 1:width]
    dark = findall(==(1), pixels)
    left = minimum(index[2] for index in dark) - 1
    right = maximum(index[2] for index in dark) - 1
    top = minimum(index[1] for index in dark) - 1
    run = 0
    while left + run < width && pixels[top + 1, left + run + 1] == 1
        run += 1
    end
    unit = run ÷ 7
    side = (right - left + 1) ÷ unit
    symbol = [pixels[top + unit * y + 1, left + unit * x + 1] for y in 0:side - 1, x in 0:side - 1]
    well_formed = true
    for y in 0:height - 1, x in 0:width - 1
        expected = 0
        if left <= x < left + unit * side && top <= y < top + unit * side
            expected = symbol[(y - top) ÷ unit + 1, (x - left) ÷ unit + 1]
        end
        pixels[y + 1, x + 1] != expected && (well_formed = false)
    end
    status = well_formed ? "ok" : "bad"
    return symbol, "image $width $height quiet $(left ÷ unit) scale $unit size $side $status"
end

function rotate_symbol(symbol)
    side = size(symbol, 1)
    return [symbol[side - x + 1, y] for y in 1:side, x in 1:side]
end

function finder_rotation(symbol)
    side = size(symbol, 1)
    corners = ((side - 7, side - 7), (side - 7, 0), (0, 0), (0, side - 7))
    scores = Int[]
    for (left, top) in corners
        score = 0
        for y in 0:6, x in 0:6
            expected = Int(max(abs(x - 3), abs(y - 3)) != 2)
            score += Int(symbol[top + y + 1, left + x + 1] == expected)
        end
        push!(scores, score)
    end
    return argmin(scores) - 1
end

mutable struct QRAttempt
    lines::Vector{String}
    text::Union{Nothing,String}
    blocks::Vector{Tuple{String,Int}}
end

function read_segment!(reader, mode, count)
    characters = String[]
    while count > 0
        if mode == "NUMERIC"
            group_size = min(3, count)
            value = read_bits!(reader, (0, 4, 7, 10)[group_size + 1])
            value >= 10^group_size && return nothing
            push!(characters, lpad(string(value), group_size, '0'))
        elseif mode == "ALPHANUMERIC"
            group_size = min(2, count)
            value = read_bits!(reader, group_size == 2 ? 11 : 6)
            value >= (group_size == 2 ? 2025 : 45) && return nothing
            group_size == 2 && push!(characters, string(QR_ALPHANUMERIC[value ÷ 45 + 1]))
            push!(characters, string(QR_ALPHANUMERIC[value % 45 + 1]))
        else
            group_size = 1
            value = read_bits!(reader, 8)
            !(32 <= value <= 126) && return nothing
            push!(characters, string(Char(value)))
        end
        count -= group_size
    end
    return join(characters)
end

function parse_data!(attempt, bits, version)
    reader = QRBitReader(bits, 0)
    text = String[]
    stop = 0
    modes = Dict(value => mode for (mode, value) in QR_INDICATORS)
    while remaining_bits(reader) >= 4
        indicator = read_bits!(reader, 4)
        indicator == 0 && break
        if !haskey(modes, indicator)
            push!(attempt.lines, "parse failed indicator $(binary_digits(indicator, 4))")
            return
        end
        mode = modes[indicator]
        width = count_width(mode, version)
        if remaining_bits(reader) < width
            push!(attempt.lines, "parse failed length $mode")
            return
        end
        count = read_bits!(reader, width)
        if remaining_bits(reader) < data_width(mode, count)
            push!(attempt.lines, "parse failed length $mode")
            return
        end
        segment = read_segment!(reader, mode, count)
        if segment === nothing
            push!(attempt.lines, "parse failed value $mode")
            return
        end
        push!(text, segment)
        push!(attempt.lines, "segment $mode $count")
        stop = reader.position
    end
    expected = pad_bits(bits[1:stop], length(bits))[1]
    push!(attempt.lines, "padding " * (expected == bits ? "ok" : "bad"))
    attempt.text = join(text)
    push!(attempt.lines, "text \"$(attempt.text)\"")
end

function decode_attempt(codec, symbol)
    attempt = QRAttempt(String[], nothing, Tuple{String,Int}[])
    side = size(symbol, 1)
    version = (side - 17) ÷ 4
    first_value, second_value = [read_matrix_value(symbol, positions) for positions in format_positions(side)]
    nearest_first = argmin(item -> count_ones(xor(first_value, item[1])), codec.formats)
    nearest_second = argmin(item -> count_ones(xor(second_value, item[1])), codec.formats)
    d1, d2 = count_ones(xor(first_value, nearest_first[1])), count_ones(xor(second_value, nearest_second[1]))
    prefix = "format $(binary_digits(first_value, 15)) $(binary_digits(second_value, 15)) distance $d1 $d2"
    chosen = d2 < d1 ? nearest_second : nearest_first
    if min(d1, d2) > 3
        push!(attempt.lines, prefix * " unreadable")
        return attempt
    end
    _, level, mask = chosen
    push!(attempt.lines, prefix * " level $level mask $mask")
    if version >= 7
        first_value, second_value = [read_matrix_value(
            symbol,
            positions
        ) for positions in version_positions(side)]
        nearest_first_version = argmin(item -> count_ones(xor(first_value, item[1])), codec.versions)
        nearest_second_version = argmin(item -> count_ones(xor(second_value, item[1])), codec.versions)
        d1 = count_ones(xor(first_value, nearest_first_version[1]))
        d2 = count_ones(xor(second_value, nearest_second_version[1]))
        prefix = "version $(binary_digits(first_value, 18)) $(binary_digits(second_value, 18)) distance $d1 $d2"
        chosen_version = d2 < d1 ? nearest_second_version : nearest_first_version
        if min(d1, d2) > 3
            push!(attempt.lines, prefix * " unreadable")
            return attempt
        end
        push!(attempt.lines, prefix * " decoded $(chosen_version[2])")
        chosen_version[2] != version && return attempt
    end
    shape = geometry(codec, version)
    layout = codec.tables[(version, level)]
    unmasked = apply_mask(symbol, shape.order, mask)
    bits = join(string(unmasked[y + 1, x + 1]) for (x, y) in shape.order[1:8 * layout.total])
    blocks = deinterleave(bits_codewords(bits), layout)
    corrected_blocks = Any[]
    failed = false
    for (index, received) in enumerate(blocks)
        syndromes, corrected, positions = rs_correct(received, layout.degree)
        prefix = "block $(index - 1) syndromes $(hex_words(syndromes))"
        if corrected === nothing
            status = "failed"
            push!(attempt.lines, prefix * " failed")
            failed = true
        elseif !isempty(positions)
            status = "corrected"
            push!(attempt.lines, prefix * " corrected " * join(positions, " "))
        else
            status = "ok"
            push!(attempt.lines, prefix * " ok")
        end
        push!(attempt.blocks, (status, length(positions)))
        push!(corrected_blocks, corrected)
    end
    failed && return attempt
    data = Int[]
    for (words, count) in zip(corrected_blocks, layout.lengths)
        append!(data, words[1:count])
    end
    parse_data!(attempt, codeword_bits(data), version)
    return attempt
end

function decode_symbol(codec, symbol)
    rotations = finder_rotation(symbol)
    oriented = symbol
    for _ in 1:rotations
        oriented = rotate_symbol(oriented)
    end
    adopted = decode_attempt(codec, oriented)
    mirrored = false
    if adopted.text === nothing
        second_attempt = decode_attempt(codec, permutedims(oriented))
        if second_attempt.text !== nothing
            adopted = second_attempt
            mirrored = true
        end
    end
    label = mirrored ? "yes" : "no"
    pushfirst!(adopted.lines, "orientation rotations $rotations mirrored $label")
    return adopted
end

function damaged_symbol(encoding, operations)
    symbol = copy(encoding.symbol)
    for (operation, arguments) in operations
        if operation == "flip"
            x, y = arguments
            symbol[y + 1, x + 1] = xor(symbol[y + 1, x + 1], 1)
        elseif operation == "fill"
            left, top, width, height, color = arguments
            symbol[top + 1:top + height, left + 1:left + width] .= color
        end
    end
    kinds = ("function", "format", "version", "data", "remainder")
    counts = Dict(kind => 0 for kind in kinds)
    damaged_words = [Set{Int}() for _ in 1:encoding.blockspec.count]
    for y in 0:encoding.layout.side - 1, x in 0:encoding.layout.side - 1
        symbol[y + 1, x + 1] == encoding.symbol[y + 1, x + 1] && continue
        area = encoding.layout.areas[y + 1, x + 1]
        if area != QR_DATA
            counts[kinds[area]] += 1
        else
            index = encoding.layout.indices[(x, y)]
            if index < 8 * encoding.blockspec.total
                counts["data"] += 1
                block, word = encoding.blockspec.placement[index ÷ 8 + 1]
                push!(damaged_words[block], word)
            else
                counts["remainder"] += 1
            end
        end
    end
    for (operation, _) in operations
        operation == "rotate" && (symbol = rotate_symbol(symbol))
        operation == "mirror" && (symbol = permutedims(symbol))
    end
    details = join(("$kind $(counts[kind])" for kind in kinds), " ")
    errors = join(length.(damaged_words), " ")
    lines = [
        "check damaged operations $(length(operations))",
        "damage changed $(sum(values(counts))) $details",
        "errors $errors limit $(encoding.blockspec.degree ÷ 2)"
    ]
    return symbol, lines
end

function damage_tolerance(encoding, codec, color)
    side = encoding.layout.side
    for span in 1:side
        symbol = copy(encoding.symbol)
        start = (side - span) ÷ 2
        symbol[start + 1:start + span, start + 1:start + span] .= color
        attempt = decode_symbol(codec, symbol)
        attempt.text != encoding.request.text && return span - 1
    end
    return side
end

function new_summary()
    return Dict(name => Dict{Any,Int}() for name in (
        "totals",
        "errors",
        "modes",
        "levels",
        "versions",
        "masks",
        "checks",
        "blocks",
        "scans"
    ))
end

counter(summary, group, key) = get(summary[group], key, 0)
function increment!(summary, group, key, amount=1)
    summary[group][key] = counter(summary, group, key) + amount
end

function record_encoding!(summary, encoding)
    request, layout = encoding.request, encoding.blockspec
    increment!(summary, "totals", "encoded")
    increment!(summary, "modes", request.mode)
    increment!(summary, "levels", request.level)
    increment!(summary, "versions", request.version)
    increment!(summary, "masks", encoding.mask)
    for (key, amount) in (
        ("boosted", Int(request.boosted)),
        ("segments", length(request.segments)),
        ("data", layout.data),
        ("ec", layout.degree * layout.count),
        ("modules", encoding.layout.side^2),
        ("dark", encoding.dark)
    )
        increment!(summary, "totals", key, amount)
    end
end

function record_check!(summary, attempt, text)
    result = attempt.text === nothing ? "failed" : attempt.text == text ? "ok" : "mismatch"
    increment!(summary, "checks", result)
    for (status, positions) in attempt.blocks
        increment!(summary, "blocks", status)
        increment!(summary, "totals", "corrected_positions", positions)
    end
    return result
end

function summary_lines(summary, request_count)
    total(key) = counter(summary, "totals", key)
    pairs(group, keys) = join(("$key $(counter(summary, group, key))" for key in keys), " ")
    lines = ["requests $request_count encoded $(total("encoded")) errors $(sum(values(summary["errors"]); init=0))"]
    push!(lines, "error_kinds " * pairs("errors", QR_ERROR_KINDS))
    push!(lines, "modes " * pairs("modes", (QR_MODES..., "MIXED")))
    push!(lines, "levels " * pairs("levels", QR_LEVELS) * " boosted $(total("boosted"))")
    push!(lines, "versions " * join((counter(summary, "versions", version) for version in 1:10), " "))
    push!(lines, "masks " * join((counter(summary, "masks", mask) for mask in 0:7), " "))
    push!(lines, "segments $(total("segments")) data_codewords $(total("data")) ec_codewords $(total("ec"))")
    push!(lines, "modules $(total("modules")) dark $(total("dark"))")
    push!(
        lines,
        "checks $(sum(values(summary["checks"]); init=0)) " * pairs("checks", ("ok", "mismatch", "failed"))
    )
    push!(
        lines,
        "blocks " * pairs(
            "blocks",
            ("ok", "corrected", "failed")
        ) * " codewords $(total("corrected_positions"))"
    )
    push!(
        lines,
        "scans $(sum(values(summary["scans"]); init=0)) decoded $(counter(summary, "scans", "decoded")) failed $(counter(summary, "scans", "failed"))"
    )
    return lines
end

function check_lines(encoding, codec, params, operations, summary)
    request = encoding.request
    path = "output/qr_$(request.identifier).pbm"
    write(path, pbm_text(encoding.symbol, params["quiet_zone"], params["scale"]))
    symbol, image_line = read_image(path)
    lines = ["request $(request.identifier)", image_line, "check clean"]
    attempt = decode_symbol(codec, symbol)
    append!(lines, attempt.lines)
    push!(lines, "result " * record_check!(summary, attempt, request.text))
    if !isempty(operations)
        symbol, damage_lines = damaged_symbol(encoding, operations)
        append!(lines, damage_lines)
        attempt = decode_symbol(codec, symbol)
        append!(lines, attempt.lines)
        push!(lines, "result " * record_check!(summary, attempt, request.text))
    end
    light = damage_tolerance(encoding, codec, 0)
    dark = damage_tolerance(encoding, codec, 1)
    push!(lines, "tolerance light $light dark $dark")
    return lines
end

function capacity_lines(codec)
    lines = String[]
    for version in 1:10
        shape = geometry(codec, version)
        total = codec.tables[(version, "L")].total
        alignment = isempty(codec.alignments[version]) ? "none" : join(codec.alignments[version], " ")
        push!(
            lines,
            "version $version size $(shape.side) data_modules $(shape.data_modules) codewords $total remainder $(shape.data_modules - 8 * total) alignment $alignment"
        )
        for level in QR_LEVELS
            layout = codec.tables[(version, level)]
            maxima = Int[]
            for mode in QR_MODES
                count = 0
                while 4 + count_width(mode, version) + data_width(mode, count + 1) <= layout.capacity
                    count += 1
                end
                push!(maxima, count)
            end
            push!(
                lines,
                "level $level blocks $(layout.count) data $(layout.data) ec_per_block $(layout.degree) numeric $(maxima[1]) alphanumeric $(maxima[2]) byte $(maxima[3])"
            )
        end
    end
    return lines
end

function main()
    requests, params, tables, alignments, damage, scans = read_inputs()
    codec = new_codec(tables, alignments)
    summary = new_summary()
    mkpath("output")
    reports = Dict(name => String[] for name in ("codes", "codewords", "bitstream", "selfcheck", "scans"))
    for request in requests
        push!(reports["codes"], "request $(request.identifier)")
        error = prepare_request!(request, codec)
        if error !== nothing
            push!(reports["codes"], "error $error")
            increment!(summary, "errors", first(split(error, ' ')))
            continue
        end
        encoding = encode_request(request, codec)
        append!(reports["codes"], codes_lines(encoding, codec))
        append!(reports["codewords"], codeword_lines(encoding))
        append!(reports["bitstream"], bitstream_lines(encoding))
        record_encoding!(summary, encoding)
        append!(
            reports["selfcheck"],
            check_lines(encoding, codec, params, get(damage, request.identifier, Any[]), summary)
        )
    end
    for (name, symbol) in scans
        push!(reports["scans"], "scan $name size $(size(symbol, 1))")
        attempt = decode_symbol(codec, symbol)
        append!(reports["scans"], attempt.lines)
        result = attempt.text === nothing ? "failed" : "decoded"
        push!(reports["scans"], "result $result")
        increment!(summary, "scans", result)
    end
    reports["capacity"] = capacity_lines(codec)
    reports["summary"] = summary_lines(summary, length(requests))
    for (name, lines) in reports
        write("output/$name.txt", join((line * "\n" for line in lines)))
    end
end

main()
