local format = string.format
local function fail(message, word)
    error("ERROR " .. message .. (word and " " .. word or ""), 0)
end
local function join(values, separator)
    local text = {}
    for i, value in ipairs(values) do text[i] = tostring(value) end
    return table.concat(text, separator or " ")
end
local function frequency_text(cents) return format("%d.%02d", cents // 100, cents % 100) end
local function signed_text(value, positive_zero)
    return (value > 0 or (value == 0 and positive_zero)) and "+" .. value or tostring(value)
end

local letters, naturals = "CDEFGAB", {0, 2, 4, 5, 7, 9, 11}
local accidentals = {"bb", "b", "", "#", "x"}
local sharp_names = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
local flat_names = {"C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"}
local romans = {"I", "II", "III", "IV", "V", "VI", "VII"}
local Pitch = {}
Pitch.__index = Pitch
function Pitch.new(letter, alteration) return setmetatable({letter = letter, alteration = alteration or 0}, Pitch) end
function Pitch:natural() return naturals[self.letter] end
function Pitch:class() return (self:natural() + self.alteration) % 12 end
function Pitch:__tostring() return letters:sub(self.letter, self.letter) .. accidentals[self.alteration + 3] end
function Pitch.__eq(a, b) return a.letter == b.letter and a.alteration == b.alteration end
function Pitch.prefix(text)
    if text == "" then return nil end
    local letter = letters:find(text:sub(1, 1), 1, true)
    if not letter then return nil end
    local finish, alteration = 2, 0
    if text:sub(2, 3) == "bb" then finish, alteration = 4, -2
    elseif text:sub(2, 2) == "b" then finish, alteration = 3, -1
    elseif text:sub(2, 2) == "#" then finish, alteration = 3, 1
    elseif text:sub(2, 2) == "x" then finish, alteration = 3, 2 end
    return Pitch.new(letter, alteration), finish
end
function Pitch.parse(text)
    local pitch, finish = Pitch.prefix(text)
    if not pitch or finish ~= #text + 1 then fail("BAD PITCH", text) end
    return pitch
end
function Pitch.at_fifths(fifths)
    local index = (fifths + 1) % 7 + 1
    local letter = letters:find(("FCGDAEB"):sub(index, index), 1, true)
    return Pitch.new(letter, (fifths + 1) // 7)
end
function Pitch:raise(interval)
    local position = self.letter - 1 + interval:distance()
    local letter = position % 7 + 1
    local alteration = self:natural() + self.alteration + interval:semitones() - naturals[letter] - 12 * (position // 7)
    if alteration < -2 or alteration > 2 then fail("CANNOT SPELL") end
    return Pitch.new(letter, alteration)
end

local Note = {}
Note.__index = Note
function Note.new(pitch, octave) return setmetatable({pitch = pitch, octave = octave}, Note) end
function Note:midi() return 12 * (self.octave + 1) + self.pitch:natural() + self.pitch.alteration end
function Note:position() return 7 * self.octave + self.pitch.letter - 1 end
function Note:valid() return self.octave >= -1 and self.octave <= 9 and self:midi() >= 0 and self:midi() <= 127 end
function Note:__tostring() return tostring(self.pitch) .. self.octave end
function Note.parse(text)
    local pitch, finish = Pitch.prefix(text)
    if not pitch then fail("BAD NOTE", text) end
    local tail = text:sub(finish)
    if tail ~= "-1" and not tail:match("^[0-9]$") then fail("BAD NOTE", text) end
    local note = Note.new(pitch, tonumber(tail, 10))
    if not note:valid() then fail("BAD NOTE", text) end
    return note
end
function Note.from_midi(pitch, midi)
    return Note.new(pitch, (midi - pitch:natural() - pitch.alteration) // 12 - 1)
end
function Note.spelling(midi, flat)
    return Note.new(Pitch.parse((flat and flat_names or sharp_names)[midi % 12 + 1]), midi // 12 - 1)
end

local perfect_deltas = {dd = -2, d = -1, P = 0, A = 1, AA = 2}
local major_deltas = {dd = -3, d = -2, m = -1, M = 0, A = 1, AA = 2}
local Interval = {}
Interval.__index = Interval
function Interval.new(quality, number) return setmetatable({quality = quality, number = number}, Interval) end
function Interval:distance() return self.number - 1 end
function Interval:perfect()
    local remainder = self:distance() % 7
    return remainder == 0 or remainder == 3 or remainder == 4
end
function Interval:semitones()
    local deltas = self:perfect() and perfect_deltas or major_deltas
    return 12 * (self:distance() // 7) + naturals[self:distance() % 7 + 1] + deltas[self.quality]
end
function Interval:simple()
    local number = self.number
    while number > 8 do number = number - 7 end
    return Interval.new(self.quality, number)
end
function Interval:consonance()
    local simple = self:simple()
    if simple.quality == "P" and (simple.number == 1 or simple.number == 5 or simple.number == 8) then return "perfect" end
    if (simple.quality == "M" or simple.quality == "m") and (simple.number == 3 or simple.number == 6) then return "imperfect" end
    return "dissonant"
end
function Interval:__tostring() return self.quality .. self.number end
function Interval.parse(text)
    local quality, number = text:match("^([A-Za-z]+)([0-9]+)$")
    if not quality or #number > 2 or number:sub(1, 1) == "0" then fail("BAD INTERVAL", text) end
    local result = Interval.new(quality, tonumber(number, 10))
    local deltas = result:perfect() and perfect_deltas or major_deltas
    if deltas[quality] == nil or (result.number == 1 and (quality == "d" or quality == "dd")) then fail("BAD INTERVAL", text) end
    return result
end
local function between(a, b)
    local distance, semitones = b:position() - a:position(), b:midi() - a:midi()
    local down = distance < 0 or (distance == 0 and semitones < 0)
    if down then distance, semitones = -distance, -semitones end
    local difference = semitones - (12 * (distance // 7) + naturals[distance % 7 + 1])
    local qualities = (distance % 7 == 0 or distance % 7 == 3 or distance % 7 == 4)
        and {[-2] = "dd", [-1] = "d", [0] = "P", [1] = "A", [2] = "AA"}
        or {[-3] = "dd", [-2] = "d", [-1] = "m", [0] = "M", [1] = "A", [2] = "AA"}
    if not qualities[difference] then fail("UNNAMEABLE INTERVAL") end
    return {interval = Interval.new(qualities[difference], distance + 1), down = down, semitones = semitones}
end
local function pattern(text)
    local result = {}
    for word in text:gmatch("[^ ]+") do result[#result + 1] = Interval.parse(word) end
    return result
end
local scales = {
    major = pattern("P1 M2 M3 P4 P5 M6 M7"), natural_minor = pattern("P1 M2 m3 P4 P5 m6 m7"),
    harmonic_minor = pattern("P1 M2 m3 P4 P5 m6 M7"), melodic_minor = pattern("P1 M2 m3 P4 P5 M6 M7"),
    ionian = pattern("P1 M2 M3 P4 P5 M6 M7"), dorian = pattern("P1 M2 m3 P4 P5 M6 m7"),
    phrygian = pattern("P1 m2 m3 P4 P5 m6 m7"), lydian = pattern("P1 M2 M3 A4 P5 M6 M7"),
    mixolydian = pattern("P1 M2 M3 P4 P5 M6 m7"), aeolian = pattern("P1 M2 m3 P4 P5 m6 m7"),
    locrian = pattern("P1 m2 m3 P4 d5 m6 m7"), major_pentatonic = pattern("P1 M2 M3 P5 M6"),
    minor_pentatonic = pattern("P1 m3 P4 P5 m7"), blues = pattern("P1 m3 P4 A4 P5 m7"),
    whole_tone = pattern("P1 M2 M3 A4 A5 A6"),
}
local Quality = {}
Quality.__index = Quality
function Quality.new(name, text, suffix, numeral)
    return setmetatable({name = name, pattern = pattern(text), suffix = suffix, numeral = numeral}, Quality)
end
function Quality:lower() return self.numeral:sub(1, 1) == "i" end
function Quality:symbol(root) return tostring(root) .. self.suffix end
function Quality:roman(degree)
    local numeral = self:lower() and romans[degree]:lower() or romans[degree]
    return numeral .. self.numeral:sub(2)
end
local qualities = {
    Quality.new("maj", "P1 M3 P5", "", "I"), Quality.new("min", "P1 m3 P5", "m", "i"),
    Quality.new("dim", "P1 m3 d5", "dim", "io"), Quality.new("aug", "P1 M3 A5", "aug", "I+"),
    Quality.new("sus2", "P1 M2 P5", "sus2", "Isus2"), Quality.new("sus4", "P1 P4 P5", "sus4", "Isus4"),
    Quality.new("6", "P1 M3 P5 M6", "6", "I6"), Quality.new("m6", "P1 m3 P5 M6", "m6", "i6"),
    Quality.new("7", "P1 M3 P5 m7", "7", "I7"), Quality.new("maj7", "P1 M3 P5 M7", "maj7", "Imaj7"),
    Quality.new("m7", "P1 m3 P5 m7", "m7", "i7"), Quality.new("mMaj7", "P1 m3 P5 M7", "mMaj7", "imaj7"),
    Quality.new("m7b5", "P1 m3 d5 m7", "m7b5", "ih7"), Quality.new("dim7", "P1 m3 d5 d7", "dim7", "io7"),
    Quality.new("9", "P1 M3 P5 m7 M9", "9", "I9"), Quality.new("add9", "P1 M3 P5 M9", "add9", "Iadd9"),
}
local quality_names = {}
for _, quality in ipairs(qualities) do quality_names[quality.name] = quality end
local function parse_quality(text)
    if not quality_names[text] then fail("BAD QUALITY", text) end
    return quality_names[text]
end
local mode_info = {
    major = {scale = "major", offset = 0}, minor = {scale = "natural_minor", offset = -3},
    ionian = {scale = "ionian", offset = 0}, dorian = {scale = "dorian", offset = -2},
    phrygian = {scale = "phrygian", offset = -4}, lydian = {scale = "lydian", offset = 1},
    mixolydian = {scale = "mixolydian", offset = -1}, aeolian = {scale = "aeolian", offset = -3},
    locrian = {scale = "locrian", offset = -5},
}
local function parse_mode(text)
    if not mode_info[text] then fail("BAD MODE", text) end
    return text
end
local function build(root, intervals)
    local result = {}
    for i, interval in ipairs(intervals) do result[i] = root:raise(interval) end
    return result
end
local Key = {}
Key.__index = Key
function Key.new(tonic, mode) return setmetatable({tonic = tonic, mode = mode}, Key) end
function Key:fifths() return ({0, 2, 4, -1, 1, 3, 5})[self.tonic.letter] + 7 * self.tonic.alteration + mode_info[self.mode].offset end
function Key:scale() return build(self.tonic, scales[mode_info[self.mode].scale]) end
function Key:__tostring() return tostring(self.tonic) .. " " .. self.mode end
function Key.parse(tonic, mode)
    local pitch = Pitch.parse(tonic)
    local mode_value = parse_mode(mode)
    local key = Key.new(pitch, mode_value)
    if key:fifths() < -7 or key:fifths() > 7 then fail("THEORETICAL KEY") end
    return key
end
function Key.at_fifths(fifths, mode) return Key.new(Pitch.at_fifths(fifths - mode_info[mode].offset), mode) end
function Key:degree(pitch)
    local degree = (pitch.letter - self.tonic.letter) % 7 + 1
    local difference = pitch.alteration - self:scale()[degree].alteration
    local prefix = (difference < 0 and "b" or "#"):rep(math.abs(difference))
    return degree, prefix
end
local function degree_label(key, pitch)
    local degree, prefix = key:degree(pitch)
    return prefix .. degree
end
local function parse_number(text)
    if not text:match("^[0-9]+$") or #text > 3 or (#text > 1 and text:sub(1, 1) == "0") then fail("BAD NUMBER", text) end
    local value = tonumber(text, 10)
    if value > 127 then fail("BAD NUMBER", text) end
    return value
end
local function parse_frequency(text, tuning)
    local whole, tail = text:match("^([0-9]+)%.([0-9]+)$")
    if not whole then whole, tail = text, "" end
    if not whole:match("^[0-9]+$") or #whole > 5 or #tail > 2 then fail("BAD FREQUENCY", text) end
    local value = tonumber(whole, 10) * 100
    if tail ~= "" then value = value + tonumber(tail, 10) * (#tail == 1 and 10 or 1) end
    if value == 0 or (tuning and (value < 40000 or value > 48000)) then fail("BAD FREQUENCY", text) end
    return value
end
local function parse_inversion(text, quality)
    if not text:match("^[0-9]$") then fail("BAD INVERSION", text) end
    local value = tonumber(text, 10)
    if value >= #quality.pattern then fail("BAD INVERSION", text) end
    return value
end
local function parse_numeral(text)
    local first = text:sub(1, 1)
    local start = (first == "b" or first == "#") and 2 or 1
    local alteration = start == 1 and 0 or (first == "b" and -1 or 1)
    local finish = start
    while finish <= #text and ("IViv"):find(text:sub(finish, finish), 1, true) do finish = finish + 1 end
    local part, suffix = text:sub(start, finish - 1), text:sub(finish)
    for degree, roman in ipairs(romans) do
        local lower = part == roman:lower()
        if lower or part == roman then
            for _, quality in ipairs(qualities) do
                if quality:lower() == lower and quality.numeral:sub(2) == suffix then
                    return {degree = degree, alteration = alteration, quality = quality}
                end
            end
        end
    end
    fail("BAD NUMERAL", text)
end
local function parse_symbol(text)
    local root, finish = Pitch.prefix(text)
    if root then
        for _, quality in ipairs(qualities) do
            if quality.suffix == text:sub(finish) then return {root = root, quality = quality} end
        end
    end
    fail("BAD SYMBOL", text)
end
local function parse_values(words, first, parser)
    local result = {}
    for i = first, #words do result[#result + 1] = parser(words[i]) end
    return result
end
local function mask(pitches)
    local result = 0
    for _, pitch in ipairs(pitches) do result = result | (1 << pitch:class()) end
    return result
end
local function cadence(numerals)
    if #numerals < 2 then return "none" end
    local a, b = numerals[#numerals - 1], numerals[#numerals]
    if a.alteration == 0 and b.alteration == 0 then
        if a.degree == 5 and b.degree == 1 then return "authentic" end
        if a.degree == 4 and b.degree == 1 then return "plagal" end
        if a.degree == 5 and b.degree == 6 then return "deceptive" end
    end
    return b.alteration == 0 and b.degree == 5 and "half" or "none"
end

local limits = {
    MIDI = {1, 1}, NOTE = {1, 1}, FREQ = {1, 1}, TUNING = {1, 1}, PITCH = {1, 1},
    INTERVAL = {2, 2}, INVERT = {1, 1}, TRANSPOSE = {3, 3}, SCALE = {2, 2},
    CHORD = {2, 3}, VOICE = {2, 3}, IDENTIFY = {2, 15}, MELODY = {2, 15}, ENHARMONIC = {1, 1},
    KEYSIG = {2, 2}, RELATIVE = {2, 2}, CIRCLE = {1, 1}, DIATONIC = {2, 2},
    PROGRESSION = {3, 15}, ANALYZE = {3, 15}, FINDKEY = {1, 15}, DEGREE = {3, 3}, SPELL = {3, 3}, KEYDIST = {4, 4},
}
local tuning = 44000
local function execute(line)
    local words = {}
    for word in line:gmatch("[^ ]+") do words[#words + 1] = word end
    local command, count = words[1], #words - 1
    local arity = limits[command]
    if not arity then fail("UNKNOWN COMMAND", command) end
    if count < arity[1] or count > arity[2] then fail("ARGUMENT COUNT") end
    if command == "MIDI" then
        local note = Note.parse(words[2])
        return format("MIDI %s %d", note, note:midi())
    elseif command == "NOTE" then
        local number = parse_number(words[2])
        return format("NOTE %d %s %s", number, Note.spelling(number), Note.spelling(number, true))
    elseif command == "FREQ" then
        local note = Note.parse(words[2])
        local cents = math.floor(tuning * 2 ^ ((note:midi() - 69) / 12) + 0.5)
        return format("FREQ %s %s", note, frequency_text(cents))
    elseif command == "TUNING" then
        local value = parse_frequency(words[2], true)
        tuning = value
        return "TUNING " .. frequency_text(value)
    elseif command == "PITCH" then
        local value = parse_frequency(words[2], false)
        local height = 69 + 12 * math.log(value / tuning, 2)
        local number = math.floor(height + 0.5)
        if number < 0 or number > 127 then fail("OUT OF RANGE") end
        local cents = math.floor(100 * (height - number) + 0.5)
        return format("PITCH %s %s %s", frequency_text(value), Note.spelling(number), signed_text(cents, true))
    elseif command == "INTERVAL" then
        local a = Note.parse(words[2])
        local b = Note.parse(words[3])
        local motion = between(a, b)
        return format("INTERVAL %s %s %s %s semitones=%d simple=%s class=%s", a, b, motion.interval,
            motion.down and "down" or "up", motion.semitones, motion.interval:simple(), motion.interval:consonance())
    elseif command == "INVERT" then
        local original = Interval.parse(words[2])
        local simple = original:simple()
        local inverse_quality = {P = "P", M = "m", m = "M", A = "d", d = "A", AA = "dd", dd = "AA"}
        local inverse = Interval.new(inverse_quality[simple.quality], 9 - simple.number)
        if inverse.number == 1 and (inverse.quality == "d" or inverse.quality == "dd") then fail("CANNOT INVERT") end
        return format("INVERT %s %s %s", original, simple, inverse)
    elseif command == "TRANSPOSE" then
        local note = Note.parse(words[2])
        local interval = Interval.parse(words[3])
        local direction = words[4]
        if direction ~= "UP" and direction ~= "DOWN" then fail("BAD DIRECTION", direction) end
        local sign = direction == "UP" and 1 or -1
        local position = note:position() + sign * interval:distance()
        local midi = note:midi() + sign * interval:semitones()
        local letter, octave = position % 7 + 1, position // 7
        local alteration = midi - (12 * (octave + 1) + naturals[letter])
        if alteration < -2 or alteration > 2 then fail("CANNOT SPELL") end
        local result = Note.new(Pitch.new(letter, alteration), octave)
        if not result:valid() then fail("OUT OF RANGE") end
        return format("TRANSPOSE %s %s %s %s", note, interval, direction, result)
    elseif command == "SCALE" then
        local root = Pitch.parse(words[2])
        local intervals = scales[words[3]]
        if not intervals then fail("BAD SCALE", words[3]) end
        local pitches = build(root, intervals)
        local steps = {}
        for i, interval in ipairs(intervals) do
            local next_tone = i == #intervals and 12 or intervals[i + 1]:semitones()
            steps[i] = next_tone - interval:semitones()
        end
        return format("SCALE %s %s %s steps=%s", root, words[3], join(pitches), join(steps, ","))
    elseif command == "CHORD" or command == "VOICE" then
        local input, root
        if command == "VOICE" then input = Note.parse(words[2]); root = input.pitch
        else root = Pitch.parse(words[2]) end
        local quality = parse_quality(words[3])
        local inversion = count == 3 and parse_inversion(words[4], quality) or 0
        local tones = build(root, quality.pattern)
        local pitches = {}
        for i = 1, #tones do pitches[i] = tones[(i - 1 + inversion) % #tones + 1] end
        local symbol = quality:symbol(root) .. (inversion > 0 and "/" .. tostring(pitches[1]) or "")
        if command == "CHORD" then return "CHORD " .. symbol .. " " .. join(pitches) end
        local notes, midis = {}, {}
        local previous = input:midi()
        for i, pitch in ipairs(pitches) do
            local midi = previous
            if i > 1 or inversion > 0 then
                midi = midi + (pitch:class() - previous) % 12
                if midi == previous then midi = midi + 12 end
            end
            local note = Note.from_midi(pitch, midi)
            if not note:valid() then fail("OUT OF RANGE") end
            notes[i], midis[i], previous = note, midi, midi
        end
        return format("VOICE %s %s midi=%s", symbol, join(notes), join(midis, ","))
    elseif command == "IDENTIFY" then
        local notes = parse_values(words, 2, Note.parse)
        local ordered = {}
        for i, note in ipairs(notes) do ordered[i] = {note = note, index = i} end
        table.sort(ordered, function(a, b)
            if a.note:midi() ~= b.note:midi() then return a.note:midi() < b.note:midi() end
            return a.index < b.index
        end)
        local candidates, target = {}, 0
        for _, entry in ipairs(ordered) do
            local bit = 1 << entry.note.pitch:class()
            if target & bit == 0 then candidates[#candidates + 1] = entry.note end
            target = target | bit
        end
        local bass = candidates[1]
        for _, root in ipairs(candidates) do
            for _, quality in ipairs(qualities) do
                local candidate, inversion = 0, 0
                for i, interval in ipairs(quality.pattern) do
                    local pitch_class = (root:midi() + interval:semitones()) % 12
                    candidate = candidate | (1 << pitch_class)
                    if pitch_class == bass.pitch:class() then inversion = i - 1 end
                end
                if candidate == target then
                    local symbol = quality:symbol(root.pitch) .. (inversion > 0 and "/" .. tostring(bass.pitch) or "")
                    return format("IDENTIFY %s root=%s quality=%s inversion=%d", symbol, root.pitch, quality.name, inversion)
                end
            end
        end
        return "IDENTIFY UNKNOWN"
    elseif command == "MELODY" then
        local notes = parse_values(words, 2, Note.parse)
        local low, high = notes[1], notes[1]
        for _, note in ipairs(notes) do
            if note:midi() < low:midi() then low = note end
            if note:midi() > high:midi() then high = note end
        end
        local range = between(low, high).interval
        local steps, leaps = {}, 0
        for i = 2, #notes do
            local motion = between(notes[i - 1], notes[i])
            steps[#steps + 1] = (motion.down and "-" or "+") .. tostring(motion.interval)
            if math.abs(notes[i]:midi() - notes[i - 1]:midi()) >= 3 then leaps = leaps + 1 end
        end
        return format("MELODY n=%d low=%s high=%s range=%s leaps=%d steps=%s", count, low, high, range, leaps, join(steps, ","))
    elseif command == "ENHARMONIC" then
        local input = Note.parse(words[2])
        local notes = {}
        for letter = 1, 7 do
            for alteration = -2, 2 do
                local pitch = Pitch.new(letter, alteration)
                if pitch:class() == input.pitch:class() then
                    local note = Note.from_midi(pitch, input:midi())
                    if note:valid() then notes[#notes + 1] = note end
                end
            end
        end
        table.sort(notes, function(a, b) return a:position() < b:position() end)
        return format("ENHARMONIC %s %s", input, join(notes))
    elseif command == "CIRCLE" then
        local mode = parse_mode(words[2])
        local tonics = {}
        for fifths = -7, 7 do tonics[#tonics + 1] = Key.at_fifths(fifths, mode).tonic end
        return "CIRCLE " .. mode .. " " .. join(tonics)
    elseif command == "FINDKEY" then
        local pitches = parse_values(words, 2, Pitch.parse)
        local keys = {}
        for fifths = -7, 7 do
            for _, mode in ipairs({"major", "minor"}) do
                local key = Key.at_fifths(fifths, mode)
                local scale, matches = key:scale(), true
                for _, pitch in ipairs(pitches) do
                    local found = false
                    for _, candidate in ipairs(scale) do if candidate == pitch then found = true; break end end
                    if not found then matches = false; break end
                end
                if matches then keys[#keys + 1] = key end
            end
        end
        return "FINDKEY " .. #keys .. (#keys > 0 and " " .. join(keys, ", ") or "")
    elseif command == "SPELL" then
        local midi = parse_number(words[2])
        local key = Key.parse(words[3], words[4])
        local pitch = Note.spelling(midi, key:fifths() < 0).pitch
        for _, candidate in ipairs(key:scale()) do
            if candidate:class() == midi % 12 then pitch = candidate; break end
        end
        local note = Note.from_midi(pitch, midi)
        if not note:valid() then fail("OUT OF RANGE") end
        return format("SPELL %d %s %s %s", midi, key, note, degree_label(key, pitch))
    end

    local key = Key.parse(words[2], words[3])
    if command == "KEYSIG" then
        local fifths = key:fifths()
        if fifths == 0 then return format("KEYSIG %s none", key) end
        local names = fifths > 0 and {"F#", "C#", "G#", "D#", "A#", "E#", "B#"} or {"Bb", "Eb", "Ab", "Db", "Gb", "Cb", "Fb"}
        local chosen = {}
        for i = 1, math.abs(fifths) do chosen[i] = names[i] end
        return format("KEYSIG %s %s=%d %s", key, fifths > 0 and "sharps" or "flats", math.abs(fifths), join(chosen))
    elseif command == "RELATIVE" then
        return format("RELATIVE %s major=%s minor=%s", key, Key.at_fifths(key:fifths(), "major").tonic, Key.at_fifths(key:fifths(), "minor").tonic)
    elseif command == "DEGREE" then
        local pitch = Pitch.parse(words[4])
        return format("DEGREE %s %s %s", key, pitch, degree_label(key, pitch))
    elseif command == "KEYDIST" then
        local other = Key.parse(words[4], words[5])
        local distance = (other:fifths() - key:fifths()) % 12
        if distance > 6 then distance = distance - 12 end
        local a, b = mask(key:scale()), mask(other:scale())
        local same_tonic = key.tonic:class() == other.tonic:class()
        local relation
        if a == b then relation = same_tonic and "same" or "relative"
        elseif same_tonic then relation = "parallel"
        elseif math.abs(distance) == 1 then relation = "close"
        else relation = "distant" end
        local common = 0
        for i = 0, 11 do if a & b & (1 << i) ~= 0 then common = common + 1 end end
        return format("KEYDIST %s %s fifths=%s common=%d relation=%s", key, other, signed_text(distance), common, relation)
    elseif command == "ANALYZE" then
        local chords = parse_values(words, 4, parse_symbol)
        local results = {}
        for i, chord in ipairs(chords) do
            local degree, prefix = key:degree(chord.root)
            results[i] = prefix .. chord.quality:roman(degree)
        end
        return format("ANALYZE %s %s", key, join(results))
    elseif command == "PROGRESSION" then
        local numerals = parse_values(words, 4, parse_numeral)
        local scale = key:scale()
        local lines = {format("PROGRESSION %s %d", key, #numerals)}
        for i, numeral in ipairs(numerals) do
            local degree = scale[numeral.degree]
            local root = Pitch.new(degree.letter, degree.alteration + numeral.alteration)
            local pitches = build(root, numeral.quality.pattern)
            lines[#lines + 1] = format("%s %s %s", words[i + 3], numeral.quality:symbol(root), join(pitches))
        end
        lines[#lines + 1] = "CADENCE " .. cadence(numerals)
        return join(lines, "\n")
    else
        local scale = key:scale()
        local lines = {format("DIATONIC %s", key)}
        for size = 3, 4 do
            local items = {}
            for i = 1, 7 do
                local third = (scale[(i + 1) % 7 + 1]:class() - scale[i]:class()) % 12
                local fifth = (scale[(i + 3) % 7 + 1]:class() - scale[i]:class()) % 12
                local seventh = (scale[(i + 5) % 7 + 1]:class() - scale[i]:class()) % 12
                local name
                if size == 3 then name = third == 4 and "maj" or (fifth == 7 and "min" or "dim")
                else name = third == 4 and (seventh == 11 and "maj7" or "7") or (fifth == 7 and "m7" or "m7b5") end
                local quality = quality_names[name]
                items[i] = quality:roman(i) .. "=" .. quality:symbol(scale[i])
            end
            lines[#lines + 1] = (size == 3 and "TRIADS " or "SEVENTHS ") .. join(items)
        end
        return join(lines, "\n")
    end
end

local count = tonumber(io.read("*l"), 10)
for _ = 1, count do
    local _, output = pcall(execute, io.read("*l"))
    io.write(output, "\n")
end
