require_relative 'mesh'
require_relative 'materials'
require_relative 'transient'
require_relative 'steady'
require_relative 'report'

def sum(values) = Transient.sum(values)
def real(value, places = 2) = Report.real(value, places)
def time_text(value) = Report.time(value)
def verdict(value) = value ? 'ok' : 'failed'

def read_params(mesh)
  params = { probes: [], runs: [] }
  integers = %w[end_time probe_every max_iterations]
  File.foreach('input/params.txt') do |line|
    key, *values = line.split
    case key
    when 'probe'
      params[:probes] << { name: values[0], cell: mesh.cell(values[1].to_i, values[2].to_i) }
    when 'run'
      params[:runs] << { name: values[0], method: values[1], step: values[2].to_i }
    when 'snapshots' then params[:snapshots] = values.map(&:to_i)
    when 'bands' then params[:bands] = values.map(&:to_f)
    when 'reference' then params[:reference] = values[0]
    else params[key.to_sym] = integers.include?(key) ? values[0].to_i : values[0].to_f
    end
  end
  params
end

def read_boundary(mesh, end_time)
  segments, sources = [], []
  File.foreach('input/boundary.txt') do |line|
    type, name, *values = line.split
    if type == 'segment'
      edge, first, last, kind, *numbers = values
      segments << { name: name, edge: edge, kind: kind, numbers: numbers.map(&:to_f),
                    faces: mesh.segment_faces(edge, first.to_i, last.to_i) }
    else
      r1, c1, r2, c2 = values.first(4).map(&:to_i)
      cells = mesh.source_cells(r1, c1, r2, c2)
      intervals = values.drop(5).map(&:to_i).each_slice(2).to_a
      duration = intervals.reduce(0) { |total, (on, off)| total + [off, end_time].min - [on, end_time].min }
      power = values[4].to_f
      sources << { name: name, cells: cells, power: power, per_cell: power / cells.size,
                   intervals: intervals, duty: duration.to_f / end_time }
    end
  end
  [segments, sources]
end

def build_system(mesh, materials, segments, sources)
  by_code = materials.to_h { |material| [material[:code], material] }
  cell_materials = mesh.codes.map { |code| by_code.fetch(code) }
  capacity = cell_materials.map { |material| Materials.capacity(material, mesh.dx, mesh.thickness) }
  faces = mesh.neighbors.each_with_index.map do |neighbors, p|
    neighbors.map do |q|
      { neighbor: q, g: q ? Materials.interior(cell_materials[p][:k], cell_materials[q][:k], mesh.thickness) : 0.0, theta: nil }
    end
  end
  segments.each do |segment|
    segment[:faces].each do |p, direction|
      k = cell_materials[p][:k]
      face = faces[p][direction]
      case segment[:kind]
      when 'fixed'
        face[:g], face[:theta] = Materials.fixed(k, mesh.thickness), segment[:numbers][0]
      when 'convective'
        face[:g] = Materials.convective(k, segment[:numbers][0], mesh.dx, mesh.thickness)
        face[:theta] = segment[:numbers][1]
      end
    end
  end
  diagonal = faces.map { |row| sum(row.map { |face| face[:g] }) }
  beta = faces.map { |row| sum(row.filter_map { |face| face[:g] * face[:theta] if face[:theta] }) }
  source_all = Array.new(mesh.count, 0.0)
  sources.each { |source| source[:cells].each { |p| source_all[p] += source[:per_cell] } }
  { mesh: mesh, capacity: capacity, faces: faces, diagonal: diagonal,
    beta: beta, source_all: source_all,
    dt_max: capacity.each_index.map { |p| capacity[p] / diagonal[p] }.min }
end

def source_at(sources, time, count)
  field = Array.new(count, 0.0)
  powers = []
  sources.each do |source|
    next unless source[:intervals].any? { |on, off| on <= time && time < off }
    source[:cells].each { |p| field[p] += source[:per_cell] }
    powers << source[:power]
  end
  [field, sum(powers)]
end

def stored_heat(system, field, initial, cells = nil)
  cells ||= field.each_index
  sum(cells.map { |p| system[:capacity][p] * (field[p] - initial) })
end

def segment_flow(system, segment, field)
  return 0.0 if segment[:kind] == 'insulated'
  sum(segment[:faces].map do |p, direction|
    face = system[:faces][p][direction]
    face[:g] * (face[:theta] - field[p])
  end)
end

def hottest(field) = field.each_index.max_by { |p| [field[p], -p] }

def field_summary(mesh, field)
  p = hottest(field)
  "max #{real(field[p])} at #{mesh.coordinates(p)} min #{real(field.min)} mean #{real(sum(field) / field.size)}"
end

def perform_run(run, system, params, segments, sources)
  required = [params[:end_time], params[:probe_every], *params[:snapshots],
              *sources.flat_map { |source| source[:intervals].flatten }]
  step = run[:step]
  dt = step / 1000.0
  status = if required.any? { |time| time % step != 0 }
             :step
           elsif run[:method] == 'ftcs' && dt > system[:dt_max]
             :unstable
           else
             :accepted
           end
  result = run.merge(status: status)
  return result unless status == :accepted
  count = system[:mesh].count
  field = Array.new(count, params[:initial])
  boundary = Array.new(segments.size, 0.0)
  source_total = 0.0
  result.merge!(steps: params[:end_time] / step, snapshots: {}, energy_at: {},
                probes: [], peak: nil, alarm: nil, above: 0)
  (0..result[:steps]).each do |n|
    time = n * step
    p = hottest(field)
    result[:peak] = [field[p], time, p] if !result[:peak] || field[p] > result[:peak][0]
    if field[p] >= params[:alarm]
      result[:alarm] ||= [time, p]
      result[:above] += step if n.positive?
    end
    if time % params[:probe_every] == 0
      result[:probes] << [time, params[:probes].map { |probe| field[probe[:cell]] }]
    end
    if params[:snapshots].include?(time)
      result[:snapshots][time] = field.dup
      result[:energy_at][time] = [stored_heat(system, field, params[:initial]), sum(boundary), source_total]
    end
    break if n == result[:steps]
    source, power = source_at(sources, time, count)
    updated, intermediate = Transient.advance(run[:method], system, field, source, dt)
    segments.each_with_index do |segment, j|
      chosen = if run[:method] == 'ftcs'
                 field
               elsif %w[left right].include?(segment[:edge])
                 intermediate
               elsif run[:method] == 'backward_euler'
                 updated
               else
                 field.zip(updated).map { |a, b| (a + b) / 2 }
               end
      boundary[j] += dt * segment_flow(system, segment, chosen)
    end
    source_total += dt * power
    field = updated
  end
  result.merge(field: field, boundary: boundary, source: source_total,
               stored: stored_heat(system, field, params[:initial]))
end

def solve_steady(system, params, sources)
  rhs = system[:beta].zip(system[:source_all]).map { |a, b| a + b }
  unit_rhs = sources.map do |source|
    values = Array.new(system[:mesh].count, 0.0)
    source[:cells].each { |p| values[p] = 1.0 / source[:cells].size }
    values
  end
  field, base, *responses = Steady.band_solve(system, [rhs, system[:beta], *unit_rhs])
  solvers = []
  %w[jacobi gauss_seidel sor].each do |method|
    solvers << Steady.iterate(system, params[:initial], params[:tolerance], params[:max_iterations], method, params[:omega])
  end
  changes = solvers[0][:changes]
  rho = Math.sqrt(changes[-1] / changes[-3])
  omega = 2 / (1 + Math.sqrt(1 - rho * rho))
  solvers << Steady.iterate(system, params[:initial], params[:tolerance], params[:max_iterations], 'sor_estimated', omega)
  solvers.each do |solver|
    deltas = solver[:changes]
    solver[:rate] = Math.sqrt(deltas[-1] / deltas[-3])
    solver[:milestones] = [1000, 100, 10, 1].map do |factor|
      position = deltas.index { |delta| delta < params[:tolerance] * factor }
      position ? position + 1 : 'never'
    end
    solver[:error] = field.zip(solver[:field]).map { |a, b| (a - b).abs }.max
    solver[:residual] = Steady.residual(system, solver[:field], rhs)
  end
  { field: field, base: base, responses: responses, solvers: solvers,
    rho: rho, omega: omega, residual: Steady.residual(system, field, rhs) }
end

def steady_lines(system, params, materials, segments, sources, steady)
  mesh = system[:mesh]
  field, base, responses = steady.values_at(:field, :base, :responses)
  lines = ["steady #{field_summary(mesh, field)}", *Report.field_lines(mesh, field)]
  materials.each do |material|
    cells = mesh.codes.each_index.select { |p| mesh.codes[p] == material[:code] }
    values = cells.map { |p| field[p] }
    lines << "material #{material[:code]} #{material[:name]} cells #{cells.size} min #{real(values.min)} max #{real(values.max)} mean #{real(sum(values) / cells.size)}"
  end
  sources.each do |source|
    values = source[:cells].map { |p| field[p] }
    lines << "source #{source[:name]} power #{real(source[:power], 4)} duty #{real(source[:duty], 4)} mean #{real(sum(values) / values.size)} max #{real(values.max)}"
  end
  sources.each do |source|
    sources.each_with_index do |other, j|
      influence = sum(source[:cells].map { |p| responses[j][p] }) / source[:cells].size
      lines << "influence #{source[:name]} #{other[:name]} #{real(influence, 4)}"
    end
  end
  superposed = base.dup
  duty = base.dup
  sources.each_with_index do |source, j|
    field.each_index do |p|
      superposed[p] += source[:power] * responses[j][p]
      duty[p] += (source[:duty] * source[:power]) * responses[j][p]
    end
  end
  error = field.zip(superposed).map { |a, b| (a - b).abs }.max
  lines << "superposition #{verdict(error <= 0.000001)}"
  sources.each_with_index do |source, i|
    segments.each do |segment|
      path = segment[:kind] == 'insulated' ? 0.0 : sum(segment[:faces].map { |p, direction| system[:faces][p][direction][:g] * responses[i][p] })
      lines << "path #{source[:name]} #{segment[:name]} #{real(path, 4)}"
    end
  end
  lines << "duty_steady #{field_summary(mesh, duty)}"
  sources.each_with_index do |source, i|
    values = field.each_index.map { |p| (params[:limit] - (field[p] - source[:power] * responses[i][p])) / responses[i][p] }
    p = values.each_index.min_by { |point| [values[point], point] }
    lines << "headroom #{source[:name]} max_power #{real(values[p], 4)} at #{mesh.coordinates(p)}"
  end
  material_order = materials.each_with_index.to_h { |material, i| [material[:code], i] }
  interfaces = {}
  gradient = nil
  field.each_index do |p|
    [1, 3].each do |direction|
      face = system[:faces][p][direction]
      q = face[:neighbor]
      next unless q
      value = (field[p] - field[q]).abs / mesh.dx
      gradient = [value, p, q] if !gradient || value > gradient[0]
      first, second = mesh.codes[p], mesh.codes[q]
      next if first == second
      flow = face[:g] * (field[p] - field[q])
      if material_order[first] > material_order[second]
        first, second = second, first
        flow = -flow
      end
      entry = interfaces[[first, second]] ||= [0, 0.0, 0.0]
      entry[0] += 1
      entry[1] += flow if flow.positive?
      entry[2] += flow.abs if flow.negative?
    end
  end
  interfaces.sort_by { |(a, b), _| [material_order[a], material_order[b]] }.each do |(a, b), (faces, forward, backward)|
    lines << "interface #{a} #{b} faces #{faces} forward #{real(forward, 4)} backward #{real(backward, 4)}"
  end
  flows = segments.map { |segment| segment_flow(system, segment, field) }
  segments.each_with_index { |segment, j| lines << "segment #{segment[:name]} #{segment[:edge]} #{segment[:kind]} flow #{real(flows[j], 4)}" }
  power = sum(sources.map { |source| source[:power] })
  lines << "sources #{real(power, 4)}"
  lines << "balance #{verdict((sum(flows) + power).abs <= 0.000001 * (sum(flows.map(&:abs)) + power))}"
  lines << "max_gradient #{real(gradient[0])} between #{mesh.coordinates(gradient[1])} and #{mesh.coordinates(gradient[2])}"
  steady[:solvers].each do |solver|
    omega = solver[:method].start_with?('sor') ? " omega #{real(solver[:omega], 4)}" : ''
    lines << "solver #{solver[:method]}#{omega} iterations #{solver[:iterations]} converged #{solver[:converged] ? 'yes' : 'no'} rate #{real(solver[:rate], 6)} milestones #{solver[:milestones].join(' ')}"
  end
  lines
end

def output_runs(system, params, materials, segments, runs, steady)
  mesh = system[:mesh]
  snapshots = []
  probes = ['run,time,probe,temperature']
  comparison = ["ftcs_max_dt #{real(system[:dt_max], 4)}"]
  reference = runs.find { |run| run[:name] == params[:reference] }
  runs.each do |run|
    prefix = "run #{run[:name]} #{run[:method]} dt #{time_text(run[:step])}"
    unless run[:status] == :accepted
      rejection = "#{prefix} rejected #{run[:status]}"
      snapshots << rejection + (run[:status] == :unstable ? " max_dt #{real(system[:dt_max], 4)}" : '')
      comparison << rejection
      next
    end
    params[:snapshots].each do |time|
      field = run[:snapshots][time]
      snapshots << "#{prefix} time #{time_text(time)} #{field_summary(mesh, field)}"
      snapshots.concat(Report.field_lines(mesh, field))
    end
    run[:probes].each do |time, values|
      params[:probes].each_with_index { |probe, i| probes << "#{run[:name]},#{time_text(time)},#{probe[:name]},#{real(values[i], 3)}" }
    end
    peak, peak_time, peak_cell = run[:peak]
    alarm = run[:alarm] ? "#{time_text(run[:alarm][0])} at #{mesh.coordinates(run[:alarm][1])}" : 'never'
    comparison << "#{prefix} steps #{run[:steps]} peak #{real(peak)} time #{time_text(peak_time)} at #{mesh.coordinates(peak_cell)} alarm #{alarm} above #{time_text(run[:above])}"
    u, b, q = run[:stored], sum(run[:boundary]), run[:source]
    balanced = (u - b - q).abs <= 0.000001 * (u.abs + b.abs + q.abs)
    comparison << "energy #{run[:name]} stored #{real(u)} boundary #{real(b)} source #{real(q)} balance #{verdict(balanced)}"
    params[:snapshots].each do |time|
      u, b, q = run[:energy_at][time]
      comparison << "energy_at #{run[:name]} time #{time_text(time)} stored #{real(u)} boundary #{real(b)} source #{real(q)}"
    end
    materials.each do |material|
      cells = mesh.codes.each_index.select { |p| mesh.codes[p] == material[:code] }
      comparison << "energy_material #{run[:name]} #{material[:code]} #{real(stored_heat(system, run[:field], params[:initial], cells))}"
    end
    segments.each_with_index { |segment, j| comparison << "energy_segment #{run[:name]} #{segment[:name]} #{real(run[:boundary][j])}" }
    params[:probes].each_with_index do |probe, i|
      records = run[:probes].map { |time, values| [values[i], time] }
      maximum = records.max_by { |value, time| [value, -time] }
      minimum = records.min_by { |value, time| [value, time] }
      comparison << "probe_summary #{run[:name]} #{probe[:name]} max #{real(maximum[0], 3)} time #{time_text(maximum[1])} min #{real(minimum[0], 3)} time #{time_text(minimum[1])}"
    end
    unless run.equal?(reference)
      params[:snapshots].each do |time|
        errors = run[:snapshots][time].zip(reference[:snapshots][time]).map { |a, b| (a - b).abs }
        rms = Math.sqrt(sum(errors.map { |error| error * error }) / mesh.count)
        comparison << "compare #{run[:name]} #{reference[:name]} time #{time_text(time)} max_diff #{real(errors.max, 6)} rms_diff #{real(rms, 6)}"
      end
    end
    error = run[:field].zip(steady[:field]).map { |a, b| (a - b).abs }.max
    comparison << "final #{run[:name]} steady_max_diff #{real(error, 6)}"
  end
  comparison << "steady direct max_residual #{real(steady[:residual], 6)}"
  steady[:solvers].each do |solver|
    comparison << "steady #{solver[:method]} iterations #{solver[:iterations]} max_diff #{real(solver[:error], 6)} max_residual #{real(solver[:residual], 6)}"
  end
  comparison << "jacobi_spectral_radius #{real(steady[:rho], 6)} squared #{real(steady[:rho] * steady[:rho], 6)}"
  comparison << "omega_estimated #{real(steady[:omega], 4)}"
  isotherms = []
  [[nil, steady[:field]], *params[:snapshots].map { |time| [time, reference[:snapshots][time]] }].each do |time, field|
    counts, map = Report.isotherms(mesh, field, params[:bands])
    label = time ? "#{reference[:name]} time #{time_text(time)}" : 'steady'
    isotherms << "isotherms #{label} counts #{counts.join(' ')}"
    isotherms.concat(map)
  end
  Report.write('snapshots.txt', snapshots)
  Report.write('probes.csv', probes)
  Report.write('solver_comparison.txt', comparison)
  Report.write('isotherms.txt', isotherms)
end

if $PROGRAM_NAME == __FILE__
  mesh = Mesh.new
  materials = Materials.read
  params = read_params(mesh)
  segments, sources = read_boundary(mesh, params[:end_time])
  system = build_system(mesh, materials, segments, sources)
  steady = solve_steady(system, params, sources)
  runs = params[:runs].map { |run| perform_run(run, system, params, segments, sources) }
  Report.write('steady_state.txt', steady_lines(system, params, materials, segments, sources, steady))
  output_runs(system, params, materials, segments, runs, steady)
end
