const PITCH_NAMES = ("C-","C#","D-","D#","E-","F-","F#","G-","G#","A-","A#","B-")
const ROWS_PER_PATTERN = 64
const CHANNEL_COUNT = 4
note_number(name) = 12*parse(Int,name[3:3])+findfirst(==(name[1:2]),PITCH_NAMES)-1
note_name(number) = PITCH_NAMES[mod(number,12)+1]*string(fld(number,12))
struct Effect
    text::String
    name::String
    value::Int
end
function Effect(text)
    extended = text[1] == 'E'
    name = extended ? text[1:2] : text[1:1]
    start = extended ? 3 : 2
    Effect(text,name,parse(Int,text[start:end],base=16))
end
high(effect) = effect.value÷16
low(effect) = effect.value%16
struct Cell
    key_off::Bool
    note::Union{Nothing,Int}
    instrument::Union{Nothing,Int}
    volume::Union{Nothing,Int}
    effect::Union{Nothing,Effect}
end
function Cell(text)
    note,instrument,volume,effect = text[1:3],text[5:6],text[8:8],text[10:12]
    Cell(
        note == "OFF",
        note in ("...","OFF") ? nothing : note_number(note),
        instrument == ".." ? nothing : parse(Int,instrument,base=16),
        volume == "." ? nothing : parse(Int,volume,base=16),
        effect == "..." ? nothing : Effect(effect)
    )
end
has_note(cell) = cell.key_off || !isnothing(cell.note)
is_empty(cell) = !has_note(cell) && isnothing(cell.instrument) && isnothing(cell.volume) && isnothing(cell.effect)
Base.@kwdef mutable struct Instrument
    number::Int
    name::String
    wave::String = ""
    mode::Int = 0
    table::Vector{Int} = Int[]
    attack::Int = 0
    decay::Int = 0
    sustain::Int = 0
    release::Int = 0
    vibrato::Union{Nothing,Tuple{Int,Int,Int}} = nothing
    arpeggio::Vector{Int} = Int[]
    sweep::Int = 0
end
Base.@kwdef mutable struct Song
    title::String
    rate::Int
    speed::Int
    tempo::Int
    gain::Int
    instruments::Dict{Int,Instrument} = Dict{Int,Instrument}()
    patterns::Dict{Int,Vector{Vector{Cell}}} = Dict{Int,Vector{Vector{Cell}}}()
    order::Vector{Int} = Int[]
end
song_cells(song,position,row) = song.patterns[song.order[position+1]][row+1]
function parse_instrument(words,lines)
    instrument = Instrument(number=parse(Int,words[2],base=16),name=words[3])
    for line in lines
        parts = split(line)
        key,values = parts[1],parts[2:end]
        if key == "WAVE"
            instrument.wave = values[1]
            if instrument.wave == "PULSE"
                instrument.mode = findfirst(==(values[2]),("12","25","50","75"))-1
            elseif instrument.wave == "NOISE"
                instrument.mode = values[2] == "SHORT" ? 1 : 0
            elseif instrument.wave == "TABLE"
                instrument.table = [parse(Int,string(digit),base=16) for digit in values[2]]
            end
        elseif key == "ENVELOPE"
            instrument.attack,instrument.decay,instrument.sustain,instrument.release = parse.(Int,values)
        elseif key == "VIBRATO"
            instrument.vibrato = Tuple(parse.(Int,values))
        elseif key == "ARPEGGIO"
            instrument.arpeggio = parse.(Int,values)
        elseif key == "SWEEP"
            instrument.sweep = parse(Int,only(values))
        end
    end
    instrument
end
function read_song(path)
    lines = filter(line->!isempty(line) && !startswith(line,"#"),readlines(path))
    header = [split(line,' ';limit=2)[2] for line in lines[1:5]]
    song = Song(
        title=header[1],
        rate=parse(Int,header[2]),
        speed=parse(Int,header[3]),
        tempo=parse(Int,header[4]),
        gain=parse(Int,header[5])
    )
    index = 6
    while index <= length(lines)
        words = split(lines[index])
        if words[1] == "ORDER"
            song.order = parse.(Int,words[2:end];base=16)
            index += 1
            continue
        end
        stop = findnext(==("END"),lines,index)
        block = lines[index+1:stop-1]
        if words[1] == "INSTRUMENT"
            instrument = parse_instrument(words,block)
            song.instruments[instrument.number] = instrument
        else
            rows = [[Cell("... .. . ...") for _ in 1:CHANNEL_COUNT] for _ in 1:ROWS_PER_PATTERN]
            for line in block
                row = parse(Int,line[1:2],base=16)
                rows[row+1] = Cell.(split(line[4:end]," | "))
            end
            song.patterns[parse(Int,words[2],base=16)] = rows
        end
        index = stop+1
    end
    song
end
function read_params(path)
    fields = Dict{String,Vector{String}}()
    traces = Set{Tuple{Int,Int}}()
    for line in readlines(path)
        words = split(line)
        isempty(words) && continue
        if words[1] == "trace"
            push!(traces,Tuple(parse.(Int,words[2:end];base=16)))
        else
            fields[words[1]] = String.(words[2:end])
        end
    end
    window,roll = parse.(Int,fields["window"]),parse.(Int,fields["roll"])
    (
        max_samples=parse(
            Int,
            only(fields["max_samples"])
        ),loops=parse(Int,only(fields["loops"])),fade=parse(Int,only(fields["fade"])),
        muted=fields["mute"].=="1",window_start=window[1],window_length=window[2],window_width=window[3],window_height=window[4],window_scope=window[5],
        roll_start=roll[1],roll_rows=roll[2],preview_note=note_number(fields["preview"][1]),preview_ticks=parse(Int,fields["preview"][2]),preview_release=parse(
            Int,
            fields["preview"][3]
        ),traces=traces
    )
end
