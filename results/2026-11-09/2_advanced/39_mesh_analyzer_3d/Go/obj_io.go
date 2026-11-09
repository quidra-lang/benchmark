package main

import (
	"fmt"
	"regexp"
	"strings"
)

var integerPattern = regexp.MustCompile(`^-?[0-9]+$`)

func integerWord(word string) bool { return integerPattern.MatchString(word) }

type Polygon struct {
	Number, Line int
	Group        string
	Vertices     []int
}
type Source struct {
	Lines, Ignored int
	Vertices       []Vec
	Polygons       []*Polygon
	Errors         []SourceError
}
type SourceError struct {
	Line int
	Kind string
}

func readOBJ() *Source {
	lines := readLines("input/model.obj")
	s := &Source{Lines: len(lines), Vertices: []Vec{{}}}
	group := "default"
	ignored := map[string]bool{"vt": true, "vn": true, "s": true, "o": true, "usemtl": true, "mtllib": true}
	for index, text := range lines {
		if text == "" || strings.HasPrefix(text, "#") {
			continue
		}
		words := strings.Split(text, " ")
		keyword, args := words[0], words[1:]
		switch keyword {
		case "v":
			valid := len(args) == 3
			for _, arg := range args {
				if !integerWord(arg) {
					valid = false
				}
			}
			if !valid {
				s.Errors = append(s.Errors, SourceError{index + 1, "bad_vertex"})
			} else {
				s.Vertices = append(s.Vertices, Vec{integer64(args[0]), integer64(args[1]), integer64(args[2])})
			}
		case "f":
			if len(args) < 3 {
				s.Errors = append(s.Errors, SourceError{index + 1, "short_face"})
				continue
			}
			resolved := []int{}
			reason := ""
			for _, reference := range args {
				part, _, _ := strings.Cut(reference, "/")
				if !integerWord(part) {
					reason = "bad_index"
					break
				}
				number := integer64(part)
				if number == 0 {
					reason = "bad_index"
					break
				}
				if number < 0 {
					number = int64(len(s.Vertices)) + number
				}
				if number < 1 || number >= int64(len(s.Vertices)) {
					reason = "out_of_range"
					break
				}
				resolved = append(resolved, int(number))
			}
			if reason != "" {
				s.Errors = append(s.Errors, SourceError{index + 1, reason})
			} else {
				s.Polygons = append(s.Polygons, &Polygon{len(s.Polygons) + 1, index + 1, group, resolved})
			}
		case "g":
			group = "default"
			if len(args) > 0 {
				group = args[0]
			}
		default:
			if ignored[keyword] {
				s.Ignored++
			} else {
				s.Errors = append(s.Errors, SourceError{index + 1, "unknown_keyword"})
			}
		}
	}
	return s
}
func repairedOBJ(points []Vec, faces []*Face) []string {
	lines := []string{fmt.Sprintf("# vertices %d faces %d", len(points)-1, len(faces))}
	for _, p := range points[1:] {
		lines = append(lines, "v "+vecText(p))
	}
	previous := ""
	for _, f := range faces {
		if f.Group != previous {
			lines = append(lines, "g "+f.Group)
			previous = f.Group
		}
		lines = append(lines, fmt.Sprintf("f %d %d %d", f.Vertices[0], f.Vertices[1], f.Vertices[2]))
	}
	return lines
}
