package main

func squaredDistance(first, second Point) int {
	dx, dy := first.X-second.X, first.Y-second.Y
	return dx*dx + dy*dy
}
func integerSqrt(number int) int {
	low, high := 0, number+1
	for high-low > 1 {
		middle := (low + high) / 2
		if middle <= number/middle {
			low = middle
		} else {
			high = middle
		}
	}
	return low
}
func advance(point, goal Point, step int) (Point, bool) {
	dx, dy := goal.X-point.X, goal.Y-point.Y
	squared := dx*dx + dy*dy
	if squared <= step*step {
		return goal, true
	}
	length := integerSqrt(squared)
	return Point{point.X + dx*step/length, point.Y + dy*step/length}, false
}
func damageDealt(hp, power, armor int) int { return min(hp, max(1, power-armor)) }

type Effect struct {
	Strength, Remaining int
	Source              *Tower
}

func (e *Effect) Active() bool { return e.Remaining > 0 }
func (e *Effect) Receive(strength, duration int, source *Tower) {
	if strength > e.Strength {
		e.Strength, e.Remaining, e.Source = strength, duration, source
	} else if strength == e.Strength {
		e.Remaining = max(e.Remaining, duration)
	}
}
func (e *Effect) AdvanceTime() {
	e.Remaining--
	if e.Remaining == 0 {
		e.Strength = 0
		e.Source = nil
	}
}

type Projectile struct {
	Number                                                         int
	Tower                                                          *Tower
	Target                                                         *Enemy
	Position, Aim                                                  Point
	Targets                                                        string
	Power, Speed, Splash, SlowRate, SlowTime, BurnAmount, BurnTime int
}

func (p *Projectile) Fly() bool {
	if p.Speed == 0 {
		return true
	}
	point, arrived := advance(p.Position, p.Aim, p.Speed)
	p.Position = point
	return arrived
}
