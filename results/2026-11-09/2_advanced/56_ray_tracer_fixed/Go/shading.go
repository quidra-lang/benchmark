package main

func baseColor(m *Material, p Vec) Vec {
	if m.Checker {
		q := floorDiv(p[0], m.Size) + floorDiv(p[1], m.Size) + floorDiv(p[2], m.Size)
		if q%2 != 0 {
			return m.Second
		}
	}
	return m.Color
}
func components(m *Material, n, l, v Vec, intensity int64) (int64, int64) {
	ndl := dot(n, l)
	dif := mul(mul(m.KD, ndl), intensity)
	rv := dot(sub(scale(n, 2*ndl), l), v)
	spe := int64(0)
	if rv > 0 {
		p := S
		for j := 0; j < m.Exponent; j++ {
			p = mul(p, rv)
		}
		spe = mul(mul(m.KS, p), intensity)
	}
	return dif, spe
}
func reflected(d, n Vec) Vec { return norm(sub(d, scale(n, 2*dot(d, n)))) }
func refracted(m *Material, d, n Vec, front bool) (int64, int64, Vec, bool) {
	wr, wt := m.KR, m.KT
	tdir := Vec{}
	if m.KT == 0 {
		return wr, wt, tdir, false
	}
	eta := m.IOR
	if front {
		eta = floorDiv(S*S, m.IOR)
	}
	cn := -dot(d, n)
	disc := S*S - floorDiv(mul(eta, eta)*(S*S-cn*cn), S)
	if disc < 0 {
		return m.KR + m.KT, 0, tdir, true
	}
	tdir = norm(add(scale(d, eta), scale(n, mul(eta, cn)-isqrt(disc))))
	r0 := floorDiv((m.IOR-S)*S, m.IOR+S)
	rzero := mul(r0, r0)
	x := S - min(cn, S)
	p := S
	for j := 0; j < 5; j++ {
		p = mul(p, x)
	}
	fr := mul(m.KT, rzero+mul(S-rzero, p))
	return m.KR + fr, m.KT - fr, tdir, false
}
func mix(colors []Vec, weights []int64) Vec {
	v := Vec{}
	for j, c := range colors {
		for a := 0; a < 3; a++ {
			v[a] += floorDiv(c[a]*weights[j], S)
		}
	}
	return v
}
