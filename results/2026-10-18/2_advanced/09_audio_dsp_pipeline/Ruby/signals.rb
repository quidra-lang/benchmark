module Signals
  Signal = Struct.new(:name, :rate, :samples, :origin, :ingredients, keyword_init: true) do
    def length
      samples.length
    end
  end

  class Saturator
    attr_reader :clips

    def initialize
      @clips = 0
    end

    def call(value)
      @clips += 1 if value < -32_768 || value > 32_767
      [[value, -32_768].max, 32_767].min
    end
  end

  module_function

  def create(name, rate, samples, origin, ingredients = [])
    Signal.new(name: name, rate: rate, samples: samples.freeze,
               origin: origin, ingredients: ingredients.freeze).freeze
  end

  def rdiv(numerator, denominator)
    (2 * numerator + denominator).div(2 * denominator)
  end

  def peak(samples)
    samples.map(&:abs).max
  end

  def two_decimals(value)
    "#{value.div(100)}.#{format('%02d', value % 100)}"
  end

  def read
    lines = File.readlines('input/signals.txt', chomp: true)
    signals = []
    index = 0
    while index < lines.length
      _tag, name, rate, count = lines[index].split(' ')
      index += 1
      samples = []
      ((count.to_i + 15).div(16)).times do
        samples.concat(lines[index].split(' ').map(&:to_i))
        index += 1
      end
      signals << create(name, rate.to_i, samples, 'input')
    end
    signals
  end

  def output(signal)
    lines = ["SIGNAL #{signal.name} #{signal.rate} #{signal.length}"]
    signal.samples.each_slice(16) { |values| lines << values.join(' ') }
    lines
  end

  def impulse(count, position, amplitude)
    samples = Array.new(count, 0)
    samples[position] = amplitude
    samples
  end

  def step(count, position, amplitude)
    Array.new(count) { |index| index >= position ? amplitude : 0 }
  end

  def noise(count, seed)
    Array.new(count) do
      seed = (48_271 * seed) % 2_147_483_647
      seed % 65_536 - 32_768
    end
  end
end
