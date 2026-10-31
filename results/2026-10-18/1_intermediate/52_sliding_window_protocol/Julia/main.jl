using Printf
const KEYS = ["PROTOCOL", "FRAMES", "WINDOW", "SEQBITS", "TIMEOUT", "DELAY", "INTERVAL", "MAXTICKS", "DUPACK", "NAK", "BACKOFF", "CONGESTION", "UNSAFE", "TRACE", "RANDOM", "LOSEDATA", "LOSECTRL", "CORRUPTDATA", "CORRUPTCTRL", "DELAYDATA", "DELAYCTRL", "SNAPSHOT"]
const LISTKEYS = KEYS[16:end]
struct SettingsError <: Exception
    text::String
end
bad(s) = throw(SettingsError(s))
function configure(lines)
    raw = Dict{String,Vector{String}}()
    for w in lines
        key, values = w[1], w[2:end]
        key in KEYS || bad("unknown key $key")
        haskey(raw, key) && bad("duplicate key $key")
        count = key == "RANDOM" ? length(values) == 3 : key in LISTKEYS ? !isempty(values) : length(values) == 1
        count || bad("wrong number of values for $key")
        raw[key] = values
    end
    for key in KEYS[1:6]
        haskey(raw, key) || bad("missing key $key")
    end
    ranges = Dict("FRAMES"=>(1,60), "WINDOW"=>(1,32), "SEQBITS"=>(1,6), "TIMEOUT"=>(1,50), "DELAY"=>(1,10), "INTERVAL"=>(0,10), "MAXTICKS"=>(1,2000), "DUPACK"=>(1,10))
    values = Dict{String,Union{Int,String,Vector{Int},Dict{Int,Int}}}()
    for key in KEYS
        haskey(raw, key) || continue
        v = raw[key]
        valid = true
        if haskey(ranges, key)
            n = parse(Int, v[1])
            lo, hi = ranges[key]
            valid = lo <= n <= hi
            values[key] = n
        elseif key == "PROTOCOL"
            valid = v[1] in ("SW", "GBN", "SR")
            values[key] = v[1]
        elseif key == "TRACE"
            valid = v[1] in ("ALL", "SENDER", "RECEIVER", "NONE")
            values[key] = v[1]
        elseif key in ("NAK", "BACKOFF", "CONGESTION", "UNSAFE")
            valid = v[1] in ("ON", "OFF")
            values[key] = v[1]
        elseif key == "RANDOM"
            ns = parse.(Int, v)
            valid = 1 <= ns[1] <= 2147483646 && ns[2] >= 0 && ns[3] >= 0 && ns[2] + ns[3] <= 100
            values[key] = ns
        elseif key in ("DELAYDATA", "DELAYCTRL")
            delays = Dict{Int,Int}()
            for text in v
                i, e = parse.(Int, split(text, ':'))
                if !(1 <= i <= 9999 && 1 <= e <= 50) || haskey(delays, i)
                    valid = false
                end
                delays[i] = e
            end
            values[key] = delays
        else
            ns = parse.(Int, v)
            lo, hi = key == "SNAPSHOT" ? (0,2000) : (1,9999)
            valid = all(n -> lo <= n <= hi, ns) && length(unique(ns)) == length(ns)
            values[key] = ns
        end
        valid || bad("bad value for $key")
    end
    p, w, k = values["PROTOCOL"], values["WINDOW"], values["SEQBITS"]
    p == "SR" && haskey(raw, "DUPACK") && bad("DUPACK not supported for SR")
    limit = p == "SW" ? 1 : p == "GBN" ? 2^k - 1 : 2^(k - 1)
    unsafe = get(values, "UNSAFE", "OFF") == "ON" && p != "SW"
    w > limit && !unsafe && bad("window $w exceeds limit $limit for $p")
    for (lost, corrupt, kind) in (("LOSEDATA", "CORRUPTDATA", "data"), ("LOSECTRL", "CORRUPTCTRL", "control"))
        common = intersect(get(values, lost, Int[]), get(values, corrupt, Int[]))
        isempty(common) || bad("$kind #$(minimum(common)) both lost and corrupted")
    end
    defaults = Dict{String,Union{Int,String}}("INTERVAL"=>0, "MAXTICKS"=>1000, "NAK"=>"OFF", "BACKOFF"=>"OFF", "CONGESTION"=>"OFF", "UNSAFE"=>"OFF", "TRACE"=>"ALL")
    for (key, value) in defaults
        get!(values, key, value)
    end
    for key in ("LOSEDATA", "LOSECTRL", "CORRUPTDATA", "CORRUPTCTRL", "SNAPSHOT")
        get!(values, key, Int[])
    end
    for key in ("DELAYDATA", "DELAYCTRL")
        get!(values, key, Dict{Int,Int}())
    end
    values
end
function decimal(x::Int, y::Int, digits::Int)
    scale = 10^digits
    value = div(scale * x, y)
    string(div(value, scale), ".", lpad(string(mod(value, scale)), digits, '0'))
end
struct Transit
    number::Int
    value::Int
    kind::String
    outcome::String
end
struct Result
    name::String
    protocol::String
    status::String
    delivered::Int
    completion::Int
    data::Int
end
function simulate(name, c)
    p, n, w, k, T, d = (c[x] for x in KEYS[1:6])
    M = 2^k
    g, L = c["INTERVAL"], c["MAXTICKS"]
    sr = p == "SR"
    congestion = c["CONGESTION"] == "ON"
    trace = c["TRACE"]
    println("config: $p n=$n w=$w k=$k T=$T d=$d")
    randomtext = haskey(c, "RANDOM") ? join(c["RANDOM"], "/") : "off"
    duptext = haskey(c, "DUPACK") ? string(c["DUPACK"]) : "off"
    println("options: interval=$g limit=$L dupack=$duptext nak=$(lowercase(c["NAK"])) backoff=$(lowercase(c["BACKOFF"])) congestion=$(lowercase(c["CONGESTION"])) unsafe=$(lowercase(c["UNSAFE"])) trace=$(lowercase(trace)) random=$randomtext")
    base = H = next = D = r = A = 0
    C = T
    timer = -1
    cwnd, threshold = 1, w
    nakmark = false
    marks = falses(n)
    timers = fill(-1, n)
    queue = Int[]
    buffer = Dict{Int,Int}()
    tx = zeros(Int, n)
    first = fill(-1, n)
    delivered = fill(-1, n)
    acked = fill(-1, n)
    dataevents = [Transit[] for _ in 0:(L + 60)]
    controlevents = [Transit[] for _ in 0:(L + 60)]
    stats = Dict(key=>0 for key in ("data", "resent", "control", "nak", "timeouts", "fastretx", "lost_data", "lost_ctrl", "corrupt_data", "corrupt_ctrl", "delivered", "errors", "discarded", "max_buffer"))
    x = haskey(c, "RANDOM") ? c["RANDOM"][1] : 1
    latency = 0
    completion = -1
    tend = L
    tick = 0
    function emit(side, text)
        (side == "ALWAYS" || trace == "ALL" || trace == side) && println("$tick $text")
    end
    function outcome(kind, number)
        result = "normal"
        if haskey(c, "RANDOM")
            x = mod(48271x, 2147483647)
            v = mod(x, 100)
            loss, corrupt = c["RANDOM"][2:3]
            result = v < loss ? "LOST" : v < loss + corrupt ? "CORRUPT" : "normal"
        end
        key = kind == "data" ? "DATA" : "CTRL"
        number in c["LOSE" * key] && (result = "LOST")
        number in c["CORRUPT" * key] && (result = "CORRUPT")
        result
    end
    function control(kind, value)
        stats["control"] += 1
        j = stats["control"]
        kind == "NAK" && (stats["nak"] += 1)
        emit("RECEIVER", "$kind a=$value #$j")
        arrival = tick + d + get(c["DELAYCTRL"], j, 0)
        push!(controlevents[arrival + 1], Transit(j, value, kind, outcome(kind, j)))
    end
    function deliver(payload)
        if payload == r
            emit("RECEIVER", "DELIVER f=$r")
            stats["delivered"] += 1
            delivered[r + 1] = tick
            latency += tick - first[payload + 1]
        else
            emit("RECEIVER", "DELIVER f=$r wrong=$payload")
            stats["errors"] += 1
        end
        r += 1
        nakmark = false
    end
    function discard(seq)
        stats["discarded"] += 1
        emit("RECEIVER", "DISCARD seq=$seq")
    end
    function goback()
        next, timer, D = base, -1, 0
    end
    function increase(count)
        congestion || return
        for _ in 1:count
            cwnd >= w && continue
            if cwnd < threshold
                cwnd += 1
            else
                A += 1
                if A == cwnd
                    cwnd += 1
                    A = 0
                end
            end
        end
    end
    function decrease(timeout)
        congestion || return
        threshold = max(div(cwnd, 2), 1)
        cwnd = timeout ? 1 : threshold
        A = 0
    end
    function cwndline(old)
        congestion && old != (cwnd, threshold) && emit("SENDER", "CWND $cwnd ssthresh=$threshold")
    end
    for t in 0:L
        tick = t
        for e in sort(dataevents[t + 1]; by=e -> e.number)
            if e.outcome != "normal"
                stats[e.outcome == "LOST" ? "lost_data" : "corrupt_data"] += 1
                emit("RECEIVER", "$(e.outcome) data #$(e.number)")
                continue
            end
            seq = mod(e.value, M)
            emit("RECEIVER", "RECV seq=$seq #$(e.number)")
            if !sr
                if seq == mod(r, M)
                    deliver(e.value)
                    control("ACK", seq)
                else
                    discard(seq)
                    if c["NAK"] == "ON" && !nakmark
                        control("NAK", mod(r, M))
                        nakmark = true
                    elseif r > 0
                        control("ACK", mod(r - 1, M))
                    end
                end
            else
                o = mod(seq - r, M)
                if o < w
                    pos = r + o
                    if haskey(buffer, pos)
                        discard(seq)
                        control("ACK", seq)
                    elseif o == 0
                        deliver(e.value)
                        while haskey(buffer, r)
                            deliver(pop!(buffer, r))
                        end
                        control("ACK", seq)
                    else
                        buffer[pos] = e.value
                        stats["max_buffer"] = max(stats["max_buffer"], length(buffer))
                        emit("RECEIVER", "BUFFER f=$pos")
                        control("ACK", seq)
                        if c["NAK"] == "ON" && !nakmark
                            control("NAK", mod(r, M))
                            nakmark = true
                        end
                    end
                else
                    discard(seq)
                    mod(r - seq, M) <= w && control("ACK", seq)
                end
            end
        end
        for e in sort(controlevents[t + 1]; by=e -> e.number)
            kind, value, j = e.kind, e.value, e.number
            if e.outcome != "normal"
                stats[e.outcome == "LOST" ? "lost_ctrl" : "corrupt_ctrl"] += 1
                emit("SENDER", "$(e.outcome) $(lowercase(kind)) #$j")
                continue
            end
            old = (cwnd, threshold)
            oldbase = base
            f = base + mod(value - base, M)
            accepted = false
            if kind == "ACK"
                if !sr && f < H
                    accepted = true
                    base = f + 1
                    next = max(next, base)
                elseif sr && f < H && !marks[f + 1]
                    accepted = true
                    marks[f + 1] = true
                    acked[f + 1] < 0 && (acked[f + 1] = t)
                    timers[f + 1] = -1
                    filter!(!=(f), queue)
                    while base < H && marks[base + 1]
                        base += 1
                    end
                end
            elseif !sr && f <= H
                accepted = true
                base = f
                goback()
            elseif sr && f < H && !marks[f + 1]
                accepted = true
                timers[f + 1] = -1
                f in queue || push!(queue, f)
            end
            if base > oldbase
                C = T
                !sr && (D = 0)
                if !sr
                    for a in oldbase:(base - 1)
                        acked[a + 1] < 0 && (acked[a + 1] = t)
                    end
                end
            end
            if accepted
                newly = sr ? (kind == "ACK" ? 1 : 0) : base - oldbase
                increase(newly)
                if !sr && kind == "ACK"
                    timer = base == next ? -1 : t + C
                end
                kind == "NAK" && decrease(false)
                emit("SENDER", "GOT$kind a=$value #$j base=$base")
            else
                emit("SENDER", "OLD$kind a=$value #$j")
                if !sr && kind == "ACK" && haskey(c, "DUPACK") && base >= 1 && value == mod(base - 1, M)
                    D += 1
                    if D == c["DUPACK"]
                        stats["fastretx"] += 1
                        emit("SENDER", "FASTRETX f=$base")
                        goback()
                        decrease(false)
                    end
                end
            end
            cwndline(old)
        end
        done = base == n
        if !done
            expired = sr ? [f for f in base:(H - 1) if timers[f + 1] == t] : timer == t ? [base] : Int[]
            for f in expired
                old = (cwnd, threshold)
                stats["timeouts"] += 1
                emit("SENDER", "TIMEOUT f=$f")
                if sr
                    timers[f + 1] = -1
                    push!(queue, f)
                else
                    goback()
                end
                c["BACKOFF"] == "ON" && (C = min(2C, 8T))
                decrease(true)
                cwndline(old)
            end
            E = congestion ? min(w, cwnd) : w
            send = -1
            if sr
                if !isempty(queue)
                    send = popfirst!(queue)
                elseif H < n && H < base + E && H * g <= t
                    send = H
                    H += 1
                end
            elseif next < n && next < base + E && (next < H || next * g <= t)
                send = next
                H = max(H, next + 1)
                next += 1
            end
            if send >= 0
                stats["data"] += 1
                i = stats["data"]
                word = tx[send + 1] == 0 ? "SEND" : "RESEND"
                if word == "SEND"
                    first[send + 1] = t
                else
                    stats["resent"] += 1
                end
                tx[send + 1] += 1
                emit("SENDER", "$word f=$send seq=$(mod(send, M)) #$i")
                arrival = t + d + get(c["DELAYDATA"], i, 0)
                push!(dataevents[arrival + 1], Transit(i, send, "data", outcome("data", i)))
                if sr
                    timers[send + 1] = t + C
                elseif timer < 0
                    timer = t + C
                end
            end
        end
        if t in c["SNAPSHOT"]
            E = congestion ? min(w, cwnd) : w
            sx, rx = Char[], Char[]
            for f in 0:(n - 1)
                acknowledged = sr ? marks[f + 1] : f < base
                waiting = sr ? f in queue : next <= f < H
                sent = sr ? f < H : f < next
                push!(sx, acknowledged ? 'A' : waiting ? 'R' : sent ? 'O' : f < base + E ? 'W' : '.')
                push!(rx, f < r ? 'D' : sr && haskey(buffer, f) ? 'B' : (sr ? f < r + w : f == r) ? 'W' : '.')
            end
            emit("ALWAYS", "SNAPSHOT sender=$(join(sx)) receiver=$(join(rx))")
        end
        if done || t == L
            emit("ALWAYS", done ? "DONE" : "ABORT")
            completion = done ? t : -1
            tend = t
            break
        end
    end
    text(v) = v < 0 ? "-" : string(v)
    for f in 0:(n - 1)
        println("frame $f: seq=$(mod(f, M)) tx=$(tx[f + 1]) first=$(text(first[f + 1])) delivered=$(text(delivered[f + 1])) acked=$(text(acked[f + 1]))")
    end
    for (prefix, keys) in (("totals", ["data", "resent", "control", "nak", "timeouts", "fastretx"]), ("channel", ["lost_data", "lost_ctrl", "corrupt_data", "corrupt_ctrl"]), ("receiver", ["delivered", "errors", "discarded", "max_buffer"]))
        println("$prefix: ", join(("$key=$(stats[key])" for key in keys), " "))
    end
    Dgood, X = stats["delivered"], stats["data"]
    goodput = completion < 0 ? "-" : decimal(Dgood, completion, 2)
    lag = Dgood == 0 ? "-" : decimal(latency, Dgood, 2)
    println("result: completion=$(text(completion)) goodput=$goodput efficiency=$(decimal(100Dgood, X, 1))% utilization=$(decimal(100X, tend + 1, 1))% latency=$lag")
    Result(name, p, completion < 0 ? "aborted" : "done", Dgood, completion, X)
end
function main()
    q = parse(Int, readline())
    results = Result[]
    for _ in 1:q
        name = String(split(readline())[2])
        lines = Vector{String}[]
        while true
            line = readline()
            line == "END" && break
            push!(lines, String.(split(line)))
        end
        println("== $name ==")
        try
            c = configure(lines)
            push!(results, simulate(name, c))
        catch e
            e isa SettingsError || rethrow()
            println("error: ", e.text)
            push!(results, Result(name, "", "invalid", 0, -1, 0))
        end
    end
    println("== ranking ==")
    completed = filter(r -> r.status == "done", results)
    function better(a, b)
        left, right = a.delivered * b.completion, b.delivered * a.completion
        left != right && return left > right
        a.delivered * b.data > b.delivered * a.data
    end
    sort!(completed; lt=better, alg=MergeSort)
    for (i, r) in enumerate(completed)
        println("$i. $(r.name) $(r.protocol) goodput=$(decimal(r.delivered, r.completion, 2)) efficiency=$(decimal(100r.delivered, r.data, 1))%")
    end
    for r in results
        r.status != "done" && println("- $(r.name) $(r.status)")
    end
    println("== protocols ==")
    for p in ("SW", "GBN", "SR")
        runs = filter(r -> r.protocol == p, completed)
        isempty(runs) && continue
        D, T, X = sum(r.delivered for r in runs), sum(r.completion for r in runs), sum(r.data for r in runs)
        println("$p: runs=$(length(runs)) goodput=$(decimal(D, T, 2)) efficiency=$(decimal(100D, X, 1))%")
    end
end
main()
