require 'csv'
require 'ostruct'
require_relative 'kernels'

Example = Data.define(:id, :point, :label)
MulticlassExample = Data.define(:id, :point, :class_number, :role)

def read_binary(path)
  CSV.read(path, headers: true).map { |r| Example.new(r['id'], [r['x1'].to_f, r['x2'].to_f], r['label'].to_i) }
end

def read_inputs
  multi = CSV.read('input/multiclass.csv', headers: true).map do |r|
    MulticlassExample.new(r['id'], [r['x1'].to_f, r['x2'].to_f], r['class'].to_i, r['role'])
  end
  settings = OpenStruct.new(kernels: [])
  File.foreach('input/params.txt') do |line|
    keyword, *v = line.split
    case keyword
    when 'KERNEL' then settings.kernels << KernelDefinition.new(*v)
    when 'C_GRID', 'PLOT_X', 'PLOT_Y' then settings[keyword.downcase] = v.map(&:to_f)
    when 'LEARNING_CURVE', 'PLOT_SIZE' then settings[keyword.downcase] = v.map(&:to_i)
    when 'TOLERANCE', 'EPS' then settings[keyword.downcase] = v[0].to_f
    when 'MULTICLASS' then settings.multiclass = [v[0], v[1].to_f]
    when 'PEGASOS' then settings.pegasos = [v[0].to_f, v[1].to_i, v[2].to_i]
    else settings[keyword.downcase] = v[0].to_i
    end
  end
  [read_binary('input/train.csv'), read_binary('input/test.csv'), *multi.partition { |e| e.role == 'train' }, settings]
end
