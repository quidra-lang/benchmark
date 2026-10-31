module Analysis

import ..Scoring

export Repetition, KasiskiData, frequency, ioc, column, columniocs,
    averageioc, kasiski, kasiskicount, periodtable, kasiskitable,
    toppairs, percentage, report

struct Repetition
    text::String
    positions::Vector{Int}
    gaps::Vector{Int}
    divisor::Int
end

struct KasiskiData
    repeats::Vector{Repetition}
    gaps::Vector{Int}
end

function frequency(text::AbstractString)
    counts = zeros(Int, 26)
    for c in text
        counts[Scoring.value(c) + 1] += 1
    end
    return counts
end

function ioc(text::AbstractString)
    n = length(text)
    n < 2 && return 0
    total = sum(Int128(count) * (count - 1) for count in frequency(text))
    return Int(div(100000 * total, n * (n - 1)))
end

function column(text::AbstractString, period::Int, offset::Int)
    chars = collect(text)
    return join(chars[(offset + 1):period:length(chars)])
end

function columniocs(text::AbstractString, period::Int)
    return [ioc(column(text, period, i)) for i in 0:(period - 1)]
end

function averageioc(text::AbstractString, period::Int)
    return sum(columniocs(text, period)) ÷ period
end

function kasiski(text::AbstractString)
    chars = collect(text)
    occurrences = Dict{String, Vector{Int}}()
    for i in 1:(length(chars) - 2)
        trigram = join(chars[i:i + 2])
        push!(get!(occurrences, trigram, Int[]), i)
    end
    repeats, gaps = Repetition[], Int[]
    for trigram in sort!(collect(keys(occurrences)))
        positions = occurrences[trigram]
        length(positions) < 2 && continue
        differences = [positions[i] - positions[i - 1] for i in 2:length(positions)]
        append!(gaps, differences)
        push!(repeats, Repetition(trigram, positions, differences, foldl(gcd, differences)))
    end
    return KasiskiData(repeats, gaps)
end

function kasiskicount(data::KasiskiData, period::Int)
    return count(gap -> gap % period == 0, data.gaps)
end

numberlist(values) = join(values, ",")

function periodtable(text::AbstractString, maxlen::Int, data::KasiskiData)
    lines = String[]
    for period in 1:maxlen
        columns = columniocs(text, period)
        average = sum(columns) ÷ period
        push!(lines, "L=$period ioc=$average kasiski=$(kasiskicount(data, period)) cols=$(numberlist(columns))")
    end
    return lines
end

function kasiskitable(data::KasiskiData)
    result = String["kasiski repeats=$(length(data.repeats)) spacings=$(length(data.gaps))"]
    for item in data.repeats
        push!(result, "$(item.text) at=$(numberlist(item.positions)) gaps=$(numberlist(item.gaps)) gcd=$(item.divisor)")
    end
    return result
end

function toppairs(text::AbstractString, digraphs::Bool)
    chars = collect(text)
    counts = Dict{String, Int}()
    step = digraphs ? 2 : 1
    for i in 1:step:(length(chars) - 1)
        pair = join(chars[i:i + 1])
        counts[pair] = get(counts, pair, 0) + 1
    end
    ordered = sort!(collect(keys(counts)), by=key -> (-counts[key], key))
    return join(["$key:$(counts[key])" for key in Iterators.take(ordered, 10)], " ")
end

function percentage(count::Int, total::Int)
    tenths = (2000 * count + total) ÷ (2 * total)
    return "$(tenths ÷ 10).$(tenths % 10)"
end

function report(job::Int, source::String, text::AbstractString,
    mono::Vector{Int}, bi::Vector{Vector{Int}}, maxlen::Int)
    data = kasiski(text)
    counts = frequency(text)
    chars = collect(text)
    doubles, pairdoubles = 0, 0
    for i in 1:(length(chars) - 1)
        if chars[i] == chars[i + 1]
            doubles += 1
            if isodd(i)
                pairdoubles += 1
            end
        end
    end
    result = String[
        "JOB $job ANALYZE source=$source",
        "letters=$(length(chars))",
        "ioc=$(ioc(text)) mono=$(Scoring.monogram(text, mono)) bigram=$(Scoring.bigram(text, bi))",
        "doubles=$doubles pair_doubles=$pairdoubles distinct=$(count(!iszero, counts))"
    ]
    for i in 1:26
        push!(result, "$(Scoring.upper(i - 1)) $(counts[i]) $(percentage(counts[i], length(chars)))")
    end
    push!(result, "bigrams $(toppairs(text, false))")
    append!(result, periodtable(text, maxlen, data))
    append!(result, kasiskitable(data))
    return result
end

end
