module Boosting
  Row = Data.define(:id, :values, :label)
  Inputs = Data.define(:features, :train, :test, :multi_features, :multi_train, :multi_test, :params)
  Params = Data.define(
    :rounds, :variants, :bins, :smoothing, :convergence, :clip, :folds, :margins,
    :classes, :samme_rounds, :permutation, :noise_seed, :noise, :sizes, :shrinkage, :bootstrap
  )

  module_function

  def read_binary(path)
    header, *records = File.readlines(path, chomp: true, encoding: Encoding::US_ASCII)
    rows = records.map do |line|
      fields = line.split(',')
      Row.new(fields[0], fields[1...-1].map(&:to_f), fields[-1].to_i)
    end
    [header.split(',')[1...-1], rows]
  end

  def read_multiclass(path)
    header, *records = File.readlines(path, chomp: true, encoding: Encoding::US_ASCII)
    training = []
    testing = []
    records.each do |line|
      fields = line.split(',')
      row = Row.new(fields[0], fields[1...-2].map(&:to_f), fields[-2].to_i)
      (fields[-1] == 'train' ? training : testing) << row
    end
    [header.split(',')[1...-2], training, testing]
  end

  def read_params(path)
    fields = File.readlines(path, chomp: true, encoding: Encoding::US_ASCII).to_h do |line|
      key, *values = line.split(' ')
      [key, values]
    end
    noise = fields['NOISE'].map(&:to_i)
    Params.new(
      rounds: fields['ROUNDS'][0].to_i, variants: fields['VARIANTS'],
      bins: fields['BINS'][0].to_i, smoothing: fields['SMOOTHING'][0].to_f,
      convergence: fields['CONVERGENCE'][0].to_f, clip: fields['CLIP'][0].to_f,
      folds: fields['FOLDS'][0].to_i, margins: fields['MARGINS'].map(&:to_f),
      classes: fields['CLASSES'][0].to_i, samme_rounds: fields['SAMME_ROUNDS'][0].to_i,
      permutation: fields['PERMUTATION'].map(&:to_i), noise_seed: noise[0], noise: noise.drop(1),
      sizes: fields['SIZES'].map(&:to_i), shrinkage: fields['SHRINKAGE'].map(&:to_f),
      bootstrap: fields['BOOTSTRAP'].map(&:to_i)
    )
  end

  def read_inputs(directory = 'input')
    features, training = read_binary(File.join(directory, 'train.csv'))
    _, testing = read_binary(File.join(directory, 'test.csv'))
    multi_features, multi_training, multi_testing = read_multiclass(File.join(directory, 'multiclass.csv'))
    Inputs.new(features, training, testing, multi_features, multi_training, multi_testing,
               read_params(File.join(directory, 'params.txt')))
  end
end
