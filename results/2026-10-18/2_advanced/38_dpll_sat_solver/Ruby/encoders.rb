module Encoders
  module_function

  def queens(n)
    clauses = (0...n).map { |r| (1..n).map { |c| r * n + c } }
    (1..n * n).each do |a|
      ar, ac = (a - 1).divmod(n)
      ((a + 1)..n * n).each do |b|
        br, bc = (b - 1).divmod(n)
        clauses << [-a, -b] if ar == br || ac == bc || (ar - br).abs == (ac - bc).abs
      end
    end
    [n * n, clauses]
  end

  def pigeon(pigeons, holes)
    clauses = (0...pigeons).map { |p| (1..holes).map { |h| p * holes + h } }
    (0...pigeons).each do |p|
      (1..holes).to_a.combination(2) { |a, b| clauses << [-(p * holes + a), -(p * holes + b)] }
    end
    (1..holes).each do |h|
      (0...pigeons).to_a.combination(2) { |a, b| clauses << [-(a * holes + h), -(b * holes + h)] }
    end
    [pigeons * holes, clauses]
  end

  def coloring(graph, colors)
    clauses = (0...graph[:vertices]).map { |v| (1..colors).map { |c| v * colors + c } }
    (0...graph[:vertices]).each do |v|
      (1..colors).to_a.combination(2) { |a, b| clauses << [-(v * colors + a), -(v * colors + b)] }
    end
    graph[:edges].each do |a, b|
      (1..colors).each { |c| clauses << [-((a - 1) * colors + c), -((b - 1) * colors + c)] }
    end
    [graph[:vertices] * colors, clauses]
  end

  def positions(model, rows, width)
    (0...rows).map { |r| (1..width).find { |c| model[r * width + c] } }
  end
end
