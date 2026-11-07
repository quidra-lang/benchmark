package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Image struct {
	W, H   int
	Pixels []int
}
type Params struct {
	Min, Max                                                        int
	Windows                                                         map[string][]int
	TextureWindow                                                   int
	TextureThreshold, Uniqueness                                    int64
	LR                                                              int
	WTACost, SGMCost                                                string
	SGMWindow, Paths                                                int
	P1, P2, Gamma                                                   int64
	SpeckleSize, SpeckleRange, FusionVotes, ObjectRange, ObjectSize int
	Focal, Baseline                                                 int64
	Samples                                                         [][2]int
}

func lines(path string) []string {
	b, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	return strings.Split(strings.TrimSuffix(string(b), "\n"), "\n")
}
func integer(s string) int {
	v, e := strconv.Atoi(s)
	if e != nil {
		panic(e)
	}
	return v
}
func readPGM(path string) Image {
	a := lines(path)
	header := strings.Fields(a[1])
	img := Image{W: integer(header[0]), H: integer(header[1])}
	for _, line := range a[3:] {
		for _, s := range strings.Fields(line) {
			img.Pixels = append(img.Pixels, integer(s))
		}
	}
	return img
}
func readParams() Params {
	p := Params{Windows: map[string][]int{}}
	for _, line := range lines("input/params.txt") {
		a := strings.Fields(line)
		switch a[0] {
		case "disparity_min":
			p.Min = integer(a[1])
		case "disparity_max":
			p.Max = integer(a[1])
		case "sad_windows", "ssd_windows", "census_windows":
			kind := strings.TrimSuffix(a[0], "_windows")
			for _, s := range a[1:] {
				p.Windows[kind] = append(p.Windows[kind], integer(s))
			}
		case "texture_window":
			p.TextureWindow = integer(a[1])
		case "texture_threshold":
			p.TextureThreshold = int64(integer(a[1]))
		case "uniqueness":
			p.Uniqueness = int64(integer(a[1]))
		case "lr_max_diff":
			p.LR = integer(a[1])
		case "wta_cost":
			p.WTACost = a[1]
		case "sgm_cost":
			p.SGMCost = a[1]
		case "sgm_window":
			p.SGMWindow = integer(a[1])
		case "sgm_paths":
			p.Paths = integer(a[1])
		case "p1":
			p.P1 = int64(integer(a[1]))
		case "p2":
			p.P2 = int64(integer(a[1]))
		case "p2_gamma":
			p.Gamma = int64(integer(a[1]))
		case "speckle_size":
			p.SpeckleSize = integer(a[1])
		case "speckle_range":
			p.SpeckleRange = integer(a[1])
		case "fusion_min_votes":
			p.FusionVotes = integer(a[1])
		case "object_range":
			p.ObjectRange = integer(a[1])
		case "object_min_size":
			p.ObjectSize = integer(a[1])
		case "focal_length":
			p.Focal = int64(integer(a[1]))
		case "baseline":
			p.Baseline = int64(integer(a[1]))
		case "sample":
			p.Samples = append(p.Samples, [2]int{integer(a[1]), integer(a[2])})
		}
	}
	return p
}
func writeLines(name string, a []string) {
	if e := os.MkdirAll("output", 0755); e != nil {
		panic(e)
	}
	if e := os.WriteFile("output/"+name, []byte(strings.Join(a, "\n")+"\n"), 0644); e != nil {
		panic(e)
	}
}
func writePGM(name string, w, h int, pixels []int) {
	out := []string{"P2", fmt.Sprint(w, " ", h), "255"}
	for y := 0; y < h; y++ {
		row := []string{}
		for x := 0; x < w; x++ {
			row = append(row, fmt.Sprint(pixels[y*w+x]))
		}
		out = append(out, strings.Join(row, " "))
	}
	writeLines(name, out)
}
