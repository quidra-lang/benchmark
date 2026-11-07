module Bom
  Row = Struct.new(:parent, :child, :quantity, :scrap, keyword_init: true)

  def self.need(row, quantity)
    (quantity * row.quantity * (100 + row.scrap) + 99).div(100)
  end

  class Structure
    attr_reader :children, :parents, :low_level, :cumulative, :order

    def initialize(items, errors)
      @children = items.to_h { |id, _item| [id, []] }
      @parents = items.to_h { |id, _item| [id, []] }
      File.readlines('input/bom.csv', chomp: true).drop(1).each_with_index do |line, index|
        parent, child, quantity, scrap = line.split(',')
        quantity = quantity.to_i
        scrap = scrap.to_i
        message = if !items.key?(parent)
                    "unknown item #{parent}"
                  elsif !items.key?(child)
                    "unknown item #{child}"
                  elsif quantity < 1
                    "bad quantity #{quantity}"
                  elsif scrap > 50
                    "bad scrap #{scrap}"
                  elsif parent == child
                    "cycle #{parent} -> #{parent}"
                  elsif @children[parent].any? { |row| row.child == child }
                    "duplicate #{parent} -> #{child}"
                  elsif (path = find_path(child, parent, {}))
                    "cycle #{([parent] + path).join(' -> ')}"
                  end
        if message
          errors << "bom.csv line #{index + 2}: #{message}"
          next
        end
        row = Row.new(parent: parent, child: child, quantity: quantity, scrap: scrap)
        @children[parent] << row
        @children[parent].sort_by!(&:child)
        @parents[child] << row
      end
      @parents.each_value { |rows| rows.sort_by!(&:parent) }
      @low_level = {}
      items.each_key { |id| level(id) }
      @order = items.keys.sort_by { |id| [@low_level[id], id] }
      @cumulative = {}
      @order.reverse_each do |id|
        longest = @children[id].map { |row| @cumulative[row.child] }.max || 0
        @cumulative[id] = items[id].lead_time + longest
      end
    end

    def manufactured?(id)
      !@children[id].empty?
    end

    private

    def find_path(id, target, visited)
      return [id] if id == target

      visited[id] = true
      @children[id].each do |row|
        next if visited[row.child]

        path = find_path(row.child, target, visited)
        return [id] + path if path
      end
      nil
    end

    def level(id)
      return @low_level[id] if @low_level.key?(id)

      @low_level[id] = if @parents[id].empty?
                         0
                       else
                         @parents[id].map { |row| level(row.parent) }.max + 1
                       end
    end
  end
end
