# frozen_string_literal: true

require 'set'

module Baskets
  Product = Struct.new(:name, :category, :price)

  class Transaction
    attr_reader :id, :customer, :day, :units

    def initialize(id, customer, day)
      @id = id
      @customer = customer
      @day = day
      @units = Hash.new(0)
    end

    def products
      Set.new(@units.keys)
    end

    def extended(master)
      products.merge(@units.keys.map { |item| master.fetch(item).category })
    end
  end

  def self.csv_records(path)
    File.readlines(path, chomp: true).drop(1).each_with_index.map do |line, index|
      [index + 2, line.split(',', -1)]
    end
  end

  def self.contained?(itemset, basket)
    itemset.all? { |item| basket.include?(item) }
  end
end
