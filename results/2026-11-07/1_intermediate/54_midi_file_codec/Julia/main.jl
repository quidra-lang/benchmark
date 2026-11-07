using Printf

mutable struct Event
    tick::Int64
    status::Int
    meta::Int
    data::Vector{Int}
end
mutable struct Song
    format::Int
    division::Int64
    tracks::Vector{Vector{Event}}
end
struct Placed
    event::Event
    track::Int
    order::Int
end
struct Note
    on::Placed
    off::Placed
    length::Int64
end
struct ParseFailure <: Exception
    position::Int
    reason::String
end
const CHANNEL_NAMES = ["NOTE_OFF", "NOTE_ON", "POLY_PRESSURE", "CONTROL", "PROGRAM", "CHANNEL_PRESSURE", "PITCH_BEND"]
const META_NAMES = Dict(0=>"SEQUENCE_NUMBER", 1=>"TEXT_EVENT", 2=>"COPYRIGHT", 3=>"TRACK_NAME", 4=>"INSTRUMENT_NAME", 5=>"LYRIC", 6=>"MARKER", 7=>"CUE_POINT", 32=>"CHANNEL_PREFIX", 47=>"END_OF_TRACK", 81=>"TEMPO", 84=>"SMPTE_OFFSET", 88=>"TIME_SIGNATURE", 89=>"KEY_SIGNATURE", 127=>"SEQUENCER_SPECIFIC")
const META_CODES = Dict(name=>code for (code, name) in META_NAMES)
const KEY_NAMES = [
    ["Cb", "Gb", "Db", "Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#"],
    ["Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#", "G#", "D#", "A#"]
]
number(s) = parse(Int64, s)
channel(e) = e.status % 16 + 1
ismeta(e, code) = e.status == 255 && e.meta == code
ison(e) = e.status ÷ 16 == 9 && e.data[2] > 0
isoff(e) = e.status ÷ 16 == 8 || (e.status ÷ 16 == 9 && e.data[2] == 0)
eot(tick) = Event(tick, 255, 47, Int[])
note_name(n) = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"][n % 12 + 1] * string(n ÷ 12 - 1)
function kind(e)
    e.status < 240 && return CHANNEL_NAMES[e.status ÷ 16 - 7]
    e.status == 240 && return "SYSEX"
    e.status == 247 && return "SYSEX_ESCAPE"
    get(META_NAMES, e.meta, "META")
end
function bigendian(data)
    value = Int64(0)
    for b in data
        value = value * 256 + b
    end
    value
end
function bytes_be(value, size)
    result = zeros(Int, size)
    for i in size:-1:1
        result[i] = mod(value, 256)
        value = fld(value, 256)
    end
    result
end
function song_summary(s)
    count = sum(length, s.tracks)
    "format $(s.format) tracks $(length(s.tracks)) division $(s.division) events $count"
end
song_length(s) = maximum(track[end].tick for track in s.tracks)
function ordered(s)
    items = [(e.tick, t, i, e) for (t, track) in enumerate(s.tracks) for (i, e) in enumerate(track)]
    sort!(items; by=x -> x[1:3])
    [Placed(item[4], item[2]-1, i-1) for (i, item) in enumerate(items)]
end
function event_line(e, track)
    fields = [string(e.tick), string(track), kind(e)]
    d = e.data
    if e.status < 240
        push!(fields, string(channel(e)))
        high = e.status ÷ 16
        if high in (8, 9, 10)
            append!(fields, [note_name(d[1]), string(d[2])])
        elseif high == 14
            push!(fields, string(d[1] + 128*d[2] - 8192))
        else
            append!(fields, string.(d))
        end
    elseif e.status == 255 && 1 <= e.meta <= 7
        push!(fields, "\"" * String(UInt8.(d)) * "\"")
    elseif ismeta(e, 0) || ismeta(e, 81)
        push!(fields, string(bigendian(d)))
    elseif ismeta(e, 32)
        push!(fields, string(d[1]+1))
    elseif ismeta(e, 47)
    elseif ismeta(e, 84)
        append!(fields, string.(d))
    elseif ismeta(e, 88)
        append!(fields, ["$(d[1])/$(1 << d[2])", string(d[3]), string(d[4])])
    elseif ismeta(e, 89)
        sf = d[1] >= 128 ? d[1]-256 : d[1]
        append!(fields, [KEY_NAMES[d[2]+1][sf+8], d[2] == 0 ? "major" : "minor"])
    else
        e.status == 255 && e.meta != 127 && push!(fields, @sprintf("%02X", e.meta))
        push!(fields, string(length(d)))
        !isempty(d) && push!(fields, join([@sprintf("%02X", b) for b in d]))
    end
    join(fields, " ")
end
function parse_hex(data)
    fail(pos, reason) = throw(ParseFailure(pos, reason))
    function chunk(pos, id)
        length(data)-pos < 8 && fail(pos, "truncated chunk")
        String(UInt8.(data[pos+1:pos+4])) != id && fail(pos, "bad chunk id")
        len = bigendian(data[pos+5:pos+8])
        pos+8+len > length(data) && fail(pos, "truncated chunk")
        pos+8, pos+8+len
    end
    start, finish = chunk(0, "MThd")
    finish-start != 6 && fail(4, "bad header length")
    f, count, division = bigendian(data[9:10]), bigendian(data[11:12]), bigendian(data[13:14])
    f > 2 && fail(8, "bad format")
    (count == 0 || f == 0 && count != 1) && fail(10, "bad track count")
    division >= 32768 && fail(12, "smpte timing not supported")
    division == 0 && fail(12, "bad division")
    s = Song(f, division, Vector{Event}[])
    pos = finish
    for t in 1:count
        pos == length(data) && fail(pos, "missing track")
        start, finish = chunk(pos, "MTrk")
        pos = start
        tick = Int64(0)
        running = 0
        track = Event[]
        while pos < finish
            !isempty(track) && ismeta(track[end], 47) && fail(pos, "event after end of track")
            event_start = pos
            function readbyte()
                pos >= finish && fail(event_start, "truncated event")
                pos += 1
                data[pos]
            end
            function vlq()
                at = pos
                value = Int64(0)
                for i in 1:4
                    b = readbyte()
                    value = value*128 + (b & 127)
                    b < 128 && return value
                end
                fail(at, "variable-length value too long")
            end
            tick += vlq()
            status_pos = pos
            pos >= finish && fail(event_start, "truncated event")
            status = data[pos+1]
            if status < 128
                running == 0 && fail(pos, "data byte without running status")
                status = running
            else
                pos += 1
            end
            e = Event(tick, status, 0, Int[])
            if status < 240
                running = status
                n = status ÷ 16 in (12, 13) ? 1 : 2
                for j in 1:n
                    at = pos
                    b = readbyte()
                    b >= 128 && fail(at, "bad data byte")
                    push!(e.data, b)
                end
            elseif status in (240, 247, 255)
                running = 0
                status == 255 && (e.meta = readbyte())
                len = vlq()
                pos+len > finish && fail(event_start, "truncated event")
                e.data = data[pos+1:pos+len]
                pos += len
                if status == 255
                    sizes = Dict(0=>2, 32=>1, 47=>0, 81=>3, 84=>5, 88=>4, 89=>2)
                    haskey(sizes, e.meta) && sizes[e.meta] != len && fail(status_pos, "bad meta length")
                    d = e.data
                    bad = e.meta == 81 && bigendian(d) == 0
                    bad |= e.meta == 32 && d[1] > 15
                    bad |= e.meta == 88 && (d[1] == 0 || d[2] > 6)
                    if e.meta == 89
                        sf = d[1] >= 128 ? d[1]-256 : d[1]
                        bad |= !( -7 <= sf <= 7 ) || d[2] > 1
                    end
                    bad && fail(status_pos, "bad meta data")
                end
            else
                fail(status_pos, "unknown status byte")
            end
            push!(track, e)
        end
        (isempty(track) || !ismeta(track[end], 47)) && fail(finish, "missing end of track")
        push!(s.tracks, track)
        pos = finish
    end
    pos < length(data) && fail(pos, "extra data")
    s
end
function parse_text(lines)
    lineno = 1
    fail(reason) = throw(ParseFailure(lineno, reason))
    require(ok) = ok || fail("bad value")
    h = split(lines[1])
    (length(h) != 4 || h[1] != "HEADER") && fail("bad header")
    f, count, division = number.(h[2:4])
    !(0 <= f <= 2 && 1 <= count <= 65535 && 1 <= division <= 32767 && (f != 0 || count == 1)) && fail("bad header")
    s = Song(f, division, [Event[] for _ in 1:count])
    current = 1
    for (i, line) in enumerate(lines[2:end])
        lineno = i+1
        w = split(line, ' '; limit=4)
        tick, track, name = number(w[1]), number(w[2])+1, w[3]
        fields = length(w) == 4 ? String.(split(w[4], ' ')) : String[]
        index = findfirst(==(name), CHANNEL_NAMES)
        known = haskey(META_CODES, name)
        (isnothing(index) && !known && !(name in ("META", "SYSEX", "SYSEX_ESCAPE"))) && fail("unknown event type")
        e = Event(tick, 255, 0, Int[])
        function value(at, lo, hi)
            require(at <= length(fields))
            n = number(fields[at])
            require(lo <= n <= hi)
            n
        end
        if !isnothing(index)
            n = index in (5, 6, 7) ? 2 : 3
            require(length(fields) == n)
            e.status = (index+7)*16 + value(1, 1, 16)-1
            if index <= 3
                pitch = findfirst(p -> note_name(p) == fields[2], 0:127)
                require(!isnothing(pitch))
                e.data = [pitch-1, value(3, 0, 127)]
            elseif index == 7
                bend = value(2, -8192, 8191)+8192
                e.data = [bend % 128, bend ÷ 128]
            else
                e.data = [value(j, 0, 127) for j in 2:n]
            end
        elseif known && 1 <= META_CODES[name] <= 7
            require(length(w) == 4)
            text = w[4]
            require(length(text) >= 2 && startswith(text, '"') && endswith(text, '"'))
            require(!occursin('"', text[2:end-1]))
            e.meta = META_CODES[name]
            e.data = Int.(codeunits(text[2:end-1]))
        elseif name in ("META", "SYSEX", "SYSEX_ESCAPE", "SEQUENCER_SPECIFIC")
            if name == "SYSEX"
                e.status = 240
            elseif name == "SYSEX_ESCAPE"
                e.status = 247
            elseif name == "META"
                require(length(fields) >= 2 && occursin(r"^[0-9A-F]{2}$", fields[1]))
                e.meta = parse(Int, fields[1]; base=16)
                require(!haskey(META_NAMES, e.meta))
                fields = fields[2:end]
            else
                e.meta = 127
            end
            len = value(1, 0, 1000000)
            if len == 0
                require(length(fields) == 1)
            else
                require(length(fields) == 2 && length(fields[2]) == len*2)
                require(occursin(r"^[0-9A-F]+$", fields[2]))
                e.data = [parse(Int, fields[2][j:j+1]; base=16) for j in 1:2:length(fields[2])]
            end
        else
            e.meta = META_CODES[name]
            if e.meta == 0
                require(length(fields) == 1)
                e.data = bytes_be(value(1, 0, 65535), 2)
            elseif e.meta == 32
                require(length(fields) == 1)
                e.data = [value(1, 1, 16)-1]
            elseif e.meta == 47
                require(isempty(fields))
            elseif e.meta == 81
                require(length(fields) == 1)
                e.data = bytes_be(value(1, 1, 16777215), 3)
            elseif e.meta == 84
                require(length(fields) == 5)
                e.data = [value(j, 0, 255) for j in 1:5]
            elseif e.meta == 88
                require(length(fields) == 3)
                fraction = number.(split(fields[1], '/'))
                nn, dd = fraction
                exponent = findfirst(j -> dd == 1 << j, 0:6)
                require(1 <= nn <= 255 && !isnothing(exponent))
                e.data = [nn, exponent-1, value(2, 0, 255), value(3, 0, 255)]
            elseif e.meta == 89
                require(length(fields) == 2)
                found = false
                for mi in 0:1, sf in -7:7
                    if fields == [KEY_NAMES[mi+1][sf+8], mi == 0 ? "major" : "minor"]
                        e.data = [mod(sf, 256), mi]
                        found = true
                    end
                end
                require(found)
            end
        end
        track > count && fail("bad track")
        row = s.tracks[current]
        ended = !isempty(row) && ismeta(row[end], 47)
        track < current && fail("out of order")
        track > current && (!ended || track > current+1) && fail("missing end of track")
        track == current && ended && fail("event after end of track")
        if track == current+1
            current += 1
            row = s.tracks[current]
        end
        !isempty(row) && tick < row[end].tick && fail("out of order")
        push!(row, e)
    end
    lineno = length(lines)+1
    (current < count || isempty(s.tracks[current]) || !ismeta(s.tracks[current][end], 47)) && fail("missing end of track")
    s
end
function vlq(value)
    data = [value % 128]
    value ÷= 128
    while value > 0
        pushfirst!(data, (value % 128) | 128)
        value ÷= 128
    end
    data
end
function encode(s, running, zero)
    result = [Int.(codeunits("MThd")); bytes_be(6, 4); bytes_be(s.format, 2); bytes_be(length(s.tracks), 2); bytes_be(s.division, 2)]
    for track in s.tracks
        data = Int[]
        last = Int64(0)
        status = 0
        for e in track
            append!(data, vlq(e.tick-last))
            last = e.tick
            st, body = e.status, e.data
            if zero && st ÷ 16 == 8
                st += 16
                body = [body[1], 0]
            end
            if st < 240
                (!running || status != st) && push!(data, st)
                append!(data, body)
                status = st
            else
                status = 0
                push!(data, st)
                st == 255 && push!(data, e.meta)
                append!(data, vlq(length(body)))
                append!(data, body)
            end
        end
        append!(result, [Int.(codeunits("MTrk")); bytes_be(length(data), 4); data])
    end
    result
end
function pairing(s)
    queues = Dict{Tuple{Int,Int},Vector{Placed}}()
    notes = Note[]
    unmatched = Placed[]
    for p in ordered(s)
        e = p.event
        !(ison(e) || isoff(e)) && continue
        queue = get!(queues, (channel(e), e.data[1]), Placed[])
        if ison(e)
            push!(queue, p)
        elseif isempty(queue)
            push!(unmatched, p)
        else
            on = popfirst!(queue)
            push!(notes, Note(on, p, e.tick-on.event.tick))
        end
    end
    for queue in values(queues)
        append!(unmatched, queue)
    end
    sort!(notes; by=n -> (n.on.event.tick, channel(n.on.event), n.on.event.data[1], n.on.order))
    sort!(unmatched; by=p -> p.order)
    notes, unmatched
end
function time_at(s, tick)
    total, last, tempo = Int64(0), Int64(0), Int64(500000)
    for p in ordered(s)
        e = p.event
        e.tick > tick && break
        if ismeta(e, 81)
            total += (e.tick-last)*tempo
            last, tempo = e.tick, bigendian(e.data)
        end
    end
    usec = (total+(tick-last)*tempo) ÷ s.division
    @sprintf("%d.%03d", usec ÷ 1000, usec % 1000)
end
function bar_at(s, tick)
    start, bar, nn, beat = Int64(0), Int64(1), Int64(4), s.division
    for p in ordered(s)
        e = p.event
        e.tick > tick && break
        if ismeta(e, 88)
            size = nn*beat
            bar += (e.tick-start+size-1) ÷ size
            start = e.tick
            nn = e.data[1]
            beat = s.division*4 ÷ (1 << e.data[2])
        end
    end
    x = tick-start
    "$(bar+x ÷ (nn*beat)):$(x % (nn*beat) ÷ beat+1):$(x % beat)"
end
function execute(words, songs, settings)
    cmd, a = words[1], words[2:end]
    commands = ["DECODE", "ENCODE", "TIMING", "NOTES", "STATS", "ROLL", "TRANSPOSE", "QUANTIZE", "VELOCITY", "TEMPO", "FILTER", "MERGE", "SPLIT", "COPY", "LIST", "RUNNING", "NOTEOFF"]
    if !(cmd in commands)
        println("error: unknown command")
        return
    elseif cmd == "LIST"
        for name in sort(collect(keys(songs)))
            println(name, " ", song_summary(songs[name]))
        end
        isempty(songs) && println("no songs")
        return
    elseif cmd in ("RUNNING", "NOTEOFF")
        if !(a[1] in (cmd == "RUNNING" ? ("ON", "OFF") : ("ZERO", "KEEP")))
            println("error: bad argument")
        else
            settings[cmd] = a[1]
            println(lowercase(cmd), " ", lowercase(a[1]))
        end
        return
    elseif !haskey(songs, a[1])
        println("error: no song ", a[1])
        return
    end
    s = songs[a[1]]
    args = cmd == "COPY" ? Int64[] : number.(a[2:end])
    valid = true
    if cmd == "TRANSPOSE"
        valid = -127 <= args[1] <= 127 && (length(args) == 1 || 1 <= args[2] <= 16)
    elseif cmd == "QUANTIZE"
        valid = 1 <= args[1] <= 1000000 && 0 <= args[2] <= 100
    elseif cmd == "VELOCITY"
        valid = 0 <= args[1] <= 1000 && -127 <= args[2] <= 127
    elseif cmd == "TEMPO"
        valid = all(x -> 1 <= x <= 1000, args)
    elseif cmd == "FILTER"
        valid = all(x -> 1 <= x <= 16, args)
    elseif cmd == "ROLL"
        valid = 0 <= args[1] <= 10000000 && 1 <= args[2] <= 10000000 && 1 <= args[3] <= 10000000 && args[2] > args[1]
        valid && (valid = cld(args[2]-args[1], args[3]) <= 64)
    end
    if !valid
        println("error: bad argument")
    elseif cmd in ("TIMING", "STATS") && s.format == 2
        println("error: format 2 not supported")
    elseif cmd == "MERGE" && s.format != 1
        println("error: not format 1")
    elseif cmd == "SPLIT" && s.format != 0
        println("error: not format 0")
    elseif cmd == "COPY"
        songs[a[2]] = deepcopy(s)
        println("copied ", a[1], " to ", a[2])
    elseif cmd == "DECODE"
        println("HEADER $(s.format) $(length(s.tracks)) $(s.division)")
        for (t, track) in enumerate(s.tracks), e in track
            println(event_line(e, t-1))
        end
    elseif cmd == "ENCODE"
        data = encode(s, settings["RUNNING"] == "ON", settings["NOTEOFF"] == "ZERO")
        for i in 1:16:length(data)
            println(@sprintf("%04X: ", i-1), join([@sprintf("%02X", b) for b in data[i:min(i+15, end)]], " "))
        end
        println(length(data), " bytes")
    elseif cmd == "TIMING"
        for p in ordered(s)
            e = p.event
            println("$(e.tick) $(p.track) $(kind(e)) $(time_at(s, e.tick)) $(bar_at(s, e.tick))")
        end
        tick = song_length(s)
        println("end $tick $(time_at(s, tick)) $(bar_at(s, tick))")
    elseif cmd in ("NOTES", "STATS", "ROLL")
        notes, unmatched = pairing(s)
        if cmd == "ROLL"
            columns = cld(args[2]-args[1], args[3])
            found = false
            for pitch in 127:-1:0
                row = fill('.', columns)
                for i in eachindex(row)
                    tick = args[1]+(i-1)*args[3]
                    for n in notes
                        n.on.event.data[1] != pitch && continue
                        start = n.on.event.tick
                        if tick <= start < tick+args[3]
                            row[i] = '#'
                            break
                        elseif start <= tick < start+n.length
                            row[i] = '='
                        end
                    end
                end
                if any(!=('.'), row)
                    println(rpad(note_name(pitch), 4), " ", join(row))
                    found = true
                end
            end
            !found && println("empty")
            return
        end
        cmd == "STATS" && println(song_summary(s))
        println("notes $(length(notes)) unmatched $(length(unmatched))")
        if cmd == "NOTES"
            for n in notes
                e = n.on.event
                println("$(e.tick) $(n.length) $(channel(e)) $(note_name(e.data[1])) $(e.data[2])")
            end
            for p in unmatched
                e = p.event
                println("unmatched $(ison(e) ? "on" : "off") $(e.tick) $(p.track) $(channel(e)) $(note_name(e.data[1]))")
            end
        else
            pitches = Int[]
            for ch in 1:16
                group = [n.on.event.data[1] for n in notes if channel(n.on.event) == ch]
                if !isempty(group)
                    println("channel $ch notes $(length(group)) range $(note_name(minimum(group))) $(note_name(maximum(group)))")
                    append!(pitches, group)
                end
            end
            println(isempty(pitches) ? "range none" : "range $(note_name(minimum(pitches))) $(note_name(maximum(pitches)))")
            println("length $(song_length(s)) ticks $(time_at(s, song_length(s))) ms")
            changes = Dict{Int64,Int}()
            for n in notes
                if n.length > 0
                    start = n.on.event.tick
                    changes[start] = get(changes, start, 0)+1
                    changes[start+n.length] = get(changes, start+n.length, 0)-1
                end
            end
            current, peak, at = 0, 0, Int64(0)
            for tick in sort(collect(keys(changes)))
                current += changes[tick]
                if current > peak
                    peak, at = current, tick
                end
            end
            println(peak == 0 ? "polyphony 0" : "polyphony $peak at $at")
        end
    elseif cmd == "TRANSPOSE"
        kept = 0
        dropped = String[]
        for (t, track) in enumerate(s.tracks)
            row = Event[]
            for e in track
                if e.status < 176 && (length(args) == 1 || channel(e) == args[2])
                    pitch = e.data[1]+args[1]
                    if !(0 <= pitch <= 127)
                        push!(dropped, "dropped $(e.tick) $(t-1) $(kind(e)) $(channel(e)) $(note_name(e.data[1]))")
                        continue
                    end
                    e.data[1] = pitch
                    kept += 1
                end
                push!(row, e)
            end
            s.tracks[t] = row
        end
        println("transposed $kept dropped $(length(dropped))")
        foreach(println, dropped)
    elseif cmd == "QUANTIZE"
        notes, unmatched = pairing(s)
        targets = [(n.on.event, n.off.event) for n in notes]
        for p in unmatched
            ison(p.event) && push!(targets, (p.event, p.event))
        end
        moved = 0
        for (on, off) in targets
            grid, strength = args
            lower = on.tick ÷ grid * grid
            target = on.tick-lower <= lower+grid-on.tick ? lower : lower+grid
            delta = fld(2*(target-on.tick)*strength+100, 200)
            moved += delta != 0
            on.tick += delta
            off !== on && (off.tick += delta)
        end
        for (t, track) in enumerate(s.tracks)
            ending = track[end]
            row = track[1:end-1]
            sort!(row; by=e -> e.tick, alg=MergeSort)
            !isempty(row) && (ending.tick = max(ending.tick, row[end].tick))
            s.tracks[t] = [row; ending]
        end
        println("quantized $(length(targets)) moved $moved")
    elseif cmd == "VELOCITY"
        count, clamped = 0, 0
        for track in s.tracks, e in track
            if ison(e)
                count += 1
                v = (e.data[2]*args[1]+50) ÷ 100+args[2]
                clamped += !(1 <= v <= 127)
                e.data[2] = clamp(v, 1, 127)
            end
        end
        println("velocity $count clamped $clamped")
    elseif cmd == "TEMPO"
        trial = deepcopy(s)
        count, exists, good = 0, false, true
        scale(v) = (2*v*args[2]+args[1]) ÷ (2*args[1])
        for track in trial.tracks, e in track
            if ismeta(e, 81)
                count += 1
                exists |= e.tick == 0
                v = scale(bigendian(e.data))
                good &= 1 <= v <= 16777215
                e.data = bytes_be(v, 3)
            end
        end
        inserted = scale(500000)
        if !exists
            good &= 1 <= inserted <= 16777215
            pushfirst!(trial.tracks[1], Event(0, 255, 81, bytes_be(inserted, 3)))
        end
        if !good
            println("error: tempo out of range")
        else
            songs[a[1]] = trial
            println("scaled $count")
            !exists && println("inserted 0 0 TEMPO $inserted")
        end
    elseif cmd == "FILTER"
        count = 0
        for (t, track) in enumerate(s.tracks)
            row = Event[]
            for e in track
                if e.status < 240 && !(channel(e) in args)
                    count += 1
                else
                    push!(row, e)
                end
            end
            s.tracks[t] = row
        end
        println("removed $count")
    elseif cmd == "MERGE"
        original = length(s.tracks)
        tick = song_length(s)
        row = [p.event for p in ordered(s) if !ismeta(p.event, 47)]
        push!(row, eot(tick))
        s.tracks = [row]
        s.format = 0
        println("merged $original tracks events $(length(row))")
    elseif cmd == "SPLIT"
        tick = song_length(s)
        rows = Dict(0=>Event[])
        for e in s.tracks[1]
            ismeta(e, 47) && continue
            ch = e.status < 240 ? channel(e) : 0
            push!(get!(rows, ch, Event[]), e)
        end
        s.tracks = [[rows[ch]; eot(tick)] for ch in sort(collect(keys(rows)))]
        s.format = 1
        println("split tracks $(length(s.tracks)) events $(sum(length, s.tracks))")
    end
end
function main()
    n = parse(Int, readline())
    songs = Dict{String,Song}()
    settings = Dict("RUNNING"=>"ON", "NOTEOFF"=>"KEEP")
    for _ in 1:n
        words = String.(split(readline()))
        if words[1] in ("HEX", "TEXT")
            lines = [readline() for _ in 1:parse(Int, words[3])]
            try
                if words[1] == "HEX"
                    data = [parse(Int, b; base=16) for line in lines for b in split(line)]
                    s = parse_hex(data)
                else
                    s = parse_text(lines)
                end
                songs[words[2]] = s
                println("loaded ", words[2], " ", song_summary(s))
            catch e
                e isa ParseFailure || rethrow()
                label = words[1] == "HEX" ? "byte" : "line"
                println("error: $label $(e.position): $(e.reason)")
            end
        else
            execute(words, songs, settings)
        end
    end
end
main()
