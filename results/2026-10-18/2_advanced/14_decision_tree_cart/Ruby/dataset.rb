# frozen_string_literal: true

module Dataset
  Attribute = Struct.new(:index, :name, :type, :values, keyword_init: true)
  Row = Struct.new(:id, :values, :klass, :index, keyword_init: true)
  Data = Struct.new(:attributes, :target, :classes, :train, :validation, :test,
                    :settings, keyword_init: true)

  module_function

  def read_rows(name, attributes, classes)
    File.readlines("input/#{name}.csv", chomp: true).drop(1).each_with_index.map do |line, index|
      fields = line.split(',')
      values = attributes.map do |attribute|
        value = fields[attribute.index + 1]
        if value == '?'
          nil
        elsif attribute.type == 'INT'
          value.to_i
        else
          attribute.values.index(value)
        end
      end
      Row.new(id: fields.first, values: values, klass: classes.index(fields.last), index: index)
    end
  end

  def read
    schema = File.readlines('input/schema.txt', chomp: true).map(&:split)
    attributes = schema[0...-1].each_with_index.map do |fields, index|
      Attribute.new(index: index, name: fields[1], type: fields[2], values: fields.drop(3))
    end
    target = schema.last[1]
    classes = schema.last.drop(2)
    settings = {}
    File.readlines('input/params.txt', chomp: true).each do |line|
      keyword, *fields = line.split
      values = fields.map(&:to_i)
      settings[keyword.downcase.to_sym] = keyword == 'CURVE' ? values : values.first
    end
    Data.new(attributes: attributes, target: target, classes: classes,
             train: read_rows('train', attributes, classes),
             validation: read_rows('validation', attributes, classes),
             test: read_rows('test', attributes, classes), settings: settings)
  end
end
