package main

import (
	"os"
	"strings"
)

type Option struct{ Name, Value string }
type Operand struct {
	Kind, Name, Value string
	Records           int
}

func validName(name string) bool {
	if name == "" || !letter(name[0]) && name[0] != '_' {
		return false
	}
	for i := 0; i < len(name); i++ {
		if !letter(name[i]) && !digit(name[i]) && name[i] != '_' {
			return false
		}
	}
	return true
}
func validFilename(name string) bool {
	if name == "" || name[0] == '.' {
		return false
	}
	for i := 0; i < len(name); i++ {
		c := name[i]
		if !letter(c) && !digit(c) && !strings.ContainsRune("._-", rune(c)) {
			return false
		}
	}
	return true
}
func parseArguments(lines []string) ([]Option, []*Operand) {
	options := []Option{}
	operands := []*Operand{}
	for _, line := range lines {
		if strings.HasPrefix(line, "-F ") {
			options = append(options, Option{"FS", line[3:]})
			continue
		}
		if strings.HasPrefix(line, "-v ") {
			a := strings.SplitN(line[3:], "=", 2)
			options = append(options, Option{a[0], a[1]})
			continue
		}
		if k := strings.IndexByte(line, '='); k >= 0 && validName(line[:k]) {
			operands = append(operands, &Operand{Kind: "assignment", Name: line[:k], Value: line[k+1:]})
		} else {
			operands = append(operands, &Operand{Kind: "file", Name: line})
		}
	}
	return options, operands
}
func readText(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	return string(data)
}
func textLines(text string) []string {
	if text == "" {
		return []string{}
	}
	return strings.Split(strings.TrimSuffix(text, "\n"), "\n")
}
func readRecords(name string) []string { return textLines(readText("input/" + name)) }

type OutputStream struct {
	Parts  []string
	Open   bool
	Writes int
}

func (s *OutputStream) content() string { return strings.Join(s.Parts, "") }

type GetlineInput struct {
	Open, EverOpened bool
	Lines            []string
	Position, Reads  int
}
type Streams struct {
	Stdout      OutputStream
	Outputs     map[string]*OutputStream
	OutputOrder []string
	Inputs      map[string]*GetlineInput
	InputOrder  []string
}

func newStreams() *Streams {
	return &Streams{Outputs: map[string]*OutputStream{}, Inputs: map[string]*GetlineInput{}}
}
func (s *Streams) write(text, name, mode string, position Position) {
	if name == "" && mode == "" {
		s.Stdout.Parts = append(s.Stdout.Parts, text)
		s.Stdout.Writes++
		return
	}
	if !validFilename(name) || name == "stdout.txt" || name == "stats.txt" {
		runtimeError(position, "invalid output file name")
	}
	stream := s.Outputs[name]
	if stream == nil {
		stream = &OutputStream{}
		s.Outputs[name] = stream
		s.OutputOrder = append(s.OutputOrder, name)
	}
	if !stream.Open {
		stream.Open = true
		if mode == ">" {
			stream.Parts = nil
		}
	}
	stream.Parts = append(stream.Parts, text)
	stream.Writes++
}
func (s *Streams) getline(name string) (int, string) {
	source := s.Inputs[name]
	if source == nil {
		source = &GetlineInput{}
		s.Inputs[name] = source
		s.InputOrder = append(s.InputOrder, name)
	}
	if !source.Open {
		if !validFilename(name) {
			return -1, ""
		}
		info, err := os.Stat("input/" + name)
		if err != nil || !info.Mode().IsRegular() {
			return -1, ""
		}
		source.Lines = readRecords(name)
		source.Position = 0
		source.Open = true
		source.EverOpened = true
	}
	if source.Position == len(source.Lines) {
		return 0, ""
	}
	line := source.Lines[source.Position]
	source.Position++
	source.Reads++
	return 1, line
}
func (s *Streams) close(name string) int64 {
	closed := false
	if output := s.Outputs[name]; output != nil && output.Open {
		output.Open = false
		closed = true
	}
	if input := s.Inputs[name]; input != nil && input.Open {
		input.Open = false
		closed = true
	}
	if closed {
		return 0
	}
	return -1
}
func writeFile(path, text string) {
	if err := os.WriteFile(path, []byte(text), 0644); err != nil {
		panic(err)
	}
}
func (s *Streams) save() {
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeFile("output/stdout.txt", s.Stdout.content())
	for _, name := range s.OutputOrder {
		writeFile("output/"+name, s.Outputs[name].content())
	}
}
