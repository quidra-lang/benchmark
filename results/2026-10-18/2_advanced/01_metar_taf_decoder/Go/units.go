package main

import "fmt"

func floorDiv(n, d int64) int64 {
	q := n/d
	if n < 0 && n%d != 0 {
		q--
	}
	return q
}
func abs(n int64) int64 {
	if n < 0 {
		return -n
	}
	return n
}
func pad(n int64, width int) string {
	return fmt.Sprintf("%0*d", width, n)
}

var sine = [...]int64{0, 174, 342, 500, 643, 766, 866, 940, 985, 1000}

func sin(a int64) int64 {
	y := (a%360+360)%360
	switch {
	case y <= 90: return sine[y/10]
	case y <= 180: return sine[(180-y)/10]
	case y <= 270: return -sine[(y-180)/10]
	default: return -sine[(360-y)/10]
	}
}
func knots(v int64) int64 {
	return (v*1944+500)/1000
}
func inHg(v int64) int64 {
	return (v*2953+500)/1000
}
func hPa(v int64) int64 {
	return (v*33864+50000)/100000
}

func daysInMonth(y, m int64) int64 {
	if m == 2 {
		if y%4 == 0 && (y%100 != 0 || y%400 == 0) {
			return 29
		}
		return 28
	}
	if m == 4 || m == 6 || m == 9 || m == 11 {
		return 30
	}
	return 31
}

type Calendar struct {
	year, month, days, nextYear, nextMonth, nextDays	int64
}

func newCalendar(y, m int64) Calendar {
	ny, nm := y, m+1
	if m == 12 {
		ny++
		nm = 1
	}
	return Calendar{y, m, daysInMonth(y, m), ny, nm, daysInMonth(ny, nm)}
}
func (c Calendar) observation(w string) int64 {
	m := match(`^(\d{2})(\d{2})(\d{2})Z$`, w)
	if m == nil {
		return -1
	}
	d, h, n := number(m[1]), number(m[2]), number(m[3])
	if d < 1 || d > c.days || h > 23 || n > 59 {
		return -1
	}
	return ((d-1)*24+h)*60+n
}
func (c Calendar) dayTime(d, h, m, issueDay int64) int64 {
	limit, offset := c.days, int64(0)
	if d < issueDay {
		limit, offset = c.nextDays, c.days*1440
	}
	if d < 1 || d > limit {
		return -1
	}
	return offset+((d-1)*24+h)*60+m
}
func (c Calendar) period(w string, issueDay, maximum int64) (int64, int64, bool) {
	m := match(`^(\d{2})(\d{2})/(\d{2})(\d{2})$`, w)
	if m == nil {
		return 0, 0, false
	}
	d, h, e, k := number(m[1]), number(m[2]), number(m[3]), number(m[4])
	if h > 23 || k < 1 || k > 24 {
		return 0, 0, false
	}
	s, t := c.dayTime(d, h, 0, issueDay), c.dayTime(e, k, 0, issueDay)
	return s, t, s >= 0 && t > s && (maximum == 0 || t-s <= maximum)
}
func (c Calendar) changeTime(w string, issueDay int64) int64 {
	m := match(`^FM(\d{2})(\d{2})(\d{2})$`, w)
	if m == nil {
		return -1
	}
	h, n := number(m[2]), number(m[3])
	if h > 23 || n > 59 {
		return -1
	}
	return c.dayTime(number(m[1]), h, n, issueDay)
}
func (c Calendar) stamp(t int64) string {
	y, m := c.year, c.month
	if t >= c.days*1440 {
		t -= c.days*1440
		y, m = c.nextYear, c.nextMonth
	}
	return fmt.Sprintf("%04d-%02d-%02dT%02d:%02dZ", y, m, t/1440+1, t%1440/60, t%60)
}

func mileFraction(v *Value) (int64, int64) {
	if v.kind == "mile" {
		return v.whole*v.den+v.num, v.den
	}
	return v.meters*1000, 1609344
}
func meterValue(v *Value) int64 {
	if v.kind != "mile" {
		return v.meters
	}
	n, d := mileFraction(v)
	return 1609344*n/(1000*d)
}
func compareVisibility(a, b *Value) int64 {
	n, d := mileFraction(a)
	x, y := mileFraction(b)
	return n*y-x*d
}
func fraction(n, d int64) string {
	if d == 0 {
		return "undefined"
	}
	a, b := abs(n), d
	for b != 0 {
		a, b = b, a%b
	}
	return fmt.Sprintf("%d/%d", n/a, d/a)
}
