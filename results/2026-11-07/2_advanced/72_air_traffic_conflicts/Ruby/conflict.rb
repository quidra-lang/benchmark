require_relative 'trajectory'

module Conflict
  module_function

  def loss(relative, velocity, t1, t2, dh, dv)
    px, py, pz = relative
    wx, wy, wz = velocity
    qa = wx * wx + wy * wy
    qb = 2.0 * (px * wx + py * wy)
    qc = (px * px + py * py) - dh.to_f * dh.to_f
    lo, hi = t1.to_f, t2.to_f
    if qa < 1e-12
      return if qc >= 0
    else
      discriminant = qb * qb - 4.0 * qa * qc
      return if discriminant <= 0
      root = Math.sqrt(discriminant)
      lo = [lo, t1 + (-qb - root) / (2.0 * qa)].max
      hi = [hi, t1 + (-qb + root) / (2.0 * qa)].min
    end
    if wz == 0
      return if pz.abs >= dv
    else
      r1, r2 = (-dv.to_f - pz) / wz, (dv.to_f - pz) / wz
      lo = [lo, t1 + [r1, r2].min].max
      hi = [hi, t1 + [r1, r2].max].min
    end
    return if hi - lo <= 1e-6
    tc = qa >= 1e-12 ? t1 + (-qb / (2.0 * qa)) : t1.to_f
    tc = [[tc, lo].max, hi].min
    tau = tc - t1
    ex, ey = px + wx * tau, py + wy * tau
    {lo: lo, hi: hi, tc: tc, distance: Math.sqrt(ex * ex + ey * ey), vertical: (pz + wz * tau).abs}
  end

  def pair(a_name, a_path, b_name, b_path, dh, dv)
    pieces = []
    a_path[:segments].each do |a|
      b_path[:segments].each do |b|
        t1, t2 = [a[:ts], b[:ts]].max, [a[:te], b[:te]].min
        next unless t1 < t2
        pa, pb = Trajectory.position(a, t1), Trajectory.position(b, t1)
        relative = 3.times.map { |i| pa[i] - pb[i] }
        velocity = 3.times.map { |i| a[:velocity][i] - b[:velocity][i] }
        interval = loss(relative, velocity, t1, t2, dh, dv)
        pieces << interval.merge(a: a, b: b) if interval
      end
    end
    pieces = pieces.each_with_index.sort_by { |piece, i| [piece[:lo], i] }.map(&:first)
    conflicts = []
    pieces.each do |piece|
      if conflicts.empty? || piece[:lo] - conflicts.last[:end] > 1e-6
        conflicts << {pair: [a_name, b_name], name: "#{a_name}-#{b_name}", start: piece[:lo],
                      end: piece[:hi], pieces: [piece], closest: piece}
      else
        current = conflicts.last
        current[:pieces] << piece
        current[:end] = piece[:hi]
        current[:closest] = piece if piece[:distance] < current[:closest][:distance] - 1e-9
      end
    end
    conflicts
  end

  def all(trajectories, dh, dv)
    trajectories.keys.sort.combination(2).flat_map do |a, b|
      pair(a, trajectories[a], b, trajectories[b], dh, dv)
    end.sort_by { |item| [item[:start], *item[:pair]] }
  end
end
