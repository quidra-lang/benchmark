# frozen_string_literal: true

require_relative 'combat'

module Entities
  MonsterType = Struct.new(:name, :symbol, :min_depth, :max_depth, :weight, :hp_dice, :to_hit,
                           :defense, :damage, :speed, :xp, :traits, keyword_init: true)
  ItemType = Struct.new(:kind, :name, :min_depth, :max_depth, :weight, :damage, :to_hit,
                        :armor, :effect, :power, :dice, keyword_init: true)
  Monster = Struct.new(:id, :type, :position, :hp, :max_hp, :asleep, :energy, :was_visible, keyword_init: true)
  SYMBOLS = { 'weapon' => ')', 'armor' => '[', 'potion' => '!', 'scroll' => '?',
              'food' => '%', 'gold' => '$', 'amulet' => '"' }.freeze

  Item = Struct.new(:type, :bonus, :amount) do
    def symbol
      SYMBOLS.fetch(type.kind)
    end

    def display_name
      name = type.name.tr('_', ' ')
      return "+#{bonus} #{name}" if %w[weapon armor].include?(type.kind)
      return "#{amount} gold" if type.kind == 'gold'

      name
    end

    def reference_name
      type.kind == 'gold' ? display_name : "the #{display_name}"
    end
  end

  def self.monster_type(line)
    name, symbol, minimum, maximum, weight, hp, hit, defense, damage, speed, xp, traits = line.split(' ')
    MonsterType.new(name: name, symbol: symbol, min_depth: minimum.to_i, max_depth: maximum.to_i,
                    weight: weight.to_i, hp_dice: Combat.dice(hp), to_hit: hit.to_i,
                    defense: defense.to_i, damage: Combat.dice(damage), speed: speed.to_i,
                    xp: xp.to_i, traits: traits)
  end

  def self.item_type(line)
    kind, name, minimum, maximum, weight, *arguments = line.split(' ')
    type = ItemType.new(kind: kind, name: name, min_depth: minimum.to_i, max_depth: maximum.to_i, weight: weight.to_i)
    case kind
    when 'weapon'
      type.damage = Combat.dice(arguments[0])
      type.to_hit = arguments[1].to_i
    when 'armor'
      type.armor = arguments[0].to_i
    when 'potion'
      type.effect = arguments[0]
      type.dice = Combat.dice(arguments[1]) if type.effect == 'heal'
      type.power = arguments[1].to_i if type.effect == 'poison'
    when 'scroll'
      type.effect = arguments[0]
    when 'food'
      type.power = arguments[0].to_i
    when 'gold'
      type.dice = Combat.dice(arguments[0])
    end
    type
  end
end
