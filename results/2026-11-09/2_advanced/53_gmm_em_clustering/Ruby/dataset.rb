module Dataset
  module_function

  def read_all
    ids, points = [], []
    File.readlines('input/points.csv', chomp: true).drop(1).each do |line|
      id, x, y = line.split(',')
      ids << id
      points << [x.to_f, y.to_f]
    end
    params = File.readlines('input/params.txt').to_h do |line|
      key, *values = line.split
      parsed = case key
               when 'TYPES' then values
               when 'K', 'MAP_SIZE' then values.map(&:to_i)
               when 'ITERATIONS', 'KMEANS_MAX_ITERATIONS', 'CV_FOLDS' then values.first.to_i
               when 'GOF_EDGES', 'MAP_X', 'MAP_Y' then values.map(&:to_f)
               else values.first.to_f
               end
      [key.downcase.to_sym, parsed]
    end
    initial = {}
    File.read('input/init.txt').split("\n\n").each do |block|
      rows = block.lines.map(&:split)
      k = rows[0][1].to_i
      initial[k] = {weights: rows[1].drop(1).map(&:to_f),
                    means: rows.drop(2).map { |r| r[2, 2].map(&:to_f) },
                    covariances: rows.drop(2).map { |r| r[4, 3].map(&:to_f) }}
    end
    [ids, points, params, initial]
  end
end
