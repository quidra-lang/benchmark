module Capacity
  Center = Struct.new(:id, :minutes, :efficiency, :available, :description, keyword_init: true)
  Operation = Struct.new(:item, :number, :center, :setup, :run, keyword_init: true)

  module_function

  def read_centers(errors)
    centers = {}
    File.readlines('input/workcenters.csv', chomp: true).drop(1).each_with_index do |line, index|
      id, minutes, efficiency, description = line.split(',')
      minutes = minutes.to_i
      efficiency = efficiency.to_i
      message = if centers.key?(id)
                  "duplicate center #{id}"
                elsif efficiency < 50 || efficiency > 150
                  "bad efficiency #{efficiency}"
                end
      if message
        errors << "workcenters.csv line #{index + 2}: #{message}"
        next
      end
      centers[id] = Center.new(id: id, minutes: minutes, efficiency: efficiency,
                               available: (minutes * efficiency).div(100), description: description)
    end
    centers
  end

  def read_routings(items, bom, centers, errors)
    routings = items.to_h { |id, _item| [id, []] }
    File.readlines('input/routings.csv', chomp: true).drop(1).each_with_index do |line, index|
      item, number, center, setup, run = line.split(',')
      number = number.to_i
      run = run.to_i
      message = if !items.key?(item)
                  "unknown item #{item}"
                elsif !centers.key?(center)
                  "unknown center #{center}"
                elsif !bom.manufactured?(item)
                  "purchased item #{item}"
                elsif run < 1
                  "bad run time #{run}"
                elsif routings[item].any? { |operation| operation.number == number }
                  "duplicate #{item} operation #{number}"
                end
      if message
        errors << "routings.csv line #{index + 2}: #{message}"
        next
      end
      routings[item] << Operation.new(item: item, number: number, center: center, setup: setup.to_i, run: run)
    end
    routings.each_value { |operations| operations.sort_by!(&:number) }
    routings
  end

  def week(receipt, lead_time, index, count)
    [receipt - lead_time + (index * lead_time).div(count), 1].max
  end

  def level(load, available, horizon)
    leveled = Array.new(horizon + 1, 0)
    carry = 0
    horizon.downto(2) do |week|
      quantity = load[week] + carry
      leveled[week] = [quantity, available].min
      carry = quantity - leveled[week]
    end
    leveled[1] = load[1] + carry
    leveled
  end
end
