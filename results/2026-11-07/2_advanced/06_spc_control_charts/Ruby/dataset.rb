# frozen_string_literal: true

module Dataset
  CONSTANT_NAMES = %i[a2 a3 b3 b4 d3 d4 d2 c4].freeze
  CONSTANTS = {
    2 => [1.880, 2.659, 0.0, 3.267, 0.0, 3.267, 1.128, 0.7979],
    3 => [1.023, 1.954, 0.0, 2.568, 0.0, 2.574, 1.693, 0.8862],
    4 => [0.729, 1.628, 0.0, 2.266, 0.0, 2.282, 2.059, 0.9213],
    5 => [0.577, 1.427, 0.0, 2.089, 0.0, 2.114, 2.326, 0.9400],
    6 => [0.483, 1.287, 0.030, 1.970, 0.0, 2.004, 2.534, 0.9515],
    7 => [0.419, 1.182, 0.118, 1.882, 0.076, 1.924, 2.704, 0.9594],
    8 => [0.373, 1.099, 0.185, 1.815, 0.136, 1.864, 2.847, 0.9650],
    9 => [0.337, 1.032, 0.239, 1.761, 0.184, 1.816, 2.970, 0.9693],
    10 => [0.308, 0.975, 0.284, 1.716, 0.223, 1.777, 3.078, 0.9727]
  }.transform_values { |row| CONSTANT_NAMES.zip(row).to_h.freeze }.freeze
  REAL_SETTINGS = %w[cusum_k cusum_h ewma_lambda ewma_l ci_z].freeze
  Lot = Struct.new(:number, :inspected, :defectives, :defects, keyword_init: true)

  class Data
    attr_reader :settings, :samples, :lots, :constants

    def initialize
      @settings = {'rules' => {}}
      File.readlines('input/spec.txt', chomp: true).each do |line|
        name, *values = line.split(' ')
        if name == 'characteristic'
          @settings[name] = values[0]
        elsif name == 'rules'
          @settings['rules'][values[0]] = values.drop(1).map(&:to_i)
        else
          @settings[name] = REAL_SETTINGS.include?(name) ? values[0].to_f : values[0].to_i
        end
      end
      @samples = File.readlines('input/measurements.csv', chomp: true).drop(1).map do |line|
        line.split(',')[2].to_i
      end
      @lots = File.readlines('input/attributes.csv', chomp: true).drop(1).map do |line|
        number, inspected, defectives, defects = line.split(',').map(&:to_i)
        Lot.new(number: number, inspected: inspected, defectives: defectives, defects: defects)
      end
      @constants = CONSTANTS.fetch(@settings['subgroup_size'])
    end
  end
end
