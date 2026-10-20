module NetworkIO
  Network = Data.define(:names, :states, :parents, :expert)

  def self.read_network(path)
    lines = File.readlines(path, chomp: true).reject { |line| line.empty? || line.start_with?('#') }
    names, states, parents, expert, index = [], [], [], {}, {}
    position = 0
    while position < lines.length
      kind, name, *fields = lines[position].split
      position += 1
      case kind
      when 'VARIABLE'
        index[name] = names.length
        names << name
        states << fields
        parents << []
      when 'PARENTS'
        parents[index.fetch(name)] = fields.map { |parent| index.fetch(parent) }
      when 'CPT'
        variable = index.fetch(name)
        rows = parents[variable].inject(1) { |product, parent| product * states[parent].length }
        expert[variable] = lines[position, rows].map { |line| line.split.map(&:to_f) }
        position += rows
      end
    end
    Network.new(names, states, parents, expert)
  end

  def self.read_inputs
    network = read_network('input/network.txt')
    lines = File.readlines('input/samples.csv', chomp: true)
    columns = lines.shift.split(',').map { |name| network.names.index(name) }
    samples = lines.map do |line|
      sample = Array.new(network.names.length, 0)
      columns.zip(line.split(',')).each do |variable, state|
        sample[variable] = network.states[variable].index(state)
      end
      sample
    end
    settings = File.readlines('input/params.txt', chomp: true).map(&:split)
    params = { alpha: settings[0][1].to_f, method: settings[1][1],
               order: settings[2].drop(1).map { |name| network.names.index(name) },
               limit: settings[3][1].to_i, seed: settings[4][1].to_i,
               sources: settings.drop(5).map { |fields| fields[2] } }
    [network, samples, File.readlines('input/queries.txt', chomp: true), params]
  end
end
