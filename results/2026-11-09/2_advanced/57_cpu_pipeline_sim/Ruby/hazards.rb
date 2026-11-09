module Hazards
  extend self

  def dependencies(instructions)
    last_writer = {}
    instructions.each_with_index.map do |instruction, index|
      current = %i[rs1 rs2].filter_map do |field|
        register = instruction[field]
        { field: field, register: register, producer: last_writer[register] } if register && !register.zero?
      end
      destination = instruction[:rd]
      last_writer[destination] = index if destination && !destination.zero?
      current
    end
  end

  def id_resolved(instruction, variant)
    (instruction[:class] == 'JUMP' && instruction[:rs1].nil?) ||
      (%w[BRANCH JUMP].include?(instruction[:class]) && variant[:stage] == 'ID')
  end

  def ready_cycle(instruction, producer, producer_time, variant)
    return producer_time[:W] + 1 unless variant[:forwarding]
    result = producer[:class] == 'LOAD' ? producer_time[:W] : producer_time[:M]
    result + (id_resolved(instruction, variant) ? 1 : 0)
  end

  def forwarding_path(instruction, producer_time, instruction_time, variant)
    return 'regfile' unless producer_time && variant[:forwarding]
    resolved = id_resolved(instruction, variant)
    use_cycle = instruction_time[:X] - (resolved ? 1 : 0)
    return 'ex_mem' if producer_time[:M] == use_cycle
    return 'mem_wb' if !resolved && producer_time[:W] == use_cycle
    'regfile'
  end
end
