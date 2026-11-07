require 'set'
require_relative 'matcher'

module Linter
  CODES = %w[SYNTAX ORPHAN DUPLICATE KEY_NO_DECOMP KEY_UNREACHABLE SYNON_UNUSED PRE_CHAIN
             SYNON_UNKNOWN RULE_NO_REASM RULE_SHADOWED REF_UNBOUND TARGET_UNDEFINED TARGET_CYCLE].freeze
  ERRORS = %w[SYNTAX ORPHAN DUPLICATE SYNON_UNKNOWN REF_UNBOUND TARGET_UNDEFINED TARGET_CYCLE].to_set.freeze

  def self.reachable?(graph, start, target)
    pending = [start]
    seen = Set.new
    until pending.empty?
      current = pending.pop
      return true if current == target
      next if seen.include?(current)

      seen.add(current)
      pending.concat(graph.fetch(current))
    end
    false
  end

  def self.check(script)
    diagnostics = script[:diagnostics].dup
    add = lambda do |line, code, message|
      diagnostics << { line: line, code: code, message: message }
    end
    keywords = script[:keywords]
    rules = keywords.values.flat_map { |keyword| keyword[:memory] + keyword[:decomp] }
    items = keywords.values.flat_map do |keyword|
      (keyword[:memory] + keyword[:decomp]).flat_map do |rule|
        rule[:items].map { |item| [keyword, rule, item] }
      end
    end
    targets = items.filter_map do |_, _, item|
      item[:arguments].first if %w[GOTO RESTATE].include?(item[:kind])
    end.to_set
    replacements = script[:pre].values.flat_map { |entry| entry[:replacement] }.to_set
    used_groups = rules.flat_map { |rule| rule[:pattern].select { |element| element.start_with?('@') } }
                       .map { |element| element[1..] }.to_set
    keywords.each_value do |keyword|
      word = keyword[:word]
      add.call(keyword[:line], 'KEY_NO_DECOMP', "keyword #{word} has no DECOMP") if keyword[:decomp].empty?
      if script[:pre].key?(word) && !replacements.include?(word) && !targets.include?(word)
        add.call(keyword[:line], 'KEY_UNREACHABLE', "keyword #{word} is replaced by PRE")
      end
    end
    script[:groups].each do |name, group|
      add.call(group[:line], 'SYNON_UNUSED', "group #{name} is never used") unless used_groups.include?(name)
    end
    script[:pre].each_value do |entry|
      entry[:replacement].each do |word|
        add.call(entry[:line], 'PRE_CHAIN', "replacement #{word} is itself replaced by PRE") if script[:pre].key?(word)
      end
    end
    known = {}
    rules.each do |rule|
      missing = rule[:pattern].select { |element| element.start_with?('@') && !script[:groups].key?(element[1..]) }
      missing.each { |element| add.call(rule[:line], 'SYNON_UNKNOWN', "unknown group #{element[1..]}") }
      known[rule[:line]] = missing.empty?
      add.call(rule[:line], 'RULE_NO_REASM', 'rule has no reassembly') if rule[:items].empty?
    end
    keywords.each_value do |keyword|
      %i[memory decomp].each do |kind|
        keyword[kind].each_with_index do |rule, index|
          next unless known[rule[:line]]

          previous = keyword[kind].take(index).find do |earlier|
            known[earlier[:line]] && Matcher.covers?(earlier[:pattern], rule[:pattern], script[:groups])
          end
          add.call(rule[:line], 'RULE_SHADOWED', "pattern is shadowed by line #{previous[:line]}") if previous
        end
      end
    end
    graph = keywords.keys.to_h { |word| [word, []] }
    items.each do |keyword, _, item|
      next unless %w[GOTO RESTATE].include?(item[:kind])

      target = item[:arguments].first
      graph[keyword[:word]] << target if keywords.key?(target)
    end
    items.each do |keyword, rule, item|
      references = if item[:kind] == 'REASM'
                     item[:template].scan(/\(([0-9])\)/).flatten
                   elsif item[:kind] == 'RESTATE'
                     item[:arguments].drop(1).filter_map { |argument| argument[1] if /\A\([0-9]\)\z/.match?(argument) }
                   else
                     []
                   end
      wildcards = rule[:pattern].count { |element| Matcher.wildcard?(element) }
      references.each do |digit|
        unless digit.to_i.between?(1, wildcards)
          add.call(item[:line], 'REF_UNBOUND', "reference (#{digit}) is not bound")
        end
      end
      next unless %w[GOTO RESTATE].include?(item[:kind])

      target = item[:arguments].first
      if !keywords.key?(target)
        add.call(item[:line], 'TARGET_UNDEFINED', "target #{target} is not a keyword")
      elsif reachable?(graph, target, keyword[:word])
        add.call(item[:line], 'TARGET_CYCLE', "edge #{keyword[:word]} -> #{target} is on a cycle")
      end
    end
    ordered = diagnostics.each_with_index.sort_by { |diagnostic, index| [diagnostic[:line], CODES.index(diagnostic[:code]), index] }
    return ['OK'] if ordered.empty?

    lines = ordered.map { |diagnostic, _| "#{diagnostic[:line]} #{diagnostic[:code]} #{diagnostic[:message]}" }
    errors = diagnostics.count { |diagnostic| ERRORS.include?(diagnostic[:code]) }
    lines << "TOTAL #{diagnostics.length} errors=#{errors} warnings=#{diagnostics.length - errors}"
  end
end
