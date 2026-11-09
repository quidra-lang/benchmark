include("signals.jl")
include("effects.jl")
include("filters.jl")
include("dynamics.jl")
include("analysis.jl")
using .Signals, .AudioAnalysis

struct CommandError <: Exception
    message::String
end
fail(message) = throw(CommandError(message))
struct Argument
    name::String
    low::Union{Int,String}
    high::Union{Int,String}
end
argument(name, low=0, high=0) = Argument(name, low, high)
struct Command
    arguments::Vector{Argument}
    repeated::Vector{Argument}
    minimum::Int
    maximum::Int
end
command(args, repeated=Argument[], minimum=0, maximum=0) = Command(args, repeated, minimum, maximum)
const DST = argument("dst")
const SRC = argument("src")
const RATE = argument("rate", 1000, 48000)
const COUNT = argument("count", 1, 20000)
const NUM = argument("num", -65536, 65536)
const DEN = argument("den", 1, 65536)
const ATTACK = argument("attack", 1, 32768)
const RELEASE = argument("release", 1, 32768)
const MIN_HZ = argument("min_hz", 1, "rate_half_minus_one")
const MAX_HZ = argument("max_hz", "min_hz_plus_one", "rate_half")
const START = argument("start", 0, "last")
const TEST_ARGS = [DST, RATE, COUNT, argument("pos", 0, "count_minus_one"), argument("amp", -32768, 32767)]
const COMMANDS = Dict(
    "SET" => command([argument("var"), argument("value", -10000000, 10000000)], [argument("op"), argument("operand", -10000000, 10000000)], 0, 1),
    "IMPULSE" => command(TEST_ARGS), "STEP" => command(TEST_ARGS),
    "NOISE" => command([DST, RATE, COUNT, argument("seed", 1, 2147483646)]),
    "GAIN" => command([DST, SRC, NUM, DEN]),
    "MIX" => command([DST, DEN], [SRC, argument("weight", -65536, 65536)], 1, 8),
    "DELAY" => command([DST, SRC, argument("samples", 0, 20000)]),
    "ECHO" => command([DST, SRC, argument("delay", 1, 20000), NUM, DEN, argument("tail", 0, 20000)]),
    "RESAMPLE" => command([DST, SRC, argument("new_rate", 1000, 48000)]),
    "FADE" => command([DST, SRC, argument("in", 0, "length"), argument("out", 0, "length")]),
    "TRIM" => command([DST, SRC, START, argument("count", 1, "remaining")]),
    "CONCAT" => command([DST], [SRC], 2, 8),
    "FIR" => command([DST, SRC, argument("divisor", 1, 1000000)], [argument("tap", -32768, 32767)], 1, 64),
    "BIQUAD" => command([DST, SRC], [argument(n, -65536, 65536) for n in ["b0", "b1", "b2", "a1", "a2"]], 1, 4),
    "MOVAVG" => command([DST, SRC, argument("width", 1, 1000)]),
    "DCBLOCK" => command([DST, SRC, argument("num", 0, 65535), argument("den", "num_plus_one", 65536)]),
    "NORMALIZE" => command([DST, SRC, argument("target", 1, 32767)]),
    "GATE" => command([DST, SRC, argument("threshold", 1, 32768), argument("hold", 0, 20000)]),
    "ENVELOPE" => command([DST, SRC, ATTACK, RELEASE]),
    "COMPRESS" => command([DST, SRC, argument("threshold", 1, 32767), argument("ratio_num", 1, 100), argument("ratio_den", 1, "ratio_num"), ATTACK, RELEASE]),
    "ANALYZE" => command([SRC, MIN_HZ, MAX_HZ]), "COMPARE" => command([SRC, SRC]),
    "EXPECT" => command([SRC, argument("metric"), argument("op"), argument("value", -1000000000, 1000000000)]),
    "SEGMENTS" => command([SRC, argument("threshold", 1, 32768), argument("gap", 1, 20000), argument("min_length", 1, 20000)]),
    "ONSETS" => command([SRC, ATTACK, RELEASE, argument("threshold", 1, 32767), argument("min_gap", 1, 20000)]),
    "PITCHTRACK" => command([SRC, argument("frame", 16, "length"), argument("hop", 1, "frame"), MIN_HZ, MAX_HZ, argument("threshold", 0, 32767)]),
    "EXCERPT" => command([SRC, START, argument("count", 1, 1000)]),
    "PLOT" => command([SRC, START, argument("count", 1, "remaining"), argument("columns", 8, "columns"), argument("half", 2, 20), ATTACK, RELEASE]),
    "METER" => command([SRC, argument("block", 1, 20000)]), "HISTOGRAM" => command([SRC, argument("bins", 2, 64)]),
    "TRACE" => command([SRC]), "SAVE" => command([SRC]),
)
const GENERATORS = Set(["IMPULSE", "STEP", "NOISE", "GAIN", "MIX", "DELAY", "ECHO", "RESAMPLE", "FADE", "TRIM", "CONCAT", "FIR", "BIQUAD", "MOVAVG", "DCBLOCK", "NORMALIZE", "GATE", "ENVELOPE", "COMPRESS"])
const METRICS = ("samples", "peak", "rms", "sum", "zero_crossings", "clipped")
const ARITHMETIC = Dict("+" => (+), "-" => (-), "*" => (*), "/" => fld)
const COMPARISONS = Dict("eq" => (==), "ne" => (!=), "lt" => (<), "le" => (<=), "gt" => (>), "ge" => (>=))
mutable struct Pipeline
    signals::Dict{String,Signal}
    variables::Dict{String,Int}
    log::Vector{String}
    analysis::Vector{String}
    excerpts::Vector{String}
    waveforms::Vector{String}
    saved::Vector{String}
    steps::Int
    errors::Int
    passed::Int
    failed::Int
end
function Pipeline(loaded)
    p = Pipeline(Dict{String,Signal}(), Dict{String,Int}(), String[], ["signal,peak,rms,zero_crossings,clipped,crest,pitch_lag,pitch_hz"], String[], String[], String[], 0, 0, 0, 0)
    for s in loaded
        p.signals[s.name] = s
        push!(p.log, "load $(s.name) rate=$(s.rate) samples=$(length(s.samples)) peak=$(peak(s.samples))")
    end
    p
end
function bound(value, known, source)
    value isa Int && return value
    value == "count_minus_one" && return known["count"] - 1
    value == "columns" && return min(120, known["count"])
    value == "min_hz_plus_one" && return known["min_hz"] + 1
    value == "num_plus_one" && return known["num"] + 1
    value == "length" && return length(source.samples)
    value == "last" && return length(source.samples) - 1
    value == "remaining" && return length(source.samples) - known["start"]
    value == "rate_half" && return fld(source.rate, 2)
    value == "rate_half_minus_one" && return fld(source.rate, 2) - 1
    known[value]
end
function integer_value(p, token)
    if startswith(token, "\$")
        name = token[2:end]
        haskey(p.variables, name) || fail("undefined variable $token")
        return p.variables[name]
    end
    occursin(r"^-?(0|[1-9][0-9]{0,9})$", token) && token != "-0" || fail("bad integer $token")
    parse(Int, token)
end
function parse_arguments(p, name, spec, tokens)
    extra = length(tokens) - length(spec.arguments)
    accepted = isempty(spec.repeated) ? extra == 0 : extra >= 0 && mod(extra, length(spec.repeated)) == 0 && spec.minimum <= div(extra, length(spec.repeated)) <= spec.maximum
    accepted || fail("wrong number of arguments")
    values = Any[]
    sources = Signal[]
    known = Dict{String,Int}()
    for (i, token) in enumerate(tokens)
        a = i <= length(spec.arguments) ? spec.arguments[i] : spec.repeated[mod(i - length(spec.arguments) - 1, length(spec.repeated)) + 1]
        if a.name in ("dst", "var")
            occursin(r"^[a-z][a-z0-9_]{0,15}$", token) || fail("bad name $token")
            value = token
        elseif a.name == "src"
            haskey(p.signals, token) || fail("unknown signal $token")
            value = p.signals[token]
            push!(sources, value)
        elseif a.name == "metric"
            token in METRICS || fail("unknown metric $token")
            value = token
        elseif a.name == "op"
            haskey(name == "SET" ? ARITHMETIC : COMPARISONS, token) || fail("unknown operator $token")
            value = token
        else
            value = integer_value(p, token)
            source = isempty(sources) ? nothing : sources[1]
            bound(a.low, known, source) <= value <= bound(a.high, known, source) || fail("$(a.name) out of range")
            known[a.name] = value
        end
        push!(values, value)
    end
    values, sources
end
function same_rate(sources)
    all(s -> s.rate == sources[1].rate, sources) || fail("rate mismatch")
end
milliseconds(index, rate) = fld(index * 1000, rate)
two_decimals(h) = "$(fld(h, 100)).$(lpad(mod(h, 100), 2, '0'))"
frequency_text(rate, lag) = two_decimals(rdiv(100rate, lag))
lag_range(rate, low, high) = (cld(rate, high), fld(rate, low))
function generate!(p, number, name, values, sources)
    dst, args = values[1], values[2:end]
    extras = Pair{String,Int}[]
    if name in ("IMPULSE", "STEP", "NOISE")
        rate = args[1]
        data = name == "IMPULSE" ? impulse(args[2:end]...) : name == "STEP" ? step_signal(args[2:end]...) : noise(args[2:end]...)
    else
        source = sources[1]
        rate, x = source.rate, source.samples
        if name == "GAIN"
            data, clipped = Effects.gain(x, args[2:end]...)
            push!(extras, "clipped" => clipped)
        elseif name == "MIX"
            same_rate(sources)
            data, clipped = Effects.mix([s.samples for s in sources], args[3:2:end], args[1])
            push!(extras, "clipped" => clipped)
        elseif name == "DELAY"
            length(x) + args[2] <= 20000 || fail("result too long")
            data = Effects.delay(x, args[2])
        elseif name == "ECHO"
            abs(args[3]) < args[4] || fail("unstable feedback")
            length(x) + args[5] <= 20000 || fail("result too long")
            data, clipped = Effects.echo(x, args[2:end]...)
            push!(extras, "clipped" => clipped)
        elseif name == "RESAMPLE"
            rate = args[2]
            Effects.resampled_length(length(x), source.rate, rate) <= 20000 || fail("result too long")
            data = Effects.resample(x, source.rate, rate)
        elseif name == "FADE"
            data = Effects.fade(x, args[2:end]...)
        elseif name == "TRIM"
            data = x[args[2]+1:args[2]+args[3]]
        elseif name == "CONCAT"
            same_rate(sources)
            sum(s -> length(s.samples), sources) <= 20000 || fail("result too long")
            data = vcat((s.samples for s in sources)...)
        elseif name == "FIR"
            data, clipped = Filters.fir(x, args[2], args[3:end])
            push!(extras, "clipped" => clipped)
        elseif name == "BIQUAD"
            data, clipped = Filters.biquad(x, args[2:end])
            append!(extras, ["sections" => div(length(args)-1, 5), "clipped" => clipped])
        elseif name == "MOVAVG"
            data = Filters.moving_average(x, args[2])
        elseif name == "DCBLOCK"
            data, clipped = Filters.dc_block(x, args[2:end]...)
            push!(extras, "clipped" => clipped)
        elseif name == "NORMALIZE"
            data, source_peak = Dynamics.normalize(x, args[2])
            push!(extras, "source_peak" => source_peak)
        elseif name == "GATE"
            data, muted = Dynamics.gate(x, args[2:end]...)
            push!(extras, "muted" => muted)
        elseif name == "ENVELOPE"
            data = Dynamics.envelope(x, args[2:end]...)
        else
            data, min_gain, reduced = Dynamics.compress(x, args[2:end]...)
            append!(extras, ["min_gain" => min_gain, "reduced" => reduced])
        end
    end
    p.signals[dst] = Signal(dst, rate, data, "line $number $name", sources)
    details = "$dst rate=$rate samples=$(length(data)) peak=$(peak(data)) sum=$(sum(data))"
    details * join((" $key=$value" for (key, value) in extras))
end
plot_row(v, scale, rows) = rdiv((scale - v) * (rows - 1), 2scale)
function waveform_plot(s, start, count, columns, half, attack, release)
    x = s.samples[start+1:start+count]
    levels = Dynamics.envelope(s.samples, attack, release)[start+1:start+count]
    rows, scale = 2half + 1, max(1, peak(x))
    grid = fill(' ', rows, columns)
    for c in 0:columns-1
        first, last = fld(c * count, columns) + 1, fld((c + 1) * count, columns)
        top = plot_row(maximum(x[first:last]), scale, rows)
        bottom = plot_row(minimum(x[first:last]), scale, rows)
        level = min(scale, maximum(levels[first:last]))
        upper, lower = plot_row(level, scale, rows), plot_row(-level, scale, rows)
        for r in 0:rows-1
            grid[r+1, c+1] = r == upper || r == lower ? '*' : top <= r <= bottom ? '#' : r == half ? '-' : ' '
        end
    end
    lines = ["PLOT $(s.name) rate=$(s.rate) start=$start count=$count columns=$columns rows=$rows scale=$scale attack=$attack release=$release"]
    for r in 0:rows-1
        label = r == 0 ? string(scale) : r == half ? "0" : r == rows-1 ? string(-scale) : ""
        push!(lines, "$(lpad(label, 6)) |$(join(grid[r+1, :]))|")
    end
    push!(lines, "       +" * join(c % 10 == 0 ? '+' : '-' for c in 0:columns-1) * "+")
    time_line = "    ms"
    for c in 0:10:columns-1
        time_line = rpad(time_line, 8+c) * string(milliseconds(start + fld(c*count, columns), s.rate))
    end
    push!(lines, time_line)
    lines
end
function meter_plot(s, block)
    blocks = cld(length(s.samples), block)
    lines = ["METER $(s.name) rate=$(s.rate) samples=$(length(s.samples)) block=$block blocks=$blocks"]
    for b in 0:blocks-1
        x = s.samples[b*block+1:min((b+1)*block, end)]
        p, q = peak(x), rms(x)
        np, nq = rdiv(p*40, 32768), rdiv(q*40, 32768)
        bar = join(j < nq ? '#' : j < np ? '-' : ' ' for j in 0:39)
        push!(lines, "$(lpad(milliseconds(b*block, s.rate), 6)) |$bar| peak=$p rms=$q clipped=$(count_clipped(x))")
    end
    lines
end
function histogram_plot(s, bins)
    counts = zeros(Int, bins)
    for x in s.samples
        counts[fld((x+32768)*bins, 65536)+1] += 1
    end
    largest = maximum(counts)
    lines = ["HISTOGRAM $(s.name) rate=$(s.rate) samples=$(length(s.samples)) bins=$bins max=$largest"]
    for b in 0:bins-1
        low, high = cld(b*65536, bins)-32768, cld((b+1)*65536, bins)-32769
        push!(lines, "$(lpad(low, 6)) $(lpad(high, 6)) $(lpad(counts[b+1], 5)) |$(repeat("#", rdiv(counts[b+1]*50, largest)))")
    end
    lines
end
function pitch_row(rate, start, level, lag, low, high)
    bar = fill(' ', 41)
    if lag === nothing
        suffix = "unvoiced rms=$level"
    else
        position = high > low ? rdiv((high-lag)*40, high-low) : 0
        bar[position+1] = 'o'
        suffix = "lag=$lag hz=$(frequency_text(rate, lag)) rms=$level"
    end
    "$(lpad(milliseconds(start, rate), 6)) |$(join(bar))| $suffix"
end
function trace_lines!(lines, s, depth)
    push!(lines, "$(repeat("  ", depth))$(s.name) <- $(s.origin)")
    for ingredient in s.ingredients
        trace_lines!(lines, ingredient, depth+1)
    end
end
function metric_value(name, x)
    name == "samples" && return length(x)
    name == "peak" && return peak(x)
    name == "rms" && return rms(x)
    name == "sum" && return sum(x)
    name == "zero_crossings" && return zero_crossings(x)
    count_clipped(x)
end
function execute!(p, number, name, tokens)
    haskey(COMMANDS, name) || fail("unknown command $name")
    values, sources = parse_arguments(p, name, COMMANDS[name], tokens)
    name in GENERATORS && return [generate!(p, number, name, values, sources)]
    if name == "SET"
        var, result = values[1:2]
        if length(values) == 4
            op, operand = values[3:4]
            op == "/" && operand == 0 && fail("division by zero")
            result = ARITHMETIC[op](result, operand)
            abs(result) <= 10000000 || fail("value out of range")
        end
        p.variables[var] = result
        return ["$var=$result"]
    end
    s = sources[1]
    x, rate, count = s.samples, s.rate, length(s.samples)
    if name == "ANALYZE"
        low, high = lag_range(rate, values[2:end]...)
        low <= high || fail("empty lag range")
        high < count || fail("signal too short")
        lag = pitch_lag(x, low, high)
        lag_text, hz = lag === nothing ? ("none", "none") : (string(lag), frequency_text(rate, lag))
        push!(p.analysis, "$(s.name),$(peak(x)),$(rms(x)),$(zero_crossings(x)),$(count_clipped(x)),$(crest_fraction(x)),$lag_text,$hz")
        return ["$(s.name) lags=$low-$high"]
    elseif name == "COMPARE"
        other = sources[2]
        same_rate(sources)
        differences = [(i <= count ? x[i] : 0) - (i <= length(other.samples) ? other.samples[i] : 0) for i in 1:max(count, length(other.samples))]
        first_index = findfirst(!=(0), differences)
        first_text = first_index === nothing ? "none" : string(first_index - 1)
        return ["$(s.name) $(other.name) differing=$(Base.count(!=(0), differences)) max_diff=$(peak(differences)) first=$first_text error_energy=$(energy(differences))"]
    elseif name == "EXPECT"
        metric, op, value = values[2:end]
        measured = metric_value(metric, x)
        passed = COMPARISONS[op](measured, value)
        p.passed += passed
        p.failed += !passed
        return ["$(s.name) $metric=$measured $op $value $(passed ? "pass" : "fail")"]
    elseif name == "SEGMENTS"
        threshold, gap, min_length = values[2:end]
        found = Tuple{Int,Int}[]
        for i in 0:count-1
            abs(x[i+1]) >= threshold || continue
            if !isempty(found) && i - found[end][2] <= gap
                found[end] = (found[end][1], i)
            else
                push!(found, (i, i))
            end
        end
        reported = filter(ab -> ab[2]-ab[1]+1 >= min_length, found)
        lines = ["$(s.name) segments=$(length(reported))"]
        for (j, (a, b)) in enumerate(reported)
            part = x[a+1:b+1]
            push!(lines, "  segment $j start=$a end=$b start_ms=$(milliseconds(a, rate)) end_ms=$(milliseconds(b, rate)) peak=$(peak(part)) rms=$(rms(part)) crossings=$(zero_crossings(part))")
        end
        return lines
    elseif name == "ONSETS"
        attack, release, threshold, min_gap = values[2:end]
        levels = Dynamics.envelope(x, attack, release)
        onsets = Int[]
        for n in 0:count-1
            rising = levels[n+1] >= threshold && (n == 0 || levels[n] < threshold)
            rising && (isempty(onsets) || n - onsets[end] >= min_gap) && push!(onsets, n)
        end
        intervals = diff(onsets)
        tempo = length(onsets) < 2 ? "none" : two_decimals(rdiv(6000rate, sort(intervals)[fld(length(onsets)-2, 2)+1]))
        lines = ["$(s.name) onsets=$(length(onsets)) tempo=$tempo"]
        for (j, n) in enumerate(onsets)
            interval = j == 1 ? "none" : string(intervals[j-1])
            push!(lines, "  onset $j sample=$n ms=$(milliseconds(n, rate)) interval=$interval")
        end
        return lines
    elseif name == "PITCHTRACK"
        frame, hop, min_hz, max_hz, threshold = values[2:end]
        low, high = lag_range(rate, min_hz, max_hz)
        low <= high || fail("empty lag range")
        high < frame || fail("frame too short")
        frames = fld(count-frame, hop)+1
        rows = String[]
        voiced = 0
        for t in 0:frames-1
            part = x[t*hop+1:t*hop+frame]
            level = rms(part)
            lag = level < threshold ? nothing : pitch_lag(part, low, high)
            voiced += lag !== nothing
            push!(rows, pitch_row(rate, t*hop, level, lag, low, high))
        end
        push!(p.waveforms, "PITCHTRACK $(s.name) rate=$rate frame=$frame hop=$hop lags=$low-$high threshold=$threshold frames=$frames voiced=$voiced")
        append!(p.waveforms, rows)
        return ["$(s.name) frames=$frames voiced=$voiced"]
    elseif name == "EXCERPT"
        start, requested = values[2:end]
        size = min(requested, count-start)
        push!(p.excerpts, "EXCERPT $(s.name) rate=$rate samples=$count start=$start count=$size")
        for offset in 0:8:size-1
            group = join(" $(lpad(value, 6))" for value in x[start+offset+1:start+min(offset+8, size)])
            push!(p.excerpts, "$(lpad(start+offset, 5)):$group")
        end
        return ["$(s.name) start=$start count=$size"]
    elseif name == "PLOT"
        start, size, columns, half, attack, release = values[2:end]
        append!(p.waveforms, waveform_plot(s, start, size, columns, half, attack, release))
        return ["$(s.name) start=$start count=$size columns=$columns rows=$(2half+1)"]
    elseif name == "METER"
        append!(p.waveforms, meter_plot(s, values[2]))
        return ["$(s.name) block=$(values[2])"]
    elseif name == "HISTOGRAM"
        append!(p.waveforms, histogram_plot(s, values[2]))
        return ["$(s.name) bins=$(values[2])"]
    elseif name == "TRACE"
        lines = [s.name]
        trace_lines!(lines, s, 1)
        return lines
    else
        append!(p.saved, format_signal(s))
        return ["$(s.name) samples=$count"]
    end
end
function main()
    p = Pipeline(read_signals("input/signals.txt"))
    for (number, line) in enumerate(readlines("input/pipeline.txt"))
        (isempty(line) || startswith(line, "#")) && continue
        tokens = String.(split(line, ' '))
        try
            lines = execute!(p, number, tokens[1], tokens[2:end])
            push!(p.log, "line $number: $(tokens[1]) $(lines[1])")
            append!(p.log, lines[2:end])
            p.steps += 1
        catch error
            error isa CommandError || rethrow()
            push!(p.log, "line $number: error: $(error.message)")
            p.errors += 1
        end
    end
    for name in sort!(collect(keys(p.signals)))
        s = p.signals[name]
        push!(p.log, "signal $name rate=$(s.rate) samples=$(length(s.samples)) peak=$(peak(s.samples)) rms=$(rms(s.samples))")
    end
    push!(p.log, "summary steps=$(p.steps) errors=$(p.errors) signals=$(length(p.signals)) passed=$(p.passed) failed=$(p.failed)")
    mkpath("output")
    for (name, lines) in zip(["log.txt", "analysis.csv", "excerpts.txt", "waveforms.txt", "signals_out.txt"], [p.log, p.analysis, p.excerpts, p.waveforms, p.saved])
        open(joinpath("output", name), "w") do io
            for line in lines
                println(io, line)
            end
        end
    end
end
main()
