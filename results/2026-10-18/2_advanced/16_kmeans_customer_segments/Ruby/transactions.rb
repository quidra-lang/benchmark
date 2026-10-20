# frozen_string_literal: true

require 'set'

module Transactions
  Row = Struct.new(:customer, :day, :order_id, :category, :amount)
  Order = Struct.new(:id, :customer, :day, :net, :rows)

  def self.settings(path)
    File.readlines(path, chomp: true).to_h do |line|
      key, *values = line.split(' ')
      value = case key
              when 'METHODS' then values
              when 'K_RANGE', 'ORDER_BINS' then values.map(&:to_i)
              when 'OUTLIER_SD' then values.first.to_f
              else values.first.to_i
              end
      [key, value]
    end
  end

  def self.read(path)
    seen = Set.new
    customers = Set.new
    rows = []
    duplicates = free = total = 0
    File.readlines(path, chomp: true).drop(1).each do |line|
      customer, day, order_id, category, amount = line.split(',')
      customers.add(customer)
      total += 1
      duplicate = seen.include?(line)
      seen.add(line)
      if duplicate
        duplicates += 1
      elsif amount.to_i.zero?
        free += 1
      else
        rows << Row.new(customer, day.to_i, order_id, category, amount.to_i)
      end
    end
    { rows: rows, customers: customers, total: total, duplicates: duplicates, free: free }
  end

  def self.orders(rows, first_day, last_day)
    orders = {}
    rows.each do |row|
      next unless row.day.between?(first_day, last_day)

      order = orders[row.order_id] ||= Order.new(row.order_id, row.customer, row.day, 0, [])
      order.day = [order.day, row.day].min
      order.net += row.amount
      order.rows << row
    end
    orders.values
  end
end
