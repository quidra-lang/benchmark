module HMM
  extend self

  def ordered_sum(values)
    total = 0
    values.each { |value| total += value }
    total
  end

  def normalize(values)
    total = ordered_sum(values)
    values.map { |value| value.to_f / total }
  end

  class Model
    attr_reader :name, :states, :symbols, :missing, :initial, :transition, :emission

    def initialize(name, states, symbols, missing, initial, transition, emission)
      @name, @states, @symbols, @missing = name, states, symbols, missing
      @initial = HMM.normalize(initial)
      @transition = transition.map { |row| HMM.normalize(row) }
      @emission = emission.map { |row| HMM.normalize(row) }
    end
  end

  def read_tokens(filename)
    File.readlines(File.join('input', filename), chomp: true).map { |line| line.split(' ') }
  end

  def read_inputs
    rows = read_tokens('model.txt')
    states, symbols, missing = rows[0].drop(1), rows[1].drop(1), rows[2][1]
    k = states.length
    model = Model.new('INITIAL', states, symbols, missing, rows[3].drop(1).map(&:to_f),
                      rows[4, k].map { |row| row.drop(2).map(&:to_f) },
                      rows[4 + k, k].map { |row| row.drop(2).map(&:to_f) })
    [model, read_tokens('sequences.txt'), read_tokens('labeled.txt'), read_tokens('params.txt')]
  end

  def real(value, places = 4)
    return '-' if value.nil?
    text = format("%.#{places}f", value)
    text == '-0.' + '0' * places ? text[1..] : text
  end

  def model_lines(model)
    lines = ["MODEL #{model.name}", 'STATES ' + model.states.join(' '),
             'SYMBOLS ' + model.symbols.join(' '), "MISSING #{model.missing}",
             'INITIAL ' + model.initial.map { |v| real(v) }.join(' ')]
    [ ['TRANSITION', model.transition], ['EMISSION', model.emission] ].each do |label, rows|
      rows.each_with_index do |row, i|
        lines << "#{label} #{model.states[i]} " + row.map { |v| real(v) }.join(' ')
      end
    end
    lines
  end

  def write_lines(filename, lines)
    Dir.mkdir('output') unless Dir.exist?('output')
    File.write(File.join('output', filename), lines.join("\n") + "\n")
  end
end
