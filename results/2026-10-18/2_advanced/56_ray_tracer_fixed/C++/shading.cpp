#include "renderer.hpp"
Color base_color(const Material &material, Vec point) {
    if (material.checker_size == 0)
        return material.color;
    const I cell = floor_div(point[0], material.checker_size) + floor_div(point[1], material.checker_size) +
                   floor_div(point[2], material.checker_size);
    return cell % 2 != 0 ? material.second : material.color;
}
std::array<I, 2> phong(const Material &material, Vec normal, Vec light, Vec view, I effective) {
    const I ndl = dot(normal, light), diffuse = mul(mul(material.kd, ndl), effective);
    const Vec reflected = sub(sc(normal, 2 * ndl), light);
    const I rv = dot(reflected, view);
    I specular = 0;
    if (rv > 0) {
        I power = scale;
        for (I n = 0; n < material.exponent; ++n)
            power = mul(power, rv);
        specular = mul(mul(material.ks, power), effective);
    }
    return {diffuse, specular};
}
Vec reflected(Vec direction, Vec normal) {
    return norm(sub(direction, sc(normal, 2 * dot(direction, normal))));
}
Weights refracted(const Material &material, Vec direction, Vec normal, bool front) {
    Weights out{material.kr, material.kt, {}, false};
    if (material.kt == 0)
        return out;
    const I eta = front ? floor_div(scale * scale, material.ior) : material.ior, cn = -dot(direction, normal),
            disc = scale * scale - floor_div(mul(eta, eta) * (scale * scale - cn * cn), scale);
    if (disc < 0) {
        out.reflection = material.kr + material.kt;
        out.refraction = 0;
        out.total_internal = true;
        return out;
    }
    out.direction = norm(add(sc(direction, eta), sc(normal, mul(eta, cn) - isqrt(disc))));
    const I r0 = floor_div((material.ior - scale) * scale, material.ior + scale), base = mul(r0, r0),
            x = scale - std::min(cn, scale);
    I power = scale;
    for (int i = 0; i < 5; ++i)
        power = mul(power, x);
    const I fresnel = base + mul(scale - base, power), reflected = mul(material.kt, fresnel);
    out.reflection = material.kr + reflected;
    out.refraction = material.kt - reflected;
    return out;
}
Color mix(Color local, I local_weight, Color reflection, I reflected_weight, Color refraction,
          I refracted_weight) {
    Color out;
    for (int i = 0; i < 3; ++i)
        out[i] = floor_div(local[i] * local_weight, scale) +
                 floor_div(reflection[i] * reflected_weight, scale) +
                 floor_div(refraction[i] * refracted_weight, scale);
    return out;
}
