module Fitting
  PHI = 0.6180339887498949

  def self.golden(function, a, b, iterations)
    c = b - PHI * (b - a)
    d = a + PHI * (b - a)
    fc, fd = function.call(c), function.call(d)
    records = [[a, b, c, d, fc, fd]]
    iterations.times do
      if fc < fd
        b, d, fd = d, c, fc
        c = b - PHI * (b - a)
        fc = function.call(c)
      else
        a, c, fc = c, d, fd
        d = a + PHI * (b - a)
        fd = function.call(d)
      end
      records << [a, b, c, d, fc, fd]
    end
    fc < fd ? [c, fc, records] : [d, fd, records]
  end

  def self.nelder_mead(function, beta, gamma, db, dg, alpha, chi, psi, omega, iterations)
    vertices = [[beta, gamma], [beta + db, gamma], [beta, gamma + dg]].each_with_index.map do |point, number|
      [number, *point, function.call(*point)]
    end
    initial = vertices.dup
    serial = 3
    records = []
    order = ->(v) { [v[3], v[0]] }
    toward = ->(o, v, t) { 2.times.map { |axis| o[axis] + t * (v[axis] - o[axis]) } }
    iterations.times do
      vertices.sort_by!(&order)
      first, second, third = vertices
      centroid = [(first[1] + second[1]) / 2.0, (first[2] + second[2]) / 2.0]
      reflected = 2.times.map { |axis| centroid[axis] + alpha * (centroid[axis] - third[axis + 1]) }
      fr = function.call(*reflected)
      accepted = nil
      if fr < first[3]
        expanded = toward.call(centroid, reflected, chi)
        fe = function.call(*expanded)
        accepted, value, operation = fe < fr ? [expanded, fe, 'expand'] : [reflected, fr, 'reflect']
      elsif fr < second[3]
        accepted, value, operation = reflected, fr, 'reflect'
      elsif fr < third[3]
        contracted = toward.call(centroid, reflected, psi)
        fc = function.call(*contracted)
        accepted, value, operation = contracted, fc, 'contract_out' if fc <= fr
      else
        contracted = toward.call(centroid, third[1, 2], psi)
        fc = function.call(*contracted)
        accepted, value, operation = contracted, fc, 'contract_in' if fc < third[3]
      end
      if accepted
        vertices = [first, second, [serial, *accepted, value]]
        serial += 1
      else
        operation = 'shrink'
        vertices = [first]
        [second, third].each do |vertex|
          point = toward.call(first[1, 2], vertex[1, 2], omega)
          vertices << [serial, *point, function.call(*point)]
          serial += 1
        end
      end
      vertices.sort_by!(&order)
      records << [operation, vertices.first]
    end
    [initial, records, vertices]
  end
end
