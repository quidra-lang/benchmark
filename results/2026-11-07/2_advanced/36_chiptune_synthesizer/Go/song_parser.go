package main

import (
	"os"
	"strconv"
	"strings"
)

var pitchNames = []string{"C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"}

func integer(text string) int {
	n, err := strconv.Atoi(text)
	if err != nil {
		panic(err)
	}
	return n
}
func hexNumber(text string) int {
	n, err := strconv.ParseInt(text, 16, 64)
	if err != nil {
		panic(err)
	}
	return int(n)
}
func readLines(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func noteNumber(name string) int {
	for i, p := range pitchNames {
		if name[:2] == p {
			return 12*integer(name[2:]) + i
		}
	}
	panic(name)
}
func noteName(number int) string { return pitchNames[number%12] + strconv.Itoa(number/12) }

type Effect struct {
	Text, Name string
	Value      int64
}

func parseEffect(text string) *Effect {
	if text == "..." {
		return nil
	}
	if text[0] == 'E' {
		return &Effect{text, text[:2], int64(hexNumber(text[2:]))}
	}
	return &Effect{text, text[:1], int64(hexNumber(text[1:]))}
}
func (e *Effect) High() int64 { return e.Value / 16 }
func (e *Effect) Low() int64  { return e.Value % 16 }

type Cell struct {
	Note, Instrument, Volume int
	KeyOff                   bool
	Effect                   *Effect
}

func parseCell(text string) *Cell {
	c := &Cell{Note: -1, Instrument: -1, Volume: -1, KeyOff: text[:3] == "OFF", Effect: parseEffect(text[9:12])}
	if text[:3] != "..." && !c.KeyOff {
		c.Note = noteNumber(text[:3])
	}
	if text[4:6] != ".." {
		c.Instrument = hexNumber(text[4:6])
	}
	if text[7:8] != "." {
		c.Volume = hexNumber(text[7:8])
	}
	return c
}
func (c *Cell) HasNote() bool { return c.KeyOff || c.Note >= 0 }
func (c *Cell) Empty() bool {
	return !c.HasNote() && c.Instrument < 0 && c.Volume < 0 && c.Effect == nil
}

type Instrument struct {
	Number                                       int
	Name, Wave                                   string
	Mode, Attack, Decay, Sustain, Release, Sweep int64
	Table, Arpeggio                              []int64
	Vibrato                                      *[3]int64
}
type Pattern struct {
	Number int
	Rows   [64][4]*Cell
}
type Song struct {
	Title                    string
	Rate, Speed, Tempo, Gain int64
	Instruments              map[int]*Instrument
	Patterns                 map[int]*Pattern
	Order                    []int
}

func (s *Song) Cells(position, row int) [4]*Cell { return s.Patterns[s.Order[position]].Rows[row] }
func readSong() *Song {
	lines := []string{}
	for _, line := range readLines("input/song.txt") {
		if line != "" && !strings.HasPrefix(line, "#") {
			lines = append(lines, line)
		}
	}
	s := &Song{Title: lines[0][6:], Rate: int64(integer(lines[1][5:])), Speed: int64(integer(lines[2][6:])),
		Tempo: int64(integer(lines[3][6:])), Gain: int64(integer(lines[4][5:])), Instruments: map[int]*Instrument{},
		Patterns: map[int]*Pattern{}}
	for index := 5; index < len(lines); {
		words := strings.Fields(lines[index])
		if words[0] == "ORDER" {
			for _, v := range words[1:] {
				s.Order = append(s.Order, hexNumber(v))
			}
			index++
			continue
		}
		end := index + 1
		for lines[end] != "END" {
			end++
		}
		block := lines[index+1 : end]
		number := hexNumber(words[1])
		if words[0] == "INSTRUMENT" {
			ins := &Instrument{Number: number, Name: words[2]}
			for _, line := range block {
				v := strings.Fields(line)
				switch v[0] {
				case "WAVE":
					ins.Wave = v[1]
					if ins.Wave == "PULSE" {
						for mode, duty := range []string{"12", "25", "50", "75"} {
							if duty == v[2] {
								ins.Mode = int64(mode)
							}
						}
					} else if ins.Wave == "NOISE" {
						if v[2] == "SHORT" {
							ins.Mode = 1
						}
					} else if ins.Wave == "TABLE" {
						for _, digit := range v[2] {
							ins.Table = append(ins.Table, int64(hexNumber(string(digit))))
						}
					}
				case "ENVELOPE":
					ins.Attack = int64(integer(v[1]))
					ins.Decay = int64(integer(v[2]))
					ins.Sustain = int64(integer(v[3]))
					ins.Release = int64(integer(v[4]))
				case "VIBRATO":
					ins.Vibrato = &[3]int64{int64(integer(v[1])), int64(integer(v[2])), int64(integer(v[3]))}
				case "ARPEGGIO":
					for _, x := range v[1:] {
						ins.Arpeggio = append(ins.Arpeggio, int64(integer(x)))
					}
				case "SWEEP":
					ins.Sweep = int64(integer(v[1]))
				}
			}
			s.Instruments[number] = ins
		} else {
			p := &Pattern{Number: number}
			for r := range 64 {
				for c := range 4 {
					p.Rows[r][c] = parseCell("... .. . ...")
				}
			}
			for _, line := range block {
				r := hexNumber(line[:2])
				for c, text := range strings.Split(line[3:], " | ") {
					p.Rows[r][c] = parseCell(text)
				}
			}
			s.Patterns[number] = p
		}
		index = end + 1
	}
	return s
}

type Params struct {
	MaxSamples, Loops, Fade                                                                                                           int
	Muted                                                                                                                             [4]bool
	WindowStart, WindowLength, WindowWidth, WindowHeight, WindowScope, RollStart, RollRows, PreviewNote, PreviewTicks, PreviewRelease int
	Traces                                                                                                                            map[[2]int]bool
}

func readParams() *Params {
	p := &Params{Traces: map[[2]int]bool{}}
	for _, line := range readLines("input/params.txt") {
		v := strings.Fields(line)
		if len(v) == 0 {
			continue
		}
		switch v[0] {
		case "max_samples":
			p.MaxSamples = integer(v[1])
		case "loops":
			p.Loops = integer(v[1])
		case "fade":
			p.Fade = integer(v[1])
		case "mute":
			for i := range 4 {
				p.Muted[i] = v[i+1] == "1"
			}
		case "window":
			p.WindowStart = integer(v[1])
			p.WindowLength = integer(v[2])
			p.WindowWidth = integer(v[3])
			p.WindowHeight = integer(v[4])
			p.WindowScope = integer(v[5])
		case "roll":
			p.RollStart = integer(v[1])
			p.RollRows = integer(v[2])
		case "preview":
			p.PreviewNote = noteNumber(v[1])
			p.PreviewTicks = integer(v[2])
			p.PreviewRelease = integer(v[3])
		case "trace":
			p.Traces[[2]int{hexNumber(v[1]), hexNumber(v[2])}] = true
		}
	}
	return p
}
