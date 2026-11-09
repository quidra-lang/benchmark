const LETTERS = ('C', 'D', 'E', 'F', 'G', 'A', 'B')
const NATURALS = (0, 2, 4, 5, 7, 9, 11)
const FIFTHS = (0, 2, 4, -1, 1, 3, 5)
const ACCIDENTALS = ("bb", "b", "", "#", "x")
const SHARPS = split("C C# D D# E F F# G G# A A# B")
const FLATS = split("C Db D Eb E F Gb G Ab A Bb B")
const ROMANS = ("I", "II", "III", "IV", "V", "VI", "VII")

struct CommandError <: Exception
    message::String
end
fail(message::AbstractString) = throw(CommandError(String(message)))
bad(kind::String, word::AbstractString) = fail("BAD $kind $word")

function bounded_integer(text::AbstractString, kind::String, low::Int, high::Int)
    length(text) <= 3 && occursin(r"^(0|[1-9][0-9]*)$", text) || bad(kind, text)
    value = parse(Int, text; base = 10)
    low <= value <= high || bad(kind, text)
    value
end
function frequency(text::AbstractString, tuning::Bool)
    occursin(r"^[0-9]{1,5}(\.[0-9]{1,2})?$", text) || bad("FREQUENCY", text)
    parts = split(text, '.')
    value = parse(Int, parts[1]; base = 10) * 100
    if length(parts) == 2
        value += parse(Int, parts[2]; base = 10) * (length(parts[2]) == 1 ? 10 : 1)
    end
    (value > 0 && (!tuning || 40000 <= value <= 48000)) || bad("FREQUENCY", text)
    value
end
frequency_text(cents::Int) = string(div(cents, 100), '.', lpad(string(rem(cents, 100)), 2, '0'))

struct Pitch
    letter::Int
    alteration::Int
end
Base.:(==)(first::Pitch, second::Pitch) = first.letter == second.letter && first.alteration == second.alteration
Base.show(io::IO, pitch::Pitch) = print(io, LETTERS[pitch.letter + 1], ACCIDENTALS[pitch.alteration + 3])
pitch_class(pitch::Pitch) = mod(NATURALS[pitch.letter + 1] + pitch.alteration, 12)

function pitch_prefix(text::AbstractString, kind::String)
    isempty(text) && bad(kind, text)
    index = findfirst(==(text[1]), LETTERS)
    isnothing(index) && bad(kind, text)
    position = 2
    alteration = 0
    if position <= lastindex(text)
        if text[position] == 'b'
            alteration = -1
            position += 1
            if position <= lastindex(text) && text[position] == 'b'
                alteration = -2
                position += 1
            end
        elseif text[position] == '#'
            alteration = 1
            position += 1
        elseif text[position] == 'x'
            alteration = 2
            position += 1
        end
    end
    (pitch = Pitch(index - 1, alteration), rest = text[position:end])
end
function parse_pitch(text::AbstractString)
    parsed = pitch_prefix(text, "PITCH")
    isempty(parsed.rest) || bad("PITCH", text)
    parsed.pitch
end
function fifth_pitch(value::Int)
    indices = (3, 0, 4, 1, 5, 2, 6)
    Pitch(indices[mod(value + 1, 7) + 1], fld(value + 1, 7))
end

struct Note
    pitch::Pitch
    octave::Int
end
Base.show(io::IO, note::Note) = print(io, note.pitch, note.octave)
midi(note::Note) = 12 * (note.octave + 1) + NATURALS[note.pitch.letter + 1] + note.pitch.alteration
note_position(note::Note) = 7 * note.octave + note.pitch.letter
valid_note(note::Note) = -1 <= note.octave <= 9 && 0 <= midi(note) <= 127
function parse_note(text::AbstractString)
    parsed = pitch_prefix(text, "NOTE")
    occursin(r"^(-1|[0-9])$", parsed.rest) || bad("NOTE", text)
    note = Note(parsed.pitch, parse(Int, parsed.rest; base = 10))
    valid_note(note) || bad("NOTE", text)
    note
end
make_note(pitch::Pitch, value::Int) = Note(pitch, div(value - NATURALS[pitch.letter + 1] - pitch.alteration, 12) - 1)
spelling(value::Int, flat::Bool = false) = Note(parse_pitch((flat ? FLATS : SHARPS)[mod(value, 12) + 1]), fld(value, 12) - 1)

@enum IntervalQuality PERFECT MAJOR MINOR AUGMENTED DIMINISHED DOUBLE_AUGMENTED DOUBLE_DIMINISHED
const QUALITY_TEXT = ("P", "M", "m", "A", "d", "AA", "dd")
perfect_type(number::Int) = mod(number - 1, 7) in (0, 3, 4)
function quality_delta(quality::IntervalQuality, perfect::Bool)::Union{Int,Nothing}
    quality == PERFECT && return (perfect ? 0 : nothing)
    quality == MAJOR && return (perfect ? nothing : 0)
    quality == MINOR && return (perfect ? nothing : -1)
    quality == AUGMENTED && return 1
    quality == DOUBLE_AUGMENTED && return 2
    quality == DIMINISHED && return (perfect ? -1 : -2)
    perfect ? -2 : -3
end
struct Tone
    letters::Int
    semitones::Int
end
struct Interval
    quality::IntervalQuality
    number::Int
end
Base.show(io::IO, interval::Interval) = print(io, QUALITY_TEXT[Int(interval.quality) + 1], interval.number)
forbidden(interval::Interval) = interval.number == 1 && interval.quality in (DIMINISHED, DOUBLE_DIMINISHED)
function parse_interval(text::AbstractString)
    for quality in instances(IntervalQuality)
        prefix = QUALITY_TEXT[Int(quality) + 1]
        startswith(text, prefix) || continue
        rest = text[length(prefix) + 1:end]
        occursin(r"^[1-9][0-9]?$", rest) || continue
        number = parse(Int, rest; base = 10)
        interval = Interval(quality, number)
        if !isnothing(quality_delta(quality, perfect_type(number))) && !forbidden(interval)
            return interval
        end
    end
    bad("INTERVAL", text)
end
function simple_interval(interval::Interval)
    number = interval.number
    while number > 8
        number -= 7
    end
    Interval(interval.quality, number)
end
function interval_tone(interval::Interval)
    distance = interval.number - 1
    Tone(distance, 12 * div(distance, 7) + NATURALS[mod(distance, 7) + 1] + something(quality_delta(interval.quality, perfect_type(interval.number))))
end
function consonance(interval::Interval)
    simple = simple_interval(interval)
    simple.quality == PERFECT && simple.number in (1, 5, 8) && return "perfect"
    simple.quality in (MAJOR, MINOR) && simple.number in (3, 6) && return "imperfect"
    "dissonant"
end
struct Motion
    interval::Interval
    down::Bool
    semitones::Int
end
function between(first::Note, second::Note)
    distance = note_position(second) - note_position(first)
    semitones = midi(second) - midi(first)
    down = distance < 0 || (distance == 0 && semitones < 0)
    if down
        distance = -distance
        semitones = -semitones
    end
    difference = semitones - 12 * div(distance, 7) - NATURALS[mod(distance, 7) + 1]
    for quality in instances(IntervalQuality)
        quality_delta(quality, perfect_type(distance + 1)) == difference && return Motion(Interval(quality, distance + 1), down, semitones)
    end
    fail("UNNAMEABLE INTERVAL")
end
function raise_pitch(root::Pitch, tone::Tone)
    target = root.letter + tone.letters
    alteration = NATURALS[root.letter + 1] + root.alteration + tone.semitones - NATURALS[mod(target, 7) + 1] - 12 * fld(target, 7)
    -2 <= alteration <= 2 || fail("CANNOT SPELL")
    Pitch(mod(target, 7), alteration)
end
tone_list(text::AbstractString) = interval_tone.(parse_interval.(split(text)))
build(root::Pitch, tones::Vector{Tone}) = [raise_pitch(root, tone) for tone in tones]

struct Scale
    name::String
    tones::Vector{Tone}
end
const SCALES = [
    Scale("major", tone_list("P1 M2 M3 P4 P5 M6 M7")),
    Scale("natural_minor", tone_list("P1 M2 m3 P4 P5 m6 m7")),
    Scale("harmonic_minor", tone_list("P1 M2 m3 P4 P5 m6 M7")),
    Scale("melodic_minor", tone_list("P1 M2 m3 P4 P5 M6 M7")),
    Scale("ionian", tone_list("P1 M2 M3 P4 P5 M6 M7")),
    Scale("dorian", tone_list("P1 M2 m3 P4 P5 M6 m7")),
    Scale("phrygian", tone_list("P1 m2 m3 P4 P5 m6 m7")),
    Scale("lydian", tone_list("P1 M2 M3 A4 P5 M6 M7")),
    Scale("mixolydian", tone_list("P1 M2 M3 P4 P5 M6 m7")),
    Scale("aeolian", tone_list("P1 M2 m3 P4 P5 m6 m7")),
    Scale("locrian", tone_list("P1 m2 m3 P4 d5 m6 m7")),
    Scale("major_pentatonic", tone_list("P1 M2 M3 P5 M6")),
    Scale("minor_pentatonic", tone_list("P1 m3 P4 P5 m7")),
    Scale("blues", tone_list("P1 m3 P4 A4 P5 m7")),
    Scale("whole_tone", tone_list("P1 M2 M3 A4 A5 A6")),
]
struct Chord
    name::String
    suffix::String
    lower::Bool
    numeral_suffix::String
    tones::Vector{Tone}
end
const CHORDS = [
    Chord("maj", "", false, "", tone_list("P1 M3 P5")),
    Chord("min", "m", true, "", tone_list("P1 m3 P5")),
    Chord("dim", "dim", true, "o", tone_list("P1 m3 d5")),
    Chord("aug", "aug", false, "+", tone_list("P1 M3 A5")),
    Chord("sus2", "sus2", false, "sus2", tone_list("P1 M2 P5")),
    Chord("sus4", "sus4", false, "sus4", tone_list("P1 P4 P5")),
    Chord("6", "6", false, "6", tone_list("P1 M3 P5 M6")),
    Chord("m6", "m6", true, "6", tone_list("P1 m3 P5 M6")),
    Chord("7", "7", false, "7", tone_list("P1 M3 P5 m7")),
    Chord("maj7", "maj7", false, "maj7", tone_list("P1 M3 P5 M7")),
    Chord("m7", "m7", true, "7", tone_list("P1 m3 P5 m7")),
    Chord("mMaj7", "mMaj7", true, "maj7", tone_list("P1 m3 P5 M7")),
    Chord("m7b5", "m7b5", true, "h7", tone_list("P1 m3 d5 m7")),
    Chord("dim7", "dim7", true, "o7", tone_list("P1 m3 d5 d7")),
    Chord("9", "9", false, "9", tone_list("P1 M3 P5 m7 M9")),
    Chord("add9", "add9", false, "add9", tone_list("P1 M3 P5 M9")),
]
struct Mode
    name::String
    scale::Int
    offset::Int
end
const MODES = [Mode("major", 1, 0), Mode("minor", 2, -3), Mode("ionian", 5, 0),
    Mode("dorian", 6, -2), Mode("phrygian", 7, -4), Mode("lydian", 8, 1),
    Mode("mixolydian", 9, -1), Mode("aeolian", 10, -3), Mode("locrian", 11, -5)]
function named_index(text::AbstractString, kind::String, choices)
    index = findfirst(item -> item.name == text, choices)
    isnothing(index) && bad(kind, text)
    index
end
chord_symbol(root::Pitch, chord::Chord, bass::Union{Pitch,Nothing} = nothing) = string(root, chord.suffix, isnothing(bass) ? "" : "/$bass")
roman(degree::Int, chord::Chord) = string(chord.lower ? lowercase(ROMANS[degree]) : ROMANS[degree], chord.numeral_suffix)

struct Key
    tonic::Pitch
    mode::Int
    fifths::Int
    scale::Vector{Pitch}
end
Base.show(io::IO, key::Key) = print(io, key.tonic, ' ', MODES[key.mode].name)
function make_key(tonic::Pitch, mode::Int)
    fifths = FIFTHS[tonic.letter + 1] + 7 * tonic.alteration + MODES[mode].offset
    -7 <= fifths <= 7 || fail("THEORETICAL KEY")
    Key(tonic, mode, fifths, build(tonic, SCALES[MODES[mode].scale].tones))
end
function parse_key(arguments::Vector{String}, start::Int = 1)
    tonic = parse_pitch(arguments[start])
    mode = named_index(arguments[start + 1], "MODE", MODES)
    make_key(tonic, mode)
end
key_degree(key::Key, pitch::Pitch) = mod(pitch.letter - key.tonic.letter, 7) + 1
function key_prefix(key::Key, pitch::Pitch)
    difference = pitch.alteration - key.scale[key_degree(key, pitch)].alteration
    repeat(difference < 0 ? "b" : "#", abs(difference))
end
key_label(key::Key, pitch::Pitch) = "$(key_prefix(key, pitch))$(key_degree(key, pitch))"
key_set(key::Key) = Set(pitch_class.(key.scale))
struct Numeral
    alteration::Int
    degree::Int
    quality::Int
end
struct ChordSymbol
    root::Pitch
    quality::Int
end
function parse_numeral(text::AbstractString)
    start = text[1] in ('b', '#') ? 2 : 1
    alteration = start == 1 ? 0 : text[1] == 'b' ? -1 : 1
    finish = start
    while finish <= lastindex(text) && text[finish] in ('I', 'V', 'i', 'v')
        finish += 1
    end
    part = text[start:finish - 1]
    suffix = text[finish:end]
    for degree in eachindex(ROMANS), quality in eachindex(CHORDS)
        chord = CHORDS[quality]
        expected = chord.lower ? lowercase(ROMANS[degree]) : ROMANS[degree]
        part == expected && suffix == chord.numeral_suffix && return Numeral(alteration, degree, quality)
    end
    bad("NUMERAL", text)
end
function parse_symbol(text::AbstractString)
    parsed = pitch_prefix(text, "SYMBOL")
    quality = findfirst(chord -> chord.suffix == parsed.rest, CHORDS)
    isnothing(quality) && bad("SYMBOL", text)
    ChordSymbol(parsed.pitch, quality)
end

function identify(notes::Vector{Note})
    ordered = notes[sortperm(midi.(notes))]
    present = Set{Int}()
    candidates = Note[]
    for note in ordered
        pitch_class(note.pitch) in present && continue
        push!(present, pitch_class(note.pitch))
        push!(candidates, note)
    end
    bass = candidates[1].pitch
    for root in candidates, chord in CHORDS
        possible = [mod(midi(root) + tone.semitones, 12) for tone in chord.tones]
        Set(possible) == present || continue
        inversion = something(findfirst(==(pitch_class(bass)), possible)) - 1
        symbol = chord_symbol(root.pitch, chord, inversion == 0 ? nothing : bass)
        return "IDENTIFY $symbol root=$(root.pitch) quality=$(chord.name) inversion=$inversion"
    end
    "IDENTIFY UNKNOWN"
end
function melody(notes::Vector{Note}, arguments::Vector{String})
    values = midi.(notes)
    low, high = argmin(values), argmax(values)
    range = between(notes[low], notes[high]).interval
    steps = String[]
    for index in 2:length(notes)
        motion = between(notes[index - 1], notes[index])
        push!(steps, string(motion.down ? '-' : '+', motion.interval))
    end
    leaps = count(value -> abs(value) >= 3, diff(values))
    "MELODY n=$(length(notes)) low=$(arguments[low]) high=$(arguments[high]) range=$range leaps=$leaps steps=$(join(steps, ','))"
end
function cadence(numerals::Vector{Numeral})
    length(numerals) < 2 && return "none"
    first, second = numerals[end - 1], numerals[end]
    if first.alteration == 0 && second.alteration == 0
        first.degree == 5 && second.degree == 1 && return "authentic"
        first.degree == 4 && second.degree == 1 && return "plagal"
        first.degree == 5 && second.degree == 6 && return "deceptive"
    end
    second.alteration == 0 && second.degree == 5 ? "half" : "none"
end
function diatonic(key::Key)
    rows = ["DIATONIC $key"]
    classes = pitch_class.(key.scale)
    for size in 3:4
        items = String[]
        for index in 1:7
            third = mod(classes[mod(index + 1, 7) + 1] - classes[index], 12)
            fifth = mod(classes[mod(index + 3, 7) + 1] - classes[index], 12)
            quality = if size == 3
                third == 4 ? 1 : fifth == 7 ? 2 : 3
            else
                seventh = mod(classes[mod(index + 5, 7) + 1] - classes[index], 12)
                third == 4 ? (seventh == 11 ? 10 : 9) : fifth == 7 ? 11 : 13
            end
            chord = CHORDS[quality]
            push!(items, "$(roman(index, chord))=$(chord_symbol(key.scale[index], chord))")
        end
        push!(rows, string(size == 3 ? "TRIADS " : "SEVENTHS ", join(items, ' ')))
    end
    rows
end

const ARITIES = Dict(
    "MIDI" => (1,1), "NOTE" => (1,1), "FREQ" => (1,1), "TUNING" => (1,1), "PITCH" => (1,1),
    "INTERVAL" => (2,2), "INVERT" => (1,1), "TRANSPOSE" => (3,3), "SCALE" => (2,2),
    "CHORD" => (2,3), "VOICE" => (2,3), "IDENTIFY" => (2,15), "MELODY" => (2,15),
    "ENHARMONIC" => (1,1), "KEYSIG" => (2,2), "RELATIVE" => (2,2), "CIRCLE" => (1,1),
    "DIATONIC" => (2,2), "PROGRESSION" => (3,15), "ANALYZE" => (3,15), "FINDKEY" => (1,15),
    "DEGREE" => (3,3), "SPELL" => (3,3), "KEYDIST" => (4,4),
)
mutable struct Calculator
    tuning::Int
end

function execute(calculator::Calculator, line::String)::Vector{String}
    tokens = String.(split(line, ' '))
    command = tokens[1]
    haskey(ARITIES, command) || fail("UNKNOWN COMMAND $command")
    arguments = tokens[2:end]
    lower, upper = ARITIES[command]
    lower <= length(arguments) <= upper || fail("ARGUMENT COUNT")
    if command in ("MIDI", "FREQ", "ENHARMONIC")
        note = parse_note(arguments[1])
        value = midi(note)
        command == "MIDI" && return ["MIDI $(arguments[1]) $value"]
        if command == "FREQ"
            cents = floor(Int, calculator.tuning * exp2((value - 69) / 12) + 0.5)
            return ["FREQ $(arguments[1]) $(frequency_text(cents))"]
        end
        equivalents = Note[]
        for octave in -1:9, letter in 0:6
            alteration = value - 12 * (octave + 1) - NATURALS[letter + 1]
            -2 <= alteration <= 2 && push!(equivalents, Note(Pitch(letter, alteration), octave))
        end
        return ["ENHARMONIC $(arguments[1]) $(join(equivalents, ' '))"]
    elseif command == "NOTE"
        value = bounded_integer(arguments[1], "NUMBER", 0, 127)
        return ["NOTE $value $(spelling(value)) $(spelling(value, true))"]
    elseif command in ("TUNING", "PITCH")
        value = frequency(arguments[1], command == "TUNING")
        if command == "TUNING"
            calculator.tuning = value
            return ["TUNING $(frequency_text(value))"]
        end
        height = 69 + 12 * log2(value / calculator.tuning)
        nearest = floor(Int, height + 0.5)
        0 <= nearest <= 127 || fail("OUT OF RANGE")
        cents = floor(Int, 100 * (height - nearest) + 0.5)
        sign = cents >= 0 ? "+" : ""
        return ["PITCH $(frequency_text(value)) $(spelling(nearest)) $sign$cents"]
    elseif command == "INTERVAL"
        first = parse_note(arguments[1])
        second = parse_note(arguments[2])
        motion = between(first, second)
        direction = motion.down ? "down" : "up"
        return ["INTERVAL $(arguments[1]) $(arguments[2]) $(motion.interval) $direction semitones=$(motion.semitones) simple=$(simple_interval(motion.interval)) class=$(consonance(motion.interval))"]
    elseif command == "INVERT"
        interval = parse_interval(arguments[1])
        simple = simple_interval(interval)
        inverses = (PERFECT, MINOR, MAJOR, DIMINISHED, AUGMENTED, DOUBLE_DIMINISHED, DOUBLE_AUGMENTED)
        inverse = Interval(inverses[Int(simple.quality) + 1], 9 - simple.number)
        forbidden(inverse) && fail("CANNOT INVERT")
        return ["INVERT $(arguments[1]) $simple $inverse"]
    elseif command == "TRANSPOSE"
        note = parse_note(arguments[1])
        interval = parse_interval(arguments[2])
        direction = arguments[3]
        direction in ("UP", "DOWN") || bad("DIRECTION", direction)
        sign = direction == "UP" ? 1 : -1
        tone = interval_tone(interval)
        target = note_position(note) + sign * tone.letters
        value = midi(note) + sign * tone.semitones
        letter, octave = mod(target, 7), fld(target, 7)
        alteration = value - 12 * (octave + 1) - NATURALS[letter + 1]
        -2 <= alteration <= 2 || fail("CANNOT SPELL")
        result = Note(Pitch(letter, alteration), octave)
        valid_note(result) || fail("OUT OF RANGE")
        return ["TRANSPOSE $(arguments[1]) $(arguments[2]) $direction $result"]
    elseif command == "SCALE"
        root = parse_pitch(arguments[1])
        scale = SCALES[named_index(arguments[2], "SCALE", SCALES)]
        pitches = build(root, scale.tones)
        semitones = [tone.semitones for tone in scale.tones]
        steps = diff(vcat(semitones, 12))
        return ["SCALE $(arguments[1]) $(arguments[2]) $(join(pitches, ' ')) steps=$(join(steps, ','))"]
    elseif command in ("CHORD", "VOICE")
        input = command == "VOICE" ? parse_note(arguments[1]) : nothing
        root = isnothing(input) ? parse_pitch(arguments[1]) : input.pitch
        quality = named_index(arguments[2], "QUALITY", CHORDS)
        chord = CHORDS[quality]
        inversion = length(arguments) == 3 ? bounded_integer(arguments[3], "INVERSION", 0, length(chord.tones) - 1) : 0
        tones = build(root, chord.tones)
        ordered = vcat(tones[inversion + 1:end], tones[1:inversion])
        symbol = chord_symbol(root, chord, inversion == 0 ? nothing : ordered[1])
        command == "CHORD" && return ["CHORD $symbol $(join(ordered, ' '))"]
        value = midi(something(input))
        notes = Note[]
        for (index, pitch) in enumerate(ordered)
            if index > 1 || inversion > 0
                difference = mod(pitch_class(pitch) - value, 12)
                value += difference == 0 ? 12 : difference
            end
            note = make_note(pitch, value)
            valid_note(note) || fail("OUT OF RANGE")
            push!(notes, note)
        end
        return ["VOICE $symbol $(join(notes, ' ')) midi=$(join(midi.(notes), ','))"]
    elseif command in ("IDENTIFY", "MELODY")
        notes = parse_note.(arguments)
        return [command == "IDENTIFY" ? identify(notes) : melody(notes, arguments)]
    elseif command == "CIRCLE"
        mode = named_index(arguments[1], "MODE", MODES)
        pitches = [fifth_pitch(fifths - MODES[mode].offset) for fifths in -7:7]
        return ["CIRCLE $(arguments[1]) $(join(pitches, ' '))"]
    elseif command == "FINDKEY"
        pitches = parse_pitch.(arguments)
        keys = Key[]
        for fifths in -7:7, mode in 1:2
            key = make_key(fifth_pitch(fifths - MODES[mode].offset), mode)
            all(pitch -> pitch in key.scale, pitches) && push!(keys, key)
        end
        return ["FINDKEY $(length(keys))" * (isempty(keys) ? "" : " " * join(keys, ", "))]
    elseif command == "SPELL"
        value = bounded_integer(arguments[1], "NUMBER", 0, 127)
        key = parse_key(arguments, 2)
        index = findfirst(pitch -> pitch_class(pitch) == mod(value, 12), key.scale)
        pitch = isnothing(index) ? spelling(value, key.fifths < 0).pitch : key.scale[index]
        note = make_note(pitch, value)
        valid_note(note) || fail("OUT OF RANGE")
        return ["SPELL $value $key $note $(key_label(key, pitch))"]
    end
    key = parse_key(arguments)
    if command == "KEYSIG"
        value = key.fifths
        value == 0 && return ["KEYSIG $key none"]
        names = split(value > 0 ? "F# C# G# D# A# E# B#" : "Bb Eb Ab Db Gb Cb Fb")
        kind = value > 0 ? "sharps" : "flats"
        return ["KEYSIG $key $kind=$(abs(value)) $(join(names[1:abs(value)], ' '))"]
    elseif command == "RELATIVE"
        return ["RELATIVE $key major=$(fifth_pitch(key.fifths)) minor=$(fifth_pitch(key.fifths + 3))"]
    elseif command == "DIATONIC"
        return diatonic(key)
    elseif command == "DEGREE"
        pitch = parse_pitch(arguments[3])
        return ["DEGREE $key $(arguments[3]) $(key_label(key, pitch))"]
    elseif command == "KEYDIST"
        other = parse_key(arguments, 3)
        distance = mod(other.fifths - key.fifths, 12)
        distance > 6 && (distance -= 12)
        first_set, second_set = key_set(key), key_set(other)
        same_tonic = pitch_class(key.tonic) == pitch_class(other.tonic)
        relation = if first_set == second_set
            same_tonic ? "same" : "relative"
        elseif same_tonic
            "parallel"
        else
            abs(distance) == 1 ? "close" : "distant"
        end
        sign = distance > 0 ? "+" : ""
        return ["KEYDIST $key $other fifths=$sign$distance common=$(length(intersect(first_set, second_set))) relation=$relation"]
    elseif command == "ANALYZE"
        symbols = parse_symbol.(arguments[3:end])
        numerals = [key_prefix(key, symbol.root) * roman(key_degree(key, symbol.root), CHORDS[symbol.quality]) for symbol in symbols]
        return ["ANALYZE $key $(join(numerals, ' '))"]
    else
        numerals = parse_numeral.(arguments[3:end])
        rows = ["PROGRESSION $key $(length(numerals))"]
        for (index, numeral) in enumerate(numerals)
            degree = key.scale[numeral.degree]
            root = Pitch(degree.letter, degree.alteration + numeral.alteration)
            chord = CHORDS[numeral.quality]
            tones = build(root, chord.tones)
            push!(rows, "$(arguments[index + 2]) $(chord_symbol(root, chord)) $(join(tones, ' '))")
        end
        push!(rows, "CADENCE $(cadence(numerals))")
        return rows
    end
end

function main()
    calculator = Calculator(44000)
    count = parse(Int, readline())
    for _ in 1:count
        line = readline()
        rows = try
            execute(calculator, line)
        catch problem
            problem isa CommandError || rethrow()
            ["ERROR " * problem.message]
        end
        for row in rows
            println(row)
        end
    end
end
main()
