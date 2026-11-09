package main

type Plane struct {
	W, H int
	A    []int
}

func newPlane(w, h int) Plane { return Plane{w, h, make([]int, w*h)} }
func floor(a, b int) int {
	q := a / b
	if a < 0 && a%b != 0 {
		q--
	}
	return q
}
func clamp(a int) int { return min(max(a, 0), 255) }
func abs(a int) int {
	if a < 0 {
		return -a
	}
	return a
}
func colors(im Image) [3]Plane {
	var p [3]Plane
	for k := range p {
		p[k] = newPlane(im.W, im.H)
	}
	for i := 0; i < im.W*im.H; i++ {
		r,
			g, b := im.RGB[3*i], im.RGB[3*i+1], im.RGB[3*i+2]
		p[0].A[i] = floor(19595*r+38470*g+7471*b+32768, 65536)
		p[1].A[i] = floor(-11059*r-21709*g+32768*b+8421375,
			65536)
		p[2].A[i] = floor(32768*r-27439*g-5329*b+8421375, 65536)
	}
	return p
}
func rgb(y, cb, cr int) [3]int {
	return [3]int{clamp(y + floor(91881*(cr-128)+32768, 65536)), clamp(y + floor(-22554*(cb-128)-46802*(cr-128)+32768,
		65536)), clamp(y + floor(116130*(cb-128)+32768, 65536))}
}
func componentPlanes(im Image, g Geometry) [3]Plane {
	a := colors(im)
	var p [3]Plane
	for k := 0; k < 3; k++ {
		p[k] = newPlane(8*g.Components[k].H*g.MX,
			8*g.Components[k].V*g.MY)
		fx, fy := g.Hmax/g.Components[k].H, g.Vmax/g.Components[k].V
		for y := 0; y < p[k].H; y++ {
			for x := 0; x < p[k].W; x++ {
				s := 0
				for j := 0; j < fy; j++ {
					for i := 0; i < fx; i++ {
						s += a[k].A[min(fy*y+j,
							im.H-1)*im.W+min(fx*x+i, im.W-1)]
					}
				}
				p[k].A[y*p[k].W+x] = s / (fx * fy)
			}
		}
	}
	return p
}
func upsample(p [3]Plane, g Geometry) ([3]Plane, Image) {
	var a [3]Plane
	im := Image{g.W, g.H, make([]int,
		3*g.W*g.H)}
	for k := 0; k < 3; k++ {
		a[k] = newPlane(g.W, g.H)
		c := g.Components[k]
		for y := 0; y < g.H; y++ {
			for x := 0; x < g.W; x++ {
				a[k].A[y*g.W+x] = p[k].A[(y*c.V/g.Vmax)*p[k].W+x*c.H/g.Hmax]
			}
		}
	}
	for i := 0; i < g.W*g.H; i++ {
		v := rgb(a[0].A[i],
			a[1].A[i], a[2].A[i])
		copy(im.RGB[3*i:], v[:])
	}
	return a, im
}
