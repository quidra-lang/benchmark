require_relative 'vector3'

module Intersect
  include Vector3
  module_function

  def slab(lo, hi, origin, direction)
    near = far = near_axis = far_axis = nil
    3.times do |axis|
      component = direction[axis]
      if component.zero?
        return nil if origin[axis] < lo[axis] || origin[axis] > hi[axis]
        next
      end
      a = ((lo[axis] - origin[axis]) * S).div(component)
      b = ((hi[axis] - origin[axis]) * S).div(component)
      entry, leave = [a, b].minmax
      near, near_axis = entry, axis if near.nil? || entry > near
      far, far_axis = leave, axis if far.nil? || leave < far
    end
    near > far ? nil : [near, near_axis, far, far_axis]
  end

  def candidate(obj, origin, direction, epsilon)
    case obj[:kind]
    when 'sphere'
      oc = sub(origin, obj[:center])
      b = dot(oc, direction)
      center_t = (-b * S).div(dot(direction, direction))
      h = add(oc, sc(direction, center_t))
      q = (obj[:radius]**2).div(S) - dot(h, h)
      return nil if q.negative?
      width = (isqrt(q * S) * S).div(length(direction))
      first, second = center_t - width, center_t + width
      distance = first > epsilon ? first : second
      distance > epsilon ? [distance, nil, nil] : nil
    when 'plane'
      denominator = dot(direction, obj[:normal])
      return nil if denominator.zero?
      distance = (dot(sub(obj[:point], origin), obj[:normal]) * S).div(denominator)
      distance > epsilon ? [distance, nil, nil] : nil
    when 'box'
      interval = slab(obj[:lo], obj[:hi], origin, direction)
      return nil unless interval
      near, near_axis, far, far_axis = interval
      return [near, true, near_axis] if near > epsilon
      return [far, false, far_axis] if far > epsilon
      nil
    end
  end

  def outward_normal(obj, point, direction, intersection)
    return norm(sub(point, obj[:center])) if obj[:kind] == 'sphere'
    return obj[:normal] if obj[:kind] == 'plane'
    _, entering, axis = intersection
    sign = direction[axis].positive? ? 1 : -1
    sign = -sign if entering
    3.times.map { |a| a == axis ? sign * S : 0 }
  end

  def bounds(obj, margin)
    return nil if obj[:kind] == 'plane'
    if obj[:kind] == 'sphere'
      radius = obj[:radius] + margin
      [obj[:center].map { |a| a - radius }, obj[:center].map { |a| a + radius }]
    else
      [obj[:lo].map { |a| a - margin }, obj[:hi].map { |a| a + margin }]
    end
  end
end
