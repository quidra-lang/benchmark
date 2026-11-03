# frozen_string_literal: true

module Dataset
  def self.read
    rows = File.readlines('input/data.csv', chomp: true).map { |line| line.split(',') }
    features = rows.shift.drop(2)
    settings = File.readlines('input/params.txt', chomp: true).to_h do |line|
      keyword, *values = line.split(' ')
      [keyword, values]
    end
    { features: features, ids: rows.map(&:first), labels: rows.map { |row| row[1] },
      values: rows.map { |row| row.drop(2).map(&:to_f) }, settings: settings }
  end

  def self.write(path, lines)
    File.binwrite(path, lines.empty? ? '' : lines.join("\n") + "\n")
  end
end
