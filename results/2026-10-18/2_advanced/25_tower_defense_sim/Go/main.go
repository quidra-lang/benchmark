package main

import (
	"fmt"
	"os"
	"slices"
	"strconv"
	"strings"
)

const waveColumns = "wave,start,end,status,spawned,peak,kills,leaks,lives_lost,bounty,reward,interest,gold,lives"

var incomeFields = []string{"bounty", "reward", "interest", "early", "refund"}

func integer(text string) int { value, _ := strconv.Atoi(text); return value }
func readLines(name string) []string {
	data, err := os.ReadFile("input/" + name)
	if err != nil {
		panic(err)
	}
	if len(data) == 0 {
		return []string{}
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
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
func oneDecimal(numerator, denominator int) string {
	if denominator == 0 {
		return "-"
	}
	rounded := (20*numerator + denominator) / (2 * denominator)
	return fmt.Sprintf("%d.%d", rounded/10, rounded%10)
}
func digit(count int) byte {
	if count == 0 {
		return '.'
	}
	if count <= 9 {
		return byte('0' + count)
	}
	return '*'
}
func ruled(rows [][]byte) []string {
	ruler := make([]byte, len(rows[0]))
	for x := range ruler {
		ruler[x] = byte('0' + x%10)
	}
	lines := []string{"  " + string(ruler)}
	for y, row := range rows {
		lines = append(lines, fmt.Sprintf("%d %s", y%10, string(row)))
	}
	return lines
}
func towerID(number int) string { return "T" + strconv.Itoa(number) }
func enemyID(number int) string { return "E" + strconv.Itoa(number) }

type Params struct {
	Gold, Lives, InterestRate, InterestCap, SellRate, Start, Interval, Early int
	Snapshots                                                                map[int]bool
}

func newParams(lines []string) Params {
	fields := make([][]string, len(lines))
	for i, line := range lines {
		fields[i] = strings.Fields(line)
	}
	params := Params{integer(fields[0][1]), integer(fields[1][1]), integer(fields[2][1]), integer(fields[2][2]), integer(fields[3][1]), integer(fields[4][1]), integer(fields[4][2]), integer(fields[5][1]), map[int]bool{}}
	for _, value := range fields[6][1:] {
		params.Snapshots[integer(value)] = true
	}
	return params
}

type Action struct {
	Tick      int
	Command   string
	Arguments []string
}

func newAction(line string) Action {
	fields := strings.Fields(line)
	return Action{integer(fields[0]), fields[1], fields[2:]}
}

type WaveRecord struct {
	Number                                                                        int
	Plan                                                                          *Wave
	Start, End                                                                    int
	Status                                                                        string
	Released                                                                      []int
	Spawned, Peak, Kills, Leaks, LivesLost, Bounty, Reward, Interest, Gold, Lives int
	TowerDamage                                                                   map[int]int
}

func newWaveRecord(number int, plan *Wave, start int) *WaveRecord {
	return &WaveRecord{Number: number, Plan: plan, Start: start, Released: make([]int, len(plan.Groups)), TowerDamage: map[int]int{}}
}
func (w *WaveRecord) AllReleased() bool {
	for i, group := range w.Plan.Groups {
		if w.Released[i] != group.Count {
			return false
		}
	}
	return true
}
func (w *WaveRecord) Close(status string, tick, gold, lives int) {
	w.Status, w.End, w.Gold, w.Lives = status, tick, gold, lives
}
func (w *WaveRecord) CSVRow(towerCount int) string {
	values := []string{strconv.Itoa(w.Number), strconv.Itoa(w.Start), strconv.Itoa(w.End), w.Status, strconv.Itoa(w.Spawned), strconv.Itoa(w.Peak), strconv.Itoa(w.Kills), strconv.Itoa(w.Leaks), strconv.Itoa(w.LivesLost), strconv.Itoa(w.Bounty), strconv.Itoa(w.Reward), strconv.Itoa(w.Interest), strconv.Itoa(w.Gold), strconv.Itoa(w.Lives)}
	for number := 1; number <= towerCount; number++ {
		values = append(values, strconv.Itoa(w.TowerDamage[number]))
	}
	return strings.Join(values, ",")
}

type Game struct {
	Grid                        *GridMap
	TowerTypes                  map[string]*TowerType
	EnemyTypes                  []*EnemyType
	Waves                       []*Wave
	Params                      Params
	ExitCenter                  Point
	Tick, Gold, Lives           int
	Towers                      []*Tower
	Enemies                     []*Enemy
	EnemyCount, ProjectileCount int
	Projectiles                 []*Projectile
	Records                     []*WaveRecord
	Active                      *WaveRecord
	NextStart                   int
	Outcome                     string
	Field                       *DistanceField
	KillCounts                  []int
	Income                      map[string]int
	Spent, Done, Refused        int
	Events, Snapshots           []string
}

func newGame(grid *GridMap, towerTypes []*TowerType, enemyTypes []*EnemyType, waves []*Wave, params Params) *Game {
	game := &Game{Grid: grid, TowerTypes: map[string]*TowerType{}, EnemyTypes: enemyTypes, Waves: waves, Params: params, ExitCenter: cellCenter(grid.Exit), Gold: params.Gold, Lives: params.Lives, NextStart: params.Start, Field: newDistanceField(grid, map[Point]bool{}), KillCounts: make([]int, grid.Width*grid.Height), Income: map[string]int{}}
	for _, kind := range towerTypes {
		game.TowerTypes[kind.Name] = kind
	}
	return game
}
func (g *Game) Record(parts ...any) {
	fields := []string{strconv.Itoa(g.Tick)}
	for _, part := range parts {
		fields = append(fields, fmt.Sprint(part))
	}
	g.Events = append(g.Events, strings.Join(fields, " "))
}
func (g *Game) Run(actions []Action) {
	index := 0
	for {
		g.Tick++
		for index < len(actions) && actions[index].Tick == g.Tick {
			g.Perform(actions[index])
			index++
		}
		g.SpawnEnemies()
		g.MoveEnemies()
		if g.Outcome != "" {
			break
		}
		g.FireTowers()
		g.MoveProjectiles()
		g.CheckWaveEnd()
		if g.Params.Snapshots[g.Tick] {
			g.Snapshots = append(g.Snapshots, g.Block("SNAPSHOT")...)
		}
		if g.Outcome != "" {
			break
		}
	}
	g.Snapshots = append(g.Snapshots, g.FinalBlock()...)
}
func (g *Game) StandingTowers() []*Tower {
	towers := []*Tower{}
	for _, tower := range g.Towers {
		if tower.Standing() {
			towers = append(towers, tower)
		}
	}
	return towers
}
func (g *Game) TowerCells() map[Point]bool {
	cells := map[Point]bool{}
	for _, tower := range g.StandingTowers() {
		cells[tower.Cell] = true
	}
	return cells
}
func (g *Game) TowerAt(cell Point) *Tower {
	for _, tower := range g.Towers {
		if tower.Standing() && tower.Cell == cell {
			return tower
		}
	}
	return nil
}
func (g *Game) StandingTower(text string) *Tower {
	number := integer(text)
	if number >= 1 && number <= len(g.Towers) && g.Towers[number-1].Standing() {
		return g.Towers[number-1]
	}
	return nil
}
func (g *Game) GroundEnemies() []*Enemy {
	enemies := []*Enemy{}
	for _, enemy := range g.Enemies {
		if !enemy.Flying() {
			enemies = append(enemies, enemy)
		}
	}
	return enemies
}
func (g *Game) Perform(action Action) {
	done := false
	switch action.Command {
	case "BUILD":
		done = g.Build(action.Arguments)
	case "UPGRADE":
		done = g.Upgrade(action.Arguments)
	case "SELL":
		done = g.Sell(action.Arguments)
	case "TARGET":
		done = g.SetTarget(action.Arguments)
	case "CALL":
		done = g.CallWave()
	}
	if done {
		g.Done++
	} else {
		g.Refused++
	}
}
func (g *Game) BuildRefusal(name string, cell Point) string {
	kind := g.TowerTypes[name]
	if kind == nil {
		return "type"
	}
	if !g.Grid.Inside(cell) {
		return "bounds"
	}
	if !g.Grid.Buildable(cell) {
		return "terrain"
	}
	if g.TowerAt(cell) != nil {
		return "tower"
	}
	if g.Gold < kind.Levels[0].Cost {
		return "gold"
	}
	walkers := g.GroundEnemies()
	for _, enemy := range walkers {
		if enemy.Cell == cell || enemy.NextCell == cell {
			return "enemy"
		}
	}
	cells := g.TowerCells()
	cells[cell] = true
	trial := newDistanceField(g.Grid, cells)
	for _, spawn := range g.Grid.Spawns {
		if trial.At(spawn) < 0 {
			return "blocked"
		}
	}
	for _, enemy := range walkers {
		if trial.At(enemy.NextCell) < 0 {
			return "blocked"
		}
	}
	return ""
}
func (g *Game) Build(arguments []string) bool {
	name := arguments[0]
	cell := Point{integer(arguments[1]), integer(arguments[2])}
	reason := g.BuildRefusal(name, cell)
	if reason != "" {
		g.Record("BUILD_REFUSED", name, arguments[1], arguments[2], reason)
		return false
	}
	kind := g.TowerTypes[name]
	cost := kind.Levels[0].Cost
	tower := newTower(len(g.Towers)+1, kind, cell, g.Tick)
	g.Towers = append(g.Towers, tower)
	g.Gold -= cost
	g.Spent += cost
	g.Record("BUILD", towerID(tower.Number), name, cell.X, cell.Y, "cost", cost, "gold", g.Gold)
	g.UpdateField()
	return true
}
func (g *Game) Upgrade(arguments []string) bool {
	tower := g.StandingTower(arguments[0])
	reason := ""
	if tower == nil {
		reason = "notower"
	} else if tower.Level == len(tower.Kind.Levels) {
		reason = "maxlevel"
	} else if g.Gold < tower.Kind.Levels[tower.Level].Cost {
		reason = "gold"
	} else {
		cost := tower.Kind.Levels[tower.Level].Cost
		g.Gold -= cost
		g.Spent += cost
		tower.Level++
		tower.Investment += cost
		g.Record("UPGRADE", towerID(tower.Number), "level", tower.Level, "cost", cost, "gold", g.Gold)
		return true
	}
	g.Record("UPGRADE_REFUSED", "T"+arguments[0], reason)
	return false
}
func (g *Game) Sell(arguments []string) bool {
	tower := g.StandingTower(arguments[0])
	if tower == nil {
		g.Record("SELL_REFUSED", "T"+arguments[0], "notower")
		return false
	}
	rate := g.Params.SellRate
	if g.Tick == tower.Built {
		rate = 100
	}
	refund := tower.Investment * rate / 100
	tower.Sold = g.Tick
	g.Gold += refund
	g.Income["refund"] += refund
	g.Record("SELL", towerID(tower.Number), "refund", refund, "gold", g.Gold)
	g.UpdateField()
	return true
}
func (g *Game) SetTarget(arguments []string) bool {
	tower := g.StandingTower(arguments[0])
	reason := ""
	if tower == nil {
		reason = "notower"
	} else if !slices.Contains(targetModes, arguments[1]) {
		reason = "mode"
	} else {
		tower.Mode = arguments[1]
		g.Record("TARGET", towerID(tower.Number), tower.Mode)
		return true
	}
	g.Record("TARGET_REFUSED", "T"+arguments[0], reason)
	return false
}
func (g *Game) CallWave() bool {
	if g.Active != nil {
		g.Record("CALL_REFUSED", "active")
		return false
	}
	bonus := (g.NextStart - g.Tick) * g.Params.Early
	g.Gold += bonus
	g.Income["early"] += bonus
	g.NextStart = g.Tick
	g.Record("CALL", len(g.Records)+1, "bonus", bonus, "gold", g.Gold)
	return true
}
func (g *Game) UpdateField() {
	before := g.Field
	g.Field = newDistanceField(g.Grid, g.TowerCells())
	for i, spawn := range g.Grid.Spawns {
		old, current := before.At(spawn), g.Field.At(spawn)
		if old != current {
			g.Record("REPATH", i+1, old, current)
		}
	}
}
func (g *Game) StartWave() {
	plan := g.Waves[len(g.Records)]
	wave := newWaveRecord(len(g.Records)+1, plan, g.Tick)
	g.Records = append(g.Records, wave)
	g.Active = wave
	g.NextStart = 0
	g.Record("WAVE_START", wave.Number, "enemies", plan.EnemyCount())
}
func (g *Game) AddEnemy(enemy *Enemy) {
	g.Enemies = append(g.Enemies, enemy)
	g.EnemyCount++
	g.Active.Spawned++
	enemy.Kind.Spawned++
}
func (g *Game) RemoveEnemy(enemy *Enemy) {
	enemy.Alive = false
	for i, current := range g.Enemies {
		if current == enemy {
			g.Enemies = append(g.Enemies[:i], g.Enemies[i+1:]...)
			return
		}
	}
}
func (g *Game) SpawnEnemies() {
	if g.Tick == g.NextStart {
		g.StartWave()
	}
	wave := g.Active
	if wave == nil {
		return
	}
	for i, group := range wave.Plan.Groups {
		released := wave.Released[i]
		if released == group.Count || group.SpawnTick(wave.Start, released) != g.Tick {
			continue
		}
		wave.Released[i]++
		spawn := g.Grid.Spawns[group.Spawn-1]
		enemy := newEnemy(g.EnemyCount+1, group.Kind, group.Multiplier)
		if enemy.Flying() {
			enemy.Point = cellCenter(spawn)
		} else {
			enemy.Cell = spawn
			enemy.NextCell = g.Field.Next(spawn)
		}
		g.AddEnemy(enemy)
		g.Record("SPAWN", enemyID(enemy.Number), enemy.Kind.Name, group.Spawn, "hp", enemy.HP)
	}
	wave.Peak = max(wave.Peak, len(g.Enemies))
}
func (g *Game) MoveEnemies() {
	moving := append([]*Enemy(nil), g.Enemies...)
	for _, enemy := range moving {
		g.MoveEnemy(enemy)
		if g.Outcome != "" {
			return
		}
	}
}
func (g *Game) MoveEnemy(enemy *Enemy) {
	if enemy.Burn.Active() {
		source := enemy.Burn.Source
		damage := min(enemy.HP, enemy.Burn.Strength)
		enemy.HP -= damage
		g.Credit(source, enemy, damage)
		enemy.Burn.AdvanceTime()
		if enemy.HP == 0 {
			g.Kill(enemy, source)
			return
		}
	}
	enemy.HP = min(enemy.HP+enemy.Kind.Regen, enemy.MaxHP)
	speed := enemy.SlowedSpeed()
	if enemy.Slow.Active() {
		enemy.Slow.AdvanceTime()
	}
	arrived := false
	if enemy.Flying() {
		enemy.Point, arrived = advance(enemy.Point, g.ExitCenter, speed)
	} else {
		arrived = g.Walk(enemy, speed)
	}
	if arrived {
		g.Leak(enemy)
	}
}
func (g *Game) Walk(enemy *Enemy, speed int) bool {
	if g.Grid.Water(enemy.OccupiedCell()) {
		speed /= 2
	}
	for speed > 0 {
		rest := 100 - enemy.Progress
		if speed < rest {
			enemy.Progress += speed
			speed = 0
		} else {
			speed -= rest
			enemy.Cell = enemy.NextCell
			enemy.Progress = 0
			if enemy.Cell == g.Grid.Exit {
				return true
			}
			enemy.NextCell = g.Field.Next(enemy.Cell)
		}
	}
	return false
}
func (g *Game) Leak(enemy *Enemy) {
	g.RemoveEnemy(enemy)
	lost := min(g.Lives, enemy.Kind.Lives)
	g.Lives -= lost
	wave := g.Active
	wave.Leaks++
	wave.LivesLost += lost
	enemy.Kind.Leaks++
	g.Record("LEAK", enemyID(enemy.Number), enemy.Kind.Name, "lives", g.Lives)
	if g.Lives == 0 {
		g.Record("DEFEAT")
		g.Outcome = "defeat"
		wave.Close("lost", g.Tick, g.Gold, g.Lives)
		g.Active = nil
	}
}
func (g *Game) FireTowers() {
	for _, tower := range g.StandingTowers() {
		if g.Tick < tower.Ready {
			continue
		}
		if target := tower.SelectTarget(g.Enemies, g.Field); target != nil {
			g.Fire(tower, target)
		}
	}
}
func (g *Game) Fire(tower *Tower, target *Enemy) {
	stats := tower.Stats()
	g.ProjectileCount++
	g.Projectiles = append(g.Projectiles, &Projectile{g.ProjectileCount, tower, target, tower.Center(), target.Position(), tower.Kind.Targets, stats.Power, stats.ShotSpeed, stats.Splash, stats.SlowRate, stats.SlowTime, stats.BurnAmount, stats.BurnTime})
	tower.Shots++
	tower.Ready = g.Tick + stats.Interval
	g.Record("SHOT", towerID(tower.Number), enemyID(target.Number))
}
func (g *Game) MoveProjectiles() {
	flying := []*Projectile{}
	for _, projectile := range g.Projectiles {
		if projectile.Target.Alive {
			projectile.Aim = projectile.Target.Position()
		}
		if projectile.Fly() {
			g.Impact(projectile)
		} else {
			flying = append(flying, projectile)
		}
	}
	g.Projectiles = flying
}
func (g *Game) Impact(projectile *Projectile) {
	tower, target := projectile.Tower, projectile.Target
	victims := []*Enemy{}
	if projectile.Splash == 0 {
		if target.Alive {
			victims = append(victims, target)
		}
	} else {
		reach := projectile.Splash * projectile.Splash
		for _, enemy := range g.Enemies {
			if canAim(projectile.Targets, enemy) && squaredDistance(enemy.Position(), projectile.Aim) <= reach {
				victims = append(victims, enemy)
			}
		}
	}
	if len(victims) == 0 {
		tower.Fizzles++
	}
	for _, enemy := range victims {
		tower.Hits++
		damage := damageDealt(enemy.HP, projectile.Power, enemy.Kind.Armor)
		enemy.HP -= damage
		g.Credit(tower, enemy, damage)
		if enemy.HP == 0 {
			g.Kill(enemy, tower)
			continue
		}
		if projectile.SlowRate > 0 {
			enemy.Slow.Receive(projectile.SlowRate, projectile.SlowTime, nil)
		}
		if projectile.BurnAmount > 0 {
			enemy.Burn.Receive(projectile.BurnAmount, projectile.BurnTime, tower)
		}
	}
}
func (g *Game) Credit(tower *Tower, enemy *Enemy, damage int) {
	tower.Damage += damage
	enemy.Kind.Damage += damage
	g.Active.TowerDamage[tower.Number] += damage
}
func (g *Game) Kill(enemy *Enemy, tower *Tower) {
	g.RemoveEnemy(enemy)
	cell := enemy.OccupiedCell()
	g.KillCounts[cell.Y*g.Grid.Width+cell.X]++
	wave := g.Active
	bounty := enemy.Kind.Bounty
	tower.Kills++
	wave.Kills++
	enemy.Kind.Kills++
	g.Gold += bounty
	wave.Bounty += bounty
	g.Income["bounty"] += bounty
	g.Record("KILL", enemyID(enemy.Number), enemy.Kind.Name, towerID(tower.Number), "bounty", bounty, "gold", g.Gold)
	for i := 0; i < enemy.Kind.SplitCount; i++ {
		child := enemy.Split(g.EnemyCount + 1)
		g.AddEnemy(child)
		g.Record("SPAWN", enemyID(child.Number), child.Kind.Name, enemyID(enemy.Number), "hp", child.HP)
	}
}
func (g *Game) CheckWaveEnd() {
	wave := g.Active
	if wave == nil || len(g.Enemies) > 0 || !wave.AllReleased() {
		return
	}
	reward := wave.Plan.Reward
	g.Gold += reward
	interest := min(g.Params.InterestCap, g.Gold*g.Params.InterestRate/100)
	g.Gold += interest
	wave.Reward, wave.Interest = reward, interest
	g.Income["reward"] += reward
	g.Income["interest"] += interest
	g.Active = nil
	g.Record("WAVE_END", wave.Number, "reward", reward, "interest", interest, "gold", g.Gold)
	if wave.Number == len(g.Waves) {
		g.Record("VICTORY")
		g.Outcome = "victory"
	} else {
		g.NextStart = g.Tick + g.Params.Interval
	}
	wave.Close("cleared", g.Tick, g.Gold, g.Lives)
}
func (g *Game) MapPicture() [][]byte {
	rows := make([][]byte, g.Grid.Height)
	for y, row := range g.Grid.Rows {
		rows[y] = []byte(row)
	}
	for _, spawn := range g.Grid.Spawns {
		for _, cell := range g.Field.Path(spawn) {
			terrain := g.Grid.Terrain(cell)
			if terrain == '.' || terrain == '~' {
				rows[cell.Y][cell.X] = '+'
			}
		}
	}
	for _, tower := range g.StandingTowers() {
		rows[tower.Cell.Y][tower.Cell.X] = tower.Kind.Symbol[0]
	}
	occupants := map[Point][]*Enemy{}
	for _, enemy := range g.Enemies {
		cell := enemy.OccupiedCell()
		occupants[cell] = append(occupants[cell], enemy)
	}
	for cell, group := range occupants {
		symbol := byte('*')
		if len(group) == 1 {
			symbol = group[0].Kind.Symbol[0]
		}
		rows[cell.Y][cell.X] = symbol
	}
	return rows
}
func (g *Game) FlowPicture() [][]byte {
	rows := make([][]byte, g.Grid.Height)
	for y := range rows {
		rows[y] = make([]byte, g.Grid.Width)
		for x := range rows[y] {
			cell := Point{x, y}
			terrain := g.Grid.Terrain(cell)
			tower := g.TowerAt(cell)
			if terrain == '#' || terrain == 'E' {
				rows[y][x] = terrain
			} else if tower != nil {
				rows[y][x] = tower.Kind.Symbol[0]
			} else if g.Field.At(cell) < 0 {
				rows[y][x] = '?'
			} else {
				rows[y][x] = "^>v<"[g.Field.Direction(cell)]
			}
		}
	}
	return rows
}
func (g *Game) CoveragePicture() [][]byte {
	towers := g.StandingTowers()
	rows := make([][]byte, g.Grid.Height)
	for y := range rows {
		rows[y] = make([]byte, g.Grid.Width)
		for x := range rows[y] {
			cell := Point{x, y}
			tower := g.TowerAt(cell)
			if g.Grid.Rock(cell) {
				rows[y][x] = '#'
			} else if tower != nil {
				rows[y][x] = tower.Kind.Symbol[0]
			} else {
				center := cellCenter(cell)
				count := 0
				for _, other := range towers {
					if other.InRange(center) {
						count++
					}
				}
				rows[y][x] = digit(count)
			}
		}
	}
	return rows
}
func (g *Game) KillsPicture() [][]byte {
	rows := make([][]byte, g.Grid.Height)
	for y := range rows {
		rows[y] = make([]byte, g.Grid.Width)
		for x := range rows[y] {
			count := g.KillCounts[y*g.Grid.Width+x]
			if count > 0 {
				rows[y][x] = digit(count)
			} else if g.Grid.Rock(Point{x, y}) {
				rows[y][x] = '#'
			} else {
				rows[y][x] = '.'
			}
		}
	}
	return rows
}
func (g *Game) Block(label string) []string {
	next := "-"
	if g.Active == nil && g.Outcome == "" {
		next = strconv.Itoa(g.NextStart)
	}
	lines := []string{fmt.Sprintf("%s %d wave %d next %s gold %d lives %d", label, g.Tick, len(g.Records), next, g.Gold, g.Lives)}
	lines = append(lines, ruled(g.MapPicture())...)
	for i, spawn := range g.Grid.Spawns {
		lines = append(lines, fmt.Sprintf("PATH %d length %d", i+1, g.Field.At(spawn)))
	}
	for _, tower := range g.StandingTowers() {
		lines = append(lines, fmt.Sprintf("T%d %s %d %d level %d mode %s ready %d", tower.Number, tower.Kind.Name, tower.Cell.X, tower.Cell.Y, tower.Level, tower.Mode, tower.Ready))
	}
	for _, enemy := range g.Enemies {
		point := enemy.Position()
		lines = append(lines, fmt.Sprintf("E%d %s %d %d hp %d/%d slow %d %d burn %d %d", enemy.Number, enemy.Kind.Name, point.X, point.Y, enemy.HP, enemy.MaxHP, enemy.Slow.Strength, enemy.Slow.Remaining, enemy.Burn.Strength, enemy.Burn.Remaining))
	}
	for _, projectile := range g.Projectiles {
		lines = append(lines, fmt.Sprintf("P%d T%d E%d %d %d", projectile.Number, projectile.Tower.Number, projectile.Target.Number, projectile.Position.X, projectile.Position.Y))
	}
	return lines
}
func (g *Game) FinalBlock() []string {
	lines := g.Block("FINAL")
	lines = append(lines, "FLOW")
	lines = append(lines, ruled(g.FlowPicture())...)
	lines = append(lines, "COVERAGE")
	lines = append(lines, ruled(g.CoveragePicture())...)
	lines = append(lines, "KILLS")
	return append(lines, ruled(g.KillsPicture())...)
}
func (g *Game) WaveLines() []string {
	header := waveColumns
	for _, tower := range g.Towers {
		header += "," + towerID(tower.Number)
	}
	lines := []string{header}
	for _, wave := range g.Records {
		lines = append(lines, wave.CSVRow(len(g.Towers)))
	}
	return lines
}
func (g *Game) MVPLine() string {
	var best *Tower
	for _, tower := range g.Towers {
		if best == nil || tower.Damage > best.Damage {
			best = tower
		}
	}
	if best == nil {
		return "mvp -"
	}
	return fmt.Sprintf("mvp T%d damage %d", best.Number, best.Damage)
}
func (g *Game) TowerLine(tower *Tower, totalDamage int) string {
	state := "active"
	if !tower.Standing() {
		state = "sold " + strconv.Itoa(tower.Sold)
	}
	return fmt.Sprintf("TOWER T%d %s %d %d level %d mode %s %s shots %d hits %d fizzles %d kills %d damage %d per_shot %s share %s invested %d", tower.Number, tower.Kind.Name, tower.Cell.X, tower.Cell.Y, tower.Level, tower.Mode, state, tower.Shots, tower.Hits, tower.Fizzles, tower.Kills, tower.Damage, oneDecimal(tower.Damage, tower.Shots), oneDecimal(100*tower.Damage, totalDamage), tower.Investment)
}
func (g *Game) SummaryLines(actionCount int) []string {
	cleared, perfect := 0, 0
	for _, wave := range g.Records {
		if wave.Status == "cleared" {
			cleared++
			if wave.Leaks == 0 {
				perfect++
			}
		}
	}
	spawned, killed, leaked, totalDamage := 0, 0, 0, 0
	for _, kind := range g.EnemyTypes {
		spawned += kind.Spawned
		killed += kind.Kills
		leaked += kind.Leaks
	}
	for _, tower := range g.Towers {
		totalDamage += tower.Damage
	}
	income := []string{"income"}
	for _, field := range incomeFields {
		income = append(income, field, strconv.Itoa(g.Income[field]))
	}
	score := 10*killed + 100*g.Lives + 50*perfect + g.Gold
	lines := []string{"outcome " + g.Outcome, fmt.Sprintf("ticks %d", g.Tick), fmt.Sprintf("waves %d/%d perfect %d", cleared, len(g.Waves), perfect), fmt.Sprintf("lives %d/%d", g.Lives, g.Params.Lives), fmt.Sprintf("gold %d", g.Gold), fmt.Sprintf("enemies spawned %d killed %d leaked %d", spawned, killed, leaked), strings.Join(income, " "), fmt.Sprintf("spent %d", g.Spent), fmt.Sprintf("damage %d", totalDamage), fmt.Sprintf("actions total %d done %d refused %d unused %d", actionCount, g.Done, g.Refused, actionCount-g.Done-g.Refused), fmt.Sprintf("score %d", score), g.MVPLine()}
	for _, kind := range g.EnemyTypes {
		lines = append(lines, fmt.Sprintf("ENEMY %s spawned %d killed %d leaked %d damage %d", kind.Name, kind.Spawned, kind.Kills, kind.Leaks, kind.Damage))
	}
	for _, tower := range g.Towers {
		lines = append(lines, g.TowerLine(tower, totalDamage))
	}
	return lines
}
func main() {
	grid := readMap()
	towerTypes := parseTowerTypes(readLines("towers.txt"))
	enemyTypes, waves := parseWaves(readLines("waves.txt"))
	actions := []Action{}
	for _, line := range readLines("actions.txt") {
		actions = append(actions, newAction(line))
	}
	params := newParams(readLines("params.txt"))
	game := newGame(grid, towerTypes, enemyTypes, waves, params)
	game.Run(actions)
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeLines("events.txt", game.Events)
	writeLines("waves.csv", game.WaveLines())
	writeLines("snapshots.txt", game.Snapshots)
	writeLines("summary.txt", game.SummaryLines(len(actions)))
}
