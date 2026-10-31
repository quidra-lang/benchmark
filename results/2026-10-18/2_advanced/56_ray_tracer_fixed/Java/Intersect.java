final class Intersect {
    record Bounds(Vector3 lo, Vector3 hi) {}
    record Slab(long near, int nearAxis, long far, int farAxis) {}
    record Candidate(long distance, boolean entering, int axis) {}
    static Bounds bounds(Scene.Obj object, long pad) {
        Vector3 margin = new Vector3(pad, pad, pad);
        if (object.kind.equals("sphere")) {
            long radius = object.radius + pad;
            Vector3 extent = new Vector3(radius, radius, radius);
            return new Bounds(object.center.subtract(extent), object.center.add(extent));
        }
        return new Bounds(object.lo.subtract(margin), object.hi.add(margin));
    }
    static Slab slab(Bounds box, Vector3 origin, Vector3 direction) {
        long near = Long.MIN_VALUE, far = Long.MAX_VALUE;
        int nearAxis = -1, farAxis = -1;
        for (int a = 0; a < 3; a++) {
            long d = direction.coordinate(a), o = origin.coordinate(a), lo = box.lo().coordinate(a),
                 hi = box.hi().coordinate(a);
            if (d == 0) {
                if (o < lo || o > hi)
                    return null;
                continue;
            }
            long t1 = FixedPoint.divide((lo - o) * FixedPoint.S, d),
                 t2 = FixedPoint.divide((hi - o) * FixedPoint.S, d), entry = Math.min(t1, t2),
                 exit = Math.max(t1, t2);
            if (entry > near) {
                near = entry;
                nearAxis = a;
            }
            if (exit < far) {
                far = exit;
                farAxis = a;
            }
        }
        return near > far ? null : new Slab(near, nearAxis, far, farAxis);
    }
    static Candidate test(Scene.Obj object, Vector3 origin, Vector3 direction, long epsilon) {
        if (object.kind.equals("sphere")) {
            Vector3 oc = origin.subtract(object.center);
            long b = oc.dot(direction), tc = FixedPoint.divide(-b * FixedPoint.S, direction.dot(direction));
            Vector3 h = oc.add(direction.scale(tc));
            long q = FixedPoint.divide(object.radius * object.radius, FixedPoint.S) - h.dot(h);
            if (q < 0)
                return null;
            long w = FixedPoint.divide(FixedPoint.isqrt(q * FixedPoint.S) * FixedPoint.S, direction.length()),
                 t1 = tc - w, t2 = tc + w;
            if (t1 > epsilon)
                return new Candidate(t1, true, -1);
            if (t2 > epsilon)
                return new Candidate(t2, false, -1);
            return null;
        }
        if (object.kind.equals("plane")) {
            long den = direction.dot(object.normal);
            if (den == 0)
                return null;
            long t = FixedPoint.divide(object.point.subtract(origin).dot(object.normal) * FixedPoint.S, den);
            return t > epsilon ? new Candidate(t, true, -1) : null;
        }
        Slab slab = slab(new Bounds(object.lo, object.hi), origin, direction);
        if (slab == null)
            return null;
        if (slab.near() > epsilon)
            return new Candidate(slab.near(), true, slab.nearAxis());
        if (slab.far() > epsilon)
            return new Candidate(slab.far(), false, slab.farAxis());
        return null;
    }
    static Vector3 outward(Scene.Obj object, Candidate hit, Vector3 point, Vector3 direction) {
        if (object.kind.equals("sphere"))
            return point.subtract(object.center).normalize();
        if (object.kind.equals("plane"))
            return object.normal;
        long sign = direction.coordinate(hit.axis()) > 0 ? 1 : -1;
        if (hit.entering())
            sign = -sign;
        return Vector3.axis(hit.axis(), sign * FixedPoint.S);
    }
}
