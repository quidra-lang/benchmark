# Keep exact hundredths for position comparisons and integer-valued fits.
module Dataset
  def self.hundredths(text)
    text.delete('.').to_i
  end

  def self.read
    series = {}
    File.readlines('input/series.csv', chomp: true, encoding: 'US-ASCII').drop(1).each do |line|
      name, x, y = line.split(',')
      (series[name] ||= []) << [hundredths(x), hundredths(y)]
    end
    series.each_value { |points| points.sort_by!(&:first) }
    tests = File.readlines('input/test_points.csv', chomp: true, encoding: 'US-ASCII').drop(1).map do |line|
      name, x = line.split(',')
      [name, hundredths(x)]
    end
    settings = {}
    File.foreach('input/params.txt', encoding: 'US-ASCII') do |line|
      key, *values = line.split
      settings[key] = values
    end
    %w[ROBUST_ITERATIONS CV_FOLDS GRID_POINTS].each do |key|
      settings[key] = settings[key].first.to_i
    end
    settings['BAND_Z'] = settings['BAND_Z'].first.to_f
    settings['OUTLIER_THRESHOLD'] = hundredths(settings['OUTLIER_THRESHOLD'].first) / 100.0
    %w[BOOTSTRAP PLOT_SIZE].each { |key| settings[key].map!(&:to_i) }
    [series, tests, settings]
  end
end
