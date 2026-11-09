local M = {}
local notes = {26163, 27718, 29366, 31113, 32963, 34923, 36999, 39200, 41530, 44000, 46616, 49388}
local sine = {0, 24, 49, 74, 97, 120, 141, 161, 180, 197, 212, 224, 235, 244, 250, 253, 255, 253, 250, 244, 235, 224, 212, 197, 180, 161, 141, 120, 97, 74, 49, 24}
function M.clamp(value, low, high)
    return math.min(math.max(value, low), high)
end
function M.frequency(note)
    local octave, pitch = note // 12, note % 12
    if octave >= 4 then
        return notes[pitch + 1] * (1 << (octave - 4))
    end
    return notes[pitch + 1] // (1 << (4 - octave))
end
function M.transpose(frequency, semitones)
    return (frequency * notes[semitones % 12 + 1] // notes[1]) * (1 << (semitones // 12))
end
function M.oscillation(position, depth, divisor)
    local value = sine[position % 32 + 1] * depth // divisor
    return position < 32 and value or -value
end
function M.envelope(instrument, age, released, release_age, release_level)
    if released then
        local elapsed = age - release_age
        if elapsed < instrument.release then
            return release_level * (instrument.release - 1 - elapsed) // instrument.release
        end
        return 0
    end
    if age < instrument.attack then
        return 15 * (age + 1) // instrument.attack
    end
    if age < instrument.attack + instrument.decay then
        return 15 - (15 - instrument.sustain) * (age - instrument.attack + 1) // instrument.decay
    end
    return instrument.sustain
end
function M.wave(instrument, mode, phase, register)
    if instrument.wave == "PULSE" then
        return phase // 8192 < ({1, 2, 4, 6})[mode + 1] and 15 or 0
    elseif instrument.wave == "TRIANGLE" then
        local step = phase // 2048
        return step < 16 and 15 - step or step - 16
    elseif instrument.wave == "SAW" then
        return phase // 4096
    elseif instrument.wave == "TABLE" then
        return instrument.table[phase // 2048 + 1]
    end
    return register % 2 == 0 and 15 or 0
end
function M.clock(register, mode)
    local tap = mode == 0 and 1 or 6
    return register // 2 + ((register ~ (register >> tap)) & 1) * 16384
end
return M
