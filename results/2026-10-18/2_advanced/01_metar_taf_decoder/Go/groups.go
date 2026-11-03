package main

import (
	"regexp"
	"strconv"
	"strings"
)

var descriptors = map[string]string{
	"MI": "shallow", "BC": "patches", "PR": "partial", "DR": "low drifting",
	"BL": "blowing", "SH": "showers", "TS": "thunderstorm", "FZ": "freezing",
}
var phenomena = map[string]string{
	"DZ": "drizzle", "RA": "rain", "SN": "snow", "SG": "snow grains", "IC": "ice crystals",
	"PL": "ice pellets", "GR": "hail", "GS": "small hail", "UP": "unknown precipitation",
	"BR": "mist", "FG": "fog", "FU": "smoke", "VA": "volcanic ash", "DU": "dust", "SA": "sand",
	"HZ": "haze", "PY": "spray", "PO": "dust whirls", "SQ": "squalls", "FC": "funnel cloud",
	"SS": "sandstorm", "DS": "duststorm",
}
var amounts = map[string]string{"FEW": "few", "SCT": "scattered", "BKN": "broken", "OVC": "overcast"}
var clearCloud = map[string]string{"SKC": "sky clear", "CLR": "clear below 12000 ft", "NSC": "no significant cloud"}
var intensities = map[string]string{"-": "light", "+": "heavy", "VC": "nearby"}

func precipitation(s string) bool {
	return strings.Contains("|DZ|RA|SN|SG|IC|PL|GR|GS|UP|", "|"+s+"|")
}
func match(pattern, s string) []string {
	return regexp.MustCompile(pattern).FindStringSubmatch(s)
}
func number(s string) int64 {
	n, _ := strconv.ParseInt(s, 10, 64)
	return n
}

// Value contains the fields used by its recognized group kind; -1 denotes no gust.
type Value struct {
	raw, kind, unit, qualifier, qualifier2, runway, trend, amount, suffix, intensity, descriptor		string
	direction, speed, gust, first, second, whole, num, den, meters, height, temp, dew, value, inches, hecto	int64
	variable, calm, mixed, fractional, nsw, hasSecond							bool
	codes													[]string
}

func format(kind, text string) *Value {
	v := &Value{raw: text, gust: -1}
	var m []string
	switch kind {
	case "modifier":
		if text != "AUTO" && text != "COR" {
			return nil
		}
	case "wind":
		m = match(`^(\d{3}|VRB)(\d{2,3})(?:G(\d{2,3}))?(KT|MPS)$`, text)
		if m == nil {
			return nil
		}
		v.variable = m[1] == "VRB"
		v.direction = number(m[1])
		v.calm = m[1] == "000"
		v.speed = number(m[2])
		if m[3] != "" {
			v.gust = number(m[3])
		}
		v.unit = m[4]
	case "variation":
		m = match(`^(\d{3})V(\d{3})$`, text)
		if m == nil {
			return nil
		}
		v.first, v.second = number(m[1]), number(m[2])
	case "visibility":
		if text == "CAVOK" {
			v.kind, v.meters, v.qualifier = "cavok", 10000, "P"
			return v
		}
		if match(`^\d{4}$`, text) != nil {
			v.kind, v.meters = "meter", number(text)
			if v.meters == 9999 {
				v.meters, v.qualifier = 10000, "P"
			}
			return v
		}
		v.kind, v.den = "mile", 1
		m = match(`^(\d) (\d)/(\d{1,2})SM$`, text)
		if m != nil {
			v.whole, v.num, v.den = number(m[1]), number(m[2]), number(m[3])
			v.mixed, v.fractional = true, true
			return v
		}
		m = match(`^([MP]?)(?:(\d{1,2})|(\d)/(\d{1,2}))SM$`, text)
		if m == nil {
			return nil
		}
		v.qualifier, v.whole = m[1], number(m[2])
		if m[3] != "" {
			v.fractional = true
			v.num, v.den = number(m[3]), number(m[4])
		}
	case "rvr":
		m = match(`^R(\d{2}[LCR]?)/([MP]?)(\d{4})(?:V([MP]?)(\d{4}))?(FT)?([UDN])?$`, text)
		if m == nil {
			return nil
		}
		v.runway, v.qualifier, v.first = m[1], m[2], number(m[3])
		v.hasSecond = m[5] != ""
		v.qualifier2, v.second = m[4], number(m[5])
		v.unit = "m"
		if m[6] != "" {
			v.unit = "ft"
		}
		v.trend = m[7]
	case "weather":
		if text == "NSW" {
			v.nsw = true
			return v
		}
		s := text
		if strings.HasPrefix(s, "VC") {
			v.intensity, s = "VC", s[2:]
		} else if strings.HasPrefix(s, "-") || strings.HasPrefix(s, "+") {
			v.intensity, s = s[:1], s[1:]
		}
		if len(s) == 0 || len(s)%2 != 0 {
			return nil
		}
		codes := []string{}
		for i := 0; i < len(s); i += 2 {
			code := s[i:i+2]
			if descriptors[code] == "" && phenomena[code] == "" {
				return nil
			}
			codes = append(codes, code)
		}
		if descriptors[codes[0]] != "" {
			v.descriptor, codes = codes[0], codes[1:]
		}
		v.codes = codes
	case "cloud":
		if clearCloud[text] != "" {
			v.amount = text
			return v
		}
		m = match(`^(FEW|SCT|BKN|OVC)(\d{3})(CB|TCU)?$`, text)
		if m != nil {
			v.amount, v.height, v.suffix = m[1], number(m[2])*100, m[3]
			return v
		}
		m = match(`^VV(\d{3})$`, text)
		if m == nil {
			return nil
		}
		v.amount, v.height = "VV", number(m[1])*100
	case "temperature":
		m = match(`^(M?)(\d{2})/(M?)(\d{2})$`, text)
		if m == nil {
			return nil
		}
		v.temp, v.dew = number(m[2]), number(m[4])
		if m[1] != "" {
			v.temp = -v.temp
		}
		if m[3] != "" {
			v.dew = -v.dew
		}
	case "pressure":
		m = match(`^([AQ])(\d{4})$`, text)
		if m == nil {
			return nil
		}
		v.unit, v.value = m[1], number(m[2])
	case "noTrend":
		if text != "NOSIG" {
			return nil
		}
	default:
		return nil
	}
	return v
}

func valid(kind string, v *Value, s *Section, station *Station) bool {
	switch kind {
	case "wind":
		if v.variable {
			if v.speed < 1 {
				return false
			}
		} else if v.direction > 360 || v.direction%10 != 0 || (v.direction == 0) != (v.speed == 0) {
			return false
		}
		return v.gust < 0 || !v.calm && v.gust > v.speed
	case "variation":
		return v.first >= 10 && v.first <= 360 && v.first%10 == 0 && v.second >= 10 && v.second <= 360 &&
			v.second%10 == 0 && v.first != v.second && s.wind != nil && !s.wind.variable && !s.wind.calm
	case "visibility":
		if v.kind != "mile" {
			return true
		}
		if !v.fractional {
			return v.whole >= 1
		}
		return (v.den == 2 || v.den == 4 || v.den == 8 || v.den == 16) && v.num >= 1 && v.num < v.den && (!v.mixed || v.whole >= 1)
	case "rvr":
		exists := false
		for _, r := range station.runways {
			if r.name == v.runway {
				exists = true
			}
		}
		return exists && (!v.hasSecond || v.first < v.second)
	case "weather":
		if len(s.weather) >= 3 {
			return false
		}
		for _, w := range s.weather {
			if w.nsw {
				return false
			}
		}
		if v.nsw {
			return len(s.weather) == 0 && (s.context == "trend" || s.context == "change")
		}
		seen := map[string]bool{}
		anyPrecip, allPrecip := false, true
		for _, p := range v.codes {
			if phenomena[p] == "" || seen[p] {
				return false
			}
			seen[p] = true
			anyPrecip = anyPrecip || precipitation(p)
			allPrecip = allPrecip && precipitation(p)
		}
		if len(v.codes) == 0 && v.descriptor != "TS" && v.descriptor != "SH" {
			return false
		}
		return (v.intensity != "-" && v.intensity != "+" || anyPrecip) && (len(v.codes) < 2 || allPrecip)
	case "cloud":
		if len(s.cloud) > 0 {
			last := s.cloud[len(s.cloud)-1]
			return amounts[v.amount] != "" && amounts[last.amount] != "" && v.height > last.height
		}
	case "temperature":
		return v.dew <= v.temp
	case "pressure":
		if v.unit == "A" {
			return v.value >= 2500 && v.value <= 3150
		}
		return v.value >= 850 && v.value <= 1070
	}
	return true
}

func accept(s *Section, kind string, v *Value) {
	switch kind {
	case "modifier": s.modifier = v
	case "wind":
		if v.unit == "MPS" {
			v.speed = knots(v.speed)
			if v.gust >= 0 {
				v.gust = knots(v.gust)
			}
		}
		s.wind = v
	case "variation": s.variation = v
	case "visibility":
		s.visibility = v
		if v.kind == "cavok" {
			s.weather, s.cloud = []*Value{}, []*Value{}
		}
	case "rvr": s.rvr = append(s.rvr, v)
	case "weather": s.weather = append(s.weather, v)
	case "cloud": s.cloud = append(s.cloud, v)
	case "temperature": s.temperature = v
	case "pressure":
		v.inches, v.hecto = v.value, v.value
		if v.unit == "Q" {
			v.inches = inHg(v.value)
		} else {
			v.hecto = hPa(v.value)
		}
		s.pressure = v
	case "noTrend": s.noTrend = true
	}
}
