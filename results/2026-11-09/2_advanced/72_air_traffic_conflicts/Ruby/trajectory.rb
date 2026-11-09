module Trajectory
  module_function

  def build(plan, types)
    time = (plan[:departure] + plan[:delay]).to_f
    level = plan[:level] + plan[:offset]
    segments = []
    length = 0.0
    times = [[time, level]]
    plan[:waypoints].each_cons(2).with_index(1) do |(first, last), leg|
      dx, dy = last[:x] - first[:x], last[:y] - first[:y]
      distance = Math.sqrt(dx * dx + dy * dy) / 10.0
      duration = distance * 3600.0 / plan[:speed].to_f
      vx, vy = (dx / 10.0) / duration, (dy / 10.0) / duration
      length += distance
      target = last[:level] ? last[:level] + plan[:offset] : level
      start = [first[:x] / 10.0, first[:y] / 10.0, (level * 100).to_f]
      finish = [last[:x] / 10.0, last[:y] / 10.0, (target * 100).to_f]
      if target == level
        segments << segment(segments.size + 1, leg, 'LVL', time, time + duration, start, [vx, vy, 0.0], finish)
      else
        climb = target > level
        rate = types[plan[:type]][climb ? :climb : :descent]
        vz = rate / 60.0
        vz = -vz unless climb
        change_time = ((target - level).abs * 6000).to_f / rate.to_f
        middle = [start[0] + vx * change_time, start[1] + vy * change_time, (target * 100).to_f]
        segments << segment(segments.size + 1, leg, climb ? 'CLB' : 'DES', time, time + change_time, start, [vx, vy, vz], middle)
        segments << segment(segments.size + 1, leg, 'LVL', time + change_time, time + duration, middle, [vx, vy, 0.0], finish)
      end
      time += duration
      level = target
      times << [time, level]
    end
    {segments: segments, arrival: time, length: length, waypoint_times: times}
  end

  def segment(number, leg, phase, ts, te, start, velocity, finish)
    {number: number, leg: leg, phase: phase, ts: ts, te: te, start: start, velocity: velocity, end: finish}
  end

  def position(segment, time)
    elapsed = time - segment[:ts]
    3.times.map { |i| segment[:start][i] + segment[:velocity][i] * elapsed }
  end

  def active_segment(trajectory, time)
    segments = trajectory[:segments]
    return unless segments.first[:ts] <= time && time < segments.last[:te]
    segments.find { |part| part[:ts] <= time && time < part[:te] }
  end

  def observe(trajectory, time)
    part = active_segment(trajectory, time)
    [position(part, time), part] if part
  end
end
