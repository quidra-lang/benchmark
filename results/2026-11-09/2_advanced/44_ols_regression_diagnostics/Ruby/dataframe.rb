module Dataframe
  Frame = Struct.new(:columns, :kinds, :rows)
  module_function

  def read_csv(path, kinds = nil)
    lines = File.readlines(path, chomp: true)
    columns = lines.shift.split(',')
    records = lines.map { |line| line.split(',') }
    kinds = columns.each_with_index.to_h do |column, j|
      kind = if kinds
               kinds[column]
             elsif records.any? { |row| row[j] != 'NA' && row[j].match?(/\A[A-Z]/) }
               :categorical
             else
               :numeric
             end
      [column, kind]
    end
    rows = records.map do |record|
      columns.each_with_index.to_h do |column, j|
        value = record[j]
        parsed = if value == 'NA'
                   nil
                 elsif kinds[column] == :numeric
                   value.to_f
                 else
                   value
                 end
        [column, parsed]
      end
    end
    Frame.new(columns, kinds, rows)
  end

  def read_models(path)
    File.readlines(path, chomp: true)
  end

  def read_params(path)
    File.readlines(path, chomp: true).to_h do |line|
      keyword, *values = line.split(' ')
      value = case keyword
              when 'BEST_SUBSETS' then values[0].to_i
              when 'PLOT' then [values[0].to_i, values[1].to_i, values[2].to_f]
              else values[0].to_f
              end
      [keyword, value]
    end
  end
end
