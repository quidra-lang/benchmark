module Report
  def fmt(value, places = 4)
    text = format("%.#{places}f", value)
    text.match?(/\A-0(?:\.0+)?\z/) ? text.delete_prefix('-') : text
  end

  def curve_plot(observed, fitted)
    days, maximum = observed.length, observed.max
    width = maximum.to_s.length
    grid = Array.new(20) { Array.new(70, '.') }
    70.times do |column|
      day = column * (days - 1) / 69
      ro = [19, 20 * observed[day] / maximum].min
      rf = [19, (20.0 * fitted[day] / maximum).floor].min
      grid[ro][column] = 'o'
      grid[rf][column] = ro == rf ? '#' : '*'
    end
    lines = ["plot observed o fitted * both # days 1 #{days} max #{maximum}"]
    19.downto(0) { |row| lines << "#{(maximum * row / 20).to_s.rjust(width)} |#{grid[row].join}" }
    lines << ' ' * (width + 1) + '+' + 70.times.map { |x| x % 10 == 0 ? '+' : '-' }.join
    labels = ' ' * 70
    (0...70).step(10) do |column|
      label = (1 + column * (days - 1) / 69).to_s
      labels[column, label.length] = label
    end
    lines << (' ' * (width + 2) + labels).rstrip
    lines
  end
end
