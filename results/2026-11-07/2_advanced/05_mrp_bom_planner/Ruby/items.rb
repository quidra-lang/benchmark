module Items
  Item = Struct.new(:id, :lead_time, :rule, :lot, :safety, :on_hand,
                    :material, :labor, :description, keyword_init: true)
  RULES = %w[LFL FOQ POQ MIN].freeze

  module_function

  def lot_parameter(rule, text)
    values = text.split('/').map(&:to_i)
    valid = case rule
            when 'LFL' then values.length == 1 && values[0].zero?
            when 'FOQ', 'POQ' then values.length == 1 && values[0] >= 1
            when 'MIN' then values.length == 2 && values.all? { |value| value >= 1 }
            else false
            end
    valid ? values : nil
  end

  def read(errors)
    items = {}
    File.readlines('input/items.csv', chomp: true).drop(1).each_with_index do |line, index|
      id, lead, rule, parameter, safety, stock, material, labor, description = line.split(',')
      lot = lot_parameter(rule, parameter)
      message = if items.key?(id)
                  "duplicate item #{id}"
                elsif !RULES.include?(rule)
                  "unknown lot rule #{rule}"
                elsif lot.nil?
                  "bad lot parameter #{parameter} for #{rule}"
                end
      if message
        errors << "items.csv line #{index + 2}: #{message}"
        next
      end
      items[id] = Item.new(id: id, lead_time: lead.to_i, rule: rule, lot: lot,
                           safety: safety.to_i, on_hand: stock.to_i,
                           material: material.to_i, labor: labor.to_i, description: description)
    end
    items
  end
end
