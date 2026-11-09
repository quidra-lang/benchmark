package main

import (
	"bufio"
	"errors"
	"fmt"
	"math"
	"math/bits"
	"os"
	"slices"
	"strconv"
	"strings"
)

var naturals = [...]int{0, 2, 4, 5, 7, 9, 11}
var fifthsValues = [...]int{0, 2, 4, -1, 1, 3, 5}
var accidentals = [...]string{"bb", "b", "", "#", "x"}
var sharpNames = [...]string{"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
var flatNames = [...]string{"C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"}
var upperRomans = [...]string{"I", "II", "III", "IV", "V", "VI", "VII"}
var lowerRomans = [...]string{"i", "ii", "iii", "iv", "v", "vi", "vii"}

func bad(kind, word string) error { return fmt.Errorf("ERROR BAD %s %s", kind, word) }
func failure(message string) error { return errors.New("ERROR " + message) }
func mod(n, divisor int) int {
	r := n % divisor
	if r < 0 {
		r += divisor
	}
	return r
}
func floorDiv(n, divisor int) int { return (n - mod(n, divisor)) / divisor }
func abs(n int) int {
	if n < 0 {
		return -n
	}
	return n
}
func digits(text string) bool {
	if text == "" {
		return false
	}
	for _, c := range text {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}
func canonical(text string, low, high int) (int, bool) {
	if !digits(text) || len(text) > 1 && text[0] == '0' {
		return 0, false
	}
	n, err := strconv.Atoi(text)
	return n, err == nil && n >= low && n <= high
}
func parseNumber(text string) (int, error) {
	if value, ok := canonical(text, 0, 127); ok {
		return value, nil
	}
	return 0, bad("NUMBER", text)
}
func parseFrequency(text string, tuning bool) (int, error) {
	parts := strings.Split(text, ".")
	if len(parts) > 2 || len(parts[0]) > 5 || !digits(parts[0]) {
		return 0, bad("FREQUENCY", text)
	}
	whole, _ := strconv.Atoi(parts[0])
	cents := whole * 100
	if len(parts) == 2 {
		if len(parts[1]) > 2 || !digits(parts[1]) {
			return 0, bad("FREQUENCY", text)
		}
		fraction, _ := strconv.Atoi(parts[1])
		if len(parts[1]) == 1 {
			fraction *= 10
		}
		cents += fraction
	}
	if cents == 0 || tuning && (cents < 40000 || cents > 48000) {
		return 0, bad("FREQUENCY", text)
	}
	return cents, nil
}
func frequencyText(cents int) string { return fmt.Sprintf("%d.%02d", cents/100, cents%100) }
func join[T any](values []T, separator string) string {
	parts := make([]string, len(values))
	for i, value := range values {
		parts[i] = fmt.Sprint(value)
	}
	return strings.Join(parts, separator)
}

type Pitch struct{ Letter, Alteration int }

func pitchPrefix(text string) (Pitch, int, bool) {
	if text == "" {
		return Pitch{}, 0, false
	}
	letter := strings.IndexByte("CDEFGAB", text[0])
	if letter < 0 {
		return Pitch{}, 0, false
	}
	pitch, end := Pitch{letter, 0}, 1
	if end < len(text) {
		switch text[end] {
		case 'b':
			pitch.Alteration = -1
			end++
			if end < len(text) && text[end] == 'b' {
				pitch.Alteration = -2
				end++
			}
		case '#':
			pitch.Alteration = 1
			end++
		case 'x':
			pitch.Alteration = 2
			end++
		}
	}
	return pitch, end, true
}
func parsePitch(text string) (Pitch, error) {
	pitch, end, ok := pitchPrefix(text)
	if !ok || end != len(text) {
		return Pitch{}, bad("PITCH", text)
	}
	return pitch, nil
}
func (p Pitch) Class() int { return mod(naturals[p.Letter]+p.Alteration, 12) }
func (p Pitch) String() string { return string("CDEFGAB"[p.Letter]) + accidentals[p.Alteration+2] }
func (p Pitch) Raise(tone Tone) (Pitch, error) {
	target := p.Letter + tone.Letters
	alteration := naturals[p.Letter] + p.Alteration + tone.Semitones - naturals[target%7] - 12*(target/7)
	if alteration < -2 || alteration > 2 {
		return Pitch{}, failure("CANNOT SPELL")
	}
	return Pitch{target % 7, alteration}, nil
}
func fifthPitch(fifths int) Pitch {
	return Pitch{[...]int{3, 0, 4, 1, 5, 2, 6}[mod(fifths+1, 7)], floorDiv(fifths+1, 7)}
}

type Note struct {
	Pitch Pitch
	Octave int
}

func parseNote(text string) (Note, error) {
	pitch, end, ok := pitchPrefix(text)
	if !ok {
		return Note{}, bad("NOTE", text)
	}
	rest := text[end:]
	var octave int
	if rest == "-1" {
		octave = -1
	} else if len(rest) == 1 && rest[0] >= '0' && rest[0] <= '9' {
		octave = int(rest[0] - '0')
	} else {
		return Note{}, bad("NOTE", text)
	}
	note := Note{pitch, octave}
	if !note.Valid() {
		return Note{}, bad("NOTE", text)
	}
	return note, nil
}
func (n Note) Midi() int { return 12*(n.Octave+1) + naturals[n.Pitch.Letter] + n.Pitch.Alteration }
func (n Note) Position() int { return 7*n.Octave + n.Pitch.Letter }
func (n Note) Valid() bool { return n.Octave >= -1 && n.Octave <= 9 && n.Midi() >= 0 && n.Midi() <= 127 }
func (n Note) String() string { return fmt.Sprintf("%s%d", n.Pitch, n.Octave) }
func noteFromPitch(pitch Pitch, value int) Note {
	return Note{pitch, (value-naturals[pitch.Letter]-pitch.Alteration)/12 - 1}
}
func spelling(value int, flat bool) Note {
	name := sharpNames[value%12]
	if flat {
		name = flatNames[value%12]
	}
	pitch, _ := parsePitch(name)
	return Note{pitch, value/12 - 1}
}
func parseNotes(words []string) ([]Note, error) {
	notes := make([]Note, len(words))
	for i, word := range words {
		note, err := parseNote(word)
		if err != nil {
			return nil, err
		}
		notes[i] = note
	}
	return notes, nil
}

type IntervalQuality int

const (
	Perfect IntervalQuality = iota
	Major
	Minor
	Augmented
	Diminished
	DoubleAugmented
	DoubleDiminished
)

func (q IntervalQuality) String() string { return [...]string{"P", "M", "m", "A", "d", "AA", "dd"}[q] }
func (q IntervalQuality) Delta(perfect bool) (int, bool) {
	switch q {
	case Perfect:
		return 0, perfect
	case Major:
		return 0, !perfect
	case Minor:
		return -1, !perfect
	case Augmented:
		return 1, true
	case DoubleAugmented:
		return 2, true
	case Diminished:
		if perfect {
			return -1, true
		}
		return -2, true
	default:
		if perfect {
			return -2, true
		}
		return -3, true
	}
}
func (q IntervalQuality) Inverse() IntervalQuality {
	return [...]IntervalQuality{Perfect, Minor, Major, Diminished, Augmented, DoubleDiminished, DoubleAugmented}[q]
}

type Interval struct {
	Quality IntervalQuality
	Number int
}
type Tone struct{ Letters, Semitones int }
type Motion struct {
	Interval Interval
	Down bool
	Semitones int
}

func perfectType(number int) bool {
	r := (number - 1) % 7
	return r == 0 || r == 3 || r == 4
}
func (i Interval) Forbidden() bool { return i.Number == 1 && (i.Quality == Diminished || i.Quality == DoubleDiminished) }
func parseInterval(text string) (Interval, error) {
	for q := Perfect; q <= DoubleDiminished; q++ {
		rest, found := strings.CutPrefix(text, q.String())
		if !found {
			continue
		}
		number, ok := canonical(rest, 1, 99)
		if !ok {
			continue
		}
		interval := Interval{q, number}
		_, permitted := q.Delta(perfectType(number))
		if permitted && !interval.Forbidden() {
			return interval, nil
		}
	}
	return Interval{}, bad("INTERVAL", text)
}
func (i Interval) String() string { return fmt.Sprintf("%s%d", i.Quality, i.Number) }
func (i Interval) Tone() Tone {
	s := i.Number - 1
	delta, _ := i.Quality.Delta(perfectType(i.Number))
	return Tone{s, 12*(s/7) + naturals[s%7] + delta}
}
func (i Interval) Simple() Interval {
	for i.Number > 8 {
		i.Number -= 7
	}
	return i
}
func (i Interval) Class() string {
	simple := i.Simple()
	if simple.Quality == Perfect && (simple.Number == 1 || simple.Number == 5 || simple.Number == 8) {
		return "perfect"
	}
	if (simple.Quality == Major || simple.Quality == Minor) && (simple.Number == 3 || simple.Number == 6) {
		return "imperfect"
	}
	return "dissonant"
}
func between(a, b Note) (Motion, error) {
	distance, semitones := b.Position()-a.Position(), b.Midi()-a.Midi()
	down := distance < 0 || distance == 0 && semitones < 0
	if down {
		distance, semitones = -distance, -semitones
	}
	difference := semitones - 12*(distance/7) - naturals[distance%7]
	for q := Perfect; q <= DoubleDiminished; q++ {
		if delta, ok := q.Delta(perfectType(distance+1)); ok && delta == difference {
			return Motion{Interval{q, distance + 1}, down, semitones}, nil
		}
	}
	return Motion{}, failure("UNNAMEABLE INTERVAL")
}

type Scale struct {
	Name string
	Tones []Tone
}
type Chord struct {
	Name, Suffix, NumeralSuffix string
	Lower bool
	Tones []Tone
}
type Mode struct {
	Name string
	Scale, Offset int
}

var scales = []Scale{
	{"major", []Tone{{0,0},{1,2},{2,4},{3,5},{4,7},{5,9},{6,11}}},
	{"natural_minor", []Tone{{0,0},{1,2},{2,3},{3,5},{4,7},{5,8},{6,10}}},
	{"harmonic_minor", []Tone{{0,0},{1,2},{2,3},{3,5},{4,7},{5,8},{6,11}}},
	{"melodic_minor", []Tone{{0,0},{1,2},{2,3},{3,5},{4,7},{5,9},{6,11}}},
	{"ionian", []Tone{{0,0},{1,2},{2,4},{3,5},{4,7},{5,9},{6,11}}},
	{"dorian", []Tone{{0,0},{1,2},{2,3},{3,5},{4,7},{5,9},{6,10}}},
	{"phrygian", []Tone{{0,0},{1,1},{2,3},{3,5},{4,7},{5,8},{6,10}}},
	{"lydian", []Tone{{0,0},{1,2},{2,4},{3,6},{4,7},{5,9},{6,11}}},
	{"mixolydian", []Tone{{0,0},{1,2},{2,4},{3,5},{4,7},{5,9},{6,10}}},
	{"aeolian", []Tone{{0,0},{1,2},{2,3},{3,5},{4,7},{5,8},{6,10}}},
	{"locrian", []Tone{{0,0},{1,1},{2,3},{3,5},{4,6},{5,8},{6,10}}},
	{"major_pentatonic", []Tone{{0,0},{1,2},{2,4},{4,7},{5,9}}},
	{"minor_pentatonic", []Tone{{0,0},{2,3},{3,5},{4,7},{6,10}}},
	{"blues", []Tone{{0,0},{2,3},{3,5},{3,6},{4,7},{6,10}}},
	{"whole_tone", []Tone{{0,0},{1,2},{2,4},{3,6},{4,8},{5,10}}},
}
var chords = []Chord{
	{"maj", "", "", false, []Tone{{0,0},{2,4},{4,7}}},
	{"min", "m", "", true, []Tone{{0,0},{2,3},{4,7}}},
	{"dim", "dim", "o", true, []Tone{{0,0},{2,3},{4,6}}},
	{"aug", "aug", "+", false, []Tone{{0,0},{2,4},{4,8}}},
	{"sus2", "sus2", "sus2", false, []Tone{{0,0},{1,2},{4,7}}},
	{"sus4", "sus4", "sus4", false, []Tone{{0,0},{3,5},{4,7}}},
	{"6", "6", "6", false, []Tone{{0,0},{2,4},{4,7},{5,9}}},
	{"m6", "m6", "6", true, []Tone{{0,0},{2,3},{4,7},{5,9}}},
	{"7", "7", "7", false, []Tone{{0,0},{2,4},{4,7},{6,10}}},
	{"maj7", "maj7", "maj7", false, []Tone{{0,0},{2,4},{4,7},{6,11}}},
	{"m7", "m7", "7", true, []Tone{{0,0},{2,3},{4,7},{6,10}}},
	{"mMaj7", "mMaj7", "maj7", true, []Tone{{0,0},{2,3},{4,7},{6,11}}},
	{"m7b5", "m7b5", "h7", true, []Tone{{0,0},{2,3},{4,6},{6,10}}},
	{"dim7", "dim7", "o7", true, []Tone{{0,0},{2,3},{4,6},{6,9}}},
	{"9", "9", "9", false, []Tone{{0,0},{2,4},{4,7},{6,10},{8,14}}},
	{"add9", "add9", "add9", false, []Tone{{0,0},{2,4},{4,7},{8,14}}},
}
var modes = []Mode{
	{"major",0,0}, {"minor",1,-3}, {"ionian",4,0}, {"dorian",5,-2}, {"phrygian",6,-4},
	{"lydian",7,1}, {"mixolydian",8,-1}, {"aeolian",9,-3}, {"locrian",10,-5},
}

func parseScale(text string) (Scale, error) {
	for _, scale := range scales {
		if scale.Name == text {
			return scale, nil
		}
	}
	return Scale{}, bad("SCALE", text)
}
func parseQuality(text string) (int, error) {
	for i, chord := range chords {
		if chord.Name == text {
			return i, nil
		}
	}
	return 0, bad("QUALITY", text)
}
func parseMode(text string) (int, error) {
	for i, mode := range modes {
		if mode.Name == text {
			return i, nil
		}
	}
	return 0, bad("MODE", text)
}
func build(root Pitch, tones []Tone) ([]Pitch, error) {
	pitches := make([]Pitch, len(tones))
	for i, tone := range tones {
		pitch, err := root.Raise(tone)
		if err != nil {
			return nil, err
		}
		pitches[i] = pitch
	}
	return pitches, nil
}
func symbol(root Pitch, quality int, bass *Pitch) string {
	result := root.String() + chords[quality].Suffix
	if bass != nil {
		result += "/" + bass.String()
	}
	return result
}
func roman(degree, quality int) string {
	part := upperRomans[degree]
	if chords[quality].Lower {
		part = lowerRomans[degree]
	}
	return part + chords[quality].NumeralSuffix
}

type Key struct {
	Tonic Pitch
	Mode, Fifths int
	Scale [7]Pitch
}

func makeKey(tonic Pitch, mode int) (Key, error) {
	key := Key{Tonic: tonic, Mode: mode, Fifths: fifthsValues[tonic.Letter] + 7*tonic.Alteration + modes[mode].Offset}
	if key.Fifths < -7 || key.Fifths > 7 {
		return Key{}, failure("THEORETICAL KEY")
	}
	scale, err := build(tonic, scales[modes[mode].Scale].Tones)
	if err != nil {
		return Key{}, err
	}
	copy(key.Scale[:], scale)
	return key, nil
}
func parseKey(words []string) (Key, error) {
	tonic, err := parsePitch(words[0])
	if err != nil {
		return Key{}, err
	}
	mode, err := parseMode(words[1])
	if err != nil {
		return Key{}, err
	}
	return makeKey(tonic, mode)
}
func (k Key) String() string { return fmt.Sprintf("%s %s", k.Tonic, modes[k.Mode].Name) }
func (k Key) Degree(pitch Pitch) int { return mod(pitch.Letter-k.Tonic.Letter, 7) }
func (k Key) Prefix(pitch Pitch) string {
	difference := pitch.Alteration - k.Scale[k.Degree(pitch)].Alteration
	if difference < 0 {
		return strings.Repeat("b", -difference)
	}
	return strings.Repeat("#", difference)
}
func (k Key) Label(pitch Pitch) string { return fmt.Sprintf("%s%d", k.Prefix(pitch), k.Degree(pitch)+1) }
func (k Key) Set() uint {
	var mask uint
	for _, pitch := range k.Scale {
		mask |= 1 << pitch.Class()
	}
	return mask
}

type Numeral struct{ Alteration, Degree, Quality int }
type Symbol struct {
	Root Pitch
	Quality int
}

func parseNumeral(text string) (Numeral, error) {
	start, alteration := 0, 0
	if text[0] == 'b' {
		start, alteration = 1, -1
	} else if text[0] == '#' {
		start, alteration = 1, 1
	}
	end := start
	for end < len(text) && strings.ContainsRune("IViv", rune(text[end])) {
		end++
	}
	for degree := range 7 {
		for quality, chord := range chords {
			part := upperRomans[degree]
			if chord.Lower {
				part = lowerRomans[degree]
			}
			if text[start:end] == part && text[end:] == chord.NumeralSuffix {
				return Numeral{alteration, degree, quality}, nil
			}
		}
	}
	return Numeral{}, bad("NUMERAL", text)
}
func parseSymbol(text string) (Symbol, error) {
	root, end, ok := pitchPrefix(text)
	if ok {
		for quality, chord := range chords {
			if text[end:] == chord.Suffix {
				return Symbol{root, quality}, nil
			}
		}
	}
	return Symbol{}, bad("SYMBOL", text)
}

func chordCommand(command string, a []string) (string, error) {
	var note Note
	var root Pitch
	var err error
	if command == "VOICE" {
		note, err = parseNote(a[0])
		root = note.Pitch
	} else {
		root, err = parsePitch(a[0])
	}
	if err != nil {
		return "", err
	}
	quality, err := parseQuality(a[1])
	if err != nil {
		return "", err
	}
	chord, inversion := chords[quality], 0
	if len(a) == 3 {
		var ok bool
		inversion, ok = canonical(a[2], 0, len(chord.Tones)-1)
		if !ok {
			return "", bad("INVERSION", a[2])
		}
	}
	tones, err := build(root, chord.Tones)
	if err != nil {
		return "", err
	}
	ordered := make([]Pitch, len(tones))
	for i := range ordered {
		ordered[i] = tones[(i+inversion)%len(tones)]
	}
	var bass *Pitch
	if inversion != 0 {
		bass = &ordered[0]
	}
	name := symbol(root, quality, bass)
	if command == "CHORD" {
		return fmt.Sprintf("CHORD %s %s", name, join(ordered, " ")), nil
	}
	notes := make([]Note, len(ordered))
	values := make([]int, len(ordered))
	value := note.Midi()
	for i, pitch := range ordered {
		if i != 0 || inversion != 0 {
			difference := mod(pitch.Class()-value, 12)
			if difference == 0 {
				difference = 12
			}
			value += difference
		}
		notes[i] = noteFromPitch(pitch, value)
		if !notes[i].Valid() {
			return "", failure("OUT OF RANGE")
		}
		values[i] = value
	}
	return fmt.Sprintf("VOICE %s %s midi=%s", name, join(notes, " "), join(values, ",")), nil
}
func identify(notes []Note) string {
	slices.SortStableFunc(notes, func(a, b Note) int { return a.Midi() - b.Midi() })
	candidates := notes[:0]
	var set uint
	for _, note := range notes {
		bit := uint(1) << note.Pitch.Class()
		if set&bit == 0 {
			set |= bit
			candidates = append(candidates, note)
		}
	}
	bass := candidates[0].Pitch
	for _, root := range candidates {
		for quality, chord := range chords {
			var mask uint
			for _, tone := range chord.Tones {
				mask |= 1 << mod(root.Midi()+tone.Semitones, 12)
			}
			if mask != set {
				continue
			}
			inversion := 0
			for mod(root.Midi()+chord.Tones[inversion].Semitones, 12) != bass.Class() {
				inversion++
			}
			var slash *Pitch
			if inversion != 0 {
				slash = &bass
			}
			return fmt.Sprintf("IDENTIFY %s root=%s quality=%s inversion=%d", symbol(root.Pitch, quality, slash), root.Pitch, chord.Name, inversion)
		}
	}
	return "IDENTIFY UNKNOWN"
}
func melody(notes []Note, words []string) (string, error) {
	low, high := 0, 0
	for i, note := range notes {
		if note.Midi() < notes[low].Midi() {
			low = i
		}
		if note.Midi() > notes[high].Midi() {
			high = i
		}
	}
	rangeMotion, err := between(notes[low], notes[high])
	if err != nil {
		return "", err
	}
	steps := make([]string, len(notes)-1)
	leaps := 0
	for i := 1; i < len(notes); i++ {
		motion, err := between(notes[i-1], notes[i])
		if err != nil {
			return "", err
		}
		sign := "+"
		if motion.Down {
			sign = "-"
		}
		steps[i-1] = sign + motion.Interval.String()
		if abs(notes[i].Midi()-notes[i-1].Midi()) >= 3 {
			leaps++
		}
	}
	return fmt.Sprintf("MELODY n=%d low=%s high=%s range=%s leaps=%d steps=%s", len(notes), words[low], words[high], rangeMotion.Interval, leaps, strings.Join(steps, ",")), nil
}
func cadence(numerals []Numeral) string {
	if len(numerals) < 2 {
		return "none"
	}
	x, y := numerals[len(numerals)-2], numerals[len(numerals)-1]
	if x.Alteration == 0 && y.Alteration == 0 {
		if x.Degree == 4 && y.Degree == 0 {
			return "authentic"
		}
		if x.Degree == 3 && y.Degree == 0 {
			return "plagal"
		}
		if x.Degree == 4 && y.Degree == 5 {
			return "deceptive"
		}
	}
	if y.Alteration == 0 && y.Degree == 4 {
		return "half"
	}
	return "none"
}
func diatonic(key Key) string {
	rows := []string{"DIATONIC " + key.String()}
	for size := 3; size <= 4; size++ {
		items := make([]string, 7)
		for i, root := range key.Scale {
			third := mod(key.Scale[(i+2)%7].Class()-root.Class(), 12)
			fifth := mod(key.Scale[(i+4)%7].Class()-root.Class(), 12)
			var quality int
			if size == 3 {
				if third == 4 {
					quality = 0
				} else if fifth == 7 {
					quality = 1
				} else {
					quality = 2
				}
			} else {
				seventh := mod(key.Scale[(i+6)%7].Class()-root.Class(), 12)
				if third == 4 {
					quality = 8
					if seventh == 11 {
						quality = 9
					}
				} else if fifth == 7 {
					quality = 10
				} else {
					quality = 12
				}
			}
			items[i] = roman(i, quality) + "=" + symbol(root, quality, nil)
		}
		prefix := "TRIADS "
		if size == 4 {
			prefix = "SEVENTHS "
		}
		rows = append(rows, prefix+strings.Join(items, " "))
	}
	return strings.Join(rows, "\n")
}
func keyCommand(command string, a []string) (string, error) {
	key, err := parseKey(a)
	if err != nil {
		return "", err
	}
	switch command {
	case "KEYSIG":
		p := key.Fifths
		if p == 0 {
			return fmt.Sprintf("KEYSIG %s none", key), nil
		}
		names, kind := []string{"F#", "C#", "G#", "D#", "A#", "E#", "B#"}, "sharps"
		if p < 0 {
			names, kind = []string{"Bb", "Eb", "Ab", "Db", "Gb", "Cb", "Fb"}, "flats"
		}
		return fmt.Sprintf("KEYSIG %s %s=%d %s", key, kind, abs(p), strings.Join(names[:abs(p)], " ")), nil
	case "RELATIVE":
		return fmt.Sprintf("RELATIVE %s major=%s minor=%s", key, fifthPitch(key.Fifths), fifthPitch(key.Fifths+3)), nil
	case "DEGREE":
		pitch, err := parsePitch(a[2])
		if err != nil {
			return "", err
		}
		return fmt.Sprintf("DEGREE %s %s %s", key, a[2], key.Label(pitch)), nil
	case "KEYDIST":
		other, err := parseKey(a[2:])
		if err != nil {
			return "", err
		}
		distance := mod(other.Fifths-key.Fifths, 12)
		if distance > 6 {
			distance -= 12
		}
		sameTonic := key.Tonic.Class() == other.Tonic.Class()
		relation := "distant"
		if key.Set() == other.Set() {
			relation = "relative"
			if sameTonic {
				relation = "same"
			}
		} else if sameTonic {
			relation = "parallel"
		} else if abs(distance) == 1 {
			relation = "close"
		}
		distanceText := strconv.Itoa(distance)
		if distance > 0 {
			distanceText = "+" + distanceText
		}
		return fmt.Sprintf("KEYDIST %s %s fifths=%s common=%d relation=%s", key, other, distanceText, bits.OnesCount(key.Set()&other.Set()), relation), nil
	case "DIATONIC":
		return diatonic(key), nil
	case "ANALYZE":
		symbols := make([]Symbol, len(a)-2)
		for i, word := range a[2:] {
			parsed, err := parseSymbol(word)
			if err != nil {
				return "", err
			}
			symbols[i] = parsed
		}
		items := make([]string, len(symbols))
		for i, chord := range symbols {
			items[i] = key.Prefix(chord.Root) + roman(key.Degree(chord.Root), chord.Quality)
		}
		return fmt.Sprintf("ANALYZE %s %s", key, strings.Join(items, " ")), nil
	case "PROGRESSION":
		numerals := make([]Numeral, len(a)-2)
		for i, word := range a[2:] {
			parsed, err := parseNumeral(word)
			if err != nil {
				return "", err
			}
			numerals[i] = parsed
		}
		rows := []string{fmt.Sprintf("PROGRESSION %s %d", key, len(numerals))}
		for i, numeral := range numerals {
			root := key.Scale[numeral.Degree]
			root.Alteration += numeral.Alteration
			tones, err := build(root, chords[numeral.Quality].Tones)
			if err != nil {
				return "", err
			}
			rows = append(rows, fmt.Sprintf("%s %s %s", a[i+2], symbol(root, numeral.Quality, nil), join(tones, " ")))
		}
		rows = append(rows, "CADENCE "+cadence(numerals))
		return strings.Join(rows, "\n"), nil
	}
	return "", failure("UNKNOWN COMMAND " + command)
}

var arities = map[string][2]int{
	"MIDI": {1,1}, "NOTE": {1,1}, "FREQ": {1,1}, "TUNING": {1,1}, "PITCH": {1,1},
	"INTERVAL": {2,2}, "INVERT": {1,1}, "TRANSPOSE": {3,3}, "SCALE": {2,2},
	"CHORD": {2,3}, "VOICE": {2,3}, "IDENTIFY": {2,15}, "MELODY": {2,15},
	"ENHARMONIC": {1,1}, "KEYSIG": {2,2}, "RELATIVE": {2,2}, "CIRCLE": {1,1},
	"DIATONIC": {2,2}, "PROGRESSION": {3,15}, "ANALYZE": {3,15}, "FINDKEY": {1,15},
	"DEGREE": {3,3}, "SPELL": {3,3}, "KEYDIST": {4,4},
}

type Calculator struct{ Tuning int }

func (c *Calculator) Execute(line string) (string, error) {
	words := strings.Split(line, " ")
	command, a := words[0], words[1:]
	arity, found := arities[command]
	if !found {
		return "", failure("UNKNOWN COMMAND " + command)
	}
	if len(a) < arity[0] || len(a) > arity[1] {
		return "", failure("ARGUMENT COUNT")
	}
	switch command {
	case "MIDI", "FREQ", "ENHARMONIC":
		note, err := parseNote(a[0])
		if err != nil {
			return "", err
		}
		value := note.Midi()
		if command == "MIDI" {
			return fmt.Sprintf("MIDI %s %d", a[0], value), nil
		}
		if command == "FREQ" {
			cents := int(math.Floor(float64(c.Tuning)*math.Exp2(float64(value-69)/12) + 0.5))
			return fmt.Sprintf("FREQ %s %s", a[0], frequencyText(cents)), nil
		}
		var notes []Note
		for octave := -1; octave <= 9; octave++ {
			for letter := range 7 {
				alteration := value - 12*(octave+1) - naturals[letter]
				if alteration >= -2 && alteration <= 2 {
					notes = append(notes, Note{Pitch{letter, alteration}, octave})
				}
			}
		}
		return fmt.Sprintf("ENHARMONIC %s %s", a[0], join(notes, " ")), nil
	case "NOTE":
		value, err := parseNumber(a[0])
		if err != nil {
			return "", err
		}
		return fmt.Sprintf("NOTE %d %s %s", value, spelling(value, false), spelling(value, true)), nil
	case "TUNING", "PITCH":
		value, err := parseFrequency(a[0], command == "TUNING")
		if err != nil {
			return "", err
		}
		if command == "TUNING" {
			c.Tuning = value
			return "TUNING " + frequencyText(value), nil
		}
		x := 69 + 12*math.Log2(float64(value)/float64(c.Tuning))
		nearest := int(math.Floor(x + 0.5))
		if nearest < 0 || nearest > 127 {
			return "", failure("OUT OF RANGE")
		}
		cents := int(math.Floor(100*(x-float64(nearest)) + 0.5))
		return fmt.Sprintf("PITCH %s %s %+d", frequencyText(value), spelling(nearest, false), cents), nil
	case "INTERVAL":
		first, err := parseNote(a[0])
		if err != nil {
			return "", err
		}
		second, err := parseNote(a[1])
		if err != nil {
			return "", err
		}
		motion, err := between(first, second)
		if err != nil {
			return "", err
		}
		direction := "up"
		if motion.Down {
			direction = "down"
		}
		return fmt.Sprintf("INTERVAL %s %s %s %s semitones=%d simple=%s class=%s", a[0], a[1], motion.Interval, direction,
			motion.Semitones, motion.Interval.Simple(), motion.Interval.Class()), nil
	case "INVERT":
		interval, err := parseInterval(a[0])
		if err != nil {
			return "", err
		}
		simple := interval.Simple()
		inverse := Interval{simple.Quality.Inverse(), 9 - simple.Number}
		if inverse.Forbidden() {
			return "", failure("CANNOT INVERT")
		}
		return fmt.Sprintf("INVERT %s %s %s", a[0], simple, inverse), nil
	case "TRANSPOSE":
		note, err := parseNote(a[0])
		if err != nil {
			return "", err
		}
		interval, err := parseInterval(a[1])
		if err != nil {
			return "", err
		}
		if a[2] != "UP" && a[2] != "DOWN" {
			return "", bad("DIRECTION", a[2])
		}
		sign := 1
		if a[2] == "DOWN" {
			sign = -1
		}
		tone := interval.Tone()
		position, value := note.Position()+sign*tone.Letters, note.Midi()+sign*tone.Semitones
		letter, octave := mod(position, 7), floorDiv(position, 7)
		alteration := value - 12*(octave+1) - naturals[letter]
		if alteration < -2 || alteration > 2 {
			return "", failure("CANNOT SPELL")
		}
		result := Note{Pitch{letter, alteration}, octave}
		if !result.Valid() {
			return "", failure("OUT OF RANGE")
		}
		return fmt.Sprintf("TRANSPOSE %s %s %s %s", a[0], a[1], a[2], result), nil
	case "SCALE":
		root, err := parsePitch(a[0])
		if err != nil {
			return "", err
		}
		scale, err := parseScale(a[1])
		if err != nil {
			return "", err
		}
		pitches, err := build(root, scale.Tones)
		if err != nil {
			return "", err
		}
		steps := make([]int, len(scale.Tones))
		for i, tone := range scale.Tones {
			next := 12
			if i+1 < len(scale.Tones) {
				next = scale.Tones[i+1].Semitones
			}
			steps[i] = next - tone.Semitones
		}
		return fmt.Sprintf("SCALE %s %s %s steps=%s", a[0], a[1], join(pitches, " "), join(steps, ",")), nil
	case "CHORD", "VOICE":
		return chordCommand(command, a)
	case "IDENTIFY", "MELODY":
		notes, err := parseNotes(a)
		if err != nil {
			return "", err
		}
		if command == "IDENTIFY" {
			return identify(notes), nil
		}
		return melody(notes, a)
	case "CIRCLE":
		mode, err := parseMode(a[0])
		if err != nil {
			return "", err
		}
		pitches := make([]Pitch, 15)
		for i := range pitches {
			pitches[i] = fifthPitch(i - 7 - modes[mode].Offset)
		}
		return fmt.Sprintf("CIRCLE %s %s", a[0], join(pitches, " ")), nil
	case "FINDKEY":
		pitches := make([]Pitch, len(a))
		for i, word := range a {
			pitch, err := parsePitch(word)
			if err != nil {
				return "", err
			}
			pitches[i] = pitch
		}
		var keys []Key
		for p := -7; p <= 7; p++ {
			for mode := range 2 {
				key, err := makeKey(fifthPitch(p-modes[mode].Offset), mode)
				if err != nil {
					return "", err
				}
				match := true
				for _, pitch := range pitches {
					if !slices.Contains(key.Scale[:], pitch) {
						match = false
					}
				}
				if match {
					keys = append(keys, key)
				}
			}
		}
		result := fmt.Sprintf("FINDKEY %d", len(keys))
		if len(keys) != 0 {
			result += " " + join(keys, ", ")
		}
		return result, nil
	case "SPELL":
		value, err := parseNumber(a[0])
		if err != nil {
			return "", err
		}
		key, err := parseKey(a[1:])
		if err != nil {
			return "", err
		}
		pitch := spelling(value, key.Fifths < 0).Pitch
		for _, candidate := range key.Scale {
			if candidate.Class() == value%12 {
				pitch = candidate
				break
			}
		}
		note := noteFromPitch(pitch, value)
		if !note.Valid() {
			return "", failure("OUT OF RANGE")
		}
		return fmt.Sprintf("SPELL %d %s %s %s", value, key, note, key.Label(pitch)), nil
	default:
		return keyCommand(command, a)
	}
}

func main() {
	input := bufio.NewScanner(os.Stdin)
	input.Scan()
	count, _ := strconv.Atoi(input.Text())
	output := bufio.NewWriter(os.Stdout)
	defer output.Flush()
	calculator := Calculator{Tuning: 44000}
	for i := 0; i < count && input.Scan(); i++ {
		response, err := calculator.Execute(input.Text())
		if err != nil {
			fmt.Fprintln(output, err)
		} else {
			fmt.Fprintln(output, response)
		}
	}
}
