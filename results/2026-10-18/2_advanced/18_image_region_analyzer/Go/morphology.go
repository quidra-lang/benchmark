package main

type Point struct{ X, Y int }
type Mask [][]bool

var neighborhood = []Point{{0, -1}, {1, -1}, {1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}, {-1, -1}}

func newMask(width, height int) Mask {
	mask := make(Mask, height)
	for y := range mask {
		mask[y] = make([]bool, width)
	}
	return mask
}

func occupied(mask Mask, x, y int) bool {
	return y >= 0 && y < len(mask) && x >= 0 && x < len(mask[0]) && mask[y][x]
}

func erode(mask Mask, offsets []Point) Mask {
	result := newMask(len(mask[0]), len(mask))
	for y, row := range mask {
		for x := range row {
			result[y][x] = true
			for _, offset := range offsets {
				if !occupied(mask, x+offset.X, y+offset.Y) {
					result[y][x] = false
					break
				}
			}
		}
	}
	return result
}

func dilate(mask Mask, offsets []Point) Mask {
	result := newMask(len(mask[0]), len(mask))
	for y, row := range mask {
		for x := range row {
			for _, offset := range offsets {
				if occupied(mask, x-offset.X, y-offset.Y) {
					result[y][x] = true
					break
				}
			}
		}
	}
	return result
}

func opening(mask Mask, offsets []Point) Mask { return dilate(erode(mask, offsets), offsets) }
func closing(mask Mask, offsets []Point) Mask { return erode(dilate(mask, offsets), offsets) }

func neighborBits(pixels map[Point]bool, point Point) [8]bool {
	var bits [8]bool
	for i, offset := range neighborhood {
		bits[i] = pixels[Point{point.X + offset.X, point.Y + offset.Y}]
	}
	return bits
}

func transitions(bits [8]bool) int {
	count := 0
	for i := range bits {
		if !bits[i] && bits[(i+1)%8] {
			count++
		}
	}
	return count
}

func crossingNumber(pixels map[Point]bool, point Point) int {
	return transitions(neighborBits(pixels, point))
}

func removable(bits [8]bool, first bool) bool {
	count := 0
	for _, bit := range bits {
		if bit {
			count++
		}
	}
	if count < 2 || count > 6 || transitions(bits) != 1 {
		return false
	}
	p2, p4, p6, p8 := bits[0], bits[2], bits[4], bits[6]
	if first {
		return !(p2 && p4 && p6) && !(p4 && p6 && p8)
	}
	return !(p2 && p4 && p8) && !(p2 && p6 && p8)
}

func thinningStep(pixels map[Point]bool, first bool) bool {
	var removed []Point
	for point := range pixels {
		if removable(neighborBits(pixels, point), first) {
			removed = append(removed, point)
		}
	}
	for _, point := range removed {
		delete(pixels, point)
	}
	return len(removed) > 0
}

func thin(pixels []Point) map[Point]bool {
	skeleton := make(map[Point]bool, len(pixels))
	for _, point := range pixels {
		skeleton[point] = true
	}
	for {
		first, second := thinningStep(skeleton, true), thinningStep(skeleton, false)
		if !first && !second {
			return skeleton
		}
	}
}
