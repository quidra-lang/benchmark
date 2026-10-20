module Dataset
  module_function

  def hundredths(text)
    whole, fraction = text.split('.', 2)
    whole.to_i * 100 + (fraction || '').ljust(2, '0').to_i
  end

  def read
    groups = []
    by_name = {}
    File.readlines('input/samples.csv', chomp: true).drop(1).each do |line|
      name, value = line.split(',')
      unless by_name.key?(name)
        by_name[name] = { name: name, values: [] }
        groups << by_name[name]
      end
      by_name[name][:values] << hundredths(value)
    end
    before = []
    after = []
    File.readlines('input/paired.csv', chomp: true).drop(1).each do |line|
      _, first, second = line.split(',')
      before << hundredths(first)
      after << hundredths(second)
    end
    settings = { compare: [] }
    File.readlines('input/params.txt', chomp: true).each do |line|
      name, *values = line.split(' ')
      case name
      when 'compare' then settings[:compare] << values
      when 'power' then settings[:power] = values.map(&:to_i)
      else settings[name.to_sym] = values.first.to_i
      end
    end
    [groups, before, after, settings]
  end
end
