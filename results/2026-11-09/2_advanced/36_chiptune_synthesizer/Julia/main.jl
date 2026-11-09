include("song_parser.jl")
include("instruments.jl")
include("sequencer.jl")
include("mixer.jl")
include("report.jl")

const FMIN = 1000
const LANE_LIMIT = 3375
const EFFECT_ORDER = (
    "0",
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
    "A",
    "B",
    "C",
    "D",
    "E1",
    "E2",
    "E9",
    "EA",
    "EB",
    "EC",
    "ED",
    "EE",
    "F",
    "P",
    "Q",
    "R",
    "V"
)
const TONIC_NAMES = ("C","C#","D","D#","E","F","F#","G","G#","A","A#","B")
const MAJOR_WEIGHTS = (64,22,35,23,44,41,25,52,24,37,23,29)
const MINOR_WEIGHTS = (64,27,35,54,27,35,25,48,40,27,34,32)
hex2(value) = uppercase(string(value,base=16,pad=2))
hex1(value) = uppercase(string(value,base=16))
hex_list(values) = isempty(values) ? "none" : join(hex2.(values),' ')
note_range(notes) = isempty(notes) ? "none" : "$(note_name(minimum(notes)))..$(note_name(maximum(notes)))"
Base.@kwdef mutable struct NoteRecord
    serial::Int
    channel::Int
    position::Int
    row::Int
    instrument::Instrument
    note::Int
    start::Int
    length::Int = 0
    release::Union{Nothing,Int} = nothing
    reason::String = ""
end
Base.@kwdef mutable struct Channel
    number::Int
    instrument::Union{Nothing,Instrument} = nothing
    note::Union{Nothing,Int} = nothing
    frequency::Int = 0
    target::Int = 0
    portamento::Int = 0
    slide::Int = 0
    detune::Int = 0
    vibrato_speed::Int = 0
    vibrato_depth::Int = 0
    vibrato_position::Int = 0
    tremolo_speed::Int = 0
    tremolo_depth::Int = 0
    tremolo_position::Int = 0
    volume::Int = 15
    mode::Int = 0
    phase::Int = 0
    register::Int = 1
    age::Int = 0
    released::Bool = false
    release_age::Int = 0
    release_level::Int = 0
    envelope::Int = 0
    output_frequency::Int = 0
    output_volume::Int = 0
    amplitude::Int = 0
    increment::Int = 0
    effect::Union{Nothing,Effect} = nothing
    sounding::Bool = false
    record::Union{Nothing,NoteRecord} = nothing
    note_ons::Int = 0
    retriggers::Int = 0
    cuts::Int = 0
    active::Int = 0
    audible::Int = 0
end
effect_name(channel) = isnothing(channel.effect) ? "" : channel.effect.name
effect_value(channel) = isnothing(channel.effect) ? 0 : channel.effect.value
function key_off!(channel)
    channel.release_age,channel.release_level,channel.released = channel.age,channel.envelope,true
end
function approach!(channel,step)
    channel.frequency = channel.frequency < channel.target ? min(channel.frequency+step,channel.target) : max(
        channel.frequency-step,
        channel.target
    )
end
volume_slide!(channel) = (channel.volume=clamp(channel.volume+high(channel.effect)-low(channel.effect),0,15))
function update_output!(channel,tick,rate)
    instrument = channel.instrument
    name = effect_name(channel)
    semitones = name == "0" ? (0,high(channel.effect),low(channel.effect))[tick%3+1] : 0
    !isempty(instrument.arpeggio) && (semitones += instrument.arpeggio[channel.age%length(instrument.arpeggio)+1])
    frequency = transpose_frequency(channel.frequency,semitones)+channel.detune
    name in ("4","6") && (frequency += oscillation(channel.vibrato_position,channel.vibrato_depth,4))
    if !isnothing(instrument.vibrato)
        delay,speed,depth = instrument.vibrato
        channel.age >= delay && (frequency += oscillation((channel.age-delay)*speed%64,depth,4))
    end
    channel.output_frequency = clamp(frequency,FMIN,50*rate)
    channel.envelope = envelope_value(
        instrument,
        channel.age,
        channel.released,
        channel.release_age,
        channel.release_level
    )
    channel.output_volume = name == "7" ? clamp(
        channel.volume+oscillation(channel.tremolo_position,channel.tremolo_depth,255),
        0,
        15
    ) : channel.volume
    channel.amplitude = channel.envelope*channel.output_volume
    channel.increment = channel.output_frequency*65536÷(100*rate)
end
Base.@kwdef mutable struct Player
    song::Song
    params::NamedTuple
    channels::Vector{Channel} = [Channel(number=number) for number in 1:CHANNEL_COUNT]
    lanes::Vector{Vector{Int}} = [Int[] for _ in 1:CHANNEL_COUNT]
    samples::Vector{Int} = Int[]
    speed::Int
    tempo::Int
    delay::Int = 0
    position::Int = 0
    row::Int = 0
    cells::Vector{Cell} = Cell[]
    records::Vector{NoteRecord} = NoteRecord[]
    warnings::Vector{String} = String[]
    log::Vector{String} = String[]
    played::Vector{NamedTuple} = NamedTuple[]
    play_counts::Dict{Tuple{Int,Int},Int} = Dict{Tuple{Int,Int},Int}()
    first_starts::Dict{Tuple{Int,Int},Int} = Dict{Tuple{Int,Int},Int}()
    ticks::Int = 0
    clipped::Int = 0
    instrument_ticks::Dict{Int,Int}
    effect_counts::Dict{String,Int} = Dict(name=>0 for name in EFFECT_ORDER)
    end_reason::String = "finished"
    end_row::Union{Nothing,Tuple{Int,Int}} = nothing
    loop_start::Union{Nothing,Int} = nothing
end
warn!(player,channel,message) = push!(
    player.warnings,
    "warning $(hex2(player.position)):$(hex2(player.row)) ch$(channel.number) $message"
)
clamp_frequency(player,frequency) = clamp(frequency,FMIN,50*player.song.rate)
function end_record!(player,channel,reason)
    channel.record.length = length(player.samples)-channel.record.start
    channel.record.reason = reason
    channel.record = nothing
end
function note_on!(player,channel,note)
    !isnothing(channel.record) && end_record!(player,channel,"next")
    channel.frequency,channel.target = note_frequency(note),note_frequency(note)
    channel.phase,channel.age,channel.vibrato_position,channel.tremolo_position = 0,0,0,0
    channel.released,channel.note = false,note
    channel.note_ons += 1
    channel.record = NoteRecord(
        serial=length(player.records)+1,
        channel=channel.number,
        position=player.position,
        row=player.row,
        instrument=channel.instrument,
        note=note,
        start=length(player.samples)
    )
    push!(player.records,channel.record)
end
function apply_cell!(player,channel,cell,portamento)
    if !isnothing(cell.instrument)
        instrument = get(player.song.instruments,cell.instrument,nothing)
        if isnothing(instrument)
            warn!(player,channel,"undefined instrument $(hex2(cell.instrument))")
        else
            channel.instrument,channel.volume,channel.mode = instrument,15,instrument.mode
        end
    end
    !isnothing(cell.volume) && (channel.volume=cell.volume)
    if cell.key_off
        if !isnothing(channel.note) && !channel.released
            key_off!(channel)
            channel.record.release = length(player.samples)-channel.record.start
        else
            warn!(player,channel,"key off without note")
        end
    elseif !isnothing(cell.note)
        if isnothing(channel.instrument)
            warn!(player,channel,"note without instrument")
        elseif portamento && !isnothing(channel.note)
            channel.target,channel.note = note_frequency(cell.note),cell.note
        else
            portamento && warn!(player,channel,"portamento without note")
            note_on!(player,channel,cell.note)
        end
    end
end
function start_effect!(player,channel)
    effect = channel.effect
    name,value = effect.name,effect.value
    if name == "3"
        value > 0 && (channel.portamento=value)
    elseif name == "4"
        high(effect) > 0 && (channel.vibrato_speed=high(effect))
        low(effect) > 0 && (channel.vibrato_depth=low(effect))
    elseif name == "7"
        high(effect) > 0 && (channel.tremolo_speed=high(effect))
        low(effect) > 0 && (channel.tremolo_depth=low(effect))
    elseif name == "C"
        channel.volume = min(value,15)
    elseif name == "E1"
        channel.frequency = clamp_frequency(player,channel.frequency+10*value)
    elseif name == "E2"
        channel.frequency = clamp_frequency(player,channel.frequency-10*value)
    elseif name == "EA"
        channel.volume = min(channel.volume+value,15)
    elseif name == "EB"
        channel.volume = max(channel.volume-value,0)
    elseif name == "EE"
        player.delay = value
    elseif name == "F"
        1 <= value <= 31 && (player.speed=value)
        value >= 32 && (player.tempo=value)
    elseif name == "P"
        channel.detune = value-128
    elseif name in ("Q","R")
        if isnothing(channel.note)
            warn!(player,channel,"slide without note")
        else
            channel.note = name == "Q" ? min(channel.note+low(effect),95) : max(channel.note-low(effect),12)
            channel.target = note_frequency(channel.note)
            channel.slide = 2*high(effect)+1
        end
    elseif name == "V"
        instrument = channel.instrument
        if !isnothing(instrument) && ((instrument.wave == "PULSE" && value <= 3) || (instrument.wave == "NOISE" && value <= 1))
            channel.mode = value
        else
            warn!(player,channel,"invalid mode $(hex2(value))")
        end
    end
end
function tick_effect!(player,channel)
    name,value = channel.effect.name,channel.effect.value
    if name == "1"
        channel.frequency = clamp_frequency(player,channel.frequency+10*value)
    elseif name == "2"
        channel.frequency = clamp_frequency(player,channel.frequency-10*value)
    elseif name in ("3","5")
        approach!(channel,10*channel.portamento)
        name == "5" && volume_slide!(channel)
    elseif name in ("6","A")
        volume_slide!(channel)
    elseif name in ("Q","R") && channel.slide != 0
        approach!(channel,10*channel.slide)
    end
end
function start_row!(player)
    player.delay = 0
    for (channel,cell) in zip(player.channels,player.cells)
        channel.effect,channel.slide = cell.effect,0
        !isnothing(cell.effect) && (player.effect_counts[cell.effect.name] += 1)
        name = effect_name(channel)
        !(name == "ED" && effect_value(channel) >= 1) && apply_cell!(player,channel,cell,name in ("3","5"))
        !isnothing(channel.effect) && start_effect!(player,channel)
    end
end
function process_tick!(player,tick)
    for (channel,cell) in zip(player.channels,player.cells)
        name,value = effect_name(channel),effect_value(channel)
        if !isnothing(channel.note) && channel.age >= 1 && channel.instrument.sweep != 0
            channel.frequency = clamp_frequency(player,channel.frequency+10*channel.instrument.sweep)
        end
        tick >= 1 && !isnothing(channel.effect) && tick_effect!(player,channel)
        name == "ED" && value >= 1 && tick == value && apply_cell!(player,channel,cell,false)
        if name == "E9" && value >= 1 && tick >= 1 && tick%value == 0 && !isnothing(channel.note)
            channel.phase,channel.age,channel.released = 0,0,false
            channel.retriggers += 1
        end
        if name == "EC" && tick == value && !isnothing(channel.note)
            end_record!(player,channel,"cut")
            channel.note = nothing
            channel.cuts += 1
        end
        channel.sounding = !isnothing(channel.note)
        if channel.sounding
            update_output!(channel,tick,player.song.rate)
            channel.active += 1
            channel.audible += channel.amplitude > 0
            player.instrument_ticks[channel.instrument.number] += 1
        end
    end
end
function advance!(player)
    for channel in player.channels
        !isnothing(channel.note) && (channel.age += 1)
        name = effect_name(channel)
        if name in ("4","6")
            channel.vibrato_position = (channel.vibrato_position+channel.vibrato_speed)%64
        elseif name == "7"
            channel.tremolo_position = (channel.tremolo_position+channel.tremolo_speed)%64
        end
    end
    player.ticks += 1
end
function channel_text(channel)
    effect = isnothing(channel.effect) ? "..." : channel.effect.text
    isnothing(channel.note) && return "--- -- $(lpad("-",7)) - $(hex1(channel.volume)) $effect"
    "$(note_name(channel.note)) $(hex2(channel.instrument.number)) $(lpad(channel.output_frequency,7)) $(hex1(channel.envelope)) $(hex1(channel.output_volume)) $effect"
end
function log_row!(player,start)
    pattern = player.song.order[player.position+1]
    prefix = "$(hex2(player.position)) $(hex2(pattern)) $(hex2(player.row)) $(lpad(start,7)) $(lpad(player.speed,2)) $(lpad(player.tempo,3))"
    push!(player.log,join(vcat([prefix],channel_text.(player.channels))," | "))
    push!(
        player.played,
        (
            position=player.position,
            row=player.row,
            start=start,
            speed=player.speed,
            tempo=player.tempo,
            notes=[channel.note for channel in player.channels]
        )
    )
end
function log_tick!(player,tick)
    parts = ["  tick $(lpad(tick,3)) $(lpad(length(player.samples),7))"]
    for channel in player.channels
        text = channel.sounding ? "$(lpad(channel.output_frequency,7)) $(lpad(channel.increment,5)) $(hex1(channel.envelope))$(hex1(channel.output_volume))" : "$(lpad("-",7)) $(lpad("-",5)) --"
        push!(parts,text)
    end
    push!(player.log,join(parts," | "))
end
function play_row!(player,position,row)
    player.position,player.row = position,row
    player.cells = song_cells(player.song,position,row)
    start = length(player.samples)
    get!(player.first_starts,(position,row),start)
    start_row!(player)
    ticks = player.speed*(1+player.delay)
    for channel in player.channels
        if effect_name(channel) == "EC" && effect_value(channel) >= ticks
            warn!(player,channel,"cut beyond row")
        elseif effect_name(channel) == "ED" && effect_value(channel) >= ticks
            warn!(player,channel,"delay beyond row")
        end
    end
    tick_samples = samples_per_tick(player.song.rate,player.tempo)
    for tick in 0:ticks-1
        process_tick!(player,tick)
        tick == 0 && log_row!(player,start)
        (position,row) in player.params.traces && log_tick!(player,tick)
        count = min(tick_samples,player.params.max_samples-length(player.samples))
        player.clipped += mix_tick!(
            player.channels,
            count,
            player.song.gain,
            player.params.muted,
            player.samples,
            player.lanes
        )
        advance!(player)
        length(player.samples) == player.params.max_samples && return false
    end
    true
end
function play!(player)
    position,row = 0,0
    while true
        key = (position,row)
        player.play_counts[key] = get(player.play_counts,key,0)+1
        if !play_row!(player,position,row)
            player.end_reason = "limit"
            break
        end
        following = next_row(player.song,position,row)
        if isnothing(following)
            player.end_reason,player.end_row = "stop",(position,row)
            break
        end
        position,row = following
        if position >= length(player.song.order)
            player.end_reason = "finished"
            break
        elseif get(player.play_counts,following,0) >= player.params.loops
            player.end_reason,player.end_row = "loop",following
            player.loop_start = player.first_starts[following]
            break
        end
    end
    for channel in player.channels
        !isnothing(channel.record) && end_record!(player,channel,"end")
    end
    player.end_reason in ("limit","loop") && player.params.fade > 0 && fade_out!(
        player.samples,
        player.params.fade
    )
end
end_text(player) = player.end_reason in (
    "stop",
    "loop"
) ? "$(player.end_reason) order=$(hex2(player.end_row[1])) row=$(hex2(player.end_row[2]))" : player.end_reason
function note_lines(player)
    lines = String[]
    for record in player.records
        segment = player.lanes[record.channel][record.start+1:record.start+record.length]
        cycles = sum(segment[i] < 0 <= segment[i+1] for i in 1:length(segment)-1;init=0)
        release = isnothing(record.release) ? "-" : string(record.release)
        push!(
            lines,
            "$(lpad(record.serial,4)) ch=$(record.channel) at=$(hex2(record.position)):$(hex2(record.row)) ins=$(hex2(record.instrument.number)) note=$(note_name(record.note)) start=$(record.start) length=$(record.length) release=$release end=$(record.reason) peak=$(peak(segment,0)) cycles=$cycles"
        )
    end
    lines
end
function roll_lines(played,start,rows)
    targets = played[min(start+1,length(played)+1):min(start+rows,length(played))]
    pitches = sort(unique([note for row in targets for note in row.notes if !isnothing(note)]);rev=true)
    lines = ["ROLL start=$start rows=$(length(targets)) pitches=$(length(pitches))"]
    for pitch in pitches
        marks = String[]
        for row in targets
            owners = findall(==(pitch),row.notes)
            push!(marks,isempty(owners) ? " " : length(owners) == 1 ? string(owners[1]) : "*")
        end
        push!(lines,"$(note_name(pitch)) |$(join(marks))|")
    end
    push!(lines,"    +"*join(i%16 == 0 ? "+" : "-" for i in 0:length(targets)-1)*"+")
    lines
end
function estimate_key(totals)
    keys = Tuple{String,Int}[]
    for (weights,mode) in ((MAJOR_WEIGHTS,"major"),(MINOR_WEIGHTS,"minor")), tonic in 0:11
        score = sum(weights[mod(pitch-tonic,12)+1]*totals[pitch+1] for pitch in 0:11)
        push!(keys,("$(TONIC_NAMES[tonic+1]) $mode",score))
    end
    order = sort(collect(eachindex(keys)),by=i->(-keys[i][2],i))
    keys[order[1]],keys[order[2]]
end
function stats_lines(player)
    song,samples = player.song,player.samples
    total = length(samples)
    lines = [
        "title=$(song.title)",
        "rate=$(song.rate)",
        "samples=$total",
        "duration_ms=$(total*1000÷song.rate)",
        "end=$(end_text(player))"
    ]
    if player.end_reason == "loop"
        append!(lines,["loop_start=$(player.loop_start)","loop_length=$(total-player.loop_start)"])
    else
        append!(lines,["loop_start=-","loop_length=-"])
    end
    append!(
        lines,
        [
            "rows=$(length(player.played))",
            "ticks=$(player.ticks)",
            "clipped=$(player.clipped)",
            "peak=$(peak(samples,128))",
            "min=$(minimum(samples))",
            "max=$(maximum(samples))",
            "rms=$(root_mean_square(samples,128))",
            "zero_crossings=$(zero_crossings(samples))",
            "adler32=$(adler32_text(samples))"
        ]
    )
    positions = Int[]
    for row in player.played
        (isempty(positions) || last(positions) != row.position) && push!(positions,row.position)
    end
    push!(lines,"path "*join(hex2.(positions),' '))
    previous = nothing
    for row in player.played
        timing = (row.speed,row.tempo)
        timing != previous && push!(
            lines,
            "timing sample=$(row.start) order=$(hex2(row.position)) row=$(hex2(row.row)) speed=$(row.speed) tempo=$(row.tempo)"
        )
        previous = timing
    end
    for (channel,lane) in zip(player.channels,player.lanes)
        push!(
            lines,
            "channel $(channel.number) notes=$(channel.note_ons) retriggers=$(channel.retriggers) cuts=$(channel.cuts) active=$(channel.active) audible=$(channel.audible) peak=$(peak(lane,0)) rms=$(root_mean_square(lane,0))"
        )
    end
    for number in sort(collect(keys(song.instruments)))
        instrument = song.instruments[number]
        records = filter(record->record.instrument.number == number,player.records)
        summary = isempty(records) ? "range=none average=-" : "range=$(note_range([r.note for r in records])) average=$(sum(r.length for r in records)÷length(records))"
        push!(
            lines,
            "instrument $(hex2(number)) $(instrument.name) $(instrument.wave) notes=$(length(records)) ticks=$(player.instrument_ticks[number]) $summary"
        )
    end
    for number in sort(collect(keys(song.patterns)))
        pattern = song.patterns[number]
        rows = count(cells->any(!is_empty(cell) for cell in cells),pattern)
        notes = sum(has_note(cell) for cells in pattern for cell in cells)
        push!(lines,"pattern $(hex2(number)) rows=$rows notes=$notes orders=$(count(==(number),song.order))")
    end
    reached = reachable_rows(song)
    for (index,pattern) in enumerate(song.order)
        position = index-1
        starts = [row.start for row in player.played if row.position == position]
        first_start = isempty(starts) ? "-" : string(starts[1])
        dead = sum(!((position,row) in reached) && any(
            has_note,
            song_cells(song,position,row)
        ) for row in 0:63)
        push!(
            lines,
            "order $(hex2(position)) pattern=$(hex2(pattern)) rows=$(length(starts)) first=$first_start dead=$dead"
        )
    end
    notes = sort(unique([record.note for record in player.records]))
    for note in notes
        push!(lines,"note $(note_name(note)) count=$(count(record->record.note == note,player.records))")
    end
    used_effects = ["$name=$(player.effect_counts[name])" for name in EFFECT_ORDER if player.effect_counts[name] > 0]
    push!(lines,"effects "*(isempty(used_effects) ? "none" : join(used_effects,' ')))
    used_instruments = Set(record.instrument.number for record in player.records)
    played_positions = Set(row.position for row in player.played)
    append!(lines,[
        "unused_instruments="*hex_list([number for number in sort(collect(keys(song.instruments))) if !(number in used_instruments)]),
        "unused_patterns="*hex_list([number for number in sort(collect(keys(song.patterns))) if !(number in song.order)]),
        "unreached_orders="*hex_list([position for position in 0:length(song.order)-1 if !(position in played_positions)])
    ])
    totals = zeros(Int,12)
    for record in player.records
        record.instrument.wave != "NOISE" && (totals[record.note%12+1] += record.length)
    end
    push!(lines,"pitch_classes "*join(("$name=$value" for (name,value) in zip(TONIC_NAMES,totals)),' '))
    (best,best_score),(runner_up,runner_score) = estimate_key(totals)
    push!(lines,"key=$best score=$best_score runner_up=$runner_up score=$runner_score")
    for channel in player.channels
        records = filter(record->record.channel == channel.number,player.records)
        parts = ["usage ch$(channel.number) range=$(note_range([r.note for r in records]))"]
        for number in sort(collect(keys(song.instruments)))
            push!(parts,"$(hex2(number))=$(count(record->record.instrument.number == number,records))")
        end
        push!(lines,join(parts,' '))
    end
    append!(lines,player.warnings)
    lines
end
plot_row(value,low,high,height) = (2*(high-value)*(height-1)+(high-low))÷(2*(high-low))
function plot_lines(values,low,high,middle,height,width)
    count = length(values)
    middle_row = plot_row(middle,low,high,height)
    columns = Tuple{Int,Int}[]
    for column in 0:width-1
        covered = values[column*count÷width+1:(column+1)*count÷width]
        push!(columns,(plot_row(maximum(covered),low,high,height),plot_row(minimum(covered),low,high,height)))
    end
    lines = String[]
    for row in 0:height-1
        label = row == 0 ? string(high) : row == middle_row ? string(middle) : row == height-1 ? string(low) : ""
        marks = [top <= row <= bottom ? '#' : row == middle_row ? '-' : ' ' for (top,bottom) in columns]
        push!(lines,"$(lpad(label,5)) |$(join(marks))|")
    end
    lines
end
function axis_lines(start,count,width,rate)
    ruler = join(column%10 == 0 ? "+" : "-" for column in 0:width-1)
    labels = "    ms"
    for column in 0:10:width-1
        milliseconds = (start+column*count÷width)*1000÷rate
        labels = rpad(labels,7+column)*string(milliseconds)
    end
    ["      +$ruler+",labels]
end
function waveform_lines(player)
    params = player.params
    start,count,width = params.window_start,params.window_length,params.window_width
    axes = axis_lines(start,count,width,player.song.rate)
    lines = ["MIX start=$start length=$count width=$width height=$(params.window_height)"]
    append!(lines,plot_lines(player.samples[start+1:start+count],0,255,128,params.window_height,width))
    append!(lines,axes)
    for (channel,lane) in zip(player.channels,player.lanes)
        push!(lines,"CHANNEL $(channel.number)")
        append!(
            lines,
            plot_lines(lane[start+1:start+count],-LANE_LIMIT,LANE_LIMIT,0,params.window_scope,width)
        )
    end
    append!(lines,axes)
    lines
end
function preview_lines(song,params,instrument)
    channel = Channel(
        number=1,
        instrument=instrument,
        mode=instrument.mode,
        note=params.preview_note,
        frequency=note_frequency(params.preview_note),
        target=note_frequency(params.preview_note),
        sounding=true
    )
    tick_samples = samples_per_tick(song.rate,song.tempo)
    samples,envelopes,frequencies = Int[],String[],Int[]
    for tick in 0:params.preview_ticks-1
        channel.age = tick
        tick == params.preview_release && key_off!(channel)
        tick >= 1 && instrument.sweep != 0 && (channel.frequency=clamp(
            channel.frequency+10*instrument.sweep,
            FMIN,
            50*song.rate
        ))
        update_output!(channel,tick,song.rate)
        push!(envelopes,hex1(channel.envelope))
        push!(frequencies,channel.output_frequency)
        mix_tick!([channel],tick_samples,song.gain,[false],samples,[Int[]])
    end
    [
        "instrument $(hex2(instrument.number)) $(instrument.name) wave=$(instrument.wave) samples=$(length(samples)) peak=$(peak(samples,128)) rms=$(root_mean_square(samples,128)) adler32=$(adler32_text(samples))",
        "  env "*join(envelopes),"  freq "*join(frequencies,' ')
    ]
end
function main()
    song = read_song(joinpath("input","song.txt"))
    params = read_params(joinpath("input","params.txt"))
    player = Player(
        song=song,
        params=params,
        speed=song.speed,
        tempo=song.tempo,
        instrument_ticks=Dict(number=>0 for number in keys(song.instruments))
    )
    play!(player)
    previews = String[]
    for number in sort(collect(keys(song.instruments)))
        append!(previews,preview_lines(song,params,song.instruments[number]))
    end
    outputs = (
        "samples.txt"=>hex_lines(player.samples),"channel_log.txt"=>player.log,"notes.txt"=>note_lines(player),
        "roll.txt"=>roll_lines(
            player.played,
            params.roll_start,
            params.roll_rows
        ),"stats.txt"=>stats_lines(player),
        "waveform.txt"=>waveform_lines(player),"instruments.txt"=>previews
    )
    mkpath("output")
    for (name,lines) in outputs
        open(joinpath("output",name),"w") do handle
            foreach(line->println(handle,line),lines)
        end
    end
end
main()
