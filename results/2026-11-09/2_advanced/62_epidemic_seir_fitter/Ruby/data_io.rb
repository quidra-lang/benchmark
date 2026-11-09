require 'fileutils'

module DataIO
  def self.read_inputs
    rows = File.readlines('input/cases.csv', chomp: true).drop(1).map { |line| line.split(',').map(&:to_i) }
    groups, contacts = [], []
    File.foreach('input/population.txt') do |line|
      kind, *values = line.split
      if kind == 'group'
        groups << [values[0], values[1].to_i, values[2].to_f]
      else
        contacts << values.map(&:to_f)
      end
    end
    interventions = File.readlines('input/interventions.txt').map do |line|
      day, multiplier = line.split
      [day.to_i, multiplier.to_f]
    end
    params = { 'scenario' => [], 'contact_change' => [] }
    File.foreach('input/params.txt') do |line|
      name, *values = line.split
      params[name] = case name
                     when 'scenario'
                       params[name] << [values[0], values[1].to_f]
                     when 'contact_change'
                       params[name] << [values[0], values[1], values[2].to_f]
                     when 'holdout', 'death_lag', 'generation', 'horizon'
                       values[0].to_i
                     when 'milestones', 'golden'
                       values.map(&:to_i)
                     when 'beta_grid', 'rho_grid'
                       [values[0].to_f, values[1].to_f, values[2].to_i]
                     when 'nelder_mead'
                       [*values.take(4).map(&:to_f), values[4].to_i]
                     when 'initial', 'simplex'
                       values.map(&:to_f)
                     else
                       values[0].to_f
                     end
    end
    [rows.map { |r| r[1] }, rows.map { |r| r[2] }, groups, contacts, interventions, params]
  end

  def self.write_outputs(outputs)
    FileUtils.mkdir_p('output')
    outputs.each { |name, lines| File.write("output/#{name}", lines.join("\n") + "\n") }
  end
end
