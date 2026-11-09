package main

import (
	"fmt"
	"os"
	"strings"
)

type Config struct {
	GenerationSeed, GameSeed                                                         int64
	Width, Height, MinSize, MaxSplit, RoomMin, RoomMax, Levels                       int
	MonsterBase, MonsterStep, ItemBase, ItemStep, SleepChance, WakeChance, FOVRadius int
	MaxHP, RegenInterval, FoodStart, FoodMax, FoodHungry, FoodWeak, PackLimit        int
	HitDie                                                                           Dice
	StartItems                                                                       []string
	XPLevels                                                                         []int
	Checkpoints                                                                      map[int]bool
}

func readRows(name string) [][]string {
	data, err := os.ReadFile("input/" + name)
	if err != nil {
		panic(err)
	}
	lines := strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
	rows := make([][]string, len(lines))
	for i, line := range lines {
		rows[i] = strings.Split(line, " ")
	}
	return rows
}
func parseNumbers(tokens []string) []int {
	values := make([]int, len(tokens))
	for i, token := range tokens {
		values[i] = number(token)
	}
	return values
}
func readConfig(rows [][]string) Config {
	values := make(map[string][]string)
	for _, row := range rows {
		values[row[0]] = row[1:]
	}
	config := Config{GenerationSeed: int64(number(values["seed"][0])), GameSeed: int64(number(values["seed"][1])), Width: number(values["map"][0]), Height: number(values["map"][1]), MinSize: number(values["bsp"][0]), MaxSplit: number(values["bsp"][1]), RoomMin: number(values["room"][0]), RoomMax: number(values["room"][1]), Levels: number(values["levels"][0]), MonsterBase: number(values["monsters"][0]), MonsterStep: number(values["monsters"][1]), ItemBase: number(values["items"][0]), ItemStep: number(values["items"][1]), SleepChance: number(values["sleep"][0]), WakeChance: number(values["sleep"][1]), FOVRadius: number(values["fov"][0]), MaxHP: number(values["player"][0]), RegenInterval: number(values["player"][1]), HitDie: parseDice(values["hitdie"][0]), FoodStart: number(values["food"][0]), FoodMax: number(values["food"][1]), FoodHungry: number(values["food"][2]), FoodWeak: number(values["food"][3]), PackLimit: number(values["pack"][0]), StartItems: values["start"], XPLevels: parseNumbers(values["xp"]), Checkpoints: make(map[int]bool)}
	for _, turn := range parseNumbers(values["checkpoints"]) {
		config.Checkpoints[turn] = true
	}
	return config
}

type Command struct{ Name, Argument string }

func expandCommands(rows [][]string) []Command {
	var commands []Command
	for _, tokens := range rows {
		name, argument, count := tokens[0], "", 1
		if name == "wait" {
			if len(tokens) == 2 {
				count = number(tokens[1])
			}
		} else {
			if len(tokens) > 1 {
				argument = tokens[1]
			}
			if len(tokens) == 3 {
				count = number(tokens[2])
			}
		}
		for range count {
			commands = append(commands, Command{name, argument})
		}
	}
	return commands
}

func dec1(a, b int) string {
	if b == 0 {
		return "-"
	}
	z := (20*a + b) / (2 * b)
	return fmt.Sprintf("%d.%d", z/10, z%10)
}
func exploration(level *Level) (int, int) {
	explored, total := 0, 0
	for y, row := range level.Terrain {
		for x, terrain := range row {
			if terrain != ' ' {
				total++
				if level.Memory[y][x] != ' ' {
					explored++
				}
			}
		}
	}
	return explored, total
}

type Player struct {
	Position                                             Point
	Depth, HP, MaxHP, Level, XP, Gold, Satiation, Poison int
	Pack                                                 []*Item
	Weapon, Armor                                        *Item
}

func (player *Player) Defense() int {
	if player.Armor == nil {
		return 10
	}
	return 10 + player.Armor.Kind.Armor + player.Armor.Bonus
}

type AttackStats struct{ Count, Hits, Criticals, Damage int }

func (stats *AttackStats) Record(outcome string, damage int) {
	stats.Count++
	if outcome != "miss" {
		stats.Hits++
		stats.Damage += damage
	}
	if outcome == "critical" {
		stats.Criticals++
	}
}
func (stats AttackStats) Line(label string) string {
	return fmt.Sprintf("%s %d hits %d criticals %d damage %d accuracy %s", label, stats.Count, stats.Hits, stats.Criticals, stats.Damage, dec1(100*stats.Hits, stats.Count))
}

type Usage struct{ Picked, Quaffed, Read, Eaten, Wielded, Worn int }
type Game struct {
	Config                           Config
	MonsterTypes                     []*MonsterType
	ItemTypes                        []*ItemType
	Commands                         []Command
	GenerationRNG, RNG               *Minstd
	Levels                           []*Level
	Player                           Player
	Turn                             int
	Messages, MapLines               []string
	Visible                          [][]bool
	Distance                         [][]int
	Result, Cause                    string
	Succeeded, Failed, Unused, Moves int
	PlayerAttacks, MonsterAttacks    AttackStats
	PoisonDamage, StarvationDamage   int
	Usage                            Usage
	Kills                            []int
}

func newGame(config Config, monsterTypes []*MonsterType, itemTypes []*ItemType, commands []Command) *Game {
	game := &Game{Config: config, MonsterTypes: monsterTypes, ItemTypes: itemTypes, Commands: commands, GenerationRNG: &Minstd{config.GenerationSeed}, RNG: &Minstd{config.GameSeed}, Turn: 1, Kills: make([]int, len(monsterTypes))}
	game.buildLevels()
	game.Player = Player{Position: game.Levels[0].Arrival, Depth: 1, HP: config.MaxHP, MaxHP: config.MaxHP, Level: 1, Satiation: config.FoodStart}
	byName := make(map[string]*ItemType)
	for _, kind := range itemTypes {
		byName[kind.Name] = kind
	}
	for _, name := range config.StartItems {
		item := &Item{Kind: byName[name], Position: game.Player.Position}
		game.Player.Pack = append(game.Player.Pack, item)
		if item.Kind.Category == "weapon" && game.Player.Weapon == nil {
			game.Player.Weapon = item
		}
		if item.Kind.Category == "armor" && game.Player.Armor == nil {
			game.Player.Armor = item
		}
	}
	return game
}
func (g *Game) buildLevels() {
	config := g.Config
	generator := &LevelGenerator{g.GenerationRNG, config.MinSize, config.MaxSplit, config.RoomMin, config.RoomMax}
	for depth := 1; depth <= config.Levels; depth++ {
		level := generator.Generate(depth, config.Width, config.Height)
		if depth < config.Levels {
			level.Terrain[level.Target.Y][level.Target.X] = '>'
		} else {
			level.Items = append(level.Items, &Item{Kind: &ItemType{Category: "amulet", Name: "amulet"}, Position: level.Target})
		}
		g.placeMonsters(level)
		g.placeItems(level)
		g.Levels = append(g.Levels, level)
	}
}
func (g *Game) placeMonsters(level *Level) {
	var candidates []*MonsterType
	var weights []int
	for _, kind := range g.MonsterTypes {
		if kind.MinDepth <= level.Depth && level.Depth <= kind.MaxDepth {
			candidates = append(candidates, kind)
			weights = append(weights, kind.Weight)
		}
	}
	count := g.Config.MonsterBase + g.Config.MonsterStep*(level.Depth-1)
	for id := 1; id <= count; id++ {
		kind := candidates[g.GenerationRNG.Select(weights)]
		var point Point
		for {
			room, drawn := level.DrawRoomCell(g.GenerationRNG)
			if room != level.ArrivalRoom && level.Terrain[drawn.Y][drawn.X] == '.' && level.MonsterAt(drawn.X, drawn.Y) == nil {
				point = drawn
				break
			}
		}
		hp := kind.HP.Roll(g.GenerationRNG)
		asleep := g.GenerationRNG.Rnd(100) < g.Config.SleepChance
		level.Monsters = append(level.Monsters, &Monster{ID: id, Kind: kind, Position: point, HP: hp, MaxHP: hp, Asleep: asleep})
	}
	level.MonstersCreated = count
}
func (g *Game) placeItems(level *Level) {
	var candidates []*ItemType
	var weights []int
	for _, kind := range g.ItemTypes {
		if kind.MinDepth <= level.Depth && level.Depth <= kind.MaxDepth {
			candidates = append(candidates, kind)
			weights = append(weights, kind.Weight)
		}
	}
	count := g.Config.ItemBase + g.Config.ItemStep*(level.Depth-1)
	for range count {
		kind := candidates[g.GenerationRNG.Select(weights)]
		var point Point
		for {
			_, drawn := level.DrawRoomCell(g.GenerationRNG)
			if level.Terrain[drawn.Y][drawn.X] == '.' && level.ItemAt(drawn.X, drawn.Y) == nil {
				point = drawn
				break
			}
		}
		amount := 0
		if kind.Category == "gold" {
			amount = kind.Dice.Roll(g.GenerationRNG)
		}
		level.Items = append(level.Items, &Item{Kind: kind, Position: point, Amount: amount})
	}
	level.ItemsPlaced = len(level.Items)
}
func (g *Game) currentLevel() *Level { return g.Levels[g.Player.Depth-1] }
func (g *Game) say(text string) {
	g.Messages = append(g.Messages, fmt.Sprintf("%04d %s", g.Turn, text))
}
func (g *Game) hungerState() string {
	if g.Player.Satiation > g.Config.FoodHungry {
		return "normal"
	}
	if g.Player.Satiation > g.Config.FoodWeak {
		return "hungry"
	}
	if g.Player.Satiation > 0 {
		return "weak"
	}
	return "starving"
}
func (g *Game) finish(result, cause string) { g.Result, g.Cause = result, cause }
func (g *Game) die(cause string)            { g.say("You die."); g.finish("died", cause) }
func (g *Game) updateView() {
	level, player := g.currentLevel(), &g.Player
	g.Visible = fieldOfView(level, player.Position.X, player.Position.Y, g.Config.FOVRadius)
	for y, row := range g.Visible {
		for x, visible := range row {
			if visible {
				if item := level.ItemAt(x, y); item != nil {
					level.Memory[y][x] = item.Symbol()
				} else {
					level.Memory[y][x] = level.Terrain[y][x]
				}
			}
		}
	}
	for _, monster := range level.Monsters {
		seen := g.Visible[monster.Position.Y][monster.Position.X]
		if seen && !monster.WasVisible {
			g.say("You see the " + monster.Kind.Name + ".")
		}
		monster.WasVisible = seen
	}
}
func (g *Game) Run() {
	g.updateView()
	for _, command := range g.Commands {
		if g.Result != "" {
			g.Unused++
		} else if !g.execute(command) {
			g.Failed++
		} else {
			g.Succeeded++
			if g.Result == "" {
				g.advanceTurn()
			}
		}
	}
	if g.Result == "" {
		g.finish("alive", "commands_exhausted")
	}
}
func (g *Game) advanceTurn() {
	g.updateView()
	g.monstersAct()
	if g.Result != "" {
		return
	}
	g.endTurn()
	if g.Result != "" {
		return
	}
	if g.Config.Checkpoints[g.Turn] {
		g.writeCheckpoint()
	}
	g.Turn++
}
func (g *Game) execute(command Command) bool {
	switch command.Name {
	case "move":
		for index, name := range directionNames {
			if name == command.Argument {
				step := directions[index]
				return g.move(step.X, step.Y)
			}
		}
	case "wait":
		return true
	case "pickup":
		return g.pickup()
	case "descend":
		return g.descend()
	default:
		return g.useItem(command.Name, number(command.Argument))
	}
	panic("unknown direction")
}
func (g *Game) move(dx, dy int) bool {
	level, player := g.currentLevel(), &g.Player
	x, y := player.Position.X+dx, player.Position.Y+dy
	if !passable(level, x, y) {
		g.say("You bump into a wall.")
		return false
	}
	if !canMove(level, player.Position.X, player.Position.Y, dx, dy) {
		g.say("You cannot move diagonally through a door.")
		return false
	}
	if monster := level.MonsterAt(x, y); monster != nil {
		g.playerAttack(level, monster)
		return true
	}
	player.Position = Point{x, y}
	g.Moves++
	if item := level.ItemAt(x, y); item != nil {
		g.say("You see " + item.ReferenceName() + " here.")
	} else if level.Terrain[y][x] == '>' {
		g.say("There is a staircase down here.")
	}
	return true
}
func (g *Game) pickup() bool {
	level, player := g.currentLevel(), &g.Player
	item := level.ItemAt(player.Position.X, player.Position.Y)
	if item == nil {
		g.say("There is nothing here.")
		return false
	}
	switch item.Kind.Category {
	case "gold":
		player.Gold += item.Amount
		g.say("You pick up " + item.DisplayName() + ".")
	case "amulet":
		g.say("You pick up the amulet.")
		g.say("You win!")
		g.finish("won", "amulet")
	default:
		if len(player.Pack) >= g.Config.PackLimit {
			g.say("Your pack is full.")
			return false
		}
		player.Pack = append(player.Pack, item)
		g.say(fmt.Sprintf("You pick up the %s (%d).", item.DisplayName(), len(player.Pack)))
	}
	for index, placed := range level.Items {
		if placed == item {
			level.Items = append(level.Items[:index], level.Items[index+1:]...)
			break
		}
	}
	level.Picked++
	g.Usage.Picked++
	return true
}
func (g *Game) descend() bool {
	if g.currentLevel().Terrain[g.Player.Position.Y][g.Player.Position.X] != '>' {
		g.say("There are no stairs here.")
		return false
	}
	g.Player.Depth++
	g.Player.Position = g.currentLevel().Arrival
	g.say(fmt.Sprintf("You descend to depth %d.", g.Player.Depth))
	return true
}
func (g *Game) useItem(command string, index int) bool {
	if index > len(g.Player.Pack) {
		g.say("You do not have that item.")
		return false
	}
	item := g.Player.Pack[index-1]
	expected := map[string]string{"quaff": "potion", "read": "scroll", "wield": "weapon", "wear": "armor", "eat": "food"}[command]
	if item.Kind.Category != expected {
		g.say("You cannot " + command + " that.")
		return false
	}
	switch command {
	case "quaff":
		return g.quaff(item)
	case "read":
		return g.readScroll(item)
	case "wield":
		return g.wield(item)
	case "wear":
		return g.wear(item)
	case "eat":
		return g.eat(item)
	}
	panic("unknown item command")
}
func (g *Game) removeFromPack(item *Item) {
	for index, entry := range g.Player.Pack {
		if entry == item {
			g.Player.Pack = append(g.Player.Pack[:index], g.Player.Pack[index+1:]...)
			return
		}
	}
}
func (g *Game) quaff(item *Item) bool {
	player := &g.Player
	g.removeFromPack(item)
	g.Usage.Quaffed++
	g.say("You quaff the " + item.DisplayName() + ".")
	switch item.Kind.Effect {
	case "heal":
		player.HP += item.Kind.Dice.Roll(g.RNG)
		if player.HP > player.MaxHP {
			player.MaxHP++
			player.HP = player.MaxHP
		}
		player.Poison = 0
		g.say("You feel better.")
	case "poison":
		player.Poison += item.Kind.PoisonTurns
		g.say("You feel very sick.")
	case "level":
		g.say("You feel more experienced.")
		if player.Level <= len(g.Config.XPLevels) {
			g.gainXP(g.Config.XPLevels[player.Level-1] - player.XP)
		}
	}
	return true
}
func (g *Game) readScroll(item *Item) bool {
	level, player := g.currentLevel(), &g.Player
	g.removeFromPack(item)
	g.Usage.Read++
	g.say("You read the " + item.DisplayName() + ".")
	switch item.Kind.Effect {
	case "mapping":
		for y, row := range level.Terrain {
			for x, terrain := range row {
				if terrain != ' ' && level.Memory[y][x] == ' ' {
					level.Memory[y][x] = terrain
				}
			}
		}
		g.say("A map forms in your mind.")
	case "teleport":
		for {
			_, point := level.DrawRoomCell(g.RNG)
			if point != player.Position && level.MonsterAt(point.X, point.Y) == nil {
				player.Position = point
				break
			}
		}
		g.say("You are teleported.")
	case "enchant_weapon":
		if player.Weapon == nil {
			g.say("Your hands twitch.")
		} else {
			g.say("Your " + player.Weapon.DisplayName() + " glows blue.")
			player.Weapon.Bonus++
		}
	case "enchant_armor":
		if player.Armor == nil {
			g.say("Your skin tingles.")
		} else {
			g.say("Your " + player.Armor.DisplayName() + " glows silver.")
			player.Armor.Bonus++
		}
	}
	return true
}
func (g *Game) wield(item *Item) bool {
	if item == g.Player.Weapon {
		g.say("You are already wielding that.")
		return false
	}
	g.Player.Weapon = item
	g.Usage.Wielded++
	g.say("You are now wielding the " + item.DisplayName() + ".")
	return true
}
func (g *Game) wear(item *Item) bool {
	if item == g.Player.Armor {
		g.say("You are already wearing that.")
		return false
	}
	g.Player.Armor = item
	g.Usage.Worn++
	g.say("You are now wearing the " + item.DisplayName() + ".")
	return true
}
func (g *Game) eat(item *Item) bool {
	g.removeFromPack(item)
	g.Usage.Eaten++
	g.Player.Satiation = min(g.Player.Satiation+item.Kind.Nutrition, g.Config.FoodMax)
	g.say("You eat the " + item.DisplayName() + ".")
	return true
}
func (g *Game) playerAttack(level *Level, monster *Monster) {
	player := &g.Player
	monster.Asleep = false
	toHit, dice, bonus := player.Level, Dice{1, 2}, 0
	if weapon := player.Weapon; weapon != nil {
		toHit, dice, bonus = player.Level+weapon.Kind.ToHit+weapon.Bonus, weapon.Kind.Dice, weapon.Bonus
	}
	hunger := g.hungerState()
	if hunger == "weak" || hunger == "starving" {
		toHit -= 2
	}
	outcome, damage := resolveAttack(g.RNG, toHit, monster.Kind.Defense, dice, bonus)
	g.PlayerAttacks.Record(outcome, damage)
	name := monster.Kind.Name
	if outcome == "miss" {
		g.say("You miss the " + name + ".")
		return
	}
	hard := ""
	if outcome == "critical" {
		hard = " hard"
	}
	g.say(fmt.Sprintf("You hit the %s%s for %d.", name, hard, damage))
	monster.HP -= damage
	if monster.HP <= 0 {
		g.say("You kill the " + name + ".")
		for index, entry := range level.Monsters {
			if entry == monster {
				level.Monsters = append(level.Monsters[:index], level.Monsters[index+1:]...)
				break
			}
		}
		level.Kills++
		g.Kills[monster.Kind.Index]++
		g.gainXP(monster.Kind.XP)
	}
}
func (g *Game) gainXP(amount int) {
	player := &g.Player
	player.XP += amount
	for player.Level <= len(g.Config.XPLevels) && player.XP >= g.Config.XPLevels[player.Level-1] {
		player.Level++
		gained := g.Config.HitDie.Roll(g.RNG)
		player.MaxHP += gained
		player.HP += gained
		g.say(fmt.Sprintf("Welcome to level %d.", player.Level))
	}
}
func (g *Game) monsterAttack(monster *Monster) {
	outcome, damage := resolveAttack(g.RNG, monster.Kind.ToHit, g.Player.Defense(), monster.Kind.Damage, 0)
	g.MonsterAttacks.Record(outcome, damage)
	if outcome == "miss" {
		g.say("The " + monster.Kind.Name + " misses you.")
		return
	}
	hard := ""
	if outcome == "critical" {
		hard = " hard"
	}
	g.say(fmt.Sprintf("The %s hits you%s for %d.", monster.Kind.Name, hard, damage))
	g.Player.HP -= damage
	if g.Player.HP <= 0 {
		g.die("killed_by " + monster.Kind.Name)
	} else if monster.Kind.Poisonous {
		g.Player.Poison += 5
		g.say("You are poisoned.")
	}
}
func (g *Game) monstersAct() {
	level := g.currentLevel()
	g.Distance = distances(level, g.Player.Position.X, g.Player.Position.Y)
	for _, monster := range level.Monsters {
		monster.Energy += monster.Kind.Speed
		for monster.Energy >= 2 {
			monster.Energy -= 2
			g.monsterAction(level, monster)
			if g.Result != "" {
				return
			}
		}
	}
}
func (g *Game) monsterAction(level *Level, monster *Monster) {
	sees := g.Visible[monster.Position.Y][monster.Position.X]
	if monster.Asleep {
		if sees && g.RNG.Rnd(100) < g.Config.WakeChance {
			monster.Asleep = false
			g.say("The " + monster.Kind.Name + " wakes up.")
		}
	} else if monster.Kind.Stationary {
		if g.canAttack(level, monster) {
			g.monsterAttack(monster)
		}
	} else if monster.Kind.Erratic && g.RNG.Rnd(2) == 0 {
		g.wander(level, monster)
	} else if sees {
		g.chase(level, monster)
	} else {
		g.wander(level, monster)
	}
}
func (g *Game) canAttack(level *Level, monster *Monster) bool {
	dx, dy := g.Player.Position.X-monster.Position.X, g.Player.Position.Y-monster.Position.Y
	return max(abs(dx), abs(dy)) == 1 && canMove(level, monster.Position.X, monster.Position.Y, dx, dy)
}
func (g *Game) wander(level *Level, monster *Monster) {
	step := directions[g.RNG.Rnd(8)]
	point := monster.Position
	if !canMove(level, point.X, point.Y, step.X, step.Y) {
		return
	}
	target := Point{point.X + step.X, point.Y + step.Y}
	if target == g.Player.Position {
		g.monsterAttack(monster)
	} else if level.MonsterAt(target.X, target.Y) == nil {
		monster.Position = target
	}
}
func (g *Game) chase(level *Level, monster *Monster) {
	if g.canAttack(level, monster) {
		g.monsterAttack(monster)
		return
	}
	here := g.Distance[monster.Position.Y][monster.Position.X]
	var best Point
	found, bestDistance := false, 0
	for _, step := range directions {
		point := monster.Position
		if !canMove(level, point.X, point.Y, step.X, step.Y) {
			continue
		}
		target := Point{point.X + step.X, point.Y + step.Y}
		distance := g.Distance[target.Y][target.X]
		if distance < 0 || (here >= 0 && distance >= here) || target == g.Player.Position || level.MonsterAt(target.X, target.Y) != nil {
			continue
		}
		if !found || distance < bestDistance {
			best, found, bestDistance = target, true, distance
		}
	}
	if found {
		monster.Position = best
	}
}
func (g *Game) endTurn() {
	player := &g.Player
	for _, monster := range g.currentLevel().Monsters {
		if monster.Kind.Regenerates && monster.HP < monster.MaxHP {
			monster.HP++
		}
	}
	if player.Poison > 0 {
		player.HP--
		g.PoisonDamage++
		if player.HP <= 0 {
			g.die("poison")
			return
		}
		player.Poison--
		if player.Poison == 0 {
			g.say("You feel less sick.")
		}
	}
	if player.Satiation == 0 {
		player.HP--
		g.StarvationDamage++
		if player.HP <= 0 {
			g.die("starvation")
			return
		}
	} else {
		before := g.hungerState()
		player.Satiation--
		after := g.hungerState()
		if after != before {
			switch after {
			case "hungry":
				g.say("You are getting hungry.")
			case "weak":
				g.say("You feel weak from hunger.")
			case "starving":
				g.say("You are starving.")
			}
		}
	}
	if g.Turn%g.Config.RegenInterval == 0 && player.Poison == 0 && player.Satiation > 0 && player.HP < player.MaxHP {
		player.HP++
	}
}
func (g *Game) viewSymbol(level *Level, x, y int) byte {
	if g.Player.Position == (Point{x, y}) {
		return '@'
	}
	if monster := level.MonsterAt(x, y); monster != nil {
		return monster.Kind.Symbol
	}
	if item := level.ItemAt(x, y); item != nil {
		return item.Symbol()
	}
	return level.Terrain[y][x]
}
func (g *Game) mapRows(level *Level, current bool) []string {
	border := "+" + strings.Repeat("-", level.Width) + "+"
	lines := []string{border}
	for y := range level.Height {
		row := make([]byte, level.Width)
		for x := range row {
			row[x] = level.Memory[y][x]
			if current && g.Visible[y][x] {
				row[x] = g.viewSymbol(level, x, y)
			}
		}
		lines = append(lines, "|"+string(row)+"|")
	}
	return append(lines, border)
}
func (g *Game) statusLine() string {
	p := &g.Player
	return fmt.Sprintf("STATUS hp %d/%d level %d xp %d defense %d gold %d food %d %s poison %d", p.HP, p.MaxHP, p.Level, p.XP, p.Defense(), p.Gold, p.Satiation, g.hungerState(), p.Poison)
}
func (g *Game) writeCheckpoint() {
	g.MapLines = append(g.MapLines, fmt.Sprintf("CHECKPOINT turn %d depth %d", g.Turn, g.Player.Depth))
	g.MapLines = append(g.MapLines, g.mapRows(g.currentLevel(), true)...)
	g.MapLines = append(g.MapLines, g.statusLine())
}
func (g *Game) finalBlock() []string {
	lines := []string{fmt.Sprintf("FINAL turn %d depth %d", g.Succeeded, g.Player.Depth)}
	for _, level := range g.Levels[:g.Player.Depth] {
		explored, total := exploration(level)
		lines = append(lines, fmt.Sprintf("LEVEL %d explored %d/%d", level.Depth, explored, total))
		lines = append(lines, g.mapRows(level, level.Depth == g.Player.Depth)...)
	}
	return append(lines, g.statusLine())
}
func itemLabel(item *Item) string {
	if item == nil {
		return "-"
	}
	return item.DisplayName()
}
func (g *Game) statsLines() []string {
	p := &g.Player
	lines := []string{"result " + g.Result, "cause " + g.Cause, fmt.Sprintf("turns %d", g.Succeeded), fmt.Sprintf("depth %d", p.Depth), fmt.Sprintf("level %d", p.Level), fmt.Sprintf("xp %d", p.XP), fmt.Sprintf("hp %d/%d", p.HP, p.MaxHP), fmt.Sprintf("defense %d", p.Defense()), fmt.Sprintf("gold %d", p.Gold), fmt.Sprintf("food %d %s", p.Satiation, g.hungerState()), fmt.Sprintf("poison %d", p.Poison), "weapon " + itemLabel(p.Weapon), "armor " + itemLabel(p.Armor), fmt.Sprintf("commands %d executed %d failed %d unused %d", len(g.Commands), g.Succeeded, g.Failed, g.Unused), fmt.Sprintf("moves %d", g.Moves), g.PlayerAttacks.Line("player_attacks"), g.MonsterAttacks.Line("monster_attacks"), fmt.Sprintf("poison_damage %d starvation_damage %d", g.PoisonDamage, g.StarvationDamage), fmt.Sprintf("picked %d quaffed %d read %d eaten %d wielded %d worn %d", g.Usage.Picked, g.Usage.Quaffed, g.Usage.Read, g.Usage.Eaten, g.Usage.Wielded, g.Usage.Worn)}
	totalKills := 0
	for _, count := range g.Kills {
		totalKills += count
	}
	lines = append(lines, fmt.Sprintf("kills %d", totalKills))
	for i, kind := range g.MonsterTypes {
		if g.Kills[i] > 0 {
			lines = append(lines, fmt.Sprintf("KILL %s %d", kind.Name, g.Kills[i]))
		}
	}
	for _, level := range g.Levels {
		explored, total := exploration(level)
		lines = append(lines, fmt.Sprintf("LEVEL %d rooms %d explored %d/%d %s monsters %d/%d items %d/%d", level.Depth, len(level.Rooms), explored, total, dec1(100*explored, total), level.Kills, level.MonstersCreated, level.Picked, level.ItemsPlaced))
	}
	for i, item := range p.Pack {
		line := fmt.Sprintf("INVENTORY %d %s", i+1, item.DisplayName())
		if item == p.Weapon {
			line += " (wielded)"
		} else if item == p.Armor {
			line += " (worn)"
		}
		lines = append(lines, line)
	}
	return lines
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
	config := readConfig(readRows("config.txt"))
	var monsterTypes []*MonsterType
	for i, tokens := range readRows("monsters.txt") {
		monsterTypes = append(monsterTypes, newMonsterType(tokens, i))
	}
	var itemTypes []*ItemType
	for _, tokens := range readRows("items.txt") {
		itemTypes = append(itemTypes, parseItemType(tokens))
	}
	game := newGame(config, monsterTypes, itemTypes, expandCommands(readRows("commands.txt")))
	game.Run()
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	writeLines("messages.txt", game.Messages)
	writeLines("maps.txt", append(game.MapLines, game.finalBlock()...))
	writeLines("stats.txt", game.statsLines())
}
