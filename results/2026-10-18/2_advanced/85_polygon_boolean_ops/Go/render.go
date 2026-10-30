package main

type Rendered struct {
	Rows               []string
	Result, A, B, Both int
}

func render(result *Result, x0, y0, cw, ch, cols, rows int64) Rendered {
	out := Rendered{}
	rings := flatten(result.Polygons)
	for j := int64(0); j < rows; j++ {
		row := make([]byte, cols)
		for i := int64(0); i < cols; i++ {
			p := Point{rational(x0).Add(ratio((2*i+1)*cw, 2)), rational(y0).Add(ratio((2*(rows-1-j)+1)*ch, 2))}
			character := byte('.')
			if interior(p, rings) {
				character = '#'
				out.Result++
			} else if result.A != nil && result.B != nil {
				a, b := interior(p, result.A.Rings), interior(p, result.B.Rings)
				if a && b {
					character = '+'
					out.Both++
				} else if a {
					character = 'a'
					out.A++
				} else if b {
					character = 'b'
					out.B++
				}
			}
			row[i] = character
		}
		out.Rows = append(out.Rows, string(row))
	}
	return out
}
