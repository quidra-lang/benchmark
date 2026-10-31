package main

import "math/bits"

type Volume [][]int64

func absolute(n int) int {
	if n < 0 {
		return -n
	}
	return n
}
func clamp(v, lo, hi int) int { return min(max(v, lo), hi) }
func reference(img Image, x, y int) int {
	return img.Pixels[clamp(y, 0, img.H-1)*img.W+clamp(x, 0, img.W-1)]
}
func boxSum(values []int64, w, h, window int) []int64 {
	radius := window / 2
	pw, ph := w+2*radius, h+2*radius
	stride := pw + 1
	prefix := make([]int64, (pw+1)*(ph+1))
	for y := 0; y < ph; y++ {
		for x := 0; x < pw; x++ {
			v := values[clamp(y-radius, 0, h-1)*w+clamp(x-radius, 0, w-1)]
			prefix[(y+1)*stride+x+1] = v + prefix[y*stride+x+1] + prefix[(y+1)*stride+x] - prefix[y*stride+x]
		}
	}
	out := make([]int64, w*h)
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			out[y*w+x] = prefix[(y+window)*stride+x+window] - prefix[y*stride+x+window] - prefix[(y+window)*stride+x] + prefix[y*stride+x]
		}
	}
	return out
}
func census(img Image) []uint32 {
	out := make([]uint32, len(img.Pixels))
	for y := 0; y < img.H; y++ {
		for x := 0; x < img.W; x++ {
			v := uint32(0)
			for dy := -2; dy <= 2; dy++ {
				for dx := -2; dx <= 2; dx++ {
					if dx == 0 && dy == 0 {
						continue
					}
					v <<= 1
					if reference(img, x+dx, y+dy) < img.Pixels[y*img.W+x] {
						v |= 1
					}
				}
			}
			out[y*img.W+x] = v
		}
	}
	return out
}
func texture(img Image, window int) []int64 {
	g := make([]int64, len(img.Pixels))
	for y := 0; y < img.H; y++ {
		for x := 0; x < img.W; x++ {
			g[y*img.W+x] = int64(absolute(reference(img, x+1, y) - reference(img, x-1, y)))
		}
	}
	return boxSum(g, img.W, img.H, window)
}
func costVolume(left, right Image, cl, cr []uint32, kind string, window int, p Params) Volume {
	out := make(Volume, len(left.Pixels))
	for i := range out {
		out[i] = make([]int64, p.Max-p.Min+1)
	}
	for d := p.Min; d <= p.Max; d++ {
		pixel := make([]int64, len(left.Pixels))
		for y := 0; y < left.H; y++ {
			for x := 0; x < left.W; x++ {
				i, j := y*left.W+x, y*left.W+max(x-d, 0)
				diff := int64(left.Pixels[i] - right.Pixels[j])
				switch kind {
				case "sad":
					if diff < 0 {
						diff = -diff
					}
					pixel[i] = diff
				case "ssd":
					pixel[i] = diff * diff
				case "census":
					pixel[i] = int64(bits.OnesCount32(cl[i] ^ cr[j]))
				}
			}
		}
		sums := boxSum(pixel, left.W, left.H, window)
		for i, v := range sums {
			out[i][d-p.Min] = v
		}
	}
	return out
}
