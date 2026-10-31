package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

var protocols = []string{"SW", "GBN", "SR"}
var keys = []string{
	"PROTOCOL", "FRAMES", "WINDOW", "SEQBITS", "TIMEOUT", "DELAY",
	"INTERVAL", "MAXTICKS", "DUPACK", "NAK", "BACKOFF", "CONGESTION",
	"UNSAFE", "TRACE", "RANDOM", "LOSEDATA", "LOSECTRL", "CORRUPTDATA",
	"CORRUPTCTRL", "DELAYDATA", "DELAYCTRL", "SNAPSHOT",
}
var required = keys[:6]
var listKeys = []string{"LOSEDATA", "LOSECTRL", "CORRUPTDATA", "CORRUPTCTRL", "DELAYDATA", "DELAYCTRL", "SNAPSHOT"}
var choices = map[string][]string{
	"PROTOCOL": protocols,
	"NAK":      {"ON", "OFF"}, "BACKOFF": {"ON", "OFF"},
	"CONGESTION": {"ON", "OFF"}, "UNSAFE": {"ON", "OFF"},
	"TRACE": {"ALL", "SENDER", "RECEIVER", "NONE"},
}
var ranges = map[string][2]int{
	"FRAMES": {1, 60}, "WINDOW": {1, 32}, "SEQBITS": {1, 6},
	"TIMEOUT": {1, 50}, "DELAY": {1, 10}, "INTERVAL": {0, 10},
	"MAXTICKS": {1, 2000}, "DUPACK": {1, 10},
	"LOSEDATA": {1, 9999}, "LOSECTRL": {1, 9999},
	"CORRUPTDATA": {1, 9999}, "CORRUPTCTRL": {1, 9999},
	"SNAPSHOT": {0, 2000},
}
var traceSides = map[string][]string{
	"ALL": {"SENDER", "RECEIVER"}, "SENDER": {"SENDER"},
	"RECEIVER": {"RECEIVER"}, "NONE": {},
}

const randomMultiplier = 48271
const randomModulus = 2147483647
const unset = -1

type SettingLine struct {
	Key    string
	Values []string
}

func includes(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}

func atoi(s string) int {
	value, _ := strconv.Atoi(s)
	return value
}

func inRange(value int, interval [2]int) bool {
	return value >= interval[0] && value <= interval[1]
}

func truncated(numerator, denominator, digits int) string {
	scale := 1
	for i := 0; i < digits; i++ {
		scale *= 10
	}
	value := numerator * scale / denominator
	return fmt.Sprintf("%d.%0*d", value/scale, digits, value%scale)
}

func tickText(value int) string {
	if value == unset {
		return "-"
	}
	return strconv.Itoa(value)
}

func mod(value, modulus int) int {
	return (value%modulus + modulus) % modulus
}

func option(settings map[string][]string, key, fallback string) string {
	if values, ok := settings[key]; ok {
		return values[0]
	}
	return fallback
}

func numberSet(settings map[string][]string, key string) map[int]bool {
	result := make(map[int]bool)
	for _, value := range settings[key] {
		result[atoi(value)] = true
	}
	return result
}

func delayMap(settings map[string][]string, key string) map[int]int {
	result := make(map[int]int)
	for _, value := range settings[key] {
		parts := strings.SplitN(value, ":", 2)
		result[atoi(parts[0])] = atoi(parts[1])
	}
	return result
}

func validValue(key string, values []string) bool {
	if alternatives, ok := choices[key]; ok {
		return includes(alternatives, values[0])
	}
	if bounds, ok := ranges[key]; ok && !includes(listKeys, key) {
		return inRange(atoi(values[0]), bounds)
	}
	if key == "RANDOM" {
		seed, loss, corrupt := atoi(values[0]), atoi(values[1]), atoi(values[2])
		return inRange(seed, [2]int{1, randomModulus - 1}) && loss >= 0 &&
			corrupt >= 0 && loss+corrupt <= 100
	}
	seen := make(map[int]bool)
	for _, value := range values {
		if key == "DELAYDATA" || key == "DELAYCTRL" {
			parts := strings.SplitN(value, ":", 2)
			n, extra := atoi(parts[0]), atoi(parts[1])
			if !inRange(n, [2]int{1, 9999}) || !inRange(extra, [2]int{1, 50}) || seen[n] {
				return false
			}
			seen[n] = true
			continue
		}
		number := atoi(value)
		if !inRange(number, ranges[key]) || seen[number] {
			return false
		}
		seen[number] = true
	}
	return true
}

type Config struct {
	Protocol    string
	Frames      int
	Window      int
	Seqbits     int
	Timeout     int
	Delay       int
	Interval    int
	Limit       int
	Dupack      int
	Nak         bool
	Backoff     bool
	Congestion  bool
	Unsafe      bool
	Trace       string
	Random      []int
	LoseData    map[int]bool
	LoseCtrl    map[int]bool
	CorruptData map[int]bool
	CorruptCtrl map[int]bool
	DelayData   map[int]int
	DelayCtrl   map[int]int
	Snapshots   map[int]bool
}

func newConfig(settings map[string][]string) *Config {
	config := &Config{
		Protocol:    option(settings, "PROTOCOL", ""),
		Frames:      atoi(option(settings, "FRAMES", "0")),
		Window:      atoi(option(settings, "WINDOW", "0")),
		Seqbits:     atoi(option(settings, "SEQBITS", "0")),
		Timeout:     atoi(option(settings, "TIMEOUT", "0")),
		Delay:       atoi(option(settings, "DELAY", "0")),
		Interval:    atoi(option(settings, "INTERVAL", "0")),
		Limit:       atoi(option(settings, "MAXTICKS", "1000")),
		Dupack:      unset,
		Nak:         option(settings, "NAK", "OFF") == "ON",
		Backoff:     option(settings, "BACKOFF", "OFF") == "ON",
		Congestion:  option(settings, "CONGESTION", "OFF") == "ON",
		Unsafe:      option(settings, "UNSAFE", "OFF") == "ON",
		Trace:       option(settings, "TRACE", "ALL"),
		LoseData:    numberSet(settings, "LOSEDATA"),
		LoseCtrl:    numberSet(settings, "LOSECTRL"),
		CorruptData: numberSet(settings, "CORRUPTDATA"),
		CorruptCtrl: numberSet(settings, "CORRUPTCTRL"),
		DelayData:   delayMap(settings, "DELAYDATA"),
		DelayCtrl:   delayMap(settings, "DELAYCTRL"),
		Snapshots:   numberSet(settings, "SNAPSHOT"),
	}
	if values, ok := settings["DUPACK"]; ok {
		config.Dupack = atoi(values[0])
	}
	if values, ok := settings["RANDOM"]; ok {
		for _, value := range values {
			config.Random = append(config.Random, atoi(value))
		}
	}
	return config
}

func (config *Config) windowLimit() int {
	switch config.Protocol {
	case "SW":
		return 1
	case "GBN":
		return (1 << config.Seqbits) - 1
	default:
		return 1 << (config.Seqbits - 1)
	}
}

func (config *Config) configLine() string {
	return fmt.Sprintf("config: %s n=%d w=%d k=%d T=%d d=%d",
		config.Protocol, config.Frames, config.Window, config.Seqbits, config.Timeout, config.Delay)
}

func switchText(flag bool) string {
	if flag {
		return "on"
	}
	return "off"
}

func (config *Config) optionsLine() string {
	dupack := "off"
	if config.Dupack >= 0 {
		dupack = strconv.Itoa(config.Dupack)
	}
	random := "off"
	if len(config.Random) != 0 {
		numbers := make([]string, len(config.Random))
		for i, value := range config.Random {
			numbers[i] = strconv.Itoa(value)
		}
		random = strings.Join(numbers, "/")
	}
	return fmt.Sprintf("options: interval=%d limit=%d dupack=%s nak=%s backoff=%s congestion=%s unsafe=%s trace=%s random=%s",
		config.Interval, config.Limit, dupack, switchText(config.Nak), switchText(config.Backoff),
		switchText(config.Congestion), switchText(config.Unsafe), strings.ToLower(config.Trace), random)
}

func checkSettings(lines []SettingLine) (*Config, error) {
	settings := make(map[string][]string)
	for _, line := range lines {
		key, values := line.Key, line.Values
		if !includes(keys, key) {
			return nil, fmt.Errorf("unknown key %s", key)
		}
		if _, exists := settings[key]; exists {
			return nil, fmt.Errorf("duplicate key %s", key)
		}
		countOK := len(values) == 1
		if key == "RANDOM" {
			countOK = len(values) == 3
		} else if includes(listKeys, key) {
			countOK = len(values) >= 1
		}
		if !countOK {
			return nil, fmt.Errorf("wrong number of values for %s", key)
		}
		settings[key] = values
	}
	for _, key := range required {
		if _, exists := settings[key]; !exists {
			return nil, fmt.Errorf("missing key %s", key)
		}
	}
	for _, key := range keys {
		if values, exists := settings[key]; exists && !validValue(key, values) {
			return nil, fmt.Errorf("bad value for %s", key)
		}
	}
	config := newConfig(settings)
	if config.Protocol == "SR" && config.Dupack != unset {
		return nil, fmt.Errorf("DUPACK not supported for SR")
	}
	if (config.Protocol == "SW" || !config.Unsafe) && config.Window > config.windowLimit() {
		return nil, fmt.Errorf("window %d exceeds limit %d for %s",
			config.Window, config.windowLimit(), config.Protocol)
	}
	for number := 1; number <= 9999; number++ {
		if config.LoseData[number] && config.CorruptData[number] {
			return nil, fmt.Errorf("data #%d both lost and corrupted", number)
		}
	}
	for number := 1; number <= 9999; number++ {
		if config.LoseCtrl[number] && config.CorruptCtrl[number] {
			return nil, fmt.Errorf("control #%d both lost and corrupted", number)
		}
	}
	return config, nil
}

type FrameRecord struct {
	Transmissions int
	First         int
	Delivered     int
	Acked         int
}

type Transmission struct {
	Number  int
	Kind    string
	Value   int
	Payload int
	Outcome string
	Arrival int
}

type LossGenerator struct {
	State      int
	Loss       int
	Corruption int
}

func (generator *LossGenerator) nextOutcome() string {
	generator.State = randomMultiplier * generator.State % randomModulus
	roll := generator.State % 100
	if roll < generator.Loss {
		return "LOST"
	}
	if roll < generator.Loss+generator.Corruption {
		return "CORRUPT"
	}
	return "NORMAL"
}

type Channel struct {
	Delay       int
	Losses      map[int]bool
	Corruptions map[int]bool
	ExtraDelays map[int]int
	Sent        int
	Lost        int
	Corrupted   int
	InTransit   []Transmission
}

func (channel *Channel) send(kind string, value, payload, tick int, generator *LossGenerator) Transmission {
	channel.Sent++
	outcome := "NORMAL"
	if generator != nil {
		outcome = generator.nextOutcome()
	}
	if channel.Losses[channel.Sent] {
		outcome = "LOST"
	} else if channel.Corruptions[channel.Sent] {
		outcome = "CORRUPT"
	}
	item := Transmission{channel.Sent, kind, value, payload, outcome,
		tick + channel.Delay + channel.ExtraDelays[channel.Sent]}
	channel.InTransit = append(channel.InTransit, item)
	return item
}

func (channel *Channel) arrivals(tick int) []Transmission {
	arrived := make([]Transmission, 0)
	remaining := make([]Transmission, 0, len(channel.InTransit))
	for _, item := range channel.InTransit {
		if item.Arrival == tick {
			arrived = append(arrived, item)
		} else {
			remaining = append(remaining, item)
		}
	}
	channel.InTransit = remaining
	return arrived
}

func (channel *Channel) countDamage(item Transmission) {
	if item.Outcome == "LOST" {
		channel.Lost++
	} else {
		channel.Corrupted++
	}
}

type Simulation struct {
	Config          *Config
	Selective       bool
	Modulus         int
	Visible         map[string]bool
	Generator       *LossGenerator
	DataChannel     Channel
	ControlChannel  Channel
	Records         []FrameRecord
	Lines           []string
	Tick            int
	Base            int
	FramesSent      int
	NextFrame       int
	TimerLength     int
	Timer           int
	Duplicates      int
	Acked           []bool
	Timers          []int
	Queue           []int
	Cwnd            int
	Ssthresh        int
	RoundAcks       int
	Expected        int
	NakSent         bool
	Buffer          map[int]int
	Resent          int
	Naks            int
	Timeouts        int
	FastRetransmits int
	Delivered       int
	Errors          int
	Discarded       int
	MaxBuffer       int
	Completion      int
}

func newSimulation(config *Config) *Simulation {
	visible := make(map[string]bool)
	for _, side := range traceSides[config.Trace] {
		visible[side] = true
	}
	simulation := &Simulation{
		Config:    config,
		Selective: config.Protocol == "SR",
		Modulus:   1 << config.Seqbits,
		Visible:   visible,
		DataChannel: Channel{Delay: config.Delay, Losses: config.LoseData,
			Corruptions: config.CorruptData, ExtraDelays: config.DelayData},
		ControlChannel: Channel{Delay: config.Delay, Losses: config.LoseCtrl,
			Corruptions: config.CorruptCtrl, ExtraDelays: config.DelayCtrl},
		Records:     make([]FrameRecord, config.Frames),
		TimerLength: config.Timeout,
		Timer:       unset,
		Acked:       make([]bool, config.Frames),
		Timers:      make([]int, config.Frames),
		Cwnd:        1,
		Ssthresh:    config.Window,
		Buffer:      make(map[int]int),
		Completion:  unset,
	}
	for i := range simulation.Records {
		simulation.Records[i].First = unset
		simulation.Records[i].Delivered = unset
		simulation.Records[i].Acked = unset
		simulation.Timers[i] = unset
	}
	if len(config.Random) > 0 {
		simulation.Generator = &LossGenerator{config.Random[0], config.Random[1], config.Random[2]}
	}
	return simulation
}

func (simulation *Simulation) emit(parts ...any) {
	fields := make([]string, 0, len(parts)+1)
	fields = append(fields, strconv.Itoa(simulation.Tick))
	for _, part := range parts {
		fields = append(fields, fmt.Sprint(part))
	}
	simulation.Lines = append(simulation.Lines, strings.Join(fields, " "))
}

func (simulation *Simulation) trace(side string, parts ...any) {
	if simulation.Visible[side] {
		simulation.emit(parts...)
	}
}

func (simulation *Simulation) frameOf(value int) int {
	return simulation.Base + mod(value-simulation.Base, simulation.Modulus)
}

func (simulation *Simulation) effectiveWindow() int {
	if simulation.Config.Congestion && simulation.Cwnd < simulation.Config.Window {
		return simulation.Cwnd
	}
	return simulation.Config.Window
}

func (simulation *Simulation) run() {
	for tick := 0; tick <= simulation.Config.Limit; tick++ {
		simulation.Tick = tick
		for _, item := range simulation.DataChannel.arrivals(tick) {
			if item.Outcome == "NORMAL" {
				simulation.receiveData(item)
			} else {
				simulation.reportDamage(&simulation.DataChannel, item, "RECEIVER")
			}
		}
		for _, item := range simulation.ControlChannel.arrivals(tick) {
			if item.Outcome == "NORMAL" {
				simulation.receiveControl(item)
			} else {
				simulation.reportDamage(&simulation.ControlChannel, item, "SENDER")
			}
		}
		completed := simulation.Base == simulation.Config.Frames
		if !completed {
			simulation.processTimeouts()
			simulation.sendData()
		}
		if simulation.Config.Snapshots[tick] {
			simulation.snapshot()
		}
		if completed {
			simulation.Completion = tick
			simulation.emit("DONE")
			return
		}
	}
	simulation.emit("ABORT")
}

func (simulation *Simulation) reportDamage(channel *Channel, item Transmission, side string) {
	channel.countDamage(item)
	simulation.trace(side, item.Outcome, item.Kind, fmt.Sprintf("#%d", item.Number))
}

func (simulation *Simulation) receiveData(item Transmission) {
	simulation.trace("RECEIVER", "RECV", fmt.Sprintf("seq=%d", item.Value), fmt.Sprintf("#%d", item.Number))
	if simulation.Selective {
		simulation.selectiveReceive(item.Value, item.Payload)
	} else {
		simulation.goBackNReceive(item.Value, item.Payload)
	}
}

func (simulation *Simulation) goBackNReceive(seq, payload int) {
	if seq == simulation.Expected%simulation.Modulus {
		simulation.deliver(payload)
		simulation.sendControl("ack", seq)
		return
	}
	simulation.discard(seq)
	if simulation.Config.Nak && !simulation.NakSent {
		simulation.sendControl("nak", simulation.Expected%simulation.Modulus)
		simulation.NakSent = true
	} else if simulation.Expected > 0 {
		simulation.sendControl("ack", (simulation.Expected-1)%simulation.Modulus)
	}
}

func (simulation *Simulation) selectiveReceive(seq, payload int) {
	offset := mod(seq-simulation.Expected, simulation.Modulus)
	if offset >= simulation.Config.Window {
		simulation.discard(seq)
		if mod(simulation.Expected-seq, simulation.Modulus) <= simulation.Config.Window {
			simulation.sendControl("ack", seq)
		}
		return
	}
	position := simulation.Expected + offset
	if _, exists := simulation.Buffer[position]; exists {
		simulation.discard(seq)
		simulation.sendControl("ack", seq)
	} else if offset == 0 {
		simulation.deliver(payload)
		for {
			waiting, exists := simulation.Buffer[simulation.Expected]
			if !exists {
				break
			}
			delete(simulation.Buffer, simulation.Expected)
			simulation.deliver(waiting)
		}
		simulation.sendControl("ack", seq)
	} else {
		simulation.Buffer[position] = payload
		if len(simulation.Buffer) > simulation.MaxBuffer {
			simulation.MaxBuffer = len(simulation.Buffer)
		}
		simulation.trace("RECEIVER", "BUFFER", fmt.Sprintf("f=%d", position))
		simulation.sendControl("ack", seq)
		if simulation.Config.Nak && !simulation.NakSent {
			simulation.sendControl("nak", simulation.Expected%simulation.Modulus)
			simulation.NakSent = true
		}
	}
}

func (simulation *Simulation) deliver(payload int) {
	position := simulation.Expected
	if payload == position {
		simulation.Delivered++
		simulation.Records[payload].Delivered = simulation.Tick
		simulation.trace("RECEIVER", "DELIVER", fmt.Sprintf("f=%d", position))
	} else {
		simulation.Errors++
		simulation.trace("RECEIVER", "DELIVER", fmt.Sprintf("f=%d", position), fmt.Sprintf("wrong=%d", payload))
	}
	simulation.Expected++
	simulation.NakSent = false
}

func (simulation *Simulation) discard(seq int) {
	simulation.Discarded++
	simulation.trace("RECEIVER", "DISCARD", fmt.Sprintf("seq=%d", seq))
}

func (simulation *Simulation) sendControl(kind string, value int) {
	item := simulation.ControlChannel.send(kind, value, unset, simulation.Tick, simulation.Generator)
	if kind == "nak" {
		simulation.Naks++
	}
	simulation.trace("RECEIVER", strings.ToUpper(kind), fmt.Sprintf("a=%d", value), fmt.Sprintf("#%d", item.Number))
}

func (simulation *Simulation) receiveControl(item Transmission) {
	before := [2]int{simulation.Cwnd, simulation.Ssthresh}
	if item.Kind == "ack" {
		if simulation.Selective {
			simulation.selectiveAck(item)
		} else {
			simulation.goBackNAck(item)
		}
	} else if simulation.Selective {
		simulation.selectiveNak(item)
	} else {
		simulation.goBackNNak(item)
	}
	simulation.reportWindow(before)
}

func (simulation *Simulation) controlLine(item Transmission, accepted bool) {
	prefix := "OLD"
	if accepted {
		prefix = "GOT"
	}
	parts := []any{prefix + strings.ToUpper(item.Kind), fmt.Sprintf("a=%d", item.Value), fmt.Sprintf("#%d", item.Number)}
	if accepted {
		parts = append(parts, fmt.Sprintf("base=%d", simulation.Base))
	}
	simulation.trace("SENDER", parts...)
}

func (simulation *Simulation) goBackNAck(item Transmission) {
	frame := simulation.frameOf(item.Value)
	if frame < simulation.FramesSent {
		simulation.growWindow(frame - simulation.Base + 1)
		simulation.moveBase(frame + 1)
		if simulation.NextFrame < simulation.Base {
			simulation.NextFrame = simulation.Base
		}
		if simulation.Base == simulation.NextFrame {
			simulation.Timer = unset
		} else {
			simulation.Timer = simulation.Tick + simulation.TimerLength
		}
		simulation.controlLine(item, true)
		return
	}
	simulation.controlLine(item, false)
	if simulation.Config.Dupack == unset || simulation.Base < 1 {
		return
	}
	if item.Value == (simulation.Base-1)%simulation.Modulus {
		simulation.Duplicates++
		if simulation.Duplicates == simulation.Config.Dupack {
			simulation.FastRetransmits++
			simulation.trace("SENDER", "FASTRETX", fmt.Sprintf("f=%d", simulation.Base))
			simulation.goBack()
			simulation.halveWindow()
		}
	}
}

func (simulation *Simulation) goBackNNak(item Transmission) {
	frame := simulation.frameOf(item.Value)
	if frame > simulation.FramesSent {
		simulation.controlLine(item, false)
		return
	}
	simulation.growWindow(frame - simulation.Base)
	simulation.moveBase(frame)
	simulation.goBack()
	simulation.halveWindow()
	simulation.controlLine(item, true)
}

func (simulation *Simulation) selectiveAck(item Transmission) {
	frame := simulation.frameOf(item.Value)
	if frame >= simulation.FramesSent || simulation.Acked[frame] {
		simulation.controlLine(item, false)
		return
	}
	simulation.Acked[frame] = true
	simulation.Records[frame].Acked = simulation.Tick
	simulation.Timers[frame] = unset
	for index, queued := range simulation.Queue {
		if queued == frame {
			simulation.Queue = append(simulation.Queue[:index], simulation.Queue[index+1:]...)
			break
		}
	}
	simulation.growWindow(1)
	previous := simulation.Base
	for simulation.Base < simulation.FramesSent && simulation.Acked[simulation.Base] {
		simulation.Base++
	}
	if simulation.Base > previous {
		simulation.TimerLength = simulation.Config.Timeout
	}
	simulation.controlLine(item, true)
}

func (simulation *Simulation) selectiveNak(item Transmission) {
	frame := simulation.frameOf(item.Value)
	if frame >= simulation.FramesSent || simulation.Acked[frame] {
		simulation.controlLine(item, false)
		return
	}
	simulation.Timers[frame] = unset
	alreadyQueued := false
	for _, queued := range simulation.Queue {
		if queued == frame {
			alreadyQueued = true
			break
		}
	}
	if !alreadyQueued {
		simulation.Queue = append(simulation.Queue, frame)
	}
	simulation.halveWindow()
	simulation.controlLine(item, true)
}

func (simulation *Simulation) moveBase(newBase int) {
	if newBase <= simulation.Base {
		return
	}
	for frame := simulation.Base; frame < newBase; frame++ {
		simulation.Records[frame].Acked = simulation.Tick
	}
	simulation.Base = newBase
	simulation.TimerLength = simulation.Config.Timeout
	simulation.Duplicates = 0
}

func (simulation *Simulation) goBack() {
	simulation.NextFrame = simulation.Base
	simulation.Timer = unset
	simulation.Duplicates = 0
}

func (simulation *Simulation) growWindow(count int) {
	if !simulation.Config.Congestion {
		return
	}
	for i := 0; i < count; i++ {
		if simulation.Cwnd >= simulation.Config.Window {
			continue
		}
		if simulation.Cwnd < simulation.Ssthresh {
			simulation.Cwnd++
		} else {
			simulation.RoundAcks++
			if simulation.RoundAcks == simulation.Cwnd {
				simulation.Cwnd++
				simulation.RoundAcks = 0
			}
		}
	}
}

func (simulation *Simulation) halveWindow() {
	if simulation.Config.Congestion {
		simulation.Ssthresh = max(simulation.Cwnd/2, 1)
		simulation.Cwnd = simulation.Ssthresh
		simulation.RoundAcks = 0
	}
}

func (simulation *Simulation) collapseWindow() {
	if simulation.Config.Congestion {
		simulation.Ssthresh = max(simulation.Cwnd/2, 1)
		simulation.Cwnd = 1
		simulation.RoundAcks = 0
	}
}

func (simulation *Simulation) reportWindow(before [2]int) {
	if simulation.Cwnd != before[0] || simulation.Ssthresh != before[1] {
		simulation.trace("SENDER", "CWND", simulation.Cwnd, fmt.Sprintf("ssthresh=%d", simulation.Ssthresh))
	}
}

func (simulation *Simulation) processTimeouts() {
	if simulation.Selective {
		for frame := simulation.Base; frame < simulation.FramesSent; frame++ {
			if simulation.Timers[frame] == simulation.Tick {
				simulation.Timers[frame] = unset
				simulation.Queue = append(simulation.Queue, frame)
				simulation.timeOut(frame)
			}
		}
	} else if simulation.Timer == simulation.Tick {
		simulation.timeOut(simulation.Base)
		simulation.goBack()
	}
}

func (simulation *Simulation) timeOut(frame int) {
	before := [2]int{simulation.Cwnd, simulation.Ssthresh}
	simulation.Timeouts++
	simulation.trace("SENDER", "TIMEOUT", fmt.Sprintf("f=%d", frame))
	if simulation.Config.Backoff {
		simulation.TimerLength = min(2*simulation.TimerLength, 8*simulation.Config.Timeout)
	}
	simulation.collapseWindow()
	simulation.reportWindow(before)
}

func (simulation *Simulation) maySendNew(frame int) bool {
	return frame < simulation.Config.Frames && frame < simulation.Base+simulation.effectiveWindow() &&
		frame*simulation.Config.Interval <= simulation.Tick
}

func (simulation *Simulation) sendData() {
	if simulation.Selective {
		simulation.selectiveSend()
	} else {
		simulation.goBackNSend()
	}
}

func (simulation *Simulation) goBackNSend() {
	frame := simulation.NextFrame
	if frame >= simulation.Config.Frames || frame >= simulation.Base+simulation.effectiveWindow() {
		return
	}
	if frame >= simulation.FramesSent && frame*simulation.Config.Interval > simulation.Tick {
		return
	}
	simulation.transmit(frame)
	simulation.FramesSent = max(simulation.FramesSent, frame+1)
	simulation.NextFrame++
	if simulation.Timer == unset {
		simulation.Timer = simulation.Tick + simulation.TimerLength
	}
}

func (simulation *Simulation) selectiveSend() {
	frame := 0
	if len(simulation.Queue) > 0 {
		frame = simulation.Queue[0]
		simulation.Queue = simulation.Queue[1:]
	} else if simulation.maySendNew(simulation.FramesSent) {
		frame = simulation.FramesSent
		simulation.FramesSent++
	} else {
		return
	}
	simulation.transmit(frame)
	simulation.Timers[frame] = simulation.Tick + simulation.TimerLength
}

func (simulation *Simulation) transmit(frame int) {
	record := &simulation.Records[frame]
	seq := frame % simulation.Modulus
	item := simulation.DataChannel.send("data", seq, frame, simulation.Tick, simulation.Generator)
	record.Transmissions++
	label := "SEND"
	if record.Transmissions == 1 {
		record.First = simulation.Tick
	} else {
		simulation.Resent++
		label = "RESEND"
	}
	simulation.trace("SENDER", label, fmt.Sprintf("f=%d", frame), fmt.Sprintf("seq=%d", seq), fmt.Sprintf("#%d", item.Number))
}

func (simulation *Simulation) senderMark(frame int) string {
	acknowledged, waiting, sent := false, false, false
	if simulation.Selective {
		acknowledged = simulation.Acked[frame]
		for _, queued := range simulation.Queue {
			if queued == frame {
				waiting = true
				break
			}
		}
		sent = frame < simulation.FramesSent
	} else {
		acknowledged = frame < simulation.Base
		waiting = simulation.NextFrame <= frame && frame < simulation.FramesSent
		sent = frame < simulation.NextFrame
	}
	if acknowledged {
		return "A"
	}
	if waiting {
		return "R"
	}
	if sent {
		return "O"
	}
	if frame < simulation.Base+simulation.effectiveWindow() {
		return "W"
	}
	return "."
}

func (simulation *Simulation) receiverMark(position int) string {
	if position < simulation.Expected {
		return "D"
	}
	if simulation.Selective {
		if _, exists := simulation.Buffer[position]; exists {
			return "B"
		}
		if position < simulation.Expected+simulation.Config.Window {
			return "W"
		}
	} else if position == simulation.Expected {
		return "W"
	}
	return "."
}

func (simulation *Simulation) snapshot() {
	var sender, receiver strings.Builder
	for frame := 0; frame < simulation.Config.Frames; frame++ {
		sender.WriteString(simulation.senderMark(frame))
		receiver.WriteString(simulation.receiverMark(frame))
	}
	simulation.emit("SNAPSHOT", "sender="+sender.String(), "receiver="+receiver.String())
}

func (simulation *Simulation) dataCount() int { return simulation.DataChannel.Sent }
func (simulation *Simulation) goodputText() string {
	return truncated(simulation.Delivered, simulation.Completion, 2)
}
func (simulation *Simulation) efficiencyText() string {
	return truncated(100*simulation.Delivered, simulation.dataCount(), 1)
}
func (simulation *Simulation) latencyText() string {
	if simulation.Delivered == 0 {
		return "-"
	}
	total := 0
	for _, record := range simulation.Records {
		if record.Delivered != unset {
			total += record.Delivered - record.First
		}
	}
	return truncated(total, simulation.Delivered, 2)
}

func (simulation *Simulation) report() []string {
	lines := make([]string, 0, simulation.Config.Frames+5)
	for frame, record := range simulation.Records {
		lines = append(lines, fmt.Sprintf("frame %d: seq=%d tx=%d first=%s delivered=%s acked=%s",
			frame, frame%simulation.Modulus, record.Transmissions,
			tickText(record.First), tickText(record.Delivered), tickText(record.Acked)))
	}
	data, control := simulation.DataChannel, simulation.ControlChannel
	lines = append(lines, fmt.Sprintf("totals: data=%d resent=%d control=%d nak=%d timeouts=%d fastretx=%d",
		data.Sent, simulation.Resent, control.Sent, simulation.Naks, simulation.Timeouts, simulation.FastRetransmits))
	lines = append(lines, fmt.Sprintf("channel: lost_data=%d lost_ctrl=%d corrupt_data=%d corrupt_ctrl=%d",
		data.Lost, control.Lost, data.Corrupted, control.Corrupted))
	lines = append(lines, fmt.Sprintf("receiver: delivered=%d errors=%d discarded=%d max_buffer=%d",
		simulation.Delivered, simulation.Errors, simulation.Discarded, simulation.MaxBuffer))
	completion, goodput := "-", "-"
	if simulation.Completion != unset {
		completion = strconv.Itoa(simulation.Completion)
		goodput = simulation.goodputText()
	}
	utilization := truncated(100*data.Sent, simulation.Tick+1, 1)
	lines = append(lines, fmt.Sprintf("result: completion=%s goodput=%s efficiency=%s%% utilization=%s%% latency=%s",
		completion, goodput, simulation.efficiencyText(), utilization, simulation.latencyText()))
	return lines
}

type Scenario struct {
	Name       string
	Settings   []SettingLine
	Config     *Config
	Simulation *Simulation
}

func (scenario *Scenario) completed() bool {
	return scenario.Simulation != nil && scenario.Simulation.Completion != unset
}

func (scenario *Scenario) status() string {
	if scenario.Simulation == nil {
		return "invalid"
	}
	return "aborted"
}

func (scenario *Scenario) execute(output *[]string) {
	*output = append(*output, fmt.Sprintf("== %s ==", scenario.Name))
	config, err := checkSettings(scenario.Settings)
	if err != nil {
		*output = append(*output, "error: "+err.Error())
		return
	}
	scenario.Config = config
	*output = append(*output, config.configLine(), config.optionsLine())
	scenario.Simulation = newSimulation(config)
	scenario.Simulation.run()
	*output = append(*output, scenario.Simulation.Lines...)
	*output = append(*output, scenario.Simulation.report()...)
}

func rankingLines(scenarios []*Scenario) []string {
	lines := []string{"== ranking =="}
	var completed []*Scenario
	for _, scenario := range scenarios {
		if scenario.completed() {
			completed = append(completed, scenario)
		}
	}
	sort.SliceStable(completed, func(i, j int) bool {
		x, y := completed[i].Simulation, completed[j].Simulation
		left, right := x.Delivered*y.Completion, y.Delivered*x.Completion
		if left != right {
			return left > right
		}
		return x.Delivered*y.dataCount() > y.Delivered*x.dataCount()
	})
	for rank, scenario := range completed {
		run := scenario.Simulation
		lines = append(lines, fmt.Sprintf("%d. %s %s goodput=%s efficiency=%s%%",
			rank+1, scenario.Name, scenario.Config.Protocol, run.goodputText(), run.efficiencyText()))
	}
	for _, scenario := range scenarios {
		if !scenario.completed() {
			lines = append(lines, fmt.Sprintf("- %s %s", scenario.Name, scenario.status()))
		}
	}
	return lines
}

func protocolLines(scenarios []*Scenario) []string {
	lines := []string{"== protocols =="}
	for _, protocol := range protocols {
		runs, delivered, ticks, data := 0, 0, 0, 0
		for _, scenario := range scenarios {
			if scenario.completed() && scenario.Config.Protocol == protocol {
				runs++
				delivered += scenario.Simulation.Delivered
				ticks += scenario.Simulation.Completion
				data += scenario.Simulation.dataCount()
			}
		}
		if runs > 0 {
			lines = append(lines, fmt.Sprintf("%s: runs=%d goodput=%s efficiency=%s%%",
				protocol, runs, truncated(delivered, ticks, 2), truncated(100*delivered, data, 1)))
		}
	}
	return lines
}

func readScenarios(lines []string) []*Scenario {
	count := atoi(lines[0])
	index := 1
	scenarios := make([]*Scenario, 0, count)
	for i := 0; i < count; i++ {
		name := strings.Split(lines[index], " ")[1]
		index++
		settings := make([]SettingLine, 0)
		for lines[index] != "END" {
			parts := strings.Split(lines[index], " ")
			settings = append(settings, SettingLine{parts[0], parts[1:]})
			index++
		}
		index++
		scenarios = append(scenarios, &Scenario{Name: name, Settings: settings})
	}
	return scenarios
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 4096), 1024*1024)
	var lines []string
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
	}
	scenarios := readScenarios(lines)
	var output []string
	for _, scenario := range scenarios {
		scenario.execute(&output)
	}
	output = append(output, rankingLines(scenarios)...)
	output = append(output, protocolLines(scenarios)...)
	fmt.Println(strings.Join(output, "\n"))
}
