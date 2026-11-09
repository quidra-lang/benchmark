package main

type Bounds struct{ Lo, Hi Vec }
type Ray struct{ Origin, Direction Vec }
type Slab struct {
	Near, Far         int64
	NearAxis, FarAxis int
	Valid             bool
}
type Hit struct {
	Object   *Object
	Distance int64
	Axis     int
	Entering bool
}

func bounding(o *Object, pad int64) Bounds {
	b := Bounds{}
	for a := 0; a < 3; a++ {
		if o.Kind == "sphere" {
			b.Lo[a], b.Hi[a] = o.P[a]-o.Radius-pad, o.P[a]+o.Radius+pad
		} else {
			b.Lo[a], b.Hi[a] = o.Lo[a]-pad, o.Hi[a]+pad
		}
	}
	return b
}
func slab(b Bounds, r Ray) Slab {
	out := Slab{Near: -(1 << 62), Far: 1 << 62, Valid: true}
	for a := 0; a < 3; a++ {
		d, o := r.Direction[a], r.Origin[a]
		if d == 0 {
			if o < b.Lo[a] || o > b.Hi[a] {
				return Slab{}
			}
			continue
		}
		lo, hi := floorDiv((b.Lo[a]-o)*S, d), floorDiv((b.Hi[a]-o)*S, d)
		if lo > hi {
			lo, hi = hi, lo
		}
		if lo > out.Near {
			out.Near, out.NearAxis = lo, a
		}
		if hi < out.Far {
			out.Far, out.FarAxis = hi, a
		}
	}
	if out.Near > out.Far {
		return Slab{}
	}
	return out
}
func intersect(o *Object, r Ray, eps int64) *Hit {
	h := &Hit{Object: o}
	switch o.Kind {
	case "sphere":
		oc := sub(r.Origin, o.P)
		b := dot(oc, r.Direction)
		tc := floorDiv(-b*S, dot(r.Direction, r.Direction))
		v := add(oc, scale(r.Direction, tc))
		q := floorDiv(o.Radius*o.Radius, S) - dot(v, v)
		if q < 0 {
			return nil
		}
		w := floorDiv(isqrt(q*S)*S, length(r.Direction))
		if tc-w > eps {
			h.Distance = tc - w
		} else if tc+w > eps {
			h.Distance = tc + w
		} else {
			return nil
		}
	case "plane":
		den := dot(r.Direction, o.N)
		if den == 0 {
			return nil
		}
		t := floorDiv(dot(sub(o.P, r.Origin), o.N)*S, den)
		if t <= eps {
			return nil
		}
		h.Distance = t
	case "box":
		v := slab(Bounds{o.Lo, o.Hi}, r)
		if !v.Valid {
			return nil
		}
		if v.Near > eps {
			h.Distance, h.Axis, h.Entering = v.Near, v.NearAxis, true
		} else if v.Far > eps {
			h.Distance, h.Axis = v.Far, v.FarAxis
		} else {
			return nil
		}
	}
	return h
}
func outward(h *Hit, p Vec, d Vec) Vec {
	o := h.Object
	if o.Kind == "sphere" {
		return norm(sub(p, o.P))
	}
	if o.Kind == "plane" {
		return o.N
	}
	v := Vec{}
	sign := int64(1)
	if d[h.Axis] < 0 {
		sign = -1
	}
	if h.Entering {
		sign = -sign
	}
	v[h.Axis] = sign * S
	return v
}
