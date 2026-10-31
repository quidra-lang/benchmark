local parser = require("song_parser")
local instruments = require("instruments")
local sequencer = require("sequencer")
local mixer = require("mixer")
local report = require("report")
local clamp, hex, note_name = instruments.clamp, report.hex, parser.note_name
local effect_order = {"0", "1", "2", "3", "4", "5", "6", "7", "A", "B", "C", "D", "E1", "E2", "E9", "EA", "EB", "EC", "ED", "EE", "F", "P", "Q", "R", "V"}
local tonics = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
local function append(target, values)
    for _, value in ipairs(values) do
        target[#target + 1] = value
    end
end
local function keys(values)
    local result = {}
    for key in pairs(values) do
        result[#result + 1] = key
    end
    table.sort(result)
    return result
end
local function segment(values, start, length)
    local result = {}
    for i = start + 1, start + length do
        result[#result + 1] = values[i]
    end
    return result
end
local function hex_list(values)
    local fields = {}
    for i, value in ipairs(values) do
        fields[i] = hex(value)
    end
    return #fields > 0 and table.concat(fields, " ") or "none"
end
local function note_range(notes)
    if #notes == 0 then
        return "none"
    end
    local low, high = notes[1], notes[1]
    for _, note in ipairs(notes) do
        low, high = math.min(low, note), math.max(high, note)
    end
    return note_name(low) .. ".." .. note_name(high)
end
local Channel = {}
Channel.__index = Channel
function Channel.new(number)
    return setmetatable({number = number, frequency = 0, target = 0, portamento = 0, slide = 0, detune = 0,
        vibrato_speed = 0, vibrato_depth = 0, vibrato_position = 0, tremolo_speed = 0, tremolo_depth = 0,
        tremolo_position = 0, volume = 15, mode = 0, phase = 0, register = 1, age = 0, released = false,
        release_age = 0, release_level = 0, envelope = 0, output_frequency = 0, output_volume = 0,
        amplitude = 0, increment = 0, sounding = false, note_ons = 0, retriggers = 0, cuts = 0, active = 0, audible = 0}, Channel)
end
function Channel:effect_name()
    return self.effect and self.effect.name
end
function Channel:effect_value()
    return self.effect and self.effect.value or 0
end
function Channel:key_off()
    self.release_age, self.release_level, self.released = self.age, self.envelope, true
end
function Channel:approach(step)
    if self.frequency < self.target then
        self.frequency = math.min(self.frequency + step, self.target)
    else
        self.frequency = math.max(self.frequency - step, self.target)
    end
end
function Channel:volume_slide()
    self.volume = clamp(self.volume + self.effect.high - self.effect.low, 0, 15)
end
function Channel:update_output(tick, rate)
    local instrument, name = self.instrument, self:effect_name()
    local semitones = 0
    if name == "0" then
        semitones = ({0, self.effect.high, self.effect.low})[tick % 3 + 1]
    end
    if #instrument.arpeggio > 0 then
        semitones = semitones + instrument.arpeggio[self.age % #instrument.arpeggio + 1]
    end
    local frequency = instruments.transpose(self.frequency, semitones) + self.detune
    if name == "4" or name == "6" then
        frequency = frequency + instruments.oscillation(self.vibrato_position, self.vibrato_depth, 4)
    end
    if instrument.vibrato and self.age >= instrument.vibrato[1] then
        frequency = frequency + instruments.oscillation((self.age - instrument.vibrato[1]) * instrument.vibrato[2] % 64, instrument.vibrato[3], 4)
    end
    self.output_frequency = clamp(frequency, 1000, 50 * rate)
    self.envelope = instruments.envelope(instrument, self.age, self.released, self.release_age, self.release_level)
    self.output_volume = self.volume
    if name == "7" then
        self.output_volume = clamp(self.volume + instruments.oscillation(self.tremolo_position, self.tremolo_depth, 255), 0, 15)
    end
    self.amplitude = self.envelope * self.output_volume
    self.increment = self.output_frequency * 65536 // (100 * rate)
end
local Player = {}
Player.__index = Player
function Player.new(song, params)
    local self = setmetatable({song = song, params = params, fmax = 50 * song.rate, channels = {}, lanes = {}, samples = {},
        speed = song.speed, tempo = song.tempo, delay = 0, position = 0, row = 0, records = {}, warnings = {}, log = {},
        played = {}, play_counts = {}, first_starts = {}, ticks = 0, clipped = 0, instrument_ticks = {}, effect_counts = {}, end_reason = "finished"}, Player)
    for i = 1, 4 do
        self.channels[i], self.lanes[i] = Channel.new(i), {}
    end
    for number in pairs(song.instruments) do
        self.instrument_ticks[number] = 0
    end
    for _, name in ipairs(effect_order) do
        self.effect_counts[name] = 0
    end
    return self
end
function Player:warn(channel, message)
    self.warnings[#self.warnings + 1] = "warning " .. hex(self.position) .. ":" .. hex(self.row) .. " ch" .. channel.number .. " " .. message
end
function Player:end_record(channel, reason)
    local record = channel.record
    record.length, record.reason = #self.samples - record.start, reason
    channel.record = nil
end
function Player:note_on(channel, note)
    if channel.record then
        self:end_record(channel, "next")
    end
    channel.frequency = instruments.frequency(note)
    channel.target, channel.phase, channel.age = channel.frequency, 0, 0
    channel.vibrato_position, channel.tremolo_position, channel.released = 0, 0, false
    channel.note, channel.note_ons = note, channel.note_ons + 1
    channel.record = {serial = #self.records + 1, channel = channel.number, position = self.position, row = self.row,
        instrument = channel.instrument, note = note, start = #self.samples, length = 0}
    self.records[#self.records + 1] = channel.record
end
function Player:apply_cell(channel, cell, portamento)
    if cell.instrument then
        local instrument = self.song.instruments[cell.instrument]
        if instrument then
            channel.instrument, channel.volume, channel.mode = instrument, 15, instrument.mode
        else
            self:warn(channel, "undefined instrument " .. hex(cell.instrument))
        end
    end
    if cell.volume ~= nil then
        channel.volume = cell.volume
    end
    if cell.key_off then
        if channel.note and not channel.released then
            channel:key_off()
            channel.record.release = #self.samples - channel.record.start
        else
            self:warn(channel, "key off without note")
        end
    elseif cell.note then
        if not channel.instrument then
            self:warn(channel, "note without instrument")
        elseif portamento and channel.note then
            channel.target, channel.note = instruments.frequency(cell.note), cell.note
        else
            if portamento then
                self:warn(channel, "portamento without note")
            end
            self:note_on(channel, cell.note)
        end
    end
end
function Player:start_effect(channel)
    local effect = channel.effect
    local name, value = effect.name, effect.value
    if name == "3" then
        if value > 0 then
            channel.portamento = value
        end
    elseif name == "4" then
        if effect.high > 0 then
            channel.vibrato_speed = effect.high
        end
        if effect.low > 0 then
            channel.vibrato_depth = effect.low
        end
    elseif name == "7" then
        if effect.high > 0 then
            channel.tremolo_speed = effect.high
        end
        if effect.low > 0 then
            channel.tremolo_depth = effect.low
        end
    elseif name == "C" then
        channel.volume = math.min(value, 15)
    elseif name == "E1" then
        channel.frequency = clamp(channel.frequency + 10 * value, 1000, self.fmax)
    elseif name == "E2" then
        channel.frequency = clamp(channel.frequency - 10 * value, 1000, self.fmax)
    elseif name == "EA" then
        channel.volume = math.min(channel.volume + value, 15)
    elseif name == "EB" then
        channel.volume = math.max(channel.volume - value, 0)
    elseif name == "EE" then
        self.delay = value
    elseif name == "F" then
        if value >= 1 and value <= 31 then
            self.speed = value
        elseif value >= 32 then
            self.tempo = value
        end
    elseif name == "P" then
        channel.detune = value - 128
    elseif name == "Q" or name == "R" then
        if not channel.note then
            self:warn(channel, "slide without note")
        else
            if name == "Q" then
                channel.note = math.min(channel.note + effect.low, 95)
            else
                channel.note = math.max(channel.note - effect.low, 12)
            end
            channel.target, channel.slide = instruments.frequency(channel.note), 2 * effect.high + 1
        end
    elseif name == "V" then
        local instrument = channel.instrument
        if instrument and ((instrument.wave == "PULSE" and value <= 3) or (instrument.wave == "NOISE" and value <= 1)) then
            channel.mode = value
        else
            self:warn(channel, "invalid mode " .. hex(value))
        end
    end
end
function Player:tick_effect(channel)
    local name, value = channel.effect.name, channel.effect.value
    if name == "1" then
        channel.frequency = clamp(channel.frequency + 10 * value, 1000, self.fmax)
    elseif name == "2" then
        channel.frequency = clamp(channel.frequency - 10 * value, 1000, self.fmax)
    elseif name == "3" or name == "5" then
        channel:approach(10 * channel.portamento)
        if name == "5" then
            channel:volume_slide()
        end
    elseif name == "6" or name == "A" then
        channel:volume_slide()
    elseif (name == "Q" or name == "R") and channel.slide ~= 0 then
        channel:approach(10 * channel.slide)
    end
end
function Player:start_row()
    self.delay = 0
    for i, channel in ipairs(self.channels) do
        local cell = self.cells[i]
        channel.effect, channel.slide = cell.effect, 0
        local name, value = channel:effect_name(), channel:effect_value()
        if name then
            self.effect_counts[name] = self.effect_counts[name] + 1
        end
        if not (name == "ED" and value >= 1) then
            self:apply_cell(channel, cell, name == "3" or name == "5")
        end
        if name then
            self:start_effect(channel)
        end
    end
end
function Player:process_tick(tick)
    for i, channel in ipairs(self.channels) do
        local name, value = channel:effect_name(), channel:effect_value()
        if channel.note and channel.age >= 1 and channel.instrument.sweep ~= 0 then
            channel.frequency = clamp(channel.frequency + 10 * channel.instrument.sweep, 1000, self.fmax)
        end
        if tick >= 1 and name then
            self:tick_effect(channel)
        end
        if name == "ED" and value >= 1 and tick == value then
            self:apply_cell(channel, self.cells[i], false)
        end
        if name == "E9" and value >= 1 and tick >= 1 and tick % value == 0 and channel.note then
            channel.phase, channel.age, channel.released = 0, 0, false
            channel.retriggers = channel.retriggers + 1
        end
        if name == "EC" and tick == value and channel.note then
            self:end_record(channel, "cut")
            channel.note, channel.cuts = nil, channel.cuts + 1
        end
        channel.sounding = channel.note ~= nil
        if channel.sounding then
            channel:update_output(tick, self.song.rate)
            channel.active = channel.active + 1
            if channel.amplitude > 0 then
                channel.audible = channel.audible + 1
            end
            local number = channel.instrument.number
            self.instrument_ticks[number] = self.instrument_ticks[number] + 1
        end
    end
end
function Player:advance()
    for _, channel in ipairs(self.channels) do
        local name = channel:effect_name()
        if channel.note then
            channel.age = channel.age + 1
        end
        if name == "4" or name == "6" then
            channel.vibrato_position = (channel.vibrato_position + channel.vibrato_speed) % 64
        elseif name == "7" then
            channel.tremolo_position = (channel.tremolo_position + channel.tremolo_speed) % 64
        end
    end
    self.ticks = self.ticks + 1
end
function Player:log_row(start)
    local parts = {string.format("%s %s %s %7d %2d %3d", hex(self.position), hex(self.song.order[self.position + 1]), hex(self.row), start, self.speed, self.tempo)}
    local notes = {}
    for i, channel in ipairs(self.channels) do
        local effect = channel.effect and channel.effect.text or "..."
        if channel.note then
            parts[#parts + 1] = string.format("%s %s %7d %s %s %s", note_name(channel.note), hex(channel.instrument.number), channel.output_frequency, hex(channel.envelope, 1), hex(channel.output_volume, 1), effect)
        else
            parts[#parts + 1] = string.format("--- -- %7s - %s %s", "-", hex(channel.volume, 1), effect)
        end
        notes[i] = channel.note or false
    end
    self.log[#self.log + 1] = table.concat(parts, " | ")
    self.played[#self.played + 1] = {position = self.position, row = self.row, start = start, speed = self.speed, tempo = self.tempo, notes = notes}
end
function Player:log_tick(tick)
    local parts = {string.format("  tick %3d %7d", tick, #self.samples)}
    for _, channel in ipairs(self.channels) do
        if channel.sounding then
            parts[#parts + 1] = string.format("%7d %5d %s%s", channel.output_frequency, channel.increment, hex(channel.envelope, 1), hex(channel.output_volume, 1))
        else
            parts[#parts + 1] = string.format("%7s %5s --", "-", "-")
        end
    end
    self.log[#self.log + 1] = table.concat(parts, " | ")
end
function Player:play_row(position, row)
    self.position, self.row = position, row
    self.cells = parser.cells(self.song, position, row)
    local start, key = #self.samples, position * 64 + row
    if self.first_starts[key] == nil then
        self.first_starts[key] = start
    end
    self:start_row()
    local ticks = self.speed * (1 + self.delay)
    for _, channel in ipairs(self.channels) do
        local name, value = channel:effect_name(), channel:effect_value()
        if name == "EC" and value >= ticks then
            self:warn(channel, "cut beyond row")
        elseif name == "ED" and value >= ticks then
            self:warn(channel, "delay beyond row")
        end
    end
    local tick_samples = sequencer.samples_per_tick(self.song.rate, self.tempo)
    for tick = 0, ticks - 1 do
        self:process_tick(tick)
        if tick == 0 then
            self:log_row(start)
        end
        if self.params.traces[key] then
            self:log_tick(tick)
        end
        local count = math.min(tick_samples, self.params.max_samples - #self.samples)
        self.clipped = self.clipped + mixer.tick(self.channels, count, self.song.gain, self.params.muted, self.samples, self.lanes)
        self:advance()
        if #self.samples == self.params.max_samples then
            return false
        end
    end
    return true
end
function Player:play()
    local position, row = 0, 0
    while true do
        local key = position * 64 + row
        self.play_counts[key] = (self.play_counts[key] or 0) + 1
        if not self:play_row(position, row) then
            self.end_reason = "limit"
            break
        end
        local next_position, next_row = sequencer.next_row(self.song, position, row)
        if next_position == nil then
            self.end_reason, self.end_position, self.end_row = "stop", position, row
            break
        end
        position, row = next_position, next_row
        if position >= #self.song.order then
            self.end_reason = "finished"
            break
        end
        key = position * 64 + row
        if (self.play_counts[key] or 0) >= self.params.loops then
            self.end_reason, self.end_position, self.end_row = "loop", position, row
            self.loop_start = self.first_starts[key]
            break
        end
    end
    for _, channel in ipairs(self.channels) do
        if channel.record then
            self:end_record(channel, "end")
        end
    end
    if (self.end_reason == "limit" or self.end_reason == "loop") and self.params.fade > 0 then
        mixer.fade(self.samples, self.params.fade)
    end
end
local function note_lines(player)
    local lines = {}
    for _, record in ipairs(player.records) do
        local values = segment(player.lanes[record.channel], record.start, record.length)
        local cycles = 0
        for i = 2, #values do
            if values[i - 1] < 0 and values[i] >= 0 then
                cycles = cycles + 1
            end
        end
        lines[#lines + 1] = string.format("%4d ch=%d at=%s:%s ins=%s note=%s start=%d length=%d release=%s end=%s peak=%d cycles=%d",
            record.serial, record.channel, hex(record.position), hex(record.row), hex(record.instrument.number), note_name(record.note), record.start, record.length,
            record.release ~= nil and tostring(record.release) or "-", record.reason, report.peak(values, 0), cycles)
    end
    return lines
end
local function roll_lines(player)
    local start, finish = player.params.roll_start, math.min(#player.played, player.params.roll_start + player.params.roll_rows)
    local pitches = {}
    for i = start + 1, finish do
        for _, note in ipairs(player.played[i].notes) do
            if note then
                pitches[note] = true
            end
        end
    end
    local order, width = keys(pitches), math.max(0, finish - start)
    local lines = {"ROLL start=" .. start .. " rows=" .. width .. " pitches=" .. #order}
    for index = #order, 1, -1 do
        local marks, pitch = {}, order[index]
        for i = start + 1, finish do
            local count, owner = 0, 0
            for channel, note in ipairs(player.played[i].notes) do
                if note == pitch then
                    count, owner = count + 1, channel
                end
            end
            marks[#marks + 1] = count == 0 and " " or (count == 1 and tostring(owner) or "*")
        end
        lines[#lines + 1] = note_name(pitch) .. " |" .. table.concat(marks) .. "|"
    end
    local ruler = {}
    for i = 0, width - 1 do
        ruler[#ruler + 1] = i % 16 == 0 and "+" or "-"
    end
    lines[#lines + 1] = "    +" .. table.concat(ruler) .. "+"
    return lines
end
local function stats_lines(player)
    local song, samples, params = player.song, player.samples, player.params
    local count, low, high = #samples, samples[1], samples[1]
    for _, sample in ipairs(samples) do
        low, high = math.min(low, sample), math.max(high, sample)
    end
    local ending = player.end_reason
    if ending == "stop" or ending == "loop" then
        ending = ending .. " order=" .. hex(player.end_position) .. " row=" .. hex(player.end_row)
    end
    local lines = {"title=" .. song.title, "rate=" .. song.rate, "samples=" .. count,
        "duration_ms=" .. (count * 1000 // song.rate), "end=" .. ending,
        "loop_start=" .. (player.loop_start ~= nil and tostring(player.loop_start) or "-"),
        "loop_length=" .. (player.loop_start ~= nil and tostring(count - player.loop_start) or "-"),
        "rows=" .. #player.played, "ticks=" .. player.ticks, "clipped=" .. player.clipped,
        "peak=" .. report.peak(samples, 128), "min=" .. low, "max=" .. high,
        "rms=" .. report.rms(samples, 128), "zero_crossings=" .. report.crossings(samples), "adler32=" .. report.adler(samples)}
    local path, previous_position = {}, nil
    for _, row in ipairs(player.played) do
        if row.position ~= previous_position then
            path[#path + 1] = hex(row.position)
            previous_position = row.position
        end
    end
    lines[#lines + 1] = "path " .. table.concat(path, " ")
    local previous_speed, previous_tempo
    for _, row in ipairs(player.played) do
        if row.speed ~= previous_speed or row.tempo ~= previous_tempo then
            lines[#lines + 1] = "timing sample=" .. row.start .. " order=" .. hex(row.position) .. " row=" .. hex(row.row) .. " speed=" .. row.speed .. " tempo=" .. row.tempo
        end
        previous_speed, previous_tempo = row.speed, row.tempo
    end
    for i, channel in ipairs(player.channels) do
        lines[#lines + 1] = "channel " .. i .. " notes=" .. channel.note_ons .. " retriggers=" .. channel.retriggers .. " cuts=" .. channel.cuts .. " active=" .. channel.active .. " audible=" .. channel.audible .. " peak=" .. report.peak(player.lanes[i], 0) .. " rms=" .. report.rms(player.lanes[i], 0)
    end
    local instrument_numbers, pattern_numbers = keys(song.instruments), keys(song.patterns)
    local used_instruments, note_counts, pitch_classes = {}, {}, {}
    for i = 1, 12 do
        pitch_classes[i] = 0
    end
    for _, record in ipairs(player.records) do
        used_instruments[record.instrument.number] = true
        note_counts[record.note] = (note_counts[record.note] or 0) + 1
        if record.instrument.wave ~= "NOISE" then
            local pitch = record.note % 12 + 1
            pitch_classes[pitch] = pitch_classes[pitch] + record.length
        end
    end
    for _, number in ipairs(instrument_numbers) do
        local instrument, notes, length = song.instruments[number], {}, 0
        for _, record in ipairs(player.records) do
            if record.instrument.number == number then
                notes[#notes + 1] = record.note
                length = length + record.length
            end
        end
        local average = #notes > 0 and tostring(length // #notes) or "-"
        lines[#lines + 1] = "instrument " .. hex(number) .. " " .. instrument.name .. " " .. instrument.wave .. " notes=" .. #notes .. " ticks=" .. player.instrument_ticks[number] .. " range=" .. note_range(notes) .. " average=" .. average
    end
    local order_counts = {}
    for _, number in ipairs(song.order) do
        order_counts[number] = (order_counts[number] or 0) + 1
    end
    for _, number in ipairs(pattern_numbers) do
        local rows, notes = 0, 0
        for row = 0, 63 do
            local nonempty = false
            for _, cell in ipairs(song.patterns[number].rows[row]) do
                nonempty = nonempty or not cell.empty
                if cell.has_note then
                    notes = notes + 1
                end
            end
            if nonempty then
                rows = rows + 1
            end
        end
        lines[#lines + 1] = "pattern " .. hex(number) .. " rows=" .. rows .. " notes=" .. notes .. " orders=" .. (order_counts[number] or 0)
    end
    local reached, played_positions = sequencer.reachable(song), {}
    for position = 0, #song.order - 1 do
        local rows, first, dead = 0, "-", 0
        for _, row in ipairs(player.played) do
            if row.position == position then
                if rows == 0 then
                    first = tostring(row.start)
                end
                rows = rows + 1
            end
        end
        if rows > 0 then
            played_positions[position] = true
        end
        for row = 0, 63 do
            if not reached[position * 64 + row] then
                for _, cell in ipairs(parser.cells(song, position, row)) do
                    if cell.has_note then
                        dead = dead + 1
                        break
                    end
                end
            end
        end
        lines[#lines + 1] = "order " .. hex(position) .. " pattern=" .. hex(song.order[position + 1]) .. " rows=" .. rows .. " first=" .. first .. " dead=" .. dead
    end
    for _, note in ipairs(keys(note_counts)) do
        lines[#lines + 1] = "note " .. note_name(note) .. " count=" .. note_counts[note]
    end
    local effects = {}
    for _, name in ipairs(effect_order) do
        if player.effect_counts[name] > 0 then
            effects[#effects + 1] = name .. "=" .. player.effect_counts[name]
        end
    end
    lines[#lines + 1] = "effects " .. (#effects > 0 and table.concat(effects, " ") or "none")
    local unused_instruments, unused_patterns, unreached_orders = {}, {}, {}
    for _, number in ipairs(instrument_numbers) do
        if not used_instruments[number] then
            unused_instruments[#unused_instruments + 1] = number
        end
    end
    for _, number in ipairs(pattern_numbers) do
        if not order_counts[number] then
            unused_patterns[#unused_patterns + 1] = number
        end
    end
    for position = 0, #song.order - 1 do
        if not played_positions[position] then
            unreached_orders[#unreached_orders + 1] = position
        end
    end
    append(lines, {"unused_instruments=" .. hex_list(unused_instruments), "unused_patterns=" .. hex_list(unused_patterns), "unreached_orders=" .. hex_list(unreached_orders)})
    local fields = {}
    for i, tonic in ipairs(tonics) do
        fields[i] = tonic .. "=" .. pitch_classes[i]
    end
    lines[#lines + 1] = "pitch_classes " .. table.concat(fields, " ")
    local weights = {{64, 22, 35, 23, 44, 41, 25, 52, 24, 37, 23, 29}, {64, 27, 35, 54, 27, 35, 25, 48, 40, 27, 34, 32}}
    local modes, candidates = {"major", "minor"}, {}
    for mode = 1, 2 do
        for tonic = 0, 11 do
            local score = 0
            for pitch = 0, 11 do
                score = score + weights[mode][(pitch - tonic) % 12 + 1] * pitch_classes[pitch + 1]
            end
            candidates[#candidates + 1] = {name = tonics[tonic + 1] .. " " .. modes[mode], score = score, index = #candidates + 1}
        end
    end
    table.sort(candidates, function(a, b) return a.score > b.score or (a.score == b.score and a.index < b.index) end)
    lines[#lines + 1] = "key=" .. candidates[1].name .. " score=" .. candidates[1].score .. " runner_up=" .. candidates[2].name .. " score=" .. candidates[2].score
    for channel = 1, 4 do
        local notes, counts = {}, {}
        for _, record in ipairs(player.records) do
            if record.channel == channel then
                notes[#notes + 1] = record.note
                counts[record.instrument.number] = (counts[record.instrument.number] or 0) + 1
            end
        end
        fields = {"usage ch" .. channel .. " range=" .. note_range(notes)}
        for _, number in ipairs(instrument_numbers) do
            fields[#fields + 1] = hex(number) .. "=" .. (counts[number] or 0)
        end
        lines[#lines + 1] = table.concat(fields, " ")
    end
    append(lines, player.warnings)
    return lines
end
local function plot_lines(values, low, high, middle, height, width)
    local function row(value)
        return (2 * (high - value) * (height - 1) + (high - low)) // (2 * (high - low))
    end
    local columns, middle_row, lines = {}, row(middle), {}
    for column = 0, width - 1 do
        local start, finish = column * #values // width + 1, (column + 1) * #values // width
        local top, bottom = values[start], values[start]
        for i = start, finish do
            top, bottom = math.max(top, values[i]), math.min(bottom, values[i])
        end
        columns[column + 1] = {row(top), row(bottom)}
    end
    for r = 0, height - 1 do
        local label, marks = "", {}
        if r == 0 then
            label = tostring(high)
        elseif r == middle_row then
            label = tostring(middle)
        elseif r == height - 1 then
            label = tostring(low)
        end
        for i, limits in ipairs(columns) do
            marks[i] = r >= limits[1] and r <= limits[2] and "#" or (r == middle_row and "-" or " ")
        end
        lines[#lines + 1] = string.format("%5s |%s|", label, table.concat(marks))
    end
    return lines
end
local function waveform_lines(player)
    local params = player.params
    local start, length, width = params.window_start, params.window_length, params.window_width
    local ruler, labels = {}, "    ms"
    for column = 0, width - 1 do
        ruler[#ruler + 1] = column % 10 == 0 and "+" or "-"
        if column % 10 == 0 then
            labels = labels .. string.rep(" ", math.max(0, 7 + column - #labels)) .. ((start + column * length // width) * 1000 // player.song.rate)
        end
    end
    local axes = {"      +" .. table.concat(ruler) .. "+", labels}
    local lines = {"MIX start=" .. start .. " length=" .. length .. " width=" .. width .. " height=" .. params.window_height}
    append(lines, plot_lines(segment(player.samples, start, length), 0, 255, 128, params.window_height, width))
    append(lines, axes)
    for channel = 1, 4 do
        lines[#lines + 1] = "CHANNEL " .. channel
        append(lines, plot_lines(segment(player.lanes[channel], start, length), -3375, 3375, 0, params.window_scope, width))
    end
    append(lines, axes)
    return lines
end
local function preview_lines(song, params, instrument)
    local channel = Channel.new(1)
    channel.instrument, channel.mode, channel.note = instrument, instrument.mode, params.preview_note
    channel.frequency = instruments.frequency(params.preview_note)
    channel.target, channel.sounding = channel.frequency, true
    local samples, envelopes, frequencies = {}, {}, {}
    local count = sequencer.samples_per_tick(song.rate, song.tempo)
    for tick = 0, params.preview_ticks - 1 do
        channel.age = tick
        if tick == params.preview_release then
            channel:key_off()
        end
        if tick >= 1 and instrument.sweep ~= 0 then
            channel.frequency = clamp(channel.frequency + 10 * instrument.sweep, 1000, 50 * song.rate)
        end
        channel:update_output(tick, song.rate)
        envelopes[#envelopes + 1] = hex(channel.envelope, 1)
        frequencies[#frequencies + 1] = tostring(channel.output_frequency)
        mixer.tick({channel}, count, song.gain, {0}, samples, {{}})
    end
    return {"instrument " .. hex(instrument.number) .. " " .. instrument.name .. " wave=" .. instrument.wave .. " samples=" .. #samples .. " peak=" .. report.peak(samples, 128) .. " rms=" .. report.rms(samples, 128) .. " adler32=" .. report.adler(samples),
        "  env " .. table.concat(envelopes), "  freq " .. table.concat(frequencies, " ")}
end
local function write_lines(name, lines)
    local file = assert(io.open("output/" .. name, "w"))
    for _, line in ipairs(lines) do
        file:write(line, "\n")
    end
    file:close()
end
local song = parser.read_song("input/song.txt")
local params = parser.read_params("input/params.txt")
local player = Player.new(song, params)
player:play()
local previews = {}
for _, number in ipairs(keys(song.instruments)) do
    append(previews, preview_lines(song, params, song.instruments[number]))
end
os.execute('mkdir -p output')
write_lines("samples.txt", report.hex_lines(player.samples))
write_lines("channel_log.txt", player.log)
write_lines("notes.txt", note_lines(player))
write_lines("roll.txt", roll_lines(player))
write_lines("stats.txt", stats_lines(player))
write_lines("waveform.txt", waveform_lines(player))
write_lines("instruments.txt", previews)
