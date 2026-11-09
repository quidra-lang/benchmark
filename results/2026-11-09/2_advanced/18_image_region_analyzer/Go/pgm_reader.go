package main

import (
	"os"
	"strconv"
	"strings"
)

type Image struct {
	Name                  string
	Width, Height, Maxval int
	Pixels                [][]int64
}

func readText(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	return string(data)
}

func parseInt(text string) int {
	value, err := strconv.Atoi(text)
	if err != nil {
		panic(err)
	}
	return value
}

func readImages(path string) []Image {
	var words []string
	for line := range strings.SplitSeq(readText(path), "\n") {
		content, _, _ := strings.Cut(line, "#")
		words = append(words, strings.Fields(content)...)
	}
	var images []Image
	for position := 0; position < len(words); {
		name := words[position+1]
		width, height, maxval := parseInt(words[position+3]), parseInt(words[position+4]), parseInt(words[position+5])
		position += 6
		pixels := make([][]int64, height)
		for y := range pixels {
			pixels[y] = make([]int64, width)
			for x := range pixels[y] {
				pixels[y][x] = int64(parseInt(words[position]))
				position++
			}
		}
		images = append(images, Image{name, width, height, maxval, pixels})
	}
	return images
}
