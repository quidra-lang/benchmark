class Resolution
  attr_reader :name, :entries, :strong, :weak, :commons, :references, :referrers, :strong_definers,
              :kind, :definition, :definer, :size, :alignment, :unresolved_referrers
  attr_accessor :address, :live

  def initialize(name, entries, script)
    @name, @entries = name, entries
    @strong = entries.select { |entry| entry.kind == 'defined' && entry.binding == 'global' }
    @weak = entries.select { |entry| entry.kind == 'defined' && entry.binding == 'weak' }
    @commons = entries.select { |entry| entry.kind == 'common' }
    @references = entries.select { |entry| entry.kind == 'undefined' }
    @referrers = references.map { |entry| entry.owner.name }.uniq
    @strong_definers = (script ? ['*script*'] : []) + strong.map { |entry| entry.owner.name }
    @definition, @size, @alignment, @address, @live = nil, 0, 1, nil, false
    @unresolved_referrers = []
    if script
      @kind, @definer = 'script', '*script*'
    elsif !strong.empty?
      @kind, @definition = 'global', strong[0]
      @definer = definition.owner.name
    elsif !commons.empty?
      @kind = 'common'
      @size = commons.map(&:size).max
      @alignment = commons.map(&:alignment).max
      @definer = commons.find { |entry| entry.size == size }.owner.name
    elsif !weak.empty?
      @kind, @definition = 'weak', weak[0]
      @definer = definition.owner.name
    elsif references.any? { |entry| entry.binding == 'global' }
      @kind, @definer = 'undefined', '-'
    else
      @kind, @definer = 'weakundef', '-'
    end
  end
end

module Resolver
  module_function

  def resolve(entries, script_names)
    (entries.keys + script_names.to_a).uniq.sort.to_h do |name|
      [name, Resolution.new(name, entries.fetch(name, []), script_names.include?(name))]
    end
  end
end
