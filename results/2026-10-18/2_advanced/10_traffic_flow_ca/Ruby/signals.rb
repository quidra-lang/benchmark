# frozen_string_literal: true

module Signals
  Phase = Struct.new(:duration, :token, :greens, keyword_init: true)

  class Junction
    attr_reader :node, :offset, :phases, :cycle

    def initialize(node, offset, tokens)
      @node, @offset = node, offset
      @phases = tokens.map do |token|
        duration, green = token.split(':')
        Phase.new(duration: duration.to_i, token: green, greens: green == '-' ? [] : green.split(','))
      end
      @cycle = @phases.sum(&:duration)
    end

    def green?(segment, step)
      return true if @phases.empty?

      position = (step - 1 + @offset) % @cycle
      @phases.each do |phase|
        return phase.greens.include?(segment) if position < phase.duration

        position -= phase.duration
      end
    end

    def lines
      return ["JUNCTION #{@node} unsignalized"] if @phases.empty?

      result = ["JUNCTION #{@node} signal cycle #{@cycle} offset #{@offset}"]
      start = 0
      @phases.each_with_index do |phase, index|
        result << "  PHASE #{index + 1} #{start}-#{start + phase.duration - 1} #{phase.token}"
        start += phase.duration
      end
      result
    end
  end
end
