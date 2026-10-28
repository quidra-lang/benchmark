package main

import (
	"fmt"
	"os"
	"sort"
	"strings"
)

var effectOrder = []string{"0", "1", "2", "3", "4", "5", "6", "7", "A", "B", "C", "D", "E1", "E2", "E9", "EA", "EB", "EC", "ED", "EE", "F", "P", "Q", "R", "V"}
var tonicNames = []string{"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
var majorWeights = []int64{64, 22, 35, 23, 44, 41, 25, 52, 24, 37, 23, 29}
var minorWeights = []int64{64, 27, 35, 54, 27, 35, 25, 48, 40, 27, 34, 32}

func hex2(value int) string   { return fmt.Sprintf("%02X", value) }
func hex1(value int64) string { return fmt.Sprintf("%X", value) }
func hexList(values []int) string {
	if len(values) == 0 {
		return "none"
	}
	parts := []string{}
	for _, v := range values {
		parts = append(parts, hex2(v))
	}
	return strings.Join(parts, " ")
}
func noteRange(notes []int) string {
	if len(notes) == 0 {
		return "none"
	}
	lo, hi := notes[0], notes[0]
	for _, v := range notes {
		lo = min(lo, v)
		hi = max(hi, v)
	}
	return noteName(lo) + ".." + noteName(hi)
}
func instrumentNumbers(song *Song) []int {
	numbers := []int{}
	for n := range song.Instruments {
		numbers = append(numbers, n)
	}
	sort.Ints(numbers)
	return numbers
}
func patternNumbers(song *Song) []int {
	numbers := []int{}
	for n := range song.Patterns {
		numbers = append(numbers, n)
	}
	sort.Ints(numbers)
	return numbers
}

type NoteRecord struct {
	Serial, Channel, Position, Row, Note, Start, Length, Release int
	Instrument                                                   *Instrument
	Reason                                                       string
}
type PlayedRow struct {
	Position, Row, Start int
	Speed, Tempo         int64
	Notes                [4]int
}
type Channel struct {
	Number, Note int
	Instrument   *Instrument
	Frequency, Target, Portamento, Slide, Detune, VibratoSpeed, VibratoDepth, VibratoPosition, TremoloSpeed,
	TremoloDepth, TremoloPosition, Volume, Mode, Phase, Register, Age, ReleaseAge, ReleaseLevel,
	Envelope, OutputFrequency, OutputVolume, Amplitude, Increment int64
	Released, Sounding                         bool
	Effect                                     *Effect
	Record                                     *NoteRecord
	NoteOns, Retriggers, Cuts, Active, Audible int
}

func newChannel(number int) *Channel {
	return &Channel{Number: number, Note: -1, Volume: 15, Register: 1}
}
func (c *Channel) EffectName() string {
	if c.Effect == nil {
		return ""
	}
	return c.Effect.Name
}
func (c *Channel) EffectValue() int64 {
	if c.Effect == nil {
		return 0
	}
	return c.Effect.Value
}
func (c *Channel) KeyOff() { c.ReleaseAge = c.Age; c.ReleaseLevel = c.Envelope; c.Released = true }
func (c *Channel) Approach(step int64) {
	if c.Frequency < c.Target {
		c.Frequency = min(c.Frequency+step, c.Target)
	} else {
		c.Frequency = max(c.Frequency-step, c.Target)
	}
}
func (c *Channel) VolumeSlide() { c.Volume = clamp(c.Volume+c.Effect.High()-c.Effect.Low(), 0, 15) }
func (c *Channel) UpdateOutput(tick int, rate int64) {
	ins, name := c.Instrument, c.EffectName()
	var semitones int64
	if name == "0" {
		semitones = []int64{0, c.Effect.High(), c.Effect.Low()}[tick%3]
	}
	if len(ins.Arpeggio) > 0 {
		semitones += ins.Arpeggio[c.Age%int64(len(ins.Arpeggio))]
	}
	frequency := transpose(c.Frequency, semitones) + c.Detune
	if name == "4" || name == "6" {
		frequency += oscillation(c.VibratoPosition, c.VibratoDepth, 4)
	}
	if vib := ins.Vibrato; vib != nil && c.Age >= vib[0] {
		frequency += oscillation((c.Age-vib[0])*vib[1]%64, vib[2], 4)
	}
	c.OutputFrequency = clamp(frequency, 1000, 50*rate)
	c.Envelope = envelopeValue(ins, c.Age, c.Released, c.ReleaseAge, c.ReleaseLevel)
	c.OutputVolume = c.Volume
	if name == "7" {
		c.OutputVolume = clamp(c.Volume+oscillation(c.TremoloPosition, c.TremoloDepth, 255), 0, 15)
	}
	c.Amplitude = c.Envelope * c.OutputVolume
	c.Increment = c.OutputFrequency * 65536 / (100 * rate)
}

type Player struct {
	Song                    *Song
	Params                  *Params
	Channels                []*Channel
	Lanes                   [][]int64
	Samples                 []int64
	Speed, Tempo, Delay     int64
	Position, Row           int
	Cells                   [4]*Cell
	Records                 []*NoteRecord
	Warnings, Log           []string
	Played                  []*PlayedRow
	PlayCounts, FirstStarts map[[2]int]int
	Ticks, Clipped          int
	InstrumentTicks         map[int]int
	EffectCounts            map[string]int
	EndReason               string
	EndRow                  [2]int
	LoopStart               int
}

func newPlayer(song *Song, params *Params) *Player {
	p := &Player{Song: song, Params: params, Speed: song.Speed, Tempo: song.Tempo, PlayCounts: map[[2]int]int{},
		FirstStarts: map[[2]int]int{}, InstrumentTicks: map[int]int{}, EffectCounts: map[string]int{},
		EndReason: "finished", LoopStart: -1, Lanes: make([][]int64, 4)}
	for i := 1; i <= 4; i++ {
		p.Channels = append(p.Channels, newChannel(i))
	}
	return p
}
func (p *Player) Warn(c *Channel, message string) {
	p.Warnings = append(p.Warnings, fmt.Sprintf("warning %02X:%02X ch%d %s", p.Position, p.Row, c.Number, message))
}
func (p *Player) ClampFrequency(frequency int64) int64 { return clamp(frequency, 1000, 50*p.Song.Rate) }
func (p *Player) EndRecord(c *Channel, reason string) {
	r := c.Record
	r.Length = len(p.Samples) - r.Start
	r.Reason = reason
	c.Record = nil
}
func (p *Player) NoteOn(c *Channel, note int) {
	if c.Record != nil {
		p.EndRecord(c, "next")
	}
	c.Frequency = noteFrequency(note)
	c.Target = c.Frequency
	c.Phase = 0
	c.Age = 0
	c.VibratoPosition = 0
	c.TremoloPosition = 0
	c.Released = false
	c.Note = note
	c.NoteOns++
	c.Record = &NoteRecord{Serial: len(p.Records) + 1, Channel: c.Number, Position: p.Position, Row: p.Row,
		Instrument: c.Instrument, Note: note, Start: len(p.Samples), Release: -1}
	p.Records = append(p.Records, c.Record)
}
func (p *Player) ApplyCell(c *Channel, cell *Cell, portamento bool) {
	if cell.Instrument >= 0 {
		ins := p.Song.Instruments[cell.Instrument]
		if ins == nil {
			p.Warn(c, "undefined instrument "+hex2(cell.Instrument))
		} else {
			c.Instrument = ins
			c.Volume = 15
			c.Mode = ins.Mode
		}
	}
	if cell.Volume >= 0 {
		c.Volume = int64(cell.Volume)
	}
	if cell.KeyOff {
		if c.Note >= 0 && !c.Released {
			c.KeyOff()
			c.Record.Release = len(p.Samples) - c.Record.Start
		} else {
			p.Warn(c, "key off without note")
		}
	} else if cell.Note >= 0 {
		if c.Instrument == nil {
			p.Warn(c, "note without instrument")
		} else if portamento && c.Note >= 0 {
			c.Target = noteFrequency(cell.Note)
			c.Note = cell.Note
		} else {
			if portamento {
				p.Warn(c, "portamento without note")
			}
			p.NoteOn(c, cell.Note)
		}
	}
}
func (p *Player) NoteSlide(c *Channel, e *Effect) {
	if c.Note < 0 {
		p.Warn(c, "slide without note")
		return
	}
	if e.Name == "Q" {
		c.Note = min(c.Note+int(e.Low()), 95)
	} else {
		c.Note = max(c.Note-int(e.Low()), 12)
	}
	c.Target = noteFrequency(c.Note)
	c.Slide = 2*e.High() + 1
}
func (p *Player) StartEffect(c *Channel) {
	e := c.Effect
	v := e.Value
	switch e.Name {
	case "3":
		if v > 0 {
			c.Portamento = v
		}
	case "4":
		if e.High() > 0 {
			c.VibratoSpeed = e.High()
		}
		if e.Low() > 0 {
			c.VibratoDepth = e.Low()
		}
	case "7":
		if e.High() > 0 {
			c.TremoloSpeed = e.High()
		}
		if e.Low() > 0 {
			c.TremoloDepth = e.Low()
		}
	case "C":
		c.Volume = min(v, 15)
	case "E1":
		c.Frequency = p.ClampFrequency(c.Frequency + 10*v)
	case "E2":
		c.Frequency = p.ClampFrequency(c.Frequency - 10*v)
	case "EA":
		c.Volume = min(c.Volume+v, 15)
	case "EB":
		c.Volume = max(c.Volume-v, 0)
	case "EE":
		p.Delay = v
	case "F":
		if v >= 1 && v <= 31 {
			p.Speed = v
		} else if v >= 32 {
			p.Tempo = v
		}
	case "P":
		c.Detune = v - 128
	case "Q", "R":
		p.NoteSlide(c, e)
	case "V":
		ins := c.Instrument
		if ins != nil && (ins.Wave == "PULSE" && v <= 3 || ins.Wave == "NOISE" && v <= 1) {
			c.Mode = v
		} else {
			p.Warn(c, "invalid mode "+hex2(int(v)))
		}
	}
}
func (p *Player) TickEffect(c *Channel) {
	e := c.Effect
	switch e.Name {
	case "1":
		c.Frequency = p.ClampFrequency(c.Frequency + 10*e.Value)
	case "2":
		c.Frequency = p.ClampFrequency(c.Frequency - 10*e.Value)
	case "3":
		c.Approach(10 * c.Portamento)
	case "5":
		c.Approach(10 * c.Portamento)
		c.VolumeSlide()
	case "6", "A":
		c.VolumeSlide()
	case "Q", "R":
		if c.Slide != 0 {
			c.Approach(10 * c.Slide)
		}
	}
}
func (p *Player) StartRow() {
	p.Delay = 0
	for i, c := range p.Channels {
		cell := p.Cells[i]
		c.Effect = cell.Effect
		c.Slide = 0
		if c.Effect != nil {
			p.EffectCounts[c.Effect.Name]++
		}
		name := c.EffectName()
		if !(name == "ED" && c.EffectValue() >= 1) {
			p.ApplyCell(c, cell, name == "3" || name == "5")
		}
		if c.Effect != nil {
			p.StartEffect(c)
		}
	}
}
func (p *Player) ProcessTick(tick int) {
	for i, c := range p.Channels {
		name, value := c.EffectName(), c.EffectValue()
		if c.Note >= 0 && c.Age >= 1 && c.Instrument.Sweep != 0 {
			c.Frequency = p.ClampFrequency(c.Frequency + 10*c.Instrument.Sweep)
		}
		if tick >= 1 && c.Effect != nil {
			p.TickEffect(c)
		}
		if name == "ED" && value >= 1 && int64(tick) == value {
			p.ApplyCell(c, p.Cells[i], false)
		}
		if name == "E9" && value >= 1 && tick >= 1 && int64(tick)%value == 0 && c.Note >= 0 {
			c.Phase = 0
			c.Age = 0
			c.Released = false
			c.Retriggers++
		}
		if name == "EC" && int64(tick) == value && c.Note >= 0 {
			p.EndRecord(c, "cut")
			c.Note = -1
			c.Cuts++
		}
		c.Sounding = c.Note >= 0
		if c.Sounding {
			c.UpdateOutput(tick, p.Song.Rate)
			c.Active++
			if c.Amplitude > 0 {
				c.Audible++
			}
			p.InstrumentTicks[c.Instrument.Number]++
		}
	}
}
func (p *Player) Advance() {
	for _, c := range p.Channels {
		name := c.EffectName()
		if c.Note >= 0 {
			c.Age++
		}
		if name == "4" || name == "6" {
			c.VibratoPosition = (c.VibratoPosition + c.VibratoSpeed) % 64
		} else if name == "7" {
			c.TremoloPosition = (c.TremoloPosition + c.TremoloSpeed) % 64
		}
	}
	p.Ticks++
}
func channelText(c *Channel) string {
	effect := "..."
	if c.Effect != nil {
		effect = c.Effect.Text
	}
	if c.Note < 0 {
		return fmt.Sprintf("--- -- %7s - %X %s", "-", c.Volume, effect)
	}
	return fmt.Sprintf("%s %02X %7d %X %X %s", noteName(c.Note), c.Instrument.Number, c.OutputFrequency, c.Envelope, c.OutputVolume, effect)
}
func (p *Player) LogRow(start int) {
	parts := []string{fmt.Sprintf("%02X %02X %02X %7d %2d %3d", p.Position, p.Song.Order[p.Position], p.Row, start, p.Speed, p.Tempo)}
	var notes [4]int
	for i, c := range p.Channels {
		parts = append(parts, channelText(c))
		notes[i] = c.Note
	}
	p.Log = append(p.Log, strings.Join(parts, " | "))
	p.Played = append(p.Played, &PlayedRow{p.Position, p.Row, start, p.Speed, p.Tempo, notes})
}
func (p *Player) LogTick(tick int) {
	parts := []string{fmt.Sprintf("  tick %3d %7d", tick, len(p.Samples))}
	for _, c := range p.Channels {
		if c.Sounding {
			parts = append(parts, fmt.Sprintf("%7d %5d %X%X", c.OutputFrequency, c.Increment, c.Envelope, c.OutputVolume))
		} else {
			parts = append(parts, fmt.Sprintf("%7s %5s --", "-", "-"))
		}
	}
	p.Log = append(p.Log, strings.Join(parts, " | "))
}
func (p *Player) PlayRow(position, row int) bool {
	p.Position, p.Row = position, row
	p.Cells = p.Song.Cells(position, row)
	start := len(p.Samples)
	key := [2]int{position, row}
	if _, ok := p.FirstStarts[key]; !ok {
		p.FirstStarts[key] = start
	}
	p.StartRow()
	ticks := int(p.Speed * (1 + p.Delay))
	for _, c := range p.Channels {
		if c.EffectName() == "EC" && c.EffectValue() >= int64(ticks) {
			p.Warn(c, "cut beyond row")
		} else if c.EffectName() == "ED" && c.EffectValue() >= int64(ticks) {
			p.Warn(c, "delay beyond row")
		}
	}
	spt := samplesPerTick(p.Song.Rate, p.Tempo)
	for tick := range ticks {
		p.ProcessTick(tick)
		if tick == 0 {
			p.LogRow(start)
		}
		if p.Params.Traces[key] {
			p.LogTick(tick)
		}
		count := min(spt, p.Params.MaxSamples-len(p.Samples))
		p.Clipped += mixTick(p.Channels, count, p.Song.Gain, p.Params.Muted[:], &p.Samples, &p.Lanes)
		p.Advance()
		if len(p.Samples) == p.Params.MaxSamples {
			return false
		}
	}
	return true
}
func (p *Player) Play() {
	position, row := 0, 0
	for {
		key := [2]int{position, row}
		p.PlayCounts[key]++
		if !p.PlayRow(position, row) {
			p.EndReason = "limit"
			break
		}
		next, ok := nextRow(p.Song, position, row)
		if !ok {
			p.EndReason = "stop"
			p.EndRow = key
			break
		}
		position, row = next[0], next[1]
		if position >= len(p.Song.Order) {
			p.EndReason = "finished"
			break
		}
		if p.PlayCounts[next] >= p.Params.Loops {
			p.EndReason = "loop"
			p.EndRow = next
			p.LoopStart = p.FirstStarts[next]
			break
		}
	}
	for _, c := range p.Channels {
		if c.Record != nil {
			p.EndRecord(c, "end")
		}
	}
	if (p.EndReason == "limit" || p.EndReason == "loop") && p.Params.Fade > 0 {
		fadeOut(p.Samples, p.Params.Fade)
	}
}
func (p *Player) EndText() string {
	if p.EndReason == "stop" || p.EndReason == "loop" {
		return fmt.Sprintf("%s order=%02X row=%02X", p.EndReason, p.EndRow[0], p.EndRow[1])
	}
	return p.EndReason
}
func noteLines(p *Player) []string {
	lines := []string{}
	for _, r := range p.Records {
		segment := p.Lanes[r.Channel-1][r.Start : r.Start+r.Length]
		cycles := 0
		for i := 1; i < len(segment); i++ {
			if segment[i-1] < 0 && segment[i] >= 0 {
				cycles++
			}
		}
		release := "-"
		if r.Release >= 0 {
			release = fmt.Sprint(r.Release)
		}
		lines = append(lines, fmt.Sprintf("%4d ch=%d at=%02X:%02X ins=%02X note=%s start=%d length=%d release=%s end=%s peak=%d cycles=%d",
			r.Serial, r.Channel, r.Position, r.Row, r.Instrument.Number, noteName(r.Note), r.Start,
			r.Length, release, r.Reason, peak(segment, 0), cycles))
	}
	return lines
}
func rollLines(played []*PlayedRow, start, rows int) []string {
	left := min(start, len(played))
	right := min(start+rows, len(played))
	targets := played[left:right]
	set := map[int]bool{}
	for _, row := range targets {
		for _, note := range row.Notes {
			if note >= 0 {
				set[note] = true
			}
		}
	}
	pitches := []int{}
	for note := range set {
		pitches = append(pitches, note)
	}
	sort.Sort(sort.Reverse(sort.IntSlice(pitches)))
	lines := []string{fmt.Sprintf("ROLL start=%d rows=%d pitches=%d", start, len(targets), len(pitches))}
	for _, note := range pitches {
		marks := []byte{}
		for _, row := range targets {
			owner, count := 0, 0
			for i, n := range row.Notes {
				if n == note {
					owner = i + 1
					count++
				}
			}
			mark := byte(' ')
			if count == 1 {
				mark = byte('0' + owner)
			} else if count > 1 {
				mark = '*'
			}
			marks = append(marks, mark)
		}
		lines = append(lines, noteName(note)+" |"+string(marks)+"|")
	}
	ruler := ""
	for i := range targets {
		if i%16 == 0 {
			ruler += "+"
		} else {
			ruler += "-"
		}
	}
	return append(lines, "    +"+ruler+"+")
}
func statsLines(p *Player) []string {
	song, samples := p.Song, p.Samples
	n := len(samples)
	lo, hi := samples[0], samples[0]
	for _, v := range samples {
		lo = min(lo, v)
		hi = max(hi, v)
	}
	lines := []string{"title=" + song.Title, fmt.Sprintf("rate=%d", song.Rate), fmt.Sprintf("samples=%d",
		n), fmt.Sprintf("duration_ms=%d", int64(n)*1000/song.Rate), "end=" + p.EndText()}
	if p.EndReason == "loop" {
		lines = append(lines, fmt.Sprintf("loop_start=%d", p.LoopStart), fmt.Sprintf("loop_length=%d", n-p.LoopStart))
	} else {
		lines = append(lines, "loop_start=-", "loop_length=-")
	}
	lines = append(lines, fmt.Sprintf("rows=%d", len(p.Played)), fmt.Sprintf("ticks=%d", p.Ticks), fmt.Sprintf("clipped=%d",
		p.Clipped), fmt.Sprintf("peak=%d", peak(samples, 128)), fmt.Sprintf("min=%d", lo), fmt.Sprintf("max=%d",
		hi), fmt.Sprintf("rms=%d", rootMeanSquare(samples, 128)), fmt.Sprintf("zero_crossings=%d",
		zeroCrossings(samples)), "adler32="+adler32Text(samples))
	path := []string{}
	previous := -1
	for _, r := range p.Played {
		if r.Position != previous {
			path = append(path, hex2(r.Position))
			previous = r.Position
		}
	}
	lines = append(lines, "path "+strings.Join(path, " "))
	lastSpeed, lastTempo := int64(-1), int64(-1)
	for _, r := range p.Played {
		if r.Speed != lastSpeed || r.Tempo != lastTempo {
			lines = append(lines, fmt.Sprintf("timing sample=%d order=%02X row=%02X speed=%d tempo=%d", r.Start, r.Position, r.Row, r.Speed, r.Tempo))
		}
		lastSpeed, lastTempo = r.Speed, r.Tempo
	}
	for i, c := range p.Channels {
		lane := p.Lanes[i]
		lines = append(lines, fmt.Sprintf("channel %d notes=%d retriggers=%d cuts=%d active=%d audible=%d peak=%d rms=%d",
			c.Number, c.NoteOns, c.Retriggers, c.Cuts, c.Active, c.Audible, peak(lane, 0), rootMeanSquare(lane,
				0)))
	}
	numbers := instrumentNumbers(song)
	usedInstruments := map[int]bool{}
	noteCounts := map[int]int{}
	for _, r := range p.Records {
		usedInstruments[r.Instrument.Number] = true
		noteCounts[r.Note]++
	}
	for _, number := range numbers {
		ins := song.Instruments[number]
		notes := []int{}
		total, count := 0, 0
		for _, r := range p.Records {
			if r.Instrument == ins {
				notes = append(notes, r.Note)
				total += r.Length
				count++
			}
		}
		average := "-"
		if count > 0 {
			average = fmt.Sprint(total / count)
		}
		lines = append(lines, fmt.Sprintf("instrument %02X %s %s notes=%d ticks=%d range=%s average=%s",
			number, ins.Name, ins.Wave, count, p.InstrumentTicks[number], noteRange(notes), average))
	}
	usedPatterns := map[int]bool{}
	for _, number := range song.Order {
		usedPatterns[number] = true
	}
	for _, number := range patternNumbers(song) {
		pattern := song.Patterns[number]
		rows, notes, orders := 0, 0, 0
		for _, cells := range pattern.Rows {
			nonempty := false
			for _, cell := range cells {
				nonempty = nonempty || !cell.Empty()
				if cell.HasNote() {
					notes++
				}
			}
			if nonempty {
				rows++
			}
		}
		for _, p := range song.Order {
			if p == number {
				orders++
			}
		}
		lines = append(lines, fmt.Sprintf("pattern %02X rows=%d notes=%d orders=%d", number, rows, notes, orders))
	}
	reached := reachableRows(song)
	playedPositions := map[int]bool{}
	for position, pattern := range song.Order {
		count, first, dead := 0, -1, 0
		for _, r := range p.Played {
			if r.Position == position {
				count++
				if first < 0 {
					first = r.Start
				}
				playedPositions[position] = true
			}
		}
		for row := range 64 {
			if !reached[[2]int{position, row}] {
				for _, cell := range song.Cells(position, row) {
					if cell.HasNote() {
						dead++
						break
					}
				}
			}
		}
		text := "-"
		if first >= 0 {
			text = fmt.Sprint(first)
		}
		lines = append(lines, fmt.Sprintf("order %02X pattern=%02X rows=%d first=%s dead=%d", position, pattern, count, text, dead))
	}
	notes := []int{}
	for note := range noteCounts {
		notes = append(notes, note)
	}
	sort.Ints(notes)
	for _, note := range notes {
		lines = append(lines, fmt.Sprintf("note %s count=%d", noteName(note), noteCounts[note]))
	}
	effects := []string{}
	for _, name := range effectOrder {
		if p.EffectCounts[name] > 0 {
			effects = append(effects, fmt.Sprintf("%s=%d", name, p.EffectCounts[name]))
		}
	}
	effectText := "none"
	if len(effects) > 0 {
		effectText = strings.Join(effects, " ")
	}
	lines = append(lines, "effects "+effectText)
	unusedInstruments, unusedPatterns, unreached := []int{}, []int{}, []int{}
	for _, number := range numbers {
		if !usedInstruments[number] {
			unusedInstruments = append(unusedInstruments, number)
		}
	}
	for _, number := range patternNumbers(song) {
		if !usedPatterns[number] {
			unusedPatterns = append(unusedPatterns, number)
		}
	}
	for position := range song.Order {
		if !playedPositions[position] {
			unreached = append(unreached, position)
		}
	}
	lines = append(lines, "unused_instruments="+hexList(unusedInstruments), "unused_patterns="+hexList(unusedPatterns), "unreached_orders="+hexList(unreached))
	totals := [12]int64{}
	for _, r := range p.Records {
		if r.Instrument.Wave != "NOISE" {
			totals[r.Note%12] += int64(r.Length)
		}
	}
	classes := []string{}
	for i, name := range tonicNames {
		classes = append(classes, fmt.Sprintf("%s=%d", name, totals[i]))
	}
	lines = append(lines, "pitch_classes "+strings.Join(classes, " "))
	type Key struct {
		Name  string
		Score int64
	}
	keys := []Key{}
	for mode, weights := range [][]int64{majorWeights, minorWeights} {
		kind := "major"
		if mode == 1 {
			kind = "minor"
		}
		for tonic := range 12 {
			var score int64
			for pitch := range 12 {
				score += weights[(pitch-tonic+12)%12] * totals[pitch]
			}
			keys = append(keys, Key{tonicNames[tonic] + " " + kind, score})
		}
	}
	sort.SliceStable(keys, func(i, j int) bool { return keys[i].Score > keys[j].Score })
	lines = append(lines, fmt.Sprintf("key=%s score=%d runner_up=%s score=%d", keys[0].Name, keys[0].Score, keys[1].Name, keys[1].Score))
	for _, c := range p.Channels {
		notes := []int{}
		counts := map[int]int{}
		for _, r := range p.Records {
			if r.Channel == c.Number {
				notes = append(notes, r.Note)
				counts[r.Instrument.Number]++
			}
		}
		parts := []string{fmt.Sprintf("usage ch%d range=%s", c.Number, noteRange(notes))}
		for _, number := range numbers {
			parts = append(parts, fmt.Sprintf("%02X=%d", number, counts[number]))
		}
		lines = append(lines, strings.Join(parts, " "))
	}
	return append(lines, p.Warnings...)
}
func plotRow(value, low, high int64, height int) int {
	return int((2*(high-value)*int64(height-1) + (high - low)) / (2 * (high - low)))
}
func plotLines(values []int64, low, high, middle int64, height, width int) []string {
	length := len(values)
	middleRow := plotRow(middle, low, high, height)
	columns := [][2]int{}
	for c := range width {
		covered := values[c*length/width : (c+1)*length/width]
		lo, hi := covered[0], covered[0]
		for _, v := range covered {
			lo = min(lo, v)
			hi = max(hi, v)
		}
		columns = append(columns, [2]int{plotRow(hi, low, high, height), plotRow(lo, low, high, height)})
	}
	lines := []string{}
	for row := range height {
		label := ""
		if row == 0 {
			label = fmt.Sprint(high)
		} else if row == middleRow {
			label = fmt.Sprint(middle)
		} else if row == height-1 {
			label = fmt.Sprint(low)
		}
		marks := []byte{}
		for _, column := range columns {
			mark := byte(' ')
			if column[0] <= row && row <= column[1] {
				mark = '#'
			} else if row == middleRow {
				mark = '-'
			}
			marks = append(marks, mark)
		}
		lines = append(lines, fmt.Sprintf("%5s |%s|", label, string(marks)))
	}
	return lines
}
func axisLines(start, length, width int, rate int64) []string {
	ruler := ""
	for c := range width {
		if c%10 == 0 {
			ruler += "+"
		} else {
			ruler += "-"
		}
	}
	labels := "    ms"
	for c := 0; c < width; c += 10 {
		milliseconds := int64(start+c*length/width) * 1000 / rate
		if len(labels) < 7+c {
			labels += strings.Repeat(" ", 7+c-len(labels))
		}
		labels += fmt.Sprint(milliseconds)
	}
	return []string{"      +" + ruler + "+", labels}
}
func waveformLines(p *Player) []string {
	s := p.Params
	start, length, width := s.WindowStart, s.WindowLength, s.WindowWidth
	end := start + length
	axes := axisLines(start, length, width, p.Song.Rate)
	lines := []string{fmt.Sprintf("MIX start=%d length=%d width=%d height=%d", start, length, width, s.WindowHeight)}
	lines = append(lines, plotLines(p.Samples[start:end], 0, 255, 128, s.WindowHeight, width)...)
	lines = append(lines, axes...)
	for i, c := range p.Channels {
		lines = append(lines, fmt.Sprintf("CHANNEL %d", c.Number))
		lines = append(lines, plotLines(p.Lanes[i][start:end], -3375, 3375, 0, s.WindowScope, width)...)
	}
	return append(lines, axes...)
}
func previewLines(song *Song, params *Params, ins *Instrument) []string {
	c := newChannel(1)
	c.Instrument = ins
	c.Mode = ins.Mode
	c.Note = params.PreviewNote
	c.Frequency = noteFrequency(c.Note)
	c.Target = c.Frequency
	c.Sounding = true
	spt := samplesPerTick(song.Rate, song.Tempo)
	samples := []int64{}
	lanes := make([][]int64, 1)
	envelopes, frequencies := []string{}, []string{}
	for tick := range params.PreviewTicks {
		c.Age = int64(tick)
		if tick == params.PreviewRelease {
			c.KeyOff()
		}
		if tick >= 1 && ins.Sweep != 0 {
			c.Frequency = clamp(c.Frequency+10*ins.Sweep, 1000, 50*song.Rate)
		}
		c.UpdateOutput(tick, song.Rate)
		envelopes = append(envelopes, hex1(c.Envelope))
		frequencies = append(frequencies, fmt.Sprint(c.OutputFrequency))
		mixTick([]*Channel{c}, spt, song.Gain, []bool{false}, &samples, &lanes)
	}
	return []string{fmt.Sprintf("instrument %02X %s wave=%s samples=%d peak=%d rms=%d adler32=%s", ins.Number,
		ins.Name, ins.Wave, len(samples), peak(samples, 128), rootMeanSquare(samples, 128), adler32Text(samples)),
		"  env " + strings.Join(envelopes, ""), "  freq " + strings.Join(frequencies, " ")}
}
func writeLines(name string, lines []string) {
	text := ""
	if len(lines) > 0 {
		text = strings.Join(lines, "\n") + "\n"
	}
	if err := os.WriteFile("output/"+name, []byte(text), 0644); err != nil {
		panic(err)
	}
}
func main() {
	song, params := readSong(), readParams()
	player := newPlayer(song, params)
	player.Play()
	previews := []string{}
	for _, number := range instrumentNumbers(song) {
		previews = append(previews, previewLines(song, params, song.Instruments[number])...)
	}
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeLines("samples.txt", hexLines(player.Samples))
	writeLines("channel_log.txt", player.Log)
	writeLines("notes.txt", noteLines(player))
	writeLines("roll.txt", rollLines(player.Played, params.RollStart, params.RollRows))
	writeLines("stats.txt", statsLines(player))
	writeLines("waveform.txt", waveformLines(player))
	writeLines("instruments.txt", previews)
}
