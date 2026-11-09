require 'csv'

module Dataset
  extend self

  Row = Data.define(:id, :values, :label, :class_index)
  Contents = Data.define(:features, :classes, :train, :test, :costs, :params)

  def read_table(path)
    records = CSV.read(path, encoding: 'US-ASCII')
    features = records.shift[1...-1]
    rows = records.map { |record| [record.first.to_i, record[1...-1].map(&:to_f), record.last] }
    [features, rows]
  end

  def read_parameters(path, features)
    values = {}
    subsets = []
    pairs = []
    File.foreach(path, encoding: 'US-ASCII') do |line|
      keyword, *arguments = line.split
      case keyword
      when 'SUBSET'
        subsets << [arguments.first, arguments.drop(1).map { |name| features.index(name) }]
      when 'PAIR'
        pairs << arguments.map { |name| features.index(name) }
      else
        values[keyword] = arguments
      end
    end
    {
      prior: values['PRIOR'].first, epsilon: values['VAR_SMOOTHING'].first.to_f,
      smoothing_grid: values['SMOOTHING_GRID'].map(&:to_f), gamma: values['QDA_GAMMA'].first.to_f,
      gamma_grid: values['GAMMA_GRID'].map(&:to_f), folds: values['CV_FOLDS'].first.to_i,
      calibration_edges: values['CALIBRATION_EDGES'].map(&:to_f),
      reject_thresholds: values['REJECT_THRESHOLDS'].map(&:to_f), curve: values['CURVE'].map(&:to_i),
      outlier_threshold: values['OUTLIER_THRESHOLD'].first.to_f,
      bootstrap_count: values['BOOTSTRAP'][0].to_i, seed: values['BOOTSTRAP'][1].to_i,
      map_size: values['MAP_SIZE'].map(&:to_i), plot_size: values['PLOT_SIZE'].map(&:to_i),
      subsets:, pairs:
    }
  end

  def read_costs(path, classes)
    records = CSV.read(path, encoding: 'US-ASCII')
    columns = records.shift.drop(1)
    by_actual = records.to_h { |record| [record.first, record.drop(1).map(&:to_f)] }
    classes.map { |actual| classes.map { |decided| by_actual[actual][columns.index(decided)] } }
  end

  def read_inputs(directory = 'input')
    features, training = read_table(File.join(directory, 'train.csv'))
    _, testing = read_table(File.join(directory, 'test.csv'))
    classes = training.map(&:last).uniq.sort
    train = training.map { |id, values, label| Row.new(id, values, label, classes.index(label)) }
    test = testing.map { |id, values, label| Row.new(id, values, label, classes.index(label)) }
    costs = read_costs(File.join(directory, 'costs.csv'), classes)
    params = read_parameters(File.join(directory, 'params.txt'), features)
    Contents.new(features, classes, train, test, costs, params)
  end
end
