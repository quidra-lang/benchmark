# frozen_string_literal: true

module Vehicles
  ClassInfo = Struct.new(:name, :vmax, :weight, :overtake, :stop, keyword_init: true)

  class Vehicle
    attr_reader :number, :kind, :source, :arrival, :route, :completed_stops
    attr_accessor :insertion, :exit, :sink, :segment, :lane, :cell, :speed, :turn,
                  :network_steps, :distance, :stopped_steps, :stop_count, :lane_changes, :dwell

    def initialize(number, kind, source, arrival)
      @number, @kind, @source, @arrival = number, kind, source, arrival
      @insertion = @exit = @sink = nil
      @segment = @lane = @cell = @turn = nil
      @speed = 0
      @route = []
      @completed_stops = {}
      @network_steps = @distance = @stopped_steps = @stop_count = @lane_changes = @dwell = 0
    end

    def maximum
      [@kind.vmax, @segment.limit].min
    end

    def place(segment, lane, cell)
      @segment.cells[@lane][@cell] = nil if @segment
      @segment, @lane, @cell = segment, lane, cell
      segment.cells[lane][cell] = self
    end

    def leave
      @segment.cells[@lane][@cell] = nil
      @segment = @lane = @cell = nil
    end

    def heading_for_stop?
      @kind.stop == 'Y' && @segment && @segment.stop &&
        !@completed_stops[@segment.id] && @cell <= @segment.stop.cell
    end
  end

  def self.slowdown(speed, previous, moving_probability, stopped_probability, generator)
    random = generator.draw
    probability = previous.zero? ? stopped_probability : moving_probability
    speed > 0 && random % 1000 < probability ? speed - 1 : speed
  end
end
