require_relative 'vector3'

module Shading
  include Vector3
  module_function

  def base_color(material, point)
    if material.checker
      alternate, size = material.checker
      return alternate if point.sum { |a| a.div(size) }.odd?
    end
    material.color
  end

  def phong(material, normal, light, view, ndl, intensity, factor)
    effective = mul(intensity, factor)
    diffuse = mul(mul(material.kd, ndl), effective)
    rv = dot(sub(sc(normal, 2 * ndl), light), view)
    specular = 0
    if rv.positive?
      power = S
      material.n.times { power = mul(power, rv) }
      specular = mul(mul(material.ks, power), effective)
    end
    [diffuse, specular]
  end

  def reflected(direction, normal)
    norm(sub(direction, sc(normal, 2 * dot(direction, normal))))
  end

  def refraction(material, direction, normal, front)
    wr, wt = material.kr, material.kt
    return [wr, wt, nil, false] if wt.zero?
    eta = front ? (S * S).div(material.ior) : material.ior
    cosine = -dot(direction, normal)
    discriminant = S * S - (mul(eta, eta) * (S * S - cosine * cosine)).div(S)
    return [wr + wt, 0, nil, true] if discriminant.negative?
    transmitted = norm(add(sc(direction, eta), sc(normal, mul(eta, cosine) - isqrt(discriminant))))
    r0 = ((material.ior - S) * S).div(material.ior + S)
    reflectance = mul(r0, r0)
    x = S - [cosine, S].min
    power = S
    5.times { power = mul(power, x) }
    fresnel = reflectance + mul(S - reflectance, power)
    transfer = mul(material.kt, fresnel)
    [wr + transfer, wt - transfer, transmitted, false]
  end

  def mix(*weighted_colors)
    3.times.map { |a| weighted_colors.sum { |color, weight| (color[a] * weight).div(S) } }
  end
end
