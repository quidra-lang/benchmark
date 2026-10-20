module Chiptune
  module Instruments
    FREQUENCIES = [26163, 27718, 29366, 31113, 32963, 34923,
                   36999, 39200, 41530, 44000, 46616, 49388].freeze
    SINE = [0, 24, 49, 74, 97, 120, 141, 161, 180, 197, 212, 224, 235, 244, 250, 253,
            255, 253, 250, 244, 235, 224, 212, 197, 180, 161, 141, 120, 97, 74, 49, 24].freeze
    PULSE_WIDTHS = [1, 2, 4, 6].freeze

    module_function

    def note_frequency(note)
      octave, pitch = note.divmod(12)
      if octave >= 4
        FREQUENCIES[pitch] * 2**(octave - 4)
      else
        FREQUENCIES[pitch] / 2**(4 - octave)
      end
    end

    def transpose(frequency, semitones)
      octaves, pitch = semitones.divmod(12)
      frequency * FREQUENCIES[pitch] / FREQUENCIES[0] * 2**octaves
    end

    def oscillation(position, depth, divisor)
      value = SINE[position % 32] * depth / divisor
      position < 32 ? value : -value
    end

    def envelope_value(instrument, age, released, release_age, release_level)
      attack, decay, sustain, release = instrument.envelope
      if released
        elapsed = age - release_age
        return elapsed < release ? release_level * (release - 1 - elapsed) / release : 0
      end
      return 15 * (age + 1) / attack if age < attack
      if age < attack + decay
        return 15 - (15 - sustain) * (age - attack + 1) / decay
      end

      sustain
    end

    def wave_value(instrument, mode, phase, register)
      case instrument.wave
      when 'PULSE' then phase / 8192 < PULSE_WIDTHS[mode] ? 15 : 0
      when 'TRIANGLE'
        step = phase / 2048
        step < 16 ? 15 - step : step - 16
      when 'SAW' then phase / 4096
      when 'TABLE' then instrument.table[phase / 2048]
      when 'NOISE' then register.even? ? 15 : 0
      end
    end

    def clock_register(register, mode)
      tap = mode.zero? ? 1 : 6
      feedback = (register ^ (register >> tap)) & 1
      register / 2 + feedback * 16384
    end
  end
end
