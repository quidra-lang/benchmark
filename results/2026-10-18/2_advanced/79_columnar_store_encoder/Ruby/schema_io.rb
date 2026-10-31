require 'date'

module SchemaIO
  TYPES = %w[INT STRING BOOL DATE].freeze
  EPOCH = Date.new(1970, 1, 1, Date::GREGORIAN)
  module_function

  def day_number(text)
    year, month, day = text.split('-').map(&:to_i)
    (Date.new(year, month, day, Date::GREGORIAN) - EPOCH).to_i
  end

  def field_value(type, text)
    return nil if text.empty?
    case type
    when 'INT' then text.to_i
    when 'DATE' then day_number(text)
    when 'BOOL' then text == 'true'
    else text
    end
  end

  def value_text(type, value, null = 'NULL')
    return null if value.nil?
    type == 'DATE' ? (EPOCH + value).strftime('%Y-%m-%d') : value.to_s
  end

  def compare(first, second)
    first = first ? 1 : 0 if first == true || first == false
    second = second ? 1 : 0 if second == true || second == false
    first <=> second
  end

  def read_inputs
    columns = File.readlines('input/schema.txt', chomp: true).map do |line|
      name, type, nullability = line.split(' ')
      { name: name, type: type, nullable: nullability == 'NULLABLE' }
    end
    table = File.readlines('input/table.csv', chomp: true).drop(1).map do |line|
      line.split(',', -1).each_with_index.map { |text, index| field_value(columns[index][:type], text) }
    end
    options = { encoding: {} }
    File.foreach('input/options.txt', chomp: true) do |line|
      key, first, second = line.split(' ')
      if key == 'encoding'
        options[:encoding][first] = second
      else
        options[key.to_sym] = first.to_i
      end
    end
    queries = File.readlines('input/queries.txt', chomp: true)
    damaged = [File.read('input/damaged.hex').delete("\n")].pack('H*')
    [columns, table, options, queries, damaged]
  end

  def write_outputs(outputs)
    Dir.mkdir('output') unless Dir.exist?('output')
    outputs.each { |name, lines| File.write(File.join('output', name), lines.empty? ? '' : lines.join("\n") + "\n") }
  end
end
