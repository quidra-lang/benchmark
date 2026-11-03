module Chiptune
  module Report
    module_function

    def hex1(value) = format('%X', value)
    def hex2(value) = format('%02X', value)

    def hex_lines(samples)
      samples.each_slice(32).map { |group| group.map { |sample| hex2(sample) }.join }
    end

    def adler32(values)
      a = 1
      b = 0
      values.each do |value|
        a = (a + value) % 65521
        b = (b + a) % 65521
      end
      format('%08X', b * 65536 + a)
    end

    def isqrt(value) = Integer.sqrt(value)

    def peak(values, center = 0)
      values.map { |value| (value - center).abs }.max || 0
    end

    def rms(values, center = 0)
      isqrt(values.sum { |value| (value - center)**2 } / values.length)
    end

    def statistics(samples)
      { peak: peak(samples, 128), min: samples.min, max: samples.max,
        rms: rms(samples, 128),
        zero_crossings: samples.each_cons(2).count { |a, b| (a < 128) != (b < 128) },
        adler32: adler32(samples) }
    end
  end
end
