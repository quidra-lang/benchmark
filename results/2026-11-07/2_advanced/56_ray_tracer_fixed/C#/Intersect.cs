using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Intersect {
    public record Bounds(Vector3 lo, Vector3 hi) {
    }
    public record Slab(long near, int nearAxis, long far, int farAxis) {
    }
    public record Candidate(long distance, bool entering, int axis) {
    }
    public static Bounds ObjectBounds(Scene.Obj sceneObject, long pad) {
        Vector3 margin = new Vector3(pad, pad, pad);
        if (sceneObject.kind.Equals("sphere")) {
            long radius = sceneObject.radius + pad;
            Vector3 extent = new Vector3(radius, radius, radius);
            return new Bounds(sceneObject.center.Subtract(extent), sceneObject.center.Add(extent));
        }
        return new Bounds(sceneObject.lo.Subtract(margin), sceneObject.hi.Add(margin));
    }
    public static Slab SlabTest(Bounds box, Vector3 origin, Vector3 direction) {
        long near = long.MinValue, far = long.MaxValue;
        int nearAxis = -1, farAxis = -1;
        for (int a = 0; a < 3; a++) {
            long d = direction.Coordinate(a), o = origin.Coordinate(a), lo = box.lo.Coordinate(a),
                 hi = box.hi.Coordinate(a);
            if (d == 0) {
                if (o < lo || o > hi)
                    return null;
                continue;
            }
            long t1 = FixedPoint.Divide((lo - o) * FixedPoint.S, d),
                 t2 = FixedPoint.Divide((hi - o) * FixedPoint.S, d), entry = Math.Min(t1, t2),
                 exit = Math.Max(t1, t2);
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
    public static Candidate Test(Scene.Obj sceneObject, Vector3 origin, Vector3 direction, long epsilon) {
        if (sceneObject.kind.Equals("sphere")) {
            Vector3 oc = origin.Subtract(sceneObject.center);
            long b = oc.Dot(direction), tc = FixedPoint.Divide(-b * FixedPoint.S, direction.Dot(direction));
            Vector3 h = oc.Add(direction.Scale(tc));
            long q = FixedPoint.Divide(sceneObject.radius * sceneObject.radius, FixedPoint.S) - h.Dot(h);
            if (q < 0)
                return null;
            long w = FixedPoint.Divide(FixedPoint.Isqrt(q * FixedPoint.S) * FixedPoint.S, direction.Length()),
                 t1 = tc - w, t2 = tc + w;
            if (t1 > epsilon)
                return new Candidate(t1, true, -1);
            if (t2 > epsilon)
                return new Candidate(t2, false, -1);
            return null;
        }
        if (sceneObject.kind.Equals("plane")) {
            long den = direction.Dot(sceneObject.normal);
            if (den == 0)
                return null;
            long t = FixedPoint.Divide(
                sceneObject.point.Subtract(origin).Dot(sceneObject.normal) * FixedPoint.S, den);
            return t > epsilon ? new Candidate(t, true, -1) : null;
        }
        Slab slab = SlabTest(new Bounds(sceneObject.lo, sceneObject.hi), origin, direction);
        if (slab == null)
            return null;
        if (slab.near > epsilon)
            return new Candidate(slab.near, true, slab.nearAxis);
        if (slab.far > epsilon)
            return new Candidate(slab.far, false, slab.farAxis);
        return null;
    }
    public static Vector3 Outward(Scene.Obj sceneObject, Candidate hit, Vector3 point, Vector3 direction) {
        if (sceneObject.kind.Equals("sphere"))
            return point.Subtract(sceneObject.center).Normalize();
        if (sceneObject.kind.Equals("plane"))
            return sceneObject.normal;
        long sign = direction.Coordinate(hit.axis) > 0 ? 1 : -1;
        if (hit.entering)
            sign = -sign;
        return Vector3.Axis(hit.axis, sign * FixedPoint.S);
    }
}
