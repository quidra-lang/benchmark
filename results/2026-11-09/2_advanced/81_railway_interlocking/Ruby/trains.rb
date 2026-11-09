module Trains
  Stop = Struct.new(:kind, :section, :dwell, :scheduled_arrival, :scheduled_departure,
                    :arrival, :departure, keyword_init: true)
  Train = Struct.new(:name, :symbol, :length, :acceleration, :deceleration, :max_speed,
                     :entry, :entry_time, :entry_speed, :exit, :scheduled_exit,
                     :stops, :stop_index, :state, :direction, :path, :head, :speed,
                     :dwelling, :awaiting_departure, :emergency, :boundary,
                     :boundary_coordinate, :entered, :exited, :stats, keyword_init: true) do
    def next_stop = stops[stop_index]
  end

  def self.read
    trains, requests = {}, []
    File.foreach('input/trains.txt', chomp: true) do |line|
      kind, name, *fields = line.split(' ')
      case kind
      when 'TRAIN'
        length, acceleration, deceleration, maximum, entry, time, speed = fields
        trains[name] = Train.new(name: name, symbol: (97 + trains.size).chr,
          length: length.to_i, acceleration: acceleration.to_i, deceleration: deceleration.to_i,
          max_speed: maximum.to_i, entry: entry, entry_time: time.to_i, entry_speed: speed.to_i,
          stops: [], stop_index: 0, state: 'WAITING', path: [], head: 0, speed: 0,
          dwelling: false, emergency: false, stats: Hash.new(0))
      when 'REQUEST'
        route, time = fields
        requests << [time.to_i, name, route]
      when 'STOP', 'TURN'
        section, dwell, arrival, departure = fields
        trains.fetch(name).stops << Stop.new(kind: kind, section: section, dwell: dwell.to_i,
          scheduled_arrival: arrival.to_i, scheduled_departure: departure.to_i)
      when 'EXIT'
        trains.fetch(name).exit, trains[name].scheduled_exit = fields[0], fields[1].to_i
      end
    end
    [trains, requests]
  end

  def self.braking_distance(speed, deceleration)
    n = speed / deceleration
    n * speed - deceleration * n * (n + 1) / 2
  end

  def self.select_speed(train, distance)
    low = [train.speed - train.deceleration, 0].max
    unless train.emergency
      [train.speed + train.acceleration, train.max_speed].min.downto(low) do |speed|
        return speed if distance.nil? || speed + braking_distance(speed, train.deceleration) <= distance
      end
    end
    low
  end
end
