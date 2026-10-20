require_relative 'hazards'

module Pipeline
  include Hazards
  extend self
  CAUSES = %w[control structural load_use raw].freeze
  STAGES = %w[IF ID EX MEM WB].freeze

  def simulate(instructions, sources, variant, mispredicted)
    timings, records, delays = [], [], []
    instructions.each_with_index do |instruction, index|
      execute = instruction[:class] == 'MUL' ? variant[:latency] : 1
      if index.zero?
        fetch, decode, start = 1, 2, 3
      else
        previous = timings[-1]
        fetch = if mispredicted[index - 1]
                  previous[:X] + (id_resolved(instructions[index - 1], variant) ? 0 : 1)
                else previous[:D]
                end
        decode = [fetch + 1, previous[:X]].max
        ideal = previous[:X] + 1
        load_ready = raw_ready = ideal
        load_producer = raw_producer = nil
        sources[index].each do |source|
          producer = source[:producer]
          next if producer.nil?
          ready = ready_cycle(instruction, instructions[producer], timings[producer], variant)
          if instructions[producer][:class] == 'LOAD'
            load_ready, load_producer = ready, producer if ready > load_ready
          elsif ready > raw_ready
            raw_ready, raw_producer = ready, producer
          end
        end
        bounds = [decode + 1, previous[:M], load_ready, raw_ready]
        producers = [nil, nil, load_producer, raw_producer]
        start = ideal
        CAUSES.each_with_index do |cause, position|
          bound = bounds[position]
          next unless bound > start
          records << { cause: cause, cycles: bound - start,
                       responsible: %w[control structural].include?(cause) ? index - 1 : index,
                       waiting: index, producer: producers[position] }
          start = bound
        end
        delays << start - ideal
      end
      timings << { F: fetch, D: decode, X: start, M: start + execute, W: start + execute + 1 }
    end
    if instructions[-1][:class] == 'MUL' && variant[:latency] >= 2
      records << { cause: 'structural', cycles: variant[:latency] - 1,
                   responsible: instructions.length - 1, waiting: nil, producer: nil }
    end
    { timings: timings, records: records, delays: delays, cycles: timings[-1][:W] }
  end
end
