require_relative "estimators"

module SurvivalPlot
  module_function

  def curve_lines(groups, collections, estimates, width, height, time_limit)
    cells = Array.new(height) { Array.new(width) { [] } }
    step = time_limit.div(width)
    groups.each_with_index do |group, index|
      letter = ("A".ord + index).chr
      maximum = collections[group].map(&:time).max
      previous = nil
      width.times do |column|
        time = column * step
        break if time > maximum

        survival = Estimators.row_at(estimates[group], time)[:survival]
        band = [height - 1, (survival * height).floor].min
        cells[band][column] << letter
        if previous && previous - 1 > band
          (band + 1...previous).each { |vertical| cells[vertical][column] << letter }
        end
        previous = band
      end
    end
    border = "   +#{'-' * width}+"
    lines = [border]
    (height - 1).downto(0) do |band|
      characters = cells[band].map { |cell| cell.empty? ? " " : cell.length == 1 ? cell.first : "*" }.join
      lines << format("%3d|%s|", (100 * band).div(height), characters)
    end
    lines << border
  end
end
