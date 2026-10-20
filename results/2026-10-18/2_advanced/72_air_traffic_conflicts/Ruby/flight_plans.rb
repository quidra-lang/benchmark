require 'csv'

module FlightPlans
  module_function

  def load_all
    types = File.readlines('input/aircraft.txt', chomp: true).to_h do |line|
      name, *values = line.split
      [name, %i[climb descent minimum].zip(values.map(&:to_i)).to_h]
    end
    sectors = File.readlines('input/sectors.txt', chomp: true).each_with_index.map do |line, index|
      name, *values = line.split
      %i[x1 y1 x2 y2 lower upper capacity].zip(values.map(&:to_i)).to_h.merge(name: name, index: index)
    end
    rows = File.readlines('input/params.txt', chomp: true).map { |line| line.split.drop(1).map(&:to_i) }
    params = {dh: rows[0][0], dv: rows[0][1], lookahead: rows[1][0], max_delay: rows[2][0],
              level_min: rows[3][0], level_max: rows[3][1], sample_start: rows[4][0], sample_end: rows[4][1],
              radar: rows[5], snapshots: rows[6], leader: rows[7][0], alert: rows[8][0]}
    plans = CSV.read('input/flights.csv', headers: true).map do |row|
      waypoints = row['waypoints'].split.map do |text|
        x, y, level = text.split(':').map(&:to_i)
        {x: x, y: y, level: level}
      end
      code = row['callsign']
      [code, {callsign: code, type: row['type'], departure: row['departure_s'].to_i,
              level: row['level'].to_i, speed: row['speed_kt'].to_i, waypoints: waypoints,
              delay: 0, offset: 0, history: []}]
    end.sort.to_h
    [plans, types, sectors, params]
  end

  def clone_plan(plan)
    plan.merge(history: plan[:history].dup)
  end

  def levels(plan)
    [plan[:level] + plan[:offset]] + plan[:waypoints].drop(1).filter_map do |point|
      point[:level] + plan[:offset] if point[:level]
    end
  end
end
