require_relative 'instruments'

module Chiptune
  module Mixer
    module_function

    def channel_value(channel)
      return 0 unless channel.sounding

      instrument = channel.instrument
      level = Instruments.wave_value(instrument, channel.mode, channel.phase, channel.register)
      channel.phase += channel.increment
      if channel.phase >= 65536
        channel.phase -= 65536
        if instrument.wave == 'NOISE'
          channel.register = Instruments.clock_register(channel.register, channel.mode)
        end
      end
      (2 * level - 15) * channel.amplitude
    end

    def mix_tick(channels, count, gain, muted, samples, lanes = nil)
      clipped = 0
      count.times do
        total = 0
        channels.each_with_index do |channel, index|
          value = channel_value(channel)
          lanes[index] << value if lanes
          total += value unless muted[index]
        end
        sample = 128 + gain * total / 4096
        if sample < 0 || sample > 255
          clipped += 1
          sample = sample.clamp(0, 255)
        end
        samples << sample
      end
      clipped
    end

    def fade_out(samples, fade)
      total = samples.length
      length = [fade, total].min
      (total - length...total).each do |index|
        samples[index] = 128 + (samples[index] - 128) * (total - 1 - index) / length
      end
    end
  end
end
