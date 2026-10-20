module CBS
  Conflict = Data.define(:kind, :time, :a, :b, :u, :v)

  def self.position(path, time) = path[[time, path.length - 1].min]

  def self.conflicts(paths)
    result = []
    1.upto(paths.map { |path| path.length - 1 }.max) do |time|
      paths.length.times do |a|
        ((a + 1)...paths.length).each do |b|
          current_a, current_b = position(paths[a], time), position(paths[b], time)
          if current_a == current_b
            result << Conflict.new('vertex', time, a, b, current_a, current_a)
          elsif current_a == position(paths[b], time - 1) && current_b == position(paths[a], time - 1)
            result << Conflict.new('edge', time, a, b, position(paths[a], time - 1), current_a)
          end
        end
      end
    end
    result
  end

  def self.split(conflict)
    c = conflict
    [[c.a, c.kind, c.u, c.v, c.time], [c.b, c.kind, c.v, c.u, c.time]]
  end

  Node = Data.define(:paths, :constraints, :number, :depth, :parent, :cost, :conflicts) do
    def key = [cost, conflicts.length, number]
  end
end
