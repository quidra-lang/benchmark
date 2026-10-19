package main

import (
	"bufio"
	"fmt"
	"math/bits"
	"os"
	"strconv"
	"strings"
)

type Pattern uint32
type Flags uint8

const (
	invalid Flags = 1 << iota
	divByZero
	overflow
	underflow
	inexact
)

func (flags Flags) String() string {
	names := []string{"invalid", "divbyzero", "overflow", "underflow", "inexact"}
	var raised []string
	for i, name := range names {
		if flags&(1<<i) != 0 {
			raised = append(raised, name)
		}
	}
	if len(raised) == 0 {
		return "flags=none"
	}
	return "flags=" + strings.Join(raised, ",")
}

type Mode int

const (
	rne Mode = iota
	rna
	rtz
	rup
	rdn
)

var modeNames = [...]string{"RNE", "RNA", "RTZ", "RUP", "RDN"}

func (mode Mode) String() string { return modeNames[mode] }

func parseMode(word string) (Mode, error) {
	for mode, name := range modeNames {
		if name == word {
			return Mode(mode), nil
		}
	}
	return rne, fmt.Errorf("ERROR BAD MODE %s", word)
}

func optionalMode(words []string, index int) (Mode, error) {
	if index == len(words) {
		return rne, nil
	}
	return parseMode(words[index])
}

type Class int

const (
	zero Class = iota
	subnormal
	normal
	infinity
	quietNaN
	signalingNaN
)

func (kind Class) String() string {
	return [...]string{"zero", "subnormal", "normal", "infinity", "qnan", "snan"}[kind]
}

type Operation int

const (
	add Operation = iota
	sub
	mul
	div
	sqrt
	fma
)

type Term struct {
	negative  bool
	magnitude uint64
	exponent  int
}

func (term Term) product(other Term) Term {
	return Term{term.negative != other.negative, term.magnitude * other.magnitude, term.exponent + other.exponent}
}

func (term Term) exact() Exact {
	return newExact(term.negative, term.magnitude, term.exponent, 1)
}

func (term Term) decimal() string {
	if term.magnitude == 0 {
		return "0"
	}
	value := term.exact()
	numerator, denominator := value.scaled(0)
	var out strings.Builder
	if value.negative {
		out.WriteByte('-')
	}
	fmt.Fprint(&out, numerator/denominator)
	remainder := numerator % denominator
	if remainder != 0 {
		out.WriteByte('.')
	}
	for remainder != 0 {
		remainder *= 10
		out.WriteByte('0' + byte(remainder/denominator))
		remainder %= denominator
	}
	return out.String()
}

func sumTerms(terms []Term, mode Mode) Term {
	exponent, any, sameZero := 0, false, true
	for _, term := range terms {
		if term.magnitude != 0 {
			if !any || term.exponent < exponent {
				exponent = term.exponent
			}
			any, sameZero = true, false
		} else if term.negative != terms[0].negative {
			sameZero = false
		}
	}
	var sum int64
	for _, term := range terms {
		if term.magnitude == 0 {
			continue
		}
		magnitude := int64(term.magnitude << (term.exponent - exponent))
		if term.negative {
			sum -= magnitude
		} else {
			sum += magnitude
		}
	}
	if sum == 0 {
		negative := mode == rdn
		if sameZero {
			negative = terms[0].negative
		}
		return Term{negative, 0, 0}
	}
	if sum < 0 {
		return Term{true, uint64(-sum), exponent}
	}
	return Term{false, uint64(sum), exponent}
}

type Exact struct {
	negative               bool
	numerator, denominator uint64
	exponent               int
}

func newExact(negative bool, numerator uint64, exponent int, denominator uint64) Exact {
	if numerator == 0 {
		return Exact{negative, 0, 1, 0}
	}
	a, b := numerator, denominator
	for b != 0 {
		a, b = b, a%b
	}
	numerator, denominator = numerator/a, denominator/a
	shift := bits.TrailingZeros64(numerator)
	numerator >>= shift
	exponent += shift
	shift = bits.TrailingZeros64(denominator)
	denominator >>= shift
	exponent -= shift
	return Exact{negative, numerator, denominator, exponent}
}

func (value Exact) scaled(quantum int) (uint64, uint64) {
	shift := value.exponent - quantum
	if shift >= 0 {
		return value.numerator << shift, value.denominator
	}
	return value.numerator, value.denominator << -shift
}

func (value Exact) floorLog() int {
	power := bits.Len64(value.numerator) - bits.Len64(value.denominator)
	below := false
	if power >= 0 {
		below = value.numerator < value.denominator<<power
	} else {
		below = value.numerator<<-power < value.denominator
	}
	if below {
		power--
	}
	return value.exponent + power
}

func (value Exact) fraction() string {
	if value.numerator == 0 {
		return "0"
	}
	numerator, denominator := value.scaled(0)
	sign := ""
	if value.negative {
		sign = "-"
	}
	if denominator == 1 {
		return sign + strconv.FormatUint(numerator, 10)
	}
	return fmt.Sprintf("%s%d/%d", sign, numerator, denominator)
}

type Quantized struct {
	whole   uint64
	inexact bool
	half    int
}

func compare(a, b uint64) int {
	if a < b {
		return -1
	}
	if a > b {
		return 1
	}
	return 0
}

func integerSqrt(value uint64) uint64 {
	if value == 0 {
		return 0
	}
	root, next := value, (value+1)/2
	for next < root {
		root = next
		next = (root + value/root) / 2
	}
	return root
}

func quantize(value Exact, quantum int, squareRoot bool) Quantized {
	if squareRoot {
		quantum *= 2
	}
	numerator, denominator := value.scaled(quantum)
	if !squareRoot {
		remainder := numerator % denominator
		return Quantized{numerator / denominator, remainder != 0, compare(remainder, denominator-remainder)}
	}
	whole := integerSqrt(numerator / denominator)
	midpoint := 2*whole + 1
	return Quantized{whole, whole*whole*denominator != numerator, compare(4*numerator, midpoint*midpoint*denominator)}
}

func (value Quantized) rounded(mode Mode, negative bool) uint64 {
	increment := false
	switch mode {
	case rne:
		increment = value.half > 0 || value.half == 0 && value.whole&1 != 0
	case rna:
		increment = value.half >= 0
	case rup:
		increment = value.inexact && !negative
	case rdn:
		increment = value.inexact && negative
	}
	if increment {
		return value.whole + 1
	}
	return value.whole
}

type Rounded struct {
	pattern Pattern
	flags   Flags
}

type Input struct {
	pattern Pattern
	number  *Exact
}

type Format struct {
	name                      string
	e, m, w, bias, emin, emax int
	sign, base, inf, nan       Pattern
}

func newFormat(name string, e, m int) *Format {
	bias := (1 << (e - 1)) - 1
	base := Pattern(1) << m
	inf := ((Pattern(1) << e) - 1) << m
	return &Format{name, e, m, 1 + e + m, bias, 1 - bias, bias, 1 << (e + m), base, inf, inf | base/2}
}

func (f *Format) negative(p Pattern) bool { return p&f.sign != 0 }
func (f *Format) zero(p Pattern) bool     { return p&(f.sign-1) == 0 }

func (f *Format) signed(p Pattern, negative bool) Pattern {
	if negative {
		return p | f.sign
	}
	return p
}

func (f *Format) class(p Pattern) Class {
	magnitude, fraction := p&(f.sign-1), p&(f.base-1)
	if magnitude >= f.inf {
		if fraction == 0 {
			return infinity
		}
		if fraction >= f.base/2 {
			return quietNaN
		}
		return signalingNaN
	}
	if magnitude == 0 {
		return zero
	}
	if magnitude < f.base {
		return subnormal
	}
	return normal
}

func (f *Format) finite(p Pattern) bool { return f.class(p) <= normal }
func (f *Format) isNaN(p Pattern) bool  { return f.class(p) >= quietNaN }

func (f *Format) term(p Pattern) Term {
	field, fraction := p&(f.sign-1)>>f.m, p&(f.base-1)
	if field == 0 {
		return Term{f.negative(p), uint64(fraction), f.emin - f.m}
	}
	return Term{f.negative(p), uint64(f.base + fraction), int(field) - f.bias - f.m}
}

func (f *Format) overflow(mode Mode, negative bool) Rounded {
	toInfinity := mode == rne || mode == rna || mode == rup && !negative || mode == rdn && negative
	pattern := f.inf - 1
	if toInfinity {
		pattern = f.inf
	}
	return Rounded{f.signed(pattern, negative), overflow | inexact}
}

func (f *Format) round(value Exact, mode Mode, squareRoot bool) Rounded {
	if value.numerator == 0 {
		return Rounded{f.signed(0, value.negative), 0}
	}
	t := value.floorLog()
	if squareRoot {
		if t < 0 {
			t = -((-t + 1) / 2)
		} else {
			t /= 2
		}
	}
	if t > f.emax {
		return f.overflow(mode, value.negative)
	}
	quantum := max(t, f.emin) - f.m
	divided := quantize(value, quantum, squareRoot)
	significand := divided.rounded(mode, value.negative)
	base := uint64(f.base)
	if significand == 2*base {
		significand = base
		quantum++
	}
	if quantum > f.emax-f.m {
		return f.overflow(mode, value.negative)
	}
	var flags Flags
	if divided.inexact {
		flags |= inexact
		if t < f.emin {
			tiny := t < f.emin-1
			if !tiny {
				tiny = quantize(value, t-f.m, squareRoot).rounded(mode, value.negative) < 2*base
			}
			if tiny {
				flags |= underflow
			}
		}
	}
	magnitude := Pattern(significand)
	if significand >= base {
		magnitude = Pattern(quantum+f.m+f.bias)<<f.m | Pattern(significand-base)
	}
	return Rounded{f.signed(magnitude, value.negative), flags}
}

func (f *Format) roundTerm(term Term, mode Mode) Rounded { return f.round(term.exact(), mode, false) }
func (f *Format) roundSum(terms []Term, mode Mode) Rounded {
	return f.roundTerm(sumTerms(terms, mode), mode)
}

func (f *Format) arithmetic(operation Operation, a, b, c Pattern, mode Mode) Rounded {
	if operation == sub {
		b ^= f.sign
		operation = add
	}
	inputs := []Pattern{a, b}
	if operation == sqrt {
		inputs = inputs[:1]
	} else if operation == fma {
		inputs = append(inputs, c)
	}
	nan, nanFlags := false, Flags(0)
	for _, p := range inputs {
		nan = nan || f.isNaN(p)
		if f.class(p) == signalingNaN {
			nanFlags |= invalid
		}
	}
	if nan {
		return Rounded{f.nan, nanFlags}
	}
	ai, bi := f.class(a) == infinity, f.class(b) == infinity
	negative := f.negative(a) != f.negative(b)
	bad := Rounded{f.nan, invalid}
	switch operation {
	case add:
		if ai && bi && negative {
			return bad
		}
		if ai {
			return Rounded{a, 0}
		}
		if bi {
			return Rounded{b, 0}
		}
		return f.roundSum([]Term{f.term(a), f.term(b)}, mode)
	case mul:
		if ai || bi {
			if f.zero(a) || f.zero(b) {
				return bad
			}
			return Rounded{f.signed(f.inf, negative), 0}
		}
		return f.roundTerm(f.term(a).product(f.term(b)), mode)
	case div:
		if ai {
			if bi {
				return bad
			}
			return Rounded{f.signed(f.inf, negative), 0}
		}
		if bi {
			return Rounded{f.signed(0, negative), 0}
		}
		if f.zero(b) {
			if f.zero(a) {
				return bad
			}
			return Rounded{f.signed(f.inf, negative), divByZero}
		}
		if f.zero(a) {
			return Rounded{f.signed(0, negative), 0}
		}
		x, y := f.term(a), f.term(b)
		return f.round(newExact(negative, x.magnitude, x.exponent-y.exponent, y.magnitude), mode, false)
	case sqrt:
		if f.zero(a) {
			return Rounded{a, 0}
		}
		if f.negative(a) {
			return bad
		}
		if ai {
			return Rounded{a, 0}
		}
		return f.round(f.term(a).exact(), mode, true)
	case fma:
		if ai || bi {
			if f.zero(a) || f.zero(b) || f.class(c) == infinity && f.negative(c) != negative {
				return bad
			}
			return Rounded{f.signed(f.inf, negative), 0}
		}
		if f.class(c) == infinity {
			return Rounded{c, 0}
		}
		return f.roundSum([]Term{f.term(a).product(f.term(b)), f.term(c)}, mode)
	}
	panic("unreachable operation")
}

func unsigned(word string, base int) uint64 {
	value, _ := strconv.ParseUint(word, base, 64)
	return value
}

func (f *Format) rawOperand(word string, encoding bool) (Input, error) {
	bad := fmt.Errorf("ERROR BAD OPERAND %s", word)
	if strings.HasPrefix(word, "0b") || strings.HasPrefix(word, "0x") {
		width, radix := (f.w+3)/4, 16
		if word[1] == 'b' {
			width, radix = f.w, 2
		}
		if encoding || len(word)-2 != width {
			return Input{}, bad
		}
		pattern := Pattern(unsigned(word[2:], radix))
		if pattern >= 2*f.sign {
			return Input{}, bad
		}
		return Input{pattern: pattern}, nil
	}
	switch word {
	case "nan":
		return Input{pattern: f.nan}, nil
	case "inf":
		return Input{pattern: f.inf}, nil
	case "-inf":
		return Input{pattern: f.inf | f.sign}, nil
	}
	negative := strings.HasPrefix(word, "-")
	digits := strings.TrimPrefix(word, "-")
	var numerator uint64
	denominator := uint64(1)
	if p, q, found := strings.Cut(digits, "/"); found {
		numerator, denominator = unsigned(p, 10), unsigned(q, 10)
		if denominator == 0 {
			return Input{}, bad
		}
	} else if integer, fraction, found := strings.Cut(digits, "."); found {
		numerator = unsigned(integer+fraction, 10)
		for range len(fraction) {
			denominator *= 10
		}
	} else {
		numerator = unsigned(digits, 10)
	}
	value := newExact(negative, numerator, 0, denominator)
	return Input{number: &value}, nil
}

func (f *Format) operand(word string) (Pattern, error) {
	value, err := f.rawOperand(word, false)
	if err != nil {
		return 0, err
	}
	if value.number != nil {
		return f.round(*value.number, rne, false).pattern, nil
	}
	return value.pattern, nil
}

func (f *Format) bits(p Pattern) string {
	sign := 0
	if f.negative(p) {
		sign = 1
	}
	return fmt.Sprintf("%d|%0*b|%0*b", sign, f.e, p&(f.sign-1)>>f.m, f.m, p&(f.base-1))
}

func (f *Format) hex(p Pattern) string { return fmt.Sprintf("0x%0*X", (f.w+3)/4, p) }
func (f *Format) value(p Pattern) string {
	switch f.class(p) {
	case quietNaN, signalingNaN:
		return "nan"
	case infinity:
		if f.negative(p) {
			return "-inf"
		}
		return "inf"
	case zero:
		if f.negative(p) {
			return "-0"
		}
		return "0"
	}
	return f.term(p).decimal()
}

func (f *Format) pattern(p Pattern) string {
	return fmt.Sprintf("%s %s %s", f.bits(p), f.hex(p), f.value(p))
}

func (f *Format) result(value Rounded) string {
	return fmt.Sprintf("%s %s", f.pattern(value.pattern), value.flags)
}

func (f *Format) difference(p Pattern, exactSum Term) string {
	if !f.finite(p) {
		return f.value(p)
	}
	exactSum.negative = !exactSum.negative
	return sumTerms([]Term{f.term(p), exactSum}, rne).exact().fraction()
}

func (f *Format) orderKey(p Pattern) int64 {
	if f.negative(p) {
		return -int64(p-f.sign) - 1
	}
	return int64(p)
}

func relation(a, b int64) string {
	if a < b {
		return "LT"
	}
	if a > b {
		return "GT"
	}
	return "EQ"
}

func (f *Format) nextUp(p Pattern) Pattern {
	if p == f.inf {
		return p
	}
	if f.zero(p) {
		return 1
	}
	if f.negative(p) {
		return p - 1
	}
	return p + 1
}

func summation(f *Format, words []string) (string, error) {
	command := words[0]
	mode, err := parseMode(words[2])
	if err != nil {
		return "", err
	}
	var values []Pattern
	leftCount := 0
	for _, word := range words[3:] {
		if word == "|" {
			leftCount = len(values)
			continue
		}
		value, err := f.operand(word)
		if err != nil {
			return "", err
		}
		values = append(values, value)
	}
	if command == "DOT" && leftCount != len(values)-leftCount {
		return "", fmt.Errorf("ERROR LENGTH MISMATCH")
	}
	for _, p := range values {
		if !f.finite(p) {
			return "", fmt.Errorf("ERROR NOT FINITE")
		}
	}
	var out strings.Builder
	if command == "DOT" {
		terms := make([]Term, leftCount)
		for i := range leftCount {
			terms[i] = f.term(values[i]).product(f.term(values[leftCount+i]))
		}
		exactSum := sumTerms(terms, mode)
		first := f.arithmetic(mul, values[0], values[leftCount], 0, mode)
		naive, chained := first, first
		for i := 1; i < leftCount; i++ {
			multiplied := f.arithmetic(mul, values[i], values[leftCount+i], 0, mode)
			added := f.arithmetic(add, naive.pattern, multiplied.pattern, 0, mode)
			naive = Rounded{added.pattern, naive.flags | multiplied.flags | added.flags}
		}
		for i := 1; i < leftCount; i++ {
			fused := f.arithmetic(fma, values[i], values[leftCount+i], chained.pattern, mode)
			chained = Rounded{fused.pattern, chained.flags | fused.flags}
		}
		fmt.Fprintf(&out, "DOT %s %s n=%d\n", f.name, mode, leftCount)
		fmt.Fprintf(&out, "NAIVE %s\nCHAINED %s\n", f.result(naive), f.result(chained))
		fmt.Fprintf(&out, "EXACT %s\nFUSED %s\n", exactSum.decimal(), f.result(f.roundTerm(exactSum, mode)))
		fmt.Fprintf(&out, "DIFF naive=%s chained=%s\n", f.difference(naive.pattern, exactSum), f.difference(chained.pattern, exactSum))
		return out.String(), nil
	}
	terms := make([]Term, len(values))
	for i, p := range values {
		terms[i] = f.term(p)
	}
	exactSum := sumTerms(terms, mode)
	result, compensation := Rounded{values[0], 0}, Pattern(0)
	fmt.Fprintf(&out, "%s %s %s count=%d\n", command, f.name, mode, len(values))
	for i := 1; i < len(values); i++ {
		if command == "SUM" {
			next := f.arithmetic(add, result.pattern, values[i], 0, mode)
			result = Rounded{next.pattern, result.flags | next.flags}
			fmt.Fprintf(&out, "PARTIAL %d %s\n", i+1, f.result(next))
		} else {
			y := f.arithmetic(sub, values[i], compensation, 0, mode)
			t := f.arithmetic(add, result.pattern, y.pattern, 0, mode)
			d := f.arithmetic(sub, t.pattern, result.pattern, 0, mode)
			c := f.arithmetic(sub, d.pattern, y.pattern, 0, mode)
			flags := y.flags | t.flags | d.flags | c.flags
			result, compensation = Rounded{t.pattern, result.flags | flags}, c.pattern
			fmt.Fprintf(&out, "KSTEP %d sum=%s comp=%s %s\n", i+1, f.value(result.pattern), f.value(compensation), flags)
		}
	}
	fmt.Fprintf(&out, "RESULT %s\nEXACT %s\n", f.result(result), exactSum.decimal())
	fmt.Fprintf(&out, "ROUNDED %s\nDIFF %s\n", f.result(f.roundTerm(exactSum, mode)), f.difference(result.pattern, exactSum))
	return out.String(), nil
}

func table(f *Format) (string, error) {
	if f.w > 8 {
		return "", fmt.Errorf("ERROR TABLE TOO LARGE")
	}
	var out strings.Builder
	fmt.Fprintf(&out, "TABLE %s count=%d\n", f.name, f.inf)
	for p := Pattern(0); p < f.inf; p++ {
		gap := "-"
		if p+1 < f.inf {
			previous := f.term(p)
			previous.negative = true
			gap = sumTerms([]Term{f.term(p + 1), previous}, rne).decimal()
		}
		fmt.Fprintf(&out, "ENTRY %d %s gap=%s\n", p, f.pattern(p), gap)
	}
	fmt.Fprintf(&out, "MAX %s\nMINNORMAL %s\nMINSUBNORMAL %s\n", f.pattern(f.inf-1), f.pattern(f.base), f.pattern(1))
	fmt.Fprintf(&out, "EPSILON %s\n", (Term{false, 1, -f.m}).decimal())
	fmt.Fprintf(&out, "PATTERNS finite=%d infinite=2 nan=%d total=%d\n", 2*f.inf, 2*(f.base-1), 2*f.sign)
	return out.String(), nil
}

func integerRange(word string) (int64, int64, error) {
	switch word {
	case "I8":
		return -128, 127, nil
	case "U8":
		return 0, 255, nil
	case "I16":
		return -32768, 32767, nil
	case "U16":
		return 0, 65535, nil
	case "I32":
		return -2147483648, 2147483647, nil
	case "U32":
		return 0, 4294967295, nil
	}
	return 0, 0, fmt.Errorf("ERROR BAD TYPE %s", word)
}

func findFormat(formats map[string]*Format, name string) (*Format, error) {
	if f := formats[name]; f != nil {
		return f, nil
	}
	return nil, fmt.Errorf("ERROR UNKNOWN FORMAT %s", name)
}

func execute(formats map[string]*Format, words []string) (string, error) {
	command := words[0]
	if command == "FORMAT" {
		if formats[words[1]] != nil {
			return "", fmt.Errorf("ERROR FORMAT EXISTS %s", words[1])
		}
		e, m := int(unsigned(words[2], 10)), int(unsigned(words[3], 10))
		if e < 2 || e > 5 || m < 1 || m > 10 {
			return "", fmt.Errorf("ERROR BAD FORMAT")
		}
		f := newFormat(words[1], e, m)
		formats[f.name] = f
		return fmt.Sprintf("FORMAT %s e=%d m=%d bits=%d bias=%d emin=%d emax=%d\n", f.name, e, m, f.w, f.bias, f.emin, f.emax), nil
	}
	f, err := findFormat(formats, words[1])
	if err != nil {
		return "", err
	}
	switch command {
	case "TABLE":
		return table(f)
	case "SUM", "KAHAN", "DOT":
		return summation(f, words)
	case "CONVERT":
		g, err := findFormat(formats, words[2])
		if err != nil {
			return "", err
		}
		a, err := f.operand(words[3])
		if err != nil {
			return "", err
		}
		mode, err := optionalMode(words, 4)
		if err != nil {
			return "", err
		}
		var result Rounded
		switch f.class(a) {
		case quietNaN:
			result = Rounded{g.nan, 0}
		case signalingNaN:
			result = Rounded{g.nan, invalid}
		case infinity:
			result = Rounded{g.signed(g.inf, f.negative(a)), 0}
		case zero:
			result = Rounded{g.signed(0, f.negative(a)), 0}
		default:
			result = g.roundTerm(f.term(a), mode)
		}
		return fmt.Sprintf("CONVERT %s %s %s %s\n", f.name, g.name, mode, g.result(result)), nil
	case "ENCODE":
		value, err := f.rawOperand(words[2], true)
		if err != nil {
			return "", err
		}
		mode, err := optionalMode(words, 3)
		if err != nil {
			return "", err
		}
		result := Rounded{value.pattern, 0}
		source := f.value(value.pattern)
		if value.number != nil {
			source = value.number.fraction()
			result = f.round(*value.number, mode, false)
		}
		return fmt.Sprintf("ENCODE %s %s %s %s\n", f.name, mode, source, f.result(result)), nil
	}
	a, err := f.operand(words[2])
	if err != nil {
		return "", err
	}
	switch command {
	case "DECODE":
		kind := f.class(a)
		exponent, fraction := a&(f.sign-1)>>f.m, a&(f.base-1)
		sign := 0
		if f.negative(a) {
			sign = 1
		}
		var out strings.Builder
		fmt.Fprintf(&out, "DECODE %s %s %s %s sign=%d\n", f.name, f.bits(a), f.hex(a), kind, sign)
		if f.finite(a) {
			term, leading := f.term(a), 0
			if kind == normal {
				leading = 1
			}
			fmt.Fprintf(&out, "FIELDS exponent=%d fraction=%d unbiased=%d significand=%d.%0*b\n", exponent, fraction, term.exponent+f.m, leading, f.m, fraction)
			fmt.Fprintf(&out, "VALUE %s %s\n", term.exact().fraction(), f.value(a))
		} else if kind == infinity {
			fmt.Fprintf(&out, "FIELDS exponent=%d fraction=%d\n", exponent, fraction)
		} else {
			fmt.Fprintf(&out, "FIELDS exponent=%d fraction=%d payload=%d\n", exponent, fraction, fraction%(f.base/2))
		}
		return out.String(), nil
	case "COMPARE":
		b, err := f.operand(words[3])
		if err != nil {
			return "", err
		}
		ak, bk := f.orderKey(a), f.orderKey(b)
		numeric := relation(ak, bk)
		if f.isNaN(a) || f.isNaN(b) {
			numeric = "UN"
		} else if f.zero(a) && f.zero(b) {
			numeric = "EQ"
		}
		var flags Flags
		if f.class(a) == signalingNaN || f.class(b) == signalingNaN {
			flags = invalid
		}
		return fmt.Sprintf("COMPARE %s %s %s %s total=%s %s\n", f.name, f.hex(a), f.hex(b), numeric, relation(ak, bk), flags), nil
	case "TOINT":
		minimum, maximum, err := integerRange(words[3])
		if err != nil {
			return "", err
		}
		mode, err := optionalMode(words, 4)
		if err != nil {
			return "", err
		}
		prefix := fmt.Sprintf("TOINT %s %s %s", f.name, words[3], mode)
		if !f.finite(a) {
			return prefix + " invalid flags=invalid\n", nil
		}
		value := f.term(a).exact()
		divided := quantize(value, 0, false)
		result := int64(divided.rounded(mode, value.negative))
		if value.negative {
			result = -result
		}
		if result < minimum || result > maximum {
			return prefix + " invalid flags=invalid\n", nil
		}
		var flags Flags
		if divided.inexact {
			flags = inexact
		}
		return fmt.Sprintf("%s %d %s\n", prefix, result, flags), nil
	case "NEXTUP", "NEXTDOWN", "ULP":
		var result Rounded
		if f.isNaN(a) {
			result.pattern = f.nan
			if f.class(a) == signalingNaN {
				result.flags = invalid
			}
		} else if command == "NEXTUP" {
			result.pattern = f.nextUp(a)
		} else if command == "NEXTDOWN" {
			result.pattern = f.nextUp(a^f.sign) ^ f.sign
		} else if f.class(a) == infinity {
			result.pattern = f.inf
		} else {
			result.pattern = f.roundTerm(Term{false, 1, f.term(a).exponent}, rne).pattern
		}
		return fmt.Sprintf("%s %s %s\n", command, f.name, f.result(result)), nil
	}
	operations := map[string]Operation{"ADD": add, "SUB": sub, "MUL": mul, "DIV": div, "SQRT": sqrt, "FMA": fma}
	operation, arity := operations[command], 2
	if operation == sqrt {
		arity = 1
	} else if operation == fma {
		arity = 3
	}
	var b, c Pattern
	if arity >= 2 {
		b, err = f.operand(words[3])
		if err != nil {
			return "", err
		}
	}
	if arity == 3 {
		c, err = f.operand(words[4])
		if err != nil {
			return "", err
		}
	}
	mode, err := optionalMode(words, arity+2)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%s %s %s %s\n", command, f.name, mode, f.result(f.arithmetic(operation, a, b, c, mode))), nil
}

func main() {
	input := bufio.NewScanner(os.Stdin)
	if !input.Scan() {
		return
	}
	count, _ := strconv.Atoi(input.Text())
	formats := map[string]*Format{
		"HALF": newFormat("HALF", 5, 10),
		"E5M2": newFormat("E5M2", 5, 2),
		"E4M3": newFormat("E4M3", 4, 3),
	}
	output := bufio.NewWriter(os.Stdout)
	defer output.Flush()
	for range count {
		input.Scan()
		response, err := execute(formats, strings.Fields(input.Text()))
		if err != nil {
			fmt.Fprintln(output, err)
		} else {
			fmt.Fprint(output, response)
		}
	}
}
