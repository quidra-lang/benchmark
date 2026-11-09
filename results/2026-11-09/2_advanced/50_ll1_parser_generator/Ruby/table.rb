require_relative 'first_follow'

module ParseTable
  module_function

  def number(grammar)
    result = []
    grammar[:order].each do |lhs|
      grammar[:rules][lhs].each do |rhs|
        result << {number: result.length + 1, lhs: lhs, rhs: rhs,
                   notation: GrammarParser.production(lhs, rhs)}
      end
    end
    result
  end

  def build(grammar, sets)
    productions = number(grammar)
    cells = {}
    choices = {}
    conflicts = []
    grammar[:order].each do |lhs|
      (sets[:terminals] + ['$']).each { |token| cells[[lhs, token]] = [] }
    end
    productions.each do |item|
      direct, empty = FirstFollow.sequence(item[:rhs], sets[:nullable], sets[:first])
      reasons = direct.to_h { |token| [token, 'FIRST'] }
      sets[:follow][item[:lhs]].each { |token| reasons[token] ||= 'FOLLOW' } if empty
      item[:predict] = reasons
      reasons.each do |token, reason|
        cells[[item[:lhs], token]] << {number: item[:number], reason: reason}
      end
    end
    grammar[:order].each do |lhs|
      (sets[:terminals] + ['$']).each do |token|
        entries = cells[[lhs, token]]
        next if entries.empty?
        chosen = (entries.find { |e| e[:reason] == 'FIRST' } || entries.first)[:number]
        choices[[lhs, token]] = chosen
        next if entries.length < 2
        kinds = entries.map { |e| e[:reason] }.uniq
        kind = kinds.length == 2 ? 'FIRST/FOLLOW' : "#{kinds[0]}/#{kinds[0]}"
        conflicts << {lhs: lhs, token: token, entries: entries, chosen: chosen, kind: kind}
      end
    end
    {productions: productions, cells: cells, choices: choices, conflicts: conflicts}
  end
end
