module Dataset
  Table = Data.define(:names, :ids, :rows)
  Settings = Data.define(
    :missing, :scaling, :components, :cumulative_target, :parallel_iterations, :seed,
    :t2_limit, :spe_limit, :varimax_cycles, :top_rows, :scree_width,
    :biplot_width, :biplot_height, :circle_radius, :diagnostic_width, :diagnostic_height
  )
  Input = Data.define(:data, :supplementary, :settings)

  module_function

  def read_table(path)
    header, *lines = File.readlines(path, chomp: true)
    ids = []
    rows = lines.map do |line|
      id, *values = line.split(',')
      ids << id
      values.map { |text| text == 'NA' ? nil : text.to_f }
    end
    Table.new(header.split(',').drop(1), ids, rows)
  end

  def read_settings(path)
    entries = File.readlines(path, chomp: true).to_h do |line|
      keyword, *values = line.split(' ')
      [keyword, values]
    end
    Settings.new(
      missing: entries['MISSING'][0], scaling: entries['SCALING'][0],
      components: entries['COMPONENTS'][0],
      cumulative_target: entries['CUMULATIVE_TARGET'][0].to_f,
      parallel_iterations: entries['PARALLEL'][0].to_i, seed: entries['PARALLEL'][1].to_i,
      t2_limit: entries['T2_LIMIT'][0].to_f, spe_limit: entries['SPE_LIMIT'][0].to_f,
      varimax_cycles: entries['VARIMAX_CYCLES'][0].to_i, top_rows: entries['TOP_ROWS'][0].to_i,
      scree_width: entries['SCREE_WIDTH'][0].to_i,
      biplot_width: entries['BIPLOT_SIZE'][0].to_i, biplot_height: entries['BIPLOT_SIZE'][1].to_i,
      circle_radius: entries['CIRCLE_RADIUS'][0].to_i,
      diagnostic_width: entries['DIAGNOSTIC_SIZE'][0].to_i,
      diagnostic_height: entries['DIAGNOSTIC_SIZE'][1].to_i
    )
  end

  def load(directory)
    Input.new(
      read_table(File.join(directory, 'data.csv')),
      read_table(File.join(directory, 'supplementary.csv')),
      read_settings(File.join(directory, 'params.txt'))
    )
  end
end
