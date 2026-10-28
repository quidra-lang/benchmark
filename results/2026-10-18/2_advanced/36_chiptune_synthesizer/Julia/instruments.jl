const NOTE_TABLE = (26163,27718,29366,31113,32963,34923,36999,39200,41530,44000,46616,49388)
const SINE_TABLE = (
    0,
    24,
    49,
    74,
    97,
    120,
    141,
    161,
    180,
    197,
    212,
    224,
    235,
    244,
    250,
    253,
    255,
    253,
    250,
    244,
    235,
    224,
    212,
    197,
    180,
    161,
    141,
    120,
    97,
    74,
    49,
    24
)
function note_frequency(note)
    octave,pitch = divrem(note,12)
    octave >= 4 ? NOTE_TABLE[pitch+1]*(1 << (octave-4)) : NOTE_TABLE[pitch+1]÷(1 << (4-octave))
end
transpose_frequency(
    frequency,
    semitones
) = frequency*NOTE_TABLE[semitones%12+1]÷NOTE_TABLE[1]*(1 << (semitones÷12))
function oscillation(position,depth,divisor)
    value = SINE_TABLE[position%32+1]*depth÷divisor
    position < 32 ? value : -value
end
function envelope_value(instrument,age,released,release_age,release_level)
    if released
        elapsed = age-release_age
        return elapsed < instrument.release ? fld(
            release_level*(instrument.release-1-elapsed),
            instrument.release
        ) : 0
    elseif age < instrument.attack
        return 15*(age+1)÷instrument.attack
    elseif age < instrument.attack+instrument.decay
        return 15-(15-instrument.sustain)*(age-instrument.attack+1)÷instrument.decay
    end
    instrument.sustain
end
function wave_value(instrument,mode,phase,register)
    instrument.wave == "PULSE" && return phase÷8192 < (1,2,4,6)[mode+1] ? 15 : 0
    if instrument.wave == "TRIANGLE"
        step = phase÷2048
        return step < 16 ? 15-step : step-16
    elseif instrument.wave == "SAW"
        return phase÷4096
    elseif instrument.wave == "TABLE"
        return instrument.table[phase÷2048+1]
    end
    register%2 == 0 ? 15 : 0
end
clock_register(register,mode) = register÷2+((register ⊻ (register >> (mode == 0 ? 1 : 6))) & 1)*16384
