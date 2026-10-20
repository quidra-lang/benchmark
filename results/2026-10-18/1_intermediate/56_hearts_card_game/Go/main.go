package main

import (
    "bufio"
    "fmt"
    "os"
    "sort"
    "strconv"
    "strings"
)

const seats = "NESW"
const suits = "CDSH"
const ranks = "23456789TJQKA"
const queen = 36
const king = 37
const ace = 38
const jack = 22

type Cards [52]bool
type Play struct {
    Seat, Card int
}
type Entry struct {
    Level int
    Text string
}
type HandRecord struct {
    Number int
    Direction string
    Points [4]int
    Shooter int
    Record []string
}
type Snapshot struct {
    Hands, Taken [4]Cards
    Tricks [][]Play
    Counts [4]int
    Current []Play
    Leader int
    Broken bool
    Record []string
    LogSize, Seat, Card int
}
type Game struct {
    Rules map[string]string
    Bots *[4]string
    RNG *int64
    State string
    Number int
    Scores [4]int
    Stats [4][4]int
    Stacked map[int]Cards
    History []HandRecord
    Log []Entry
    Record []string
    Hands, Taken [4]Cards
    Passed [4]bool
    Passes [4][]int
    Direction byte
    Tricks [][]Play
    Counts [4]int
    Current []Play
    Leader int
    Broken bool
    Undo []Snapshot
}
func fail(reason string) {
    panic(reason)
}
func seatText(s int) string {
    return string(seats[s])
}
func cardText(c int) string { return string([]byte{ranks[c%13], suits[c/13]}) }
func cardList(cards Cards) []int {
    result := []int{}
    for c, present := range cards { if present { result = append(result, c) } }
    return result
}
func cardsText(cards Cards) string {
    words := []string{}
    for _, c := range cardList(cards) {
        words = append(words, cardText(c))
    }
    if len(words) == 0 {
        return "-"
    }
    return strings.Join(words, " ")
}
func asCards(list []int) Cards {
    var cards Cards
    for _, c := range list {
        cards[c] = true
    }
    return cards
}
func seatValue(word string) int {
    if len(word) != 1 || !strings.Contains(seats, word) {
        fail("bad seat " + word)
    }
    return strings.Index(seats, word)
}
func cardValue(word string) int {
    if len(word) != 2 {
        fail("bad card " + word)
    }
    r, s := strings.IndexByte(ranks, word[0]), strings.IndexByte(suits, word[1])
    if r < 0 || s < 0 {
        fail("bad card " + word)
    }
    return 13*s+r
}
func bounded(word string, low, high int) int {
    value, err := strconv.Atoi(word)
    if err != nil || value < low || value > high {
        fail("bad value " + word)
    }
    return value
}
func penalty(c int) bool {
    return c == queen || c/13 == 3
}
func ordered(cards Cards, high bool) []int {
    list := cardList(cards)
    sort.Slice(list, func(i, j int) bool {
        a, b := list[i], list[j]
        if a%13 == b%13 {
            return a/13 < b/13
        }
        if high {
            return a%13 > b%13
        }
        return a%13 < b%13
    })
    return list
}
func lowest(cards Cards) int {
    return ordered(cards, false)[0]
}
func highest(cards Cards) int {
    return ordered(cards, true)[0]
}
func filter(cards Cards, predicate func(int) bool) Cards {
    var result Cards
    for c, present := range cards {
        result[c] = present && predicate(c)
    }
    return result
}
func nonempty(cards Cards) bool {
    for _, present := range cards { if present { return true } }
    return false
}
func pairs(label string, values [4]int) string {
    return fmt.Sprintf("%s N %d E %d S %d W %d", label, values[0], values[1], values[2], values[3])
}
func direction(c byte) string { return map[byte]string{'L':"LEFT", 'R':"RIGHT", 'A':"ACROSS", 'H':"HOLD"}[c] }
func newGame(rules map[string]string, bots *[4]string, rng *int64) *Game {
    return &Game{Rules:rules, Bots:bots, RNG:rng, State:"between", Stacked:make(map[int]Cards)}
}
func (g *Game) point(c int) int {
    if c == queen {
        return 13
    }
    if c/13 == 3 {
        return 1
    }
    if c == jack && g.Rules["JACK"] == "ON" {
        return -10
    }
    return 0
}
func (g *Game) points(cards Cards) int {
    total := 0
    for _, c := range cardList(cards) {
        total += g.point(c)
    }
    return total
}
func (g *Game) write(level int, line string) {
    g.Log = append(g.Log, Entry{level,line})
    if level > 0 {
        g.Record = append(g.Record,line)
    }
}
func (g *Game) deal() {
    g.Number++
    cycle := g.Rules["PASS"]
    g.Direction = cycle[(g.Number-1)%len(cycle)]
    g.Hands = [4]Cards{}
    var used Cards
    free := []int{}
    for s := 0; s < 4; s++ {
        if cards, ok := g.Stacked[s]; ok {
            g.Hands[s] = cards
            for c, present := range cards {
                used[c] = used[c] || present
            }
        } else { free = append(free,s) }
    }
    deck := cardList(filter(asCardsRange(), func(c int) bool { return !used[c] }))
    for i := len(deck)-1; i > 0; i-- {
        *g.RNG = (48271 * *g.RNG) % 2147483647
        j := int(*g.RNG % int64(i+1))
        deck[i], deck[j] = deck[j], deck[i]
    }
    for i, c := range deck {
        g.Hands[free[i%len(free)]][c] = true
    }
    g.Stacked = make(map[int]Cards)
    g.Passed, g.Passes = [4]bool{}, [4][]int{}
    g.Taken, g.Counts = [4]Cards{}, [4]int{}
    g.Tricks, g.Current, g.Undo, g.Record = nil, nil, nil, nil
    g.Broken = false
    g.write(1,fmt.Sprintf("hand %d pass %s",g.Number,direction(g.Direction)))
    for s := 0; s < 4; s++ {
        g.write(2,seatText(s)+": "+cardsText(g.Hands[s]))
    }
    if g.Direction == 'H' { g.begin() } else { g.State = "passing" }
}
func asCardsRange() Cards {
    var cards Cards
    for c := range cards {
        cards[c] = true
    }
    return cards
}
func (g *Game) begin() {
    g.State = "playing"
    for s := 0; s < 4; s++ { if g.Hands[s][0] { g.Leader=s; break } }
    g.write(2,"lead "+seatText(g.Leader))
}
func (g *Game) passCards(s int, cards []int) {
    for _, c := range cards {
        g.Hands[s][c] = false
    }
    g.Passed[s], g.Passes[s] = true, append([]int(nil),cards...)
    g.write(2,seatText(s)+" passes "+cardsText(asCards(cards)))
    for _, passed := range g.Passed { if !passed { return } }
    offset := map[byte]int{'L':1,'R':3,'A':2}[g.Direction]
    for source, list := range g.Passes {
        for _, c := range list {
            g.Hands[(source+offset)%4][c] = true
        }
    }
    g.begin()
}
func (g *Game) actor() int {
    return (g.Leader+len(g.Current))%4
}
func (g *Game) legal() Cards {
    hand := g.Hands[g.actor()]
    if len(g.Current) == 0 {
        if len(g.Tricks) == 0 { return asCards([]int{0}) }
        safe := filter(hand,func(c int) bool { return c/13 != 3 })
        if !g.Broken && nonempty(safe) {
            return safe
        }
        return hand
    }
    led := g.Current[0].Card/13
    followers := filter(hand,func(c int) bool { return c/13 == led })
    if nonempty(followers) {
        return followers
    }
    if len(g.Tricks) == 0 && g.Rules["BLOOD"] == "OFF" {
        safe := filter(hand,func(c int) bool { return !penalty(c) })
        if nonempty(safe) {
            return safe
        }
    }
    return hand
}
func (g *Game) choosePass(s int) []int {
    hand := g.Hands[s]
    low, high := ordered(hand,false), ordered(hand,true)
    special := []int{}
    for _, c := range []int{queen,king,ace} { if hand[c] { special=append(special,c) } }
    hearts := ordered(filter(hand,func(c int) bool { return c/13==3 }),true)
    order := []int{}
    switch g.Bots[s] {
    case "LOW":
        order=high
    case "HIGH":
        order=low
    case "MOON":
        for _, c := range low { if c/13 != 3 { order=append(order,c) } }
        for _, c := range low { if c/13 == 3 { order=append(order,c) } }
    case "SMART":
        count := [4]int{}
        for _, c := range high {
            count[c/13]++
        }
        if !hand[queen] || count[2]<5 {
            order=append(order,special...)
        }
        suit := -1
        for t:=0;t<2;t++ { if count[t]>0 && (suit<0 || count[t]<count[suit]) { suit=t } }
        for _, c := range high { if c/13==suit { order=append(order,c) } }
        order=append(order,hearts...)
        order=append(order,high...)
    default:
        order=append(order,special...)
        order=append(order,hearts...)
        order=append(order,high...)
    }
    result:=[]int{}
    var seen Cards
    for _, c:=range order {
        if !seen[c] {
            seen[c]=true
            result=append(result,c)
        }
        if len(result)==3 {
            break
        }
    }
    return result
}
func (g *Game) queenPlayed() bool {
    for _, cards:=range g.Taken { if cards[queen] { return true } }
    for _, p:=range g.Current { if p.Card==queen { return true } }
    return false
}
func (g *Game) choosePlay() int {
    s:=g.actor()
    hand, legal, strategy:=g.Hands[s],g.legal(),g.Bots[s]
    if strategy=="LOW" {
        return lowest(legal)
    }
    if strategy=="HIGH" {
        return highest(legal)
    }
    if strategy=="MOON" {
        for other,cards:=range g.Taken {
            if other!=s && nonempty(filter(cards,penalty)) {
                strategy="BASIC"
                break
            }
        }
    }
    if len(g.Current)==0 {
        if strategy=="SMART" && !g.queenPlayed() && !hand[queen] {
            small:=filter(legal,func(c int) bool { return c/13==2 && c%13<10 })
            if nonempty(small) {
                return lowest(small)
            }
        }
        counts:=[4]int{}
        for _,c:=range cardList(legal) {
            counts[c/13]++
        }
        suit:=-1
        for t:=0;t<4;t++ {
            if counts[t]>0 && (suit<0 || strategy=="MOON" && counts[t]>counts[suit] || strategy!="MOON" && counts[t]<counts[suit]) {
                suit=t
            }
        }
        subset:=filter(legal,func(c int) bool { return c/13==suit })
        if strategy=="MOON" {
            return highest(subset)
        }
        return lowest(subset)
    }
    led:=g.Current[0].Card/13
    if nonempty(filter(hand,func(c int) bool { return c/13==led })) {
        winning:=-1
        for _,p:=range g.Current { if p.Card/13==led && p.Card%13>winning { winning=p.Card%13 } }
        lower:=filter(legal,func(c int) bool { return c%13<winning })
        if strategy=="MOON" {
            high:=highest(legal)
            if high%13>winning {
                return high
            }
            return lowest(legal)
        }
        if nonempty(lower) {
            return highest(lower)
        }
        if strategy=="SMART" && len(g.Current)==3 {
            safe:=legal; safe[queen]=false
            if nonempty(safe) {
                return highest(safe)
            }
            return queen
        }
        return lowest(legal)
    }
    if strategy=="MOON" {
        safe:=filter(legal,func(c int) bool { return !penalty(c) })
        if nonempty(safe) {
            return lowest(safe)
        }
        return lowest(legal)
    }
    if legal[queen] {
        return queen
    }
    if strategy=="SMART" && !g.queenPlayed() {
        if legal[ace] {
            return ace
        }
        if legal[king] {
            return king
        }
    }
    hearts:=filter(legal,func(c int) bool { return c/13==3 })
    if nonempty(hearts) {
        return highest(hearts)
    }
    return highest(legal)
}
func winner(plays []Play) int {
    best:=plays[0]
    for _,p:=range plays { if p.Card/13==best.Card/13 && p.Card%13>best.Card%13 { best=p } }
    return best.Seat
}
func playsText(plays []Play) string {
    words:=[]string{}
    for _,p:=range plays {
        words=append(words,seatText(p.Seat),cardText(p.Card))
    }
    return strings.Join(words," ")
}
func (g *Game) trickLine(plays []Play, number int) string {
    points:=0
    for _,p:=range plays {
        points+=g.point(p.Card)
    }
    return fmt.Sprintf("trick %d: %s -> %s %d",number,playsText(plays),seatText(winner(plays)),points)
}
func (g *Game) play(c int) {
    s:=g.actor()
    g.Undo = append(g.Undo, Snapshot{
        Hands: g.Hands, Taken: g.Taken,
        Tricks: append([][]Play(nil), g.Tricks...), Counts: g.Counts,
        Current: append([]Play(nil), g.Current...), Leader: g.Leader,
        Broken: g.Broken, Record: append([]string(nil), g.Record...),
        LogSize: len(g.Log), Seat: s, Card: c,
    })
    g.Hands[s][c]=false
    g.Current=append(g.Current,Play{s,c})
    if c/13==3 || c==queen && g.Rules["QSBREAK"]=="ON" {
        g.Broken=true
    }
    if len(g.Current)==4 {
        w:=winner(g.Current)
        for _,p:=range g.Current {
            g.Taken[w][p.Card]=true
        }
        g.Counts[w]++
        g.Tricks=append(g.Tricks,append([]Play(nil),g.Current...))
        g.write(2,g.trickLine(g.Current,len(g.Tricks)))
        g.Current=nil
        g.Leader=w
        if len(g.Tricks)==13 {
            g.finish()
        }
    }
}
func (g *Game) undoCard() (int,int) {
    u:=g.Undo[len(g.Undo)-1]
    g.Undo=g.Undo[:len(g.Undo)-1]
    g.Hands,g.Taken,g.Tricks,g.Counts,g.Current=u.Hands,u.Taken,u.Tricks,u.Counts,u.Current
    g.Leader,g.Broken,g.Record=u.Leader,u.Broken,u.Record
    g.Log=g.Log[:u.LogSize]
    return u.Seat,u.Card
}
func (g *Game) ranking() []int {
    order:=[]int{0,1,2,3}
    sort.SliceStable(order,func(i,j int) bool { return g.Scores[order[i]]<g.Scores[order[j]] })
    return order
}
func (g *Game) ended(scores [4]int) bool {
    limit,_:=strconv.Atoi(g.Rules["LIMIT"])
    target,_:=strconv.Atoi(g.Rules["TARGET"])
    if g.Number>=limit {
        return true
    }
    for _,v:=range scores { if v>=target { return true } }
    return false
}
func (g *Game) statsLines() []string {
    result:=[]string{}
    for s,v:=range g.Stats {
        result=append(result,fmt.Sprintf("stats %s tricks %d hearts %d queens %d moons %d",seatText(s),v[0],v[1],v[2],v[3]))
    }
    return result
}
func (g *Game) finish() {
    var points [4]int
    shooter:=-1
    for s,cards:=range g.Taken {
        points[s]=g.points(cards)
        if len(cardList(filter(cards,penalty)))==14 {
            shooter=s
        }
    }
    if shooter>=0 {
        points[shooter]-=26
        method:=g.Rules["MOON"]
        if method=="AUTO" {
            add:=g.Scores
            for s:=0;s<4;s++ { add[s]+=points[s]; if s!=shooter { add[s]+=26 } }
            best:=0
            for s:=1;s<4;s++ { if add[s]<add[best] { best=s } }
            method="ADD"
            if g.ended(add) && best!=shooter {
                method="SUB"
            }
        }
        if method=="SUB" { points[shooter]-=26 } else {
            for s:=0;s<4;s++ { if s!=shooter { points[s]+=26 } }
        }
        g.write(1,"moon "+seatText(shooter)+" "+method)
    }
    for s,cards:=range g.Taken {
        g.Scores[s]+=points[s]
        g.Stats[s][0]+=g.Counts[s]
        g.Stats[s][1]+=len(cardList(filter(cards,func(c int) bool { return c/13==3 })))
        if cards[queen] {
            g.Stats[s][2]++
        }
        if s==shooter {
            g.Stats[s][3]++
        }
    }
    g.write(1,pairs("points",points))
    g.write(1,pairs("scores",g.Scores))
    g.History=append(g.History,HandRecord{g.Number,direction(g.Direction),points,shooter,append([]string(nil),g.Record...)})
    g.State="between"
    if g.ended(g.Scores) {
        g.State="none"
        g.write(0,fmt.Sprintf("game over hands %d",g.Number))
        for r,s:=range g.ranking() {
            g.write(0,fmt.Sprintf("rank %d %s %d",r+1,seatText(s),g.Scores[s]))
        }
        for _,line:=range g.statsLines() {
            g.write(0,line)
        }
    }
}
func (g *Game) autoPass() {
    for s:=0;s<4;s++ { if !g.Passed[s] { g.passCards(s,g.choosePass(s)) } }
}
func (g *Game) autoHand() {
    if g.State=="passing" {
        g.autoPass()
    }
    for g.State=="playing" {
        g.play(g.choosePlay())
    }
}
func (g *Game) autoGame() {
    if g.State=="passing" || g.State=="playing" {
        g.autoHand()
    }
    for g.State!="none" {
        g.deal()
        g.autoHand()
    }
}
func duplicate(cards []int) {
    var seen Cards
    for _,c:=range cards { if seen[c] { fail("duplicate card "+cardText(c)) }; seen[c]=true }
}
type Table struct {
    Rules map[string]string
    Bots [4]string
    Game *Game
}
func (t *Table) active() bool {
    return t.Game!=nil && t.Game.State!="none"
}
func (t *Table) require(state string) {
    switch state {
    case "game":
        if !t.active() {
            fail("no game")
        }
    case "between":
        t.require("game"); if t.Game.State!="between" { fail("hand in progress") }
    case "hand":
        if !t.active() || t.Game.State!="passing" && t.Game.State!="playing" {
            fail("no hand")
        }
    default:
        if !t.active() || t.Game.State!=state {
            fail("not "+state)
        }
    }
}
func (t *Table) simulate(cmd string,seed,count int) []string {
    rng:=int64(seed)
    if cmd=="GAME" {
        g:=newGame(t.Rules,&t.Bots,&rng); g.autoGame()
        out:=[]string{fmt.Sprintf("game seed %d",seed)}
        for _,e:=range g.Log { if e.Level<=count { out=append(out,e.Text) } }
        return out
    }
    rounds:=1
    if cmd=="ROTATE" {
        rounds=4
    }
    var places, stats [4][4]int
    var totals [4]int
    hands:=0
    for r:=0;r<rounds;r++ {
        var bots [4]string
        for s:=0;s<4;s++ {
            bots[(s+r)%4]=t.Bots[s]
        }
        for n:=0;n<count;n++ {
            g:=newGame(t.Rules,&bots,&rng); g.autoGame(); hands+=g.Number
            ranking:=g.ranking()
            for s:=0;s<4;s++ {
                actual:=(s+r)%4
                for rank,who:=range ranking { if who==actual { places[s][rank]++ } }
                totals[s]+=g.Scores[actual]
                for k:=0;k<4;k++ {
                    stats[s][k]+=g.Stats[actual][k]
                }
            }
        }
    }
    games:=rounds*count
    out:=[]string{fmt.Sprintf("%s seed %d games %d hands %d",strings.ToLower(cmd),seed,games,hands)}
    for s:=0;s<4;s++ {
        numerator:=100*totals[s]
        cents:=numerator/games
        if numerator<0 && numerator%games!=0 {
            cents--
        }
        sign:=""
        if cents<0 {
            sign="-"
            cents=-cents
        }
        name:=seatText(s)
        if cmd=="ROTATE" {
            name+=" "+t.Bots[s]
        }
        p,v:=places[s],stats[s]
        out = append(out, fmt.Sprintf(
            "%s places %d %d %d %d total %d average %s%d.%02d tricks %d hearts %d queens %d moons %d",
            name, p[0], p[1], p[2], p[3], totals[s], sign, cents/100, cents%100,
            v[0], v[1], v[2], v[3],
        ))
    }
    return out
}
func (t *Table) command(words []string) (out []string) {
    defer func() {
        if caught := recover(); caught != nil {
            if reason, ok := caught.(string); ok {
                out = []string{"error: " + reason}
            } else {
                panic(caught)
            }
        }
    }()
    cmd,args:=words[0],words[1:]
    known:=" RULE BOT SETTINGS GAME MATCH ROTATE NEW ABANDON STACK DEAL SHOW PASS PLAY AUTO UNDO CLAIM LEGAL PREVIEW SCORE TAKEN TRICKS VOIDS UNSEEN STATS HISTORY REPLAY "
    if !strings.Contains(known," "+cmd+" ") {
        fail("unknown command "+cmd)
    }
    switch cmd {
    case "RULE":
        name,value:=args[0],args[1]
        if _,ok:=t.Rules[name];!ok {
            fail("unknown rule "+name)
        }
        valid:=false
        switch name {
        case "TARGET":
            bounded(value,1,1000); valid=true
        case "LIMIT":
            bounded(value,1,100); valid=true
        case "MOON":
            valid=value=="ADD" || value=="SUB" || value=="AUTO"
        case "PASS":
            valid=len(value)>=1 && len(value)<=8 && strings.Trim(value,"LRAH")==""
        default:
            valid=value=="ON" || value=="OFF"
        }
        if !valid {
            fail("bad value "+value)
        }
        if t.active() {
            fail("game in progress")
        }
        t.Rules[name]=value
        return []string{"rule "+name+" "+value}
    case "BOT":
        s:=seatValue(args[0]); strategy:=args[1]
        if !strings.Contains(" BASIC LOW HIGH SMART MOON "," "+strategy+" ") {
            fail("bad value "+strategy)
        }
        t.Bots[s]=strategy
        return []string{"bot "+seatText(s)+" "+strategy}
    case "SETTINGS":
        names:=[]string{"TARGET","LIMIT","MOON","JACK","QSBREAK","BLOOD","PASS"}
        ruleLine:="rules"
        for _,name:=range names {
            ruleLine+=" "+name+" "+t.Rules[name]
        }
        return []string{ruleLine,fmt.Sprintf("bots N %s E %s S %s W %s",t.Bots[0],t.Bots[1],t.Bots[2],t.Bots[3])}
    case "GAME","MATCH","ROTATE":
        seed:=bounded(args[0],1,2147483646)
        low,high:=1,50
        if cmd=="GAME" { low,high=0,2 } else if cmd=="ROTATE" { high=10 }
        return t.simulate(cmd,seed,bounded(args[1],low,high))
    case "NEW":
        seed:=bounded(args[0],1,2147483646)
        if t.active() {
            fail("game in progress")
        }
        rng:=int64(seed); t.Game=newGame(t.Rules,&t.Bots,&rng)
        return []string{fmt.Sprintf("new game seed %d",seed)}
    case "ABANDON":
        t.require("game"); t.Game=nil; return []string{"game abandoned"}
    }
    s:=-1
    cards:=[]int{}
    if cmd=="STACK" || cmd=="PASS" || cmd=="PLAY" || cmd=="CLAIM" {
        s=seatValue(args[0])
    }
    if cmd=="STACK" || cmd=="PASS" || cmd=="PLAY" { for _,word:=range args[1:] { cards=append(cards,cardValue(word)) } }
    if cmd=="STACK" && len(cards)!=13 {
        fail("need 13 cards")
    }
    if cmd=="AUTO" && !strings.Contains(" PASS CARD TRICK HAND GAME "," "+args[0]+" ") {
        fail("bad value "+args[0])
    }
    switch cmd {
    case "STACK","DEAL":
        t.require("between")
    case "SHOW":
        t.require("hand")
    case "PASS":
        t.require("passing")
    case "PLAY","UNDO","CLAIM","LEGAL","PREVIEW","TAKEN","TRICKS","VOIDS","UNSEEN":
        t.require("playing")
    case "SCORE","STATS","HISTORY","REPLAY":
        t.require("game")
    case "AUTO":
        switch args[0] {
        case "PASS":
            t.require("passing")
        case "CARD","TRICK":
            t.require("playing")
        case "HAND":
            t.require("hand")
        default:
            t.require("game")
        }
    }
    g:=t.Game; before:=len(g.Log)
    out=[]string{}
    switch cmd {
    case "STACK":
        duplicate(cards)
        for _, c := range cards {
            for other := 0; other < 4; other++ {
                if other != s && g.Stacked[other][c] {
                    fail(cardText(c) + " stacked for " + seatText(other))
                }
            }
        }
        g.Stacked[s]=asCards(cards)
        return []string{"stacked "+seatText(s)}
    case "DEAL":
        g.deal()
    case "SHOW":
        for s := 0; s < 4; s++ {
            out = append(out, seatText(s) + ": " + cardsText(g.Hands[s]))
        }
        return out
    case "PASS":
        if g.Passed[s] {
            fail(seatText(s)+" already passed")
        }
        duplicate(cards)
        for _, c := range cards {
            if !g.Hands[s][c] {
                fail(seatText(s) + " does not hold " + cardText(c))
            }
        }
        g.passCards(s,cards)
    case "PLAY":
        c:=cards[0]
        if s!=g.actor() {
            fail("waiting for "+seatText(g.actor()))
        }
        if !g.Hands[s][c] {
            fail(seatText(s)+" does not hold "+cardText(c))
        }
        legal:=g.legal()
        if !legal[c] {
            if len(g.Current) == 0 {
                if len(g.Tricks) == 0 { fail("must lead 2C") }
                fail("hearts not broken")
            }
            led:=g.Current[0].Card/13
            if nonempty(filter(g.Hands[s],func(c int) bool { return c/13==led })) { fail("must follow "+string(suits[led])) }
            fail("no points on first trick")
        }
        out=append(out,seatText(s)+" plays "+cardText(c)); g.play(c)
    case "AUTO":
        switch args[0] {
        case "PASS":
            g.autoPass()
        case "CARD":
            s, c := g.actor(), g.choosePlay()
            out = append(out, seatText(s) + " plays " + cardText(c))
            g.play(c)
        case "TRICK":
            count := len(g.Tricks)
            for g.State == "playing" && len(g.Tricks) == count {
                g.play(g.choosePlay())
            }
        case "HAND":
            g.autoHand()
        case "GAME":
            g.autoGame()
        }
    case "UNDO":
        if len(g.Undo)==0 {
            fail("nothing to undo")
        }
        s,c:=g.undoCard(); return []string{"undo "+seatText(s)+" "+cardText(c)}
    case "CLAIM":
        if s!=g.actor() {
            fail("waiting for "+seatText(g.actor()))
        }
        if len(g.Current)>0 {
            fail("trick in progress")
        }
        for _, c := range cardList(g.Hands[s]) {
            for other, hand := range g.Hands {
                if other == s {
                    continue
                }
                for _, d := range cardList(hand) {
                    if d/13 == c/13 && d%13 > c%13 {
                        fail("claim rejected")
                    }
                }
            }
        }
        var remaining Cards
        for _, hand := range g.Hands {
            for c, present := range hand {
                remaining[c] = remaining[c] || present
            }
        }
        count:=13-len(g.Tricks)
        for c,present:=range remaining {
            g.Taken[s][c]=g.Taken[s][c]||present
        }
        g.Counts[s]+=count; g.Hands=[4]Cards{}
        g.write(2,fmt.Sprintf("claim %s tricks %d points %d",seatText(s),count,g.points(remaining))); g.finish()
    case "LEGAL":
        return []string{"legal " + seatText(g.actor()) + ": " + cardsText(g.legal()) + " bot " + cardText(g.choosePlay())}
    case "PREVIEW":
        for _,c:=range cardList(g.legal()) {
            copyGame:=*g
            copyGame.Log=append([]Entry(nil),g.Log...); copyGame.Record=append([]string(nil),g.Record...)
            copyGame.Current=append([]Play(nil),g.Current...); copyGame.Tricks=append([][]Play(nil),g.Tricks...)
            copyGame.Undo=append([]Snapshot(nil),g.Undo...); copyGame.History=append([]HandRecord(nil),g.History...)
            count:=len(copyGame.Tricks); copyGame.play(c)
            for copyGame.State=="playing" && len(copyGame.Tricks)==count {
                copyGame.play(copyGame.choosePlay())
            }
            trick:=copyGame.Tricks[len(copyGame.Tricks)-1]; points:=0
            for _,p:=range trick {
                points+=g.point(p.Card)
            }
            out=append(out,fmt.Sprintf("preview %s -> %s %d",cardText(c),seatText(winner(trick)),points))
        }; return out
    case "SCORE":
        out=append(out,pairs("scores",g.Scores))
        if g.State == "playing" {
            var points [4]int
            for s := 0; s < 4; s++ { points[s] = g.points(g.Taken[s]) }
            out = append(out, pairs("taken", points))
        }
        return out
    case "TAKEN":
        for s := 0; s < 4; s++ {
            cards := filter(g.Taken[s], func(c int) bool { return g.point(c) != 0 })
            out = append(out, seatText(s) + ": " + cardsText(cards))
        }
        return out
    case "TRICKS":
        for n,trick:=range g.Tricks {
            out=append(out,g.trickLine(trick,n+1))
        }
        if len(g.Current)>0 {
            out=append(out,"current: "+playsText(g.Current))
        }
        if len(out)==0 { out=append(out,"no tricks") }; return out
    case "VOIDS":
        var voids [4][4]bool
        tricks:=append(append([][]Play(nil),g.Tricks...),g.Current)
        for _, trick := range tricks {
            if len(trick) == 0 { continue }
            led := trick[0].Card / 13
            for _, p := range trick {
                if p.Card/13 != led { voids[p.Seat][led] = true }
            }
        }
        line:="voids"
        for s := 0; s < 4; s++ {
            missing := ""
            for suit := 0; suit < 4; suit++ {
                if voids[s][suit] {
                    missing += string(suits[suit])
                }
            }
            if missing == "" {
                missing = "-"
            }
            line += " " + seatText(s) + " " + missing
        }
        return []string{line}
    case "UNSEEN":
        unseen:=asCardsRange(); s:=g.actor()
        for c,present:=range g.Hands[s] { if present { unseen[c]=false } }
        for _, hand := range g.Taken {
            for c, present := range hand {
                if present { unseen[c] = false }
            }
        }
        for _,p:=range g.Current {
            unseen[p.Card]=false
        }
        return []string{"unseen "+seatText(s)+": "+cardsText(unseen)}
    case "STATS":
        return g.statsLines()
    case "HISTORY":
        for _, h := range g.History {
            line := fmt.Sprintf("hand %d pass %s %s", h.Number, h.Direction, pairs("points", h.Points))
            if h.Shooter >= 0 {
                line += " moon " + seatText(h.Shooter)
            }
            out = append(out, line)
        }
        if len(out)==0 { out=append(out,"no hands") }; return out
    case "REPLAY":
        h:=bounded(args[0],1,len(g.History)); return append([]string(nil),g.History[h-1].Record...)
    }
    for _,e:=range g.Log[before:] {
        out=append(out,e.Text)
    }
    return out
}
func main() {
    input:=bufio.NewScanner(os.Stdin)
    // STACK has at most 21 argument words of at most ten bytes each.
    input.Buffer(make([]byte,256),256)
    input.Scan(); count,_:=strconv.Atoi(input.Text())
    t := Table{
        Rules: map[string]string{
            "TARGET": "100", "LIMIT": "100", "MOON": "ADD", "JACK": "OFF",
            "QSBREAK": "OFF", "BLOOD": "OFF", "PASS": "LRAH",
        },
        Bots: [4]string{"BASIC", "BASIC", "BASIC", "BASIC"},
    }
    output:=bufio.NewWriter(os.Stdout); defer output.Flush()
    for n:=0;n<count && input.Scan();n++ { for _,line:=range t.command(strings.Split(input.Text()," ")) { fmt.Fprintln(output,line) } }
}
