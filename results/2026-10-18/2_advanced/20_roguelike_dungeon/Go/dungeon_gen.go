package main

type Room struct{ X, Y, Width, Height int }

func (room Room) Center() Point { return Point{room.X + room.Width/2, room.Y + room.Height/2} }

type Region struct {
	X, Y, Width, Height int
	First, Second       *Region
	Leaf                int
}

type Level struct {
	Depth, Width, Height                        int
	Terrain, Memory                             [][]byte
	Rooms                                       []Room
	Arrival, Target                             Point
	ArrivalRoom                                 int
	Monsters                                    []*Monster
	Items                                       []*Item
	MonstersCreated, ItemsPlaced, Kills, Picked int
}

func newLevel(depth, width, height int) *Level {
	level := &Level{Depth: depth, Width: width, Height: height, Terrain: make([][]byte, height), Memory: make([][]byte, height)}
	for y := range height {
		level.Terrain[y] = make([]byte, width)
		level.Memory[y] = make([]byte, width)
		for x := range width {
			level.Terrain[y][x] = ' '
			level.Memory[y][x] = ' '
		}
	}
	return level
}
func (level *Level) MonsterAt(x, y int) *Monster {
	for _, monster := range level.Monsters {
		if monster.Position == (Point{x, y}) {
			return monster
		}
	}
	return nil
}
func (level *Level) ItemAt(x, y int) *Item {
	for _, item := range level.Items {
		if item.Position == (Point{x, y}) {
			return item
		}
	}
	return nil
}
func (level *Level) DrawInteriorCell(rng *Minstd, index int) Point {
	room := level.Rooms[index]
	x := room.X + 1 + rng.Rnd(room.Width-2)
	y := room.Y + 1 + rng.Rnd(room.Height-2)
	return Point{x, y}
}
func (level *Level) DrawRoomCell(rng *Minstd) (int, Point) {
	index := rng.Rnd(len(level.Rooms))
	return index, level.DrawInteriorCell(rng, index)
}

type LevelGenerator struct {
	RNG                                 *Minstd
	MinSize, MaxSplit, RoomMin, RoomMax int
}

func (generator *LevelGenerator) Generate(depth, width, height int) *Level {
	level := newLevel(depth, width, height)
	root := &Region{Width: width, Height: height, Leaf: -1}
	var leaves []*Region
	generator.split(root, 0, &leaves)
	for _, leaf := range leaves {
		level.Rooms = append(level.Rooms, generator.makeRoom(level, leaf))
	}
	generator.connect(level, root)
	room, point := level.DrawRoomCell(generator.RNG)
	level.Terrain[point.Y][point.X] = '<'
	level.Arrival, level.ArrivalRoom = point, room
	other := generator.RNG.Rnd(len(level.Rooms) - 1)
	if other >= room {
		other++
	}
	level.Target = level.DrawInteriorCell(generator.RNG, other)
	return level
}
func (generator *LevelGenerator) split(region *Region, depth int, leaves *[]*Region) {
	cv, ch := region.Width >= 2*generator.MinSize, region.Height >= 2*generator.MinSize
	if depth == generator.MaxSplit || (!cv && !ch) {
		region.Leaf = len(*leaves)
		*leaves = append(*leaves, region)
		return
	}
	vertical := cv
	if cv && ch {
		if 4*region.Width >= 5*region.Height {
			vertical = true
		} else if 4*region.Height >= 5*region.Width {
			vertical = false
		} else {
			vertical = generator.RNG.Rnd(2) == 0
		}
	}
	if vertical {
		cut := generator.MinSize + generator.RNG.Rnd(region.Width-2*generator.MinSize+1)
		region.First = &Region{X: region.X, Y: region.Y, Width: cut, Height: region.Height, Leaf: -1}
		region.Second = &Region{X: region.X + cut, Y: region.Y, Width: region.Width - cut, Height: region.Height, Leaf: -1}
	} else {
		cut := generator.MinSize + generator.RNG.Rnd(region.Height-2*generator.MinSize+1)
		region.First = &Region{X: region.X, Y: region.Y, Width: region.Width, Height: cut, Leaf: -1}
		region.Second = &Region{X: region.X, Y: region.Y + cut, Width: region.Width, Height: region.Height - cut, Leaf: -1}
	}
	generator.split(region.First, depth+1, leaves)
	generator.split(region.Second, depth+1, leaves)
}
func (generator *LevelGenerator) makeRoom(level *Level, region *Region) Room {
	width := generator.RoomMin + generator.RNG.Rnd(min(generator.RoomMax, region.Width-1)-generator.RoomMin+1)
	height := generator.RoomMin + generator.RNG.Rnd(min(generator.RoomMax, region.Height-1)-generator.RoomMin+1)
	x := region.X + generator.RNG.Rnd(region.Width-width)
	y := region.Y + generator.RNG.Rnd(region.Height-height)
	for row := y; row < y+height; row++ {
		for column := x; column < x+width; column++ {
			terrain := byte('.')
			if row == y || row == y+height-1 {
				terrain = '-'
			} else if column == x || column == x+width-1 {
				terrain = '|'
			}
			level.Terrain[row][column] = terrain
		}
	}
	return Room{x, y, width, height}
}
func (generator *LevelGenerator) connect(level *Level, region *Region) []int {
	if region.Leaf >= 0 {
		return []int{region.Leaf}
	}
	first := generator.connect(level, region.First)
	second := generator.connect(level, region.Second)
	aBest, bBest, bestDistance := -1, -1, 0
	for _, a := range first {
		for _, b := range second {
			pa, pb := level.Rooms[a].Center(), level.Rooms[b].Center()
			distance := abs(pa.X-pb.X) + abs(pa.Y-pb.Y)
			if aBest < 0 || distance < bestDistance {
				aBest, bBest, bestDistance = a, b, distance
			}
		}
	}
	generator.dig(level, level.Rooms[aBest].Center(), level.Rooms[bBest].Center(), generator.RNG.Rnd(2) == 0)
	return append(first, second...)
}
func (generator *LevelGenerator) dig(level *Level, start, end Point, horizontal bool) {
	digCell := func(x, y int) {
		switch level.Terrain[y][x] {
		case ' ':
			level.Terrain[y][x] = '#'
		case '-', '|':
			level.Terrain[y][x] = '+'
		}
	}
	horizontalLeg := func(y, x0, x1 int) {
		step := 1
		if x1 < x0 {
			step = -1
		}
		for x := x0; ; x += step {
			digCell(x, y)
			if x == x1 {
				break
			}
		}
	}
	verticalLeg := func(x, y0, y1 int) {
		step := 1
		if y1 < y0 {
			step = -1
		}
		for y := y0; ; y += step {
			digCell(x, y)
			if y == y1 {
				break
			}
		}
	}
	if horizontal {
		horizontalLeg(start.Y, start.X, end.X)
		verticalLeg(end.X, start.Y, end.Y)
	} else {
		verticalLeg(start.X, start.Y, end.Y)
		horizontalLeg(end.Y, start.X, end.X)
	}
}
