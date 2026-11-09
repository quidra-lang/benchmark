# frozen_string_literal: true

module Road
  OBSTACLE = :obstacle

  class Segment
    attr_reader :id, :from, :to, :length, :lanes, :limit, :cells, :counts, :turns
    attr_accessor :junction, :stop

    def initialize(id, from, to, length, lanes, limit)
      @id, @from, @to = id, from, to
      @length, @lanes, @limit = length, lanes, limit
      @cells = Array.new(lanes + 1) { |lane| lane.zero? ? nil : Array.new(length) }
      @counts = Hash.new(0)
      @turns = []
      @junction = nil
      @stop = nil
    end

    def free(lane, cell, cap)
      count = 0
      while count < cap && cell + count + 1 < @length && @cells[lane][cell + count + 1].nil?
        count += 1
      end
      count
    end

    def first(lane)
      @cells[lane].index { |cell| !cell.nil? } || @length
    end

    def safe?(lane, cell)
      ([0, cell - @limit].max..cell).all? { |position| @cells[lane][position].nil? }
    end

    def vehicles(reverse: false)
      result = []
      1.upto(@lanes) do |lane|
        row = reverse ? @cells[lane].reverse_each : @cells[lane].each
        row.each { |cell| result << cell unless cell.nil? || cell == OBSTACLE }
      end
      result
    end

    def picture(lane)
      @cells[lane].map do |cell|
        cell.nil? ? '.' : cell == OBSTACLE ? '#' : cell.speed.to_s
      end.join
    end
  end

  class Incident
    attr_reader :segment, :lane, :cell, :start, :finish, :active_start, :active_end

    def initialize(segment, lane, cell, start, finish)
      @segment, @lane, @cell = segment, lane, cell
      @start, @finish = start, finish
      @state = :planned
      @active_start = nil
      @active_end = nil
    end

    def update(step)
      event = nil
      if @state == :active && step > @finish
        @state = :cleared
        @segment.cells[@lane][@cell] = nil
        event = 'INCIDENT_END'
      elsif @state == :planned && step > @finish
        @state = :cancelled
      elsif @state == :planned && step >= @start && @segment.cells[@lane][@cell].nil?
        @state = :active
        @segment.cells[@lane][@cell] = OBSTACLE
        @active_start = step
        event = 'INCIDENT_START'
      end
      @active_end = step if @state == :active
      event
    end
  end
end
