module Processes
  def self.action(words)
    words[2] = words[2].to_i if words[0] == 'TRANSFER'
    words
  end

  def self.read_scripts(path = 'input/programs.txt')
    blocks = {}
    current = nil
    File.foreach(path) do |line|
      words = line.split
      case words[0]
      when 'PROCESS'
        current = { name: words[1], initial: words[3].to_i, at: [], on: [] }
        blocks[words[1]] = current
      when 'AT'
        periodic = words[2] == 'EVERY'
        current[:at] << [words[1].to_i, periodic ? words[3].to_i : nil, action(words.drop(periodic ? 4 : 2))]
      when 'ON'
        current[:on] << [words[1], action(words.drop(2))]
      end
    end
    blocks
  end

  def self.initialize_states(names, scripts)
    names.to_h do |name|
      script = scripts.fetch(name)
      others = names.reject { |other| other == name }
      [name, script.merge(balance: script[:initial], lamport: 0,
        vector: Array.new(names.size, 0), broadcast: Array.new(names.size, 0),
        events: [], next_sequence: others.to_h { |other| [other, 1] },
        reorder: others.to_h { |other| [other, {}] }, holdback: [], delivered: [],
        max_held: 0, incoming: 0, outgoing: 0, refused: 0,
        min_balance: script[:initial], counts: Hash.new(0))]
    end
  end

  def self.schedule(names, states, limit)
    names.each do |name|
      states[name][:at].each do |start, period, action|
        time = start
        while time <= limit
          yield time, name, :action, action
          break unless period
          time += period
        end
      end
    end
  end

  def self.balance_at(state, count)
    count.zero? ? state[:initial] : state[:events][count - 1][:balance]
  end

  def self.held_count(state)
    state[:reorder].values.sum(&:size) + state[:holdback].size
  end
end
