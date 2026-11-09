local M = {}
local pitches = {"C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"}
local function words(text)
    local values = {}
    for value in text:gmatch("[^ ]+") do
        values[#values + 1] = value
    end
    return values
end
function M.note_number(name)
    local pitch = name:sub(1, 2)
    for i, value in ipairs(pitches) do
        if value == pitch then
            return 12 * tonumber(name:sub(3)) + i - 1
        end
    end
end
function M.note_name(number)
    return pitches[number % 12 + 1] .. (number // 12)
end
local function cell(text)
    local note, instrument, volume, effect = text:sub(1, 3), text:sub(5, 6), text:sub(8, 8), text:sub(10, 12)
    local result = {key_off = note == "OFF", has_note = note ~= "...", empty = text == "... .. . ..."}
    if note ~= "..." and note ~= "OFF" then
        result.note = M.note_number(note)
    end
    if instrument ~= ".." then
        result.instrument = tonumber(instrument, 16)
    end
    if volume ~= "." then
        result.volume = tonumber(volume, 16)
    end
    if effect ~= "..." then
        local extended = effect:sub(1, 1) == "E"
        local value = tonumber(effect:sub(extended and 3 or 2), 16)
        result.effect = {text = effect, name = effect:sub(1, extended and 2 or 1), value = value, high = value // 16, low = value % 16}
    end
    return result
end
function M.read_song(path)
    local lines = {}
    for line in io.lines(path) do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            lines[#lines + 1] = line
        end
    end
    local song = {title = lines[1]:sub(7), rate = tonumber(lines[2]:sub(6)), speed = tonumber(lines[3]:sub(7)),
        tempo = tonumber(lines[4]:sub(7)), gain = tonumber(lines[5]:sub(6)), instruments = {}, patterns = {}, order = {}}
    local index = 6
    while index <= #lines do
        local header = words(lines[index])
        index = index + 1
        if header[1] == "ORDER" then
            for i = 2, #header do
                song.order[#song.order + 1] = tonumber(header[i], 16)
            end
        elseif header[1] == "INSTRUMENT" then
            local instrument = {number = tonumber(header[2], 16), name = header[3], mode = 0, arpeggio = {}, sweep = 0, table = {}}
            while lines[index] ~= "END" do
                local row = words(lines[index])
                if row[1] == "WAVE" then
                    instrument.wave = row[2]
                    if row[2] == "PULSE" then
                        instrument.mode = ({["12"] = 0, ["25"] = 1, ["50"] = 2, ["75"] = 3})[row[3]]
                    elseif row[2] == "NOISE" then
                        instrument.mode = row[3] == "SHORT" and 1 or 0
                    elseif row[2] == "TABLE" then
                        for i = 1, 32 do
                            instrument.table[i] = tonumber(row[3]:sub(i, i), 16)
                        end
                    end
                elseif row[1] == "ENVELOPE" then
                    instrument.attack, instrument.decay, instrument.sustain, instrument.release = tonumber(row[2]), tonumber(row[3]), tonumber(row[4]), tonumber(row[5])
                elseif row[1] == "VIBRATO" then
                    instrument.vibrato = {tonumber(row[2]), tonumber(row[3]), tonumber(row[4])}
                elseif row[1] == "ARPEGGIO" then
                    for i = 2, #row do
                        instrument.arpeggio[#instrument.arpeggio + 1] = tonumber(row[i])
                    end
                elseif row[1] == "SWEEP" then
                    instrument.sweep = tonumber(row[2])
                end
                index = index + 1
            end
            index = index + 1
            song.instruments[instrument.number] = instrument
        else
            local pattern = {number = tonumber(header[2], 16), rows = {}}
            for row = 0, 63 do
                pattern.rows[row] = {}
                for channel = 1, 4 do
                    pattern.rows[row][channel] = cell("... .. . ...")
                end
            end
            while lines[index] ~= "END" do
                local line = lines[index]
                local row = tonumber(line:sub(1, 2), 16)
                local cells = {}
                for channel = 1, 4 do
                    local start = 4 + (channel - 1) * 15
                    cells[channel] = cell(line:sub(start, start + 11))
                end
                pattern.rows[row] = cells
                index = index + 1
            end
            index = index + 1
            song.patterns[pattern.number] = pattern
        end
    end
    return song
end
function M.cells(song, position, row)
    return song.patterns[song.order[position + 1]].rows[row]
end
function M.read_params(path)
    local params = {traces = {}}
    for line in io.lines(path) do
        local row = words(line)
        local key = table.remove(row, 1)
        if key == "preview" then
            params.preview_note = M.note_number(row[1])
            params.preview_ticks, params.preview_release = tonumber(row[2]), tonumber(row[3])
        elseif key == "trace" then
            params.traces[tonumber(row[1], 16) * 64 + tonumber(row[2], 16)] = true
        else
            for i, value in ipairs(row) do
                row[i] = tonumber(value)
            end
            if key == "window" then
                params.window_start, params.window_length, params.window_width, params.window_height, params.window_scope = table.unpack(row)
            elseif key == "roll" then
                params.roll_start, params.roll_rows = row[1], row[2]
            elseif key == "mute" then
                params.muted = row
            else
                params[key] = row[1]
            end
        end
    end
    return params
end
return M
