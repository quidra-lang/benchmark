require 'ostruct'
require 'set'

Bid = Struct.new(:number, :bidder, :bundle, :amount, :xor)
Participant = Struct.new(:name, :value, :bid)

module BidsIO
  module_function

  def records(name)
    File.readlines("input/#{name}", chomp: true, encoding: 'US-ASCII').map(&:split)
  end

  def read_inputs
    reserves = records('items.txt').to_h { |name, price| [name, price.to_i] }
    auctions = {}
    current = nil
    records('bids.txt').each do |kind, name, *fields|
      if kind == 'auction'
        current = OpenStruct.new(name: name, items: fields, lines: [])
        auctions[name] = current
      else
        current.lines << [name, fields[0], fields.drop(1)]
      end
    end
    groups = []
    records('single_item.txt').each do |kind, name, *fields|
      if %w[lot slots].include?(kind)
        current = OpenStruct.new(kind: kind, name: name, arguments: fields, participants: [])
        groups << current
      else
        current.participants << Participant.new(name, fields[0].to_i, fields[1].to_i)
      end
    end
    parameters = records('params.txt').to_h do |name, *values|
      [name, name == 'run' ? values : values[0].to_i]
    end
    [reserves, auctions, groups, parameters]
  end
end
