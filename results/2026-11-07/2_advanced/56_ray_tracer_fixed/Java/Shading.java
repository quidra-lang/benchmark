final class Shading {
    record Phong(long diffuse, long specular) {}
    record Refraction(long reflected, long transmitted, Vector3 direction, boolean internal) {}
    static Scene.Color base(Scene.Material material, Vector3 point) {
        if (material.checker != null) {
            long k = FixedPoint.divide(point.x(), material.checkerSize) +
                     FixedPoint.divide(point.y(), material.checkerSize) +
                     FixedPoint.divide(point.z(), material.checkerSize);
            if (k % 2 != 0)
                return material.checker;
        }
        return material.color;
    }
    static Phong phong(Scene.Material material, Vector3 normal, Vector3 light, Vector3 view, long ndl,
                       long intensity, long factor) {
        long effective = FixedPoint.multiply(intensity, factor),
             diffuse = FixedPoint.multiply(FixedPoint.multiply(material.kd, ndl), effective),
             rv = normal.scale(2 * ndl).subtract(light).dot(view), specular = 0;
        if (rv > 0) {
            long power = FixedPoint.S;
            for (int n = 0; n < material.exponent; n++)
                power = FixedPoint.multiply(power, rv);
            specular = FixedPoint.multiply(FixedPoint.multiply(material.ks, power), effective);
        }
        return new Phong(diffuse, specular);
    }
    static Vector3 reflected(Vector3 direction, Vector3 normal) {
        return direction.subtract(normal.scale(2 * direction.dot(normal))).normalize();
    }
    static Refraction refracted(Scene.Material material, Vector3 direction, Vector3 normal, boolean front) {
        long wr = material.kr, wt = material.kt;
        if (wt == 0)
            return new Refraction(wr, wt, null, false);
        long eta = front ? FixedPoint.divide(FixedPoint.S * FixedPoint.S, material.ior) : material.ior,
             cn = -direction.dot(normal),
             disc = FixedPoint.S * FixedPoint.S -
                    FixedPoint.divide(FixedPoint.multiply(eta, eta) * (FixedPoint.S * FixedPoint.S - cn * cn),
                                      FixedPoint.S);
        if (disc < 0)
            return new Refraction(wr + wt, 0, null, true);
        Vector3 transmitted = direction.scale(eta)
                                  .add(normal.scale(FixedPoint.multiply(eta, cn) - FixedPoint.isqrt(disc)))
                                  .normalize();
        long r0 =
                 FixedPoint.divide((material.ior - FixedPoint.S) * FixedPoint.S, material.ior + FixedPoint.S),
             reflectance = FixedPoint.multiply(r0, r0), x = FixedPoint.S - Math.min(cn, FixedPoint.S),
             power = FixedPoint.S;
        for (int n = 0; n < 5; n++)
            power = FixedPoint.multiply(power, x);
        long fresnel = reflectance + FixedPoint.multiply(FixedPoint.S - reflectance, power),
             transfer = FixedPoint.multiply(material.kt, fresnel);
        return new Refraction(wr + transfer, wt - transfer, transmitted, false);
    }
    static Scene.Color mix(Scene.Color[] colors, long[] weights) {
        long[] values = new long[3];
        for (int c = 0; c < 3; c++)
            for (int i = 0; i < colors.length; i++)
                values[c] += FixedPoint.divide(colors[i].component(c) * weights[i], FixedPoint.S);
        return Scene.Color.of(values);
    }
}
