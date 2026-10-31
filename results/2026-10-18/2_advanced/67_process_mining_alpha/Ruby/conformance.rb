class PetriNet
  attr_reader :places, :transitions, :arcs, :initial, :final, :inputs, :outputs

  def initialize(places, transitions, arcs, initial, final)
    @places, @transitions, @arcs = places.dup, transitions.sort, arcs.map(&:dup)
    indices = places.each_with_index.to_h
    @initial, @final = indices[initial], indices[final]
    @inputs = @transitions.to_h { |name| [name, []] }
    @outputs = @transitions.to_h { |name| [name, []] }
    arcs.each do |from, to|
      if indices.key?(from)
        @inputs[to] << indices[from]
      else
        @outputs[from] << indices[to]
      end
    end
    @inputs.each_value(&:sort!)
    @outputs.each_value(&:sort!)
  end

  def marking(final = false)
    tokens = Array.new(@places.length, 0)
    tokens[final ? @final : @initial] = 1
    tokens
  end

  def enabled?(marking, transition)
    @inputs.key?(transition) && @inputs[transition].all? { |place| marking[place] >= 1 }
  end

  def enabled_transitions(marking)
    @transitions.select { |transition| enabled?(marking, transition) }
  end

  def fire(marking, transition)
    result = marking.dup
    @inputs[transition].each { |place| result[place] -= 1 }
    @outputs[transition].each { |place| result[place] += 1 }
    result
  end
end

module Conformance
  module_function

  def read_model
    places, transitions, arcs = [], [], []
    initial = final = nil
    File.foreach('input/model.txt', chomp: true) do |line|
      kind, first, second = line.split
      case kind
      when 'PLACE' then places << first
      when 'TRANSITION' then transitions << first
      when 'ARC' then arcs << [first, second]
      when 'INITIAL' then initial = first
      when 'FINAL' then final = first
      end
    end
    PetriNet.new(places, transitions, arcs, initial, final)
  end

  def replay_record(net)
    {missing: 0, remaining: 0, consumed: 0, produced: 0, skipped: 0, fitting: 0,
     places: net.places.map do
       {missing: 0, remaining: 0, deviating: 0, waiting_count: 0, waiting_total: 0,
        waiting_maximum: 0, consumptions: Hash.new(0)}
     end}
  end

  def fitness(record)
    Rational(1, 2) * (1 - Rational(record[:missing], record[:consumed])) +
      Rational(1, 2) * (1 - Rational(record[:remaining], record[:produced]))
  end
end
