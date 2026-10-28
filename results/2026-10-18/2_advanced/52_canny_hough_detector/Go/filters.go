package main

func newImage(width, height int) Image {
	out := make(Image, height)
	for y := range out {
		out[y] = make([]int, width)
	}
	return out
}
func clamp(v, low, high int) int { return min(max(v, low), high) }
func reference(image Image, x, y int) int {
	return image[clamp(y, 0, len(image)-1)][clamp(x, 0, len(image[0])-1)]
}
func abs(v int) int {
	if v < 0 {
		return -v
	}
	return v
}
func floorDiv(a, b int) int {
	q := a / b
	if a%b < 0 {
		q--
	}
	return q
}
func smooth(image Image, p Params) Image {
	width, height := len(image[0]), len(image)
	out := newImage(width, height)
	size := p.integer("gauss_size")
	half := size / 2
	kernel := p["gauss_kernel"]
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			total := 0
			for j := 0; j < size; j++ {
				for i := 0; i < size; i++ {
					total += int(kernel[j*size+i]) * reference(image, x+i-half, y+j-half)
				}
			}
			out[y][x] = floorDiv(total, p.integer("gauss_divisor"))
		}
	}
	return out
}
func gradient(image Image) (Image, Image, Image) {
	width, height := len(image[0]), len(image)
	gx, gy, magnitude := newImage(width, height), newImage(width, height), newImage(width, height)
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			q1, q2, q3 := reference(image, x-1, y-1), reference(image, x, y-1), reference(image, x+1, y-1)
			q4, q6 := reference(image, x-1, y), reference(image, x+1, y)
			q7, q8, q9 := reference(image, x-1, y+1), reference(image, x, y+1), reference(image, x+1, y+1)
			gx[y][x] = (q3 + 2*q6 + q9) - (q1 + 2*q4 + q7)
			gy[y][x] = (q7 + 2*q8 + q9) - (q1 + 2*q2 + q3)
			magnitude[y][x] = abs(gx[y][x]) + abs(gy[y][x])
		}
	}
	return gx, gy, magnitude
}
