package main

import (
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Traffic struct {
	time     int
	id, body string
}
type Server struct {
	config   map[string]string
	motd     []string
	traffic  []Traffic
	clients  []*Client
	channels []*Channel
	byID     map[string]*Client
	time,
	end int
	sent, gone  []string
	commands    map[string]int
	numerics    map[int]int
	disconnects map[string]int
	connectLines,
	disconnectLines, messageLines, dropped, queued, processed, discarded, empty, pings, errors, peakConnections,
	peakConnectionsAt, peakRegistered, peakRegisteredAt int
}

func number(s string) int { v, _ := strconv.Atoi(s); return v }
func readLines(path string) []string {
	b, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	if len(b) == 0 {
		return nil
	}
	return strings.Split(strings.TrimSuffix(string(b),
		"\n"), "\n")
}
func (s *Server) setting(key string) int { return number(s.config[key]) }
func (s *Server) send(c *Client, text string) {
	s.sent = append(s.sent, fmt.Sprintf("%d %s %s", s.time, c.id, text))
	c.sent++
}
func (s *Server) numeric(c *Client, n int, format string, a ...any) {
	s.numerics[n]++
	s.send(c, fmt.Sprintf(":%s %03d %s %s",
		s.config["NAME"], n, c.addressee(), fmt.Sprintf(format, a...)))
}
func (s *Server) errorReply(c *Client, n int, target string) {
	text := map[int]string{401: ":No such nick/channel",
		403: ":No such channel", 404: ":Cannot send to channel", 405: ":You have joined too many channels",
		431: ":No nickname given", 432: ":Erroneous nickname", 433: ":Nickname is already in use", 442: ":You're not on that channel",
		451: ":You have not registered", 462: ":You may not reregister", 467: ":Channel key already set", 471: ":Cannot join channel (+l)",
		473: ":Cannot join channel (+i)", 474: ":Cannot join channel (+b)", 475: ":Cannot join channel (+k)",
		482: ":You're not channel operator", 501: ":Unknown MODE flag", 502: ":Cannot change mode for other users"}[n]
	if target != "" {
		text = target + " " + text
	}
	s.numeric(c,
		n, "%s", text)
}
func (s *Server) user(nick string) *Client {
	for _, c := range s.clients {
		if c.registered && fold(c.nick) == fold(nick) {
			return c
		}
	}
	return nil
}
func (s *Server) channel(name string) *Channel {
	for _, ch := range s.channels {
		if fold(ch.name) == fold(name) {
			return ch
		}
	}
	return nil
}
func (s *Server) members(ch *Channel, except *Client, text string) {
	for _, m := range ch.members {
		if m.client != except {
			s.send(m.client, text)
		}
	}
}
func (s *Server) peers(c *Client, text string) {
	for _, other := range s.clients {
		if other == c {
			continue
		}
		for _, ch := range c.channels {
			if ch.member(other) != nil {
				s.send(other, text)
				break
			}
		}
	}
}
func (s *Server) remove(c *Client, ch *Channel) {
	ch.remove(c)
	if len(ch.members) == 0 {
		s.channels = removeChannel(s.channels,
			ch)
		for _, other := range s.clients {
			other.invites = removeChannel(other.invites, ch)
		}
	}
}
func (s *Server) disconnect(c *Client, reason, kind string) {
	if kind != "closed" {
		s.errors++
		s.send(c, fmt.Sprintf("ERROR :Closing Link: %s[%s] (%s)",
			c.addressee(), c.host, reason))
	}
	if c.registered {
		s.peers(c, ":"+c.prefix()+" QUIT :"+reason)
	}
	for _, ch := range append([]*Channel(nil), c.channels...) {
		s.remove(c, ch)
	}
	s.discarded += len(c.queue)
	c.queue = nil
	c.alive = false
	delete(s.byID,
		c.id)
	for i, v := range s.clients {
		if v == c {
			s.clients = append(s.clients[:i], s.clients[i+1:]...)
			break
		}
	}
	s.gone = append(s.gone,
		fmt.Sprintf("GONE %d %s %s %s", s.time, c.id, c.addressee(), reason))
	s.disconnects[kind]++
}
func (s *Server) register(c *Client) {
	if c.registered || c.nick == "" || c.user == "" {
		return
	}
	c.registered = true
	c.signon = s.time
	c.lastSpeaking = s.time
	count := 0
	for _, v := range s.clients {
		if v.registered {
			count++
		}
	}
	if count > s.peakRegistered {
		s.peakRegistered = count
		s.peakRegisteredAt = s.time
	}
	name := s.config["NAME"]
	s.numeric(c,
		1, ":Welcome to the Internet Relay Network %s", c.prefix())
	s.numeric(c, 2, ":Your host is %s, running version %s",
		name, s.config["VERSION"])
	s.numeric(c, 3, ":This server was created %s", s.config["CREATED"])
	s.numeric(c,
		4, "%s %s i biklmnotv", name, s.config["VERSION"])
	s.numeric(c, 5, "CASEMAPPING=rfc1459 CHANTYPES=# NICKLEN=%s CHANNELLEN=%s TOPICLEN=%s CHANLIMIT=#:%s CHANMODES=b,k,l,imnt PREFIX=(ov)@+ :are supported by this server",
		s.config["NICKLEN"], s.config["CHANNELLEN"], s.config["TOPICLEN"], s.config["MAXCHANNELS"])
	s.numeric(c,
		375, ":- %s Message of the day -", name)
	for _, text := range s.motd {
		s.numeric(c, 372, ":- %s", text)
	}
	s.numeric(c,
		376, ":End of /MOTD command.")
	if c.invisible {
		s.send(c, ":"+c.nick+" MODE "+c.nick+" :+i")
	}
}
func (s *Server) names(c *Client, ch *Channel) {
	names := ch.names(c)
	if names != "" {
		s.numeric(c, 353, "= %s :%s",
			ch.name, names)
	}
	s.numeric(c, 366, "%s :End of /NAMES list.", ch.name)
}
func (s *Server) topic(c *Client, ch *Channel) {
	if ch.topic == "" {
		s.numeric(c, 331, "%s :No topic is set",
			ch.name)
	} else {
		s.numeric(c, 332, "%s :%s", ch.name, ch.topic)
		s.numeric(c, 333, "%s %s %d", ch.name, ch.setter,
			ch.topicTime)
	}
}
func (s *Server) need(c *Client, command string, args []string, count int) bool {
	if len(args) >= count {
		return false
	}
	s.numeric(c,
		461, "%s :Not enough parameters", command)
	return true
}
func (s *Server) process(c *Client, raw string) {
	s.processed++
	cmd, a := parse(raw)
	if cmd == "" {
		s.empty++
		return
	}
	s.commands[cmd]++
	if !c.registered && cmd != "NICK" && cmd != "USER" && cmd != "PING" && cmd != "PONG" && cmd != "QUIT" {
		s.errorReply(c,
			451, "")
		return
	}
	switch cmd {
	case "NICK":
		if len(a) == 0 || a[0] == "" {
			s.errorReply(c, 431, "")
			return
		}
		nick := a[0][:min(len(a[0]), s.setting("NICKLEN"))]
		if !validNick(nick) {
			s.errorReply(c,
				432, nick)
			return
		}
		if nick == c.nick {
			return
		}
		for _, other := range s.clients {
			if other != c && other.nick != "" && fold(other.nick) == fold(nick) {
				s.errorReply(c,
					433, nick)
				return
			}
		}
		if c.registered {
			text := ":" + c.prefix() + " NICK :" + nick
			s.send(c, text)
			s.peers(c,
				text)
		}
		c.nick = nick
		s.register(c)
	case "USER":
		if c.user != "" {
			s.errorReply(c, 462, "")
			return
		}
		if s.need(c, cmd, a, 4) {
			return
		}
		c.user = a[0]
		c.real = a[3]
		c.invisible = digits(a[1]) && len(a[1]) <= 3 && (number(a[1])/8)%2 == 1
		s.register(c)
	case "PING":
		if len(a) == 0 || a[0] == "" {
			s.numeric(c, 409, ":No origin specified")
			return
		}
		s.send(c, fmt.Sprintf(":%s PONG %s :%s",
			s.config["NAME"], s.config["NAME"], a[0]))
	case "PONG":
		return
	case "QUIT":
		reason := "Client Quit"
		if len(a) > 0 && a[0] != "" {
			reason = "Quit: " + a[0]
		}
		s.disconnect(c, reason, "quit")
	case "JOIN":
		if s.need(c, cmd, a, 1) {
			return
		}
		if a[0] == "0" {
			for _, ch := range append([]*Channel(nil), c.channels...) {
				s.members(ch,
					nil, ":"+c.prefix()+" PART "+ch.name)
				s.remove(c, ch)
			}
			return
		}
		var keyList []string
		if len(a) > 1 {
			keyList = strings.Split(a[1],
				",")
		}
		for i, x := range strings.Split(a[0], ",") {
			key := ""
			if i < len(keyList) {
				key = keyList[i]
			}
			if !validChannel(x,
				s.setting("CHANNELLEN")) {
				s.errorReply(c, 403, x)
				continue
			}
			ch := s.channel(x)
			if ch != nil && ch.member(c) != nil {
				continue
			}
			if len(c.channels) >= s.setting("MAXCHANNELS") {
				s.errorReply(c,
					405, x)
				continue
			}
			if ch == nil {
				ch = newChannel(x, s.time)
				s.channels = append(s.channels, ch)
			} else {
				invited := containsChannel(c.invites,
					ch)
				err := 0
				switch {
				case ch.banned(c) && !invited:
					err = 474
				case ch.flags["i"] && !invited:
					err = 473
				case ch.key != "" && key != ch.key:
					err = 475
				case ch.limit > 0 && len(ch.members) >= ch.limit:
					err = 471
				}
				if err != 0 {
					s.errorReply(c,
						err, ch.name)
					continue
				}
			}
			c.invites = removeChannel(c.invites, ch)
			ch.add(c)
			s.members(ch, nil, ":"+c.prefix()+" JOIN "+ch.name)
			if ch.topic != "" {
				s.topic(c,
					ch)
			}
			s.names(c, ch)
		}
	case "PART":
		if s.need(c, cmd, a, 1) {
			return
		}
		suffix := ""
		if len(a) > 1 && a[1] != "" {
			suffix = " :" + a[1]
		}
		for _, x := range strings.Split(a[0], ",") {
			ch := s.channel(x)
			if ch == nil {
				s.errorReply(c, 403, x)
				continue
			}
			if ch.member(c) == nil {
				s.errorReply(c,
					442, ch.name)
				continue
			}
			s.members(ch, nil, ":"+c.prefix()+" PART "+ch.name+suffix)
			s.remove(c, ch)
		}
	case "PRIVMSG", "NOTICE":
		notice := cmd == "NOTICE"
		if !notice {
			c.lastSpeaking = s.time
		}
		if len(a) == 0 || a[0] == "" {
			if !notice {
				s.numeric(c,
					411, ":No recipient given (%s)", cmd)
			}
			return
		}
		if len(a) < 2 || a[1] == "" {
			if !notice {
				s.numeric(c, 412,
					":No text to send")
			}
			return
		}
		for _, x := range strings.Split(a[0], ",") {
			if strings.HasPrefix(x, "#") {
				ch := s.channel(x)
				if ch == nil {
					if !notice {
						s.errorReply(c,
							401, x)
					}
					continue
				}
				if !ch.canSpeak(c) {
					if !notice {
						s.errorReply(c, 404, ch.name)
					}
					continue
				}
				ch.messages++
				s.members(ch,
					c, ":"+c.prefix()+" "+cmd+" "+ch.name+" :"+a[1])
			} else {
				u := s.user(x)
				if u == nil {
					if !notice {
						s.errorReply(c,
							401, x)
					}
					continue
				}
				s.send(u, ":"+c.prefix()+" "+cmd+" "+u.nick+" :"+a[1])
				if !notice && u.away != "" {
					s.numeric(c,
						301, "%s :%s", u.nick, u.away)
				}
			}
		}
	case "TOPIC":
		if s.need(c, cmd, a, 1) {
			return
		}
		ch := s.channel(a[0])
		if ch == nil {
			s.errorReply(c, 403, a[0])
			return
		}
		m := ch.member(c)
		if m == nil {
			s.errorReply(c,
				442, ch.name)
			return
		}
		if len(a) == 1 {
			s.topic(c, ch)
			return
		}
		if ch.flags["t"] && !m.op {
			s.errorReply(c,
				482, ch.name)
			return
		}
		ch.topic = a[1][:min(len(a[1]), s.setting("TOPICLEN"))]
		ch.setter = c.nick
		ch.topicTime = s.time
		s.members(ch,
			nil, ":"+c.prefix()+" TOPIC "+ch.name+" :"+ch.topic)
	case "NAMES":
		if len(a) == 0 {
			s.numeric(c, 366, "* :End of /NAMES list.")
			return
		}
		for _, x := range strings.Split(a[0],
			",") {
			ch := s.channel(x)
			if ch == nil {
				s.numeric(c, 366, "%s :End of /NAMES list.", x)
			} else {
				s.names(c,
					ch)
			}
		}
	case "WHOIS":
		if len(a) == 0 {
			s.errorReply(c, 431, "")
			return
		}
		u := s.user(a[0])
		if u == nil {
			s.errorReply(c,
				401, a[0])
			s.numeric(c, 318, "%s :End of /WHOIS list.", a[0])
			return
		}
		s.numeric(c, 311, "%s %s %s * :%s",
			u.nick, u.user, u.host, u.real)
		if len(u.channels) > 0 {
			s.numeric(c, 319, "%s :%s", u.nick, channelNames(u,
				" "))
		}
		s.numeric(c, 312, "%s %s :%s", u.nick, s.config["NAME"], s.config["DESCRIPTION"])
		if u.away != "" {
			s.numeric(c,
				301, "%s :%s", u.nick, u.away)
		}
		s.numeric(c, 317, "%s %d %d :seconds idle, signon time", u.nick, s.time-u.lastSpeaking,
			u.signon)
		s.numeric(c, 318, "%s :End of /WHOIS list.", u.nick)
	case "AWAY":
		if len(a) > 0 && a[0] != "" {
			c.away = a[0]
			s.numeric(c, 306, ":You have been marked as being away")
		} else {
			c.away = ""
			s.numeric(c,
				305, ":You are no longer marked as being away")
		}
	case "INVITE":
		if s.need(c, cmd, a, 2) {
			return
		}
		u := s.user(a[0])
		if u == nil {
			s.errorReply(c, 401, a[0])
			return
		}
		ch := s.channel(a[1])
		if ch == nil {
			s.errorReply(c,
				403, a[1])
			return
		}
		m := ch.member(c)
		if m == nil {
			s.errorReply(c, 442, ch.name)
			return
		}
		if ch.member(u) != nil {
			s.numeric(c,
				443, "%s %s :is already on channel", u.nick, ch.name)
			return
		}
		if ch.flags["i"] && !m.op {
			s.errorReply(c,
				482, ch.name)
			return
		}
		if !containsChannel(u.invites, ch) {
			u.invites = append(u.invites, ch)
		}
		s.numeric(c,
			341, "%s %s", u.nick, ch.name)
		if u.away != "" {
			s.numeric(c, 301, "%s :%s", u.nick, u.away)
		}
		s.send(u, ":"+c.prefix()+" INVITE "+u.nick+" :"+ch.name)
	case "KICK":
		if s.need(c, cmd, a, 2) {
			return
		}
		ch := s.channel(a[0])
		if ch == nil {
			s.errorReply(c, 403, a[0])
			return
		}
		m := ch.member(c)
		if m == nil {
			s.errorReply(c,
				442, ch.name)
			return
		}
		if !m.op {
			s.errorReply(c, 482, ch.name)
			return
		}
		u := s.user(a[1])
		if u == nil {
			s.errorReply(c,
				401, a[1])
			return
		}
		if ch.member(u) == nil {
			s.numeric(c, 441, "%s %s :They aren't on that channel", u.nick,
				ch.name)
			return
		}
		reason := c.nick
		if len(a) > 2 && a[2] != "" {
			reason = a[2]
		}
		s.members(ch, nil, ":"+c.prefix()+" KICK "+ch.name+" "+u.nick+" :"+reason)
		s.remove(u,
			ch)
	case "MODE":
		if s.need(c, cmd, a, 1) {
			return
		}
		if strings.HasPrefix(a[0], "#") {
			s.channelMode(c, a)
		} else {
			s.userMode(c, a)
		}
	default:
		s.numeric(c, 421, "%s :Unknown command", cmd)
	}
}
func (s *Server) userMode(c *Client, a []string) {
	u := s.user(a[0])
	if u == nil {
		s.errorReply(c, 401, a[0])
		return
	}
	if u != c {
		s.errorReply(c,
			502, "")
		return
	}
	if len(a) == 1 {
		s.numeric(c, 221, "%s", c.mode())
		return
	}
	var changes []ModeItem
	sign := "+"
	unknown := false
	for _, r := range a[1] {
		flag := string(r)
		if flag == "+" || flag == "-" {
			sign = flag
		} else if flag == "i" {
			want := sign == "+"
			if c.invisible != want {
				c.invisible = want
				changes = append(changes,
					ModeItem{sign: sign, flag: "i"})
			}
		} else {
			unknown = true
		}
	}
	if len(changes) > 0 {
		s.send(c, ":"+c.nick+" MODE "+c.nick+" :"+changeString(changes))
	}
	if unknown {
		s.errorReply(c,
			501, "")
	}
}
func (s *Server) channelMode(c *Client, a []string) {
	ch := s.channel(a[0])
	if ch == nil {
		s.errorReply(c, 403,
			a[0])
		return
	}
	if len(a) == 1 {
		s.numeric(c, 324, "%s %s", ch.name, ch.mode(ch.member(c) != nil))
		s.numeric(c,
			329, "%s %d", ch.name, ch.created)
		return
	}
	items := modeItems(a[1], a[2:])
	m := ch.member(c)
	op := m != nil && m.op
	listed,
		denied := false, false
	var changes []ModeItem
	for _, item := range items {
		flag := item.flag
		plus := item.sign == "+"
		if !strings.Contains("biklmnotv",
			flag) {
			s.numeric(c, 472, "%s :is unknown mode char to me for %s", flag, ch.name)
			continue
		}
		if flag == "b" && !item.has {
			if plus && !listed {
				for _, b := range ch.bans {
					s.numeric(c, 367, "%s %s %s %d", ch.name, b.mask, b.setter, b.time)
				}
				s.numeric(c, 368,
					"%s :End of channel ban list", ch.name)
				listed = true
			}
			continue
		}
		if (flag == "o" || flag == "v") && !item.has || plus && (flag == "k" || flag == "l") && !item.has {
			continue
		}
		if !op {
			if !denied {
				s.errorReply(c,
					482, ch.name)
				denied = true
			}
			continue
		}
		changed := false
		switch flag {
		case "o", "v":
			u := s.user(item.arg)
			if u == nil {
				s.errorReply(c,
					401, item.arg)
				continue
			}
			member := ch.member(u)
			if member == nil {
				s.numeric(c, 441, "%s %s :They aren't on that channel",
					u.nick, ch.name)
				continue
			}
			if flag == "o" {
				if member.op != plus {
					member.op = plus
					changed = true
				}
			} else if member.voice != plus {
				member.voice = plus
				changed = true
			}
			item.arg = u.nick
		case "b":
			mask := normalizeMask(item.arg)
			index := -1
			for i, b := range ch.bans {
				if fold(b.mask) == fold(mask) {
					index = i
					break
				}
			}
			if plus && index < 0 {
				ch.bans = append(ch.bans,
					Ban{mask, c.nick, s.time})
				item.arg = mask
				changed = true
			} else if !plus && index >= 0 {
				item.arg = ch.bans[index].mask
				ch.bans = append(ch.bans[:index],
					ch.bans[index+1:]...)
				changed = true
			}
		case "k":
			if plus {
				if ch.key != "" {
					s.errorReply(c, 467, ch.name)
				} else {
					ch.key = item.arg
					changed = true
				}
			} else if ch.key != "" {
				ch.key = ""
				item.arg = "*"
				changed = true
			}
		case "l":
			if plus {
				v := number(item.arg)
				if ch.limit != v {
					ch.limit = v
					changed = true
				}
				item.arg = strconv.Itoa(v)
			} else {
				if ch.limit > 0 {
					ch.limit = 0
					changed = true
				}
				item.has = false
			}
		default:
			if ch.flags[flag] != plus {
				ch.flags[flag] = plus
				changed = true
			}
			item.has = false
		}
		if changed {
			changes = append(changes,
				item)
		}
	}
	if len(changes) > 0 {
		s.members(ch, nil, ":"+c.prefix()+" MODE "+ch.name+" "+changeString(changes))
	}
}
func (s *Server) arrive(e Traffic) {
	if strings.HasPrefix(e.body, "CONNECT ") {
		s.connectLines++
		c := newClient(e.id,
			e.body[len("CONNECT "):], s.time, s.setting("BUCKET"))
		s.clients = append(s.clients, c)
		s.byID[c.id] = c
		if len(s.clients) > s.peakConnections {
			s.peakConnections = len(s.clients)
			s.peakConnectionsAt = s.time
		}
		return
	}
	if e.body == "DISCONNECT" {
		s.disconnectLines++
		if c := s.byID[e.id]; c != nil {
			s.disconnect(c,
				"Remote host closed the connection", "closed")
		}
		return
	}
	s.messageLines++
	c := s.byID[e.id]
	if c == nil {
		s.dropped++
		return
	}
	c.received++
	c.lastReceived = s.time
	c.pinging = false
	if len(c.queue) == 0 && c.tokens > 0 {
		c.use(s.time,
			s.setting("BUCKET"), s.setting("REFILL"))
		s.process(c, e.body)
	} else if len(c.queue) >= s.setting("QUEUE") {
		s.discarded++
		s.disconnect(c,
			"Excess Flood", "flood")
	} else {
		c.queue = append(c.queue, e.body)
		s.queued++
	}
}
func (s *Server) run() {
	at := 0
	for t := 0; t <= s.end; t++ {
		s.time = t
		for _, c := range append([]*Client(nil), s.clients...) {
			c.refillTokens(t,
				s.setting("BUCKET"), s.setting("REFILL"))
			for c.alive && len(c.queue) > 0 && c.tokens > 0 {
				c.use(t, s.setting("BUCKET"),
					s.setting("REFILL"))
				raw := c.queue[0]
				c.queue = c.queue[1:]
				s.process(c, raw)
			}
		}
		for at < len(s.traffic) && s.traffic[at].time == t {
			s.arrive(s.traffic[at])
			at++
		}
		for _, c := range append([]*Client(nil), s.clients...) {
			if c.pinging {
				if t-c.pingAt >= s.setting("TIMEOUT") {
					s.disconnect(c,
						fmt.Sprintf("Ping timeout: %d seconds", t-c.lastReceived), "timeout")
				}
			} else if t-c.lastReceived >= s.setting("PINGFREQ") {
				s.send(c,
					"PING :"+s.config["NAME"])
				s.pings++
				c.pinging = true
				c.pingAt = t
			}
		}
	}
}
func (s *Server) channelLines() []string {
	var out []string
	members, bans := 0, 0
	for _, ch := range s.channels {
		out = append(out,
			fmt.Sprintf("CHANNEL %s created %d members %d peak %d messages %d modes %s", ch.name, ch.created,
				len(ch.members), ch.peak, ch.messages, ch.mode(true)))
		if ch.topic == "" {
			out = append(out, "TOPIC none")
		} else {
			out = append(out,
				fmt.Sprintf("TOPIC %s %d %s", ch.setter, ch.topicTime, ch.topic))
		}
		for _, b := range ch.bans {
			out = append(out,
				fmt.Sprintf("BAN %s %s %d", b.mask, b.setter, b.time))
		}
		out = append(out, "MEMBERS "+ch.names(ch.members[0].client))
		members += len(ch.members)
		bans += len(ch.bans)
	}
	out = append(out,
		fmt.Sprintf("TOTAL channels %d members %d bans %d", len(s.channels), members, bans))
	return out
}
func (s *Server) clientLines() []string {
	var out []string
	registered, invisible, away := 0, 0, 0
	for _, c := range s.clients {
		user,
			signon := c.user, "-"
		if user == "" {
			user = "*"
		}
		if c.registered {
			signon = strconv.Itoa(c.signon)
			registered++
		}
		if c.invisible {
			invisible++
		}
		joined := channelNames(c,
			",")
		if joined == "" {
			joined = "none"
		}
		var inviteNames []string
		for _, ch := range c.invites {
			inviteNames = append(inviteNames,
				ch.name)
		}
		invites := strings.Join(inviteNames, ",")
		if invites == "" {
			invites = "none"
		}
		out = append(out,
			fmt.Sprintf("CLIENT %s %s %s %s %s connected %d signon %s received %d sent %d tokens %d queue %d channels %s invites %s",
				c.id, c.addressee(), user, c.host, c.mode(), c.connected, signon, c.received, c.sent, c.tokens, len(c.queue),
				joined, invites))
		if c.away != "" {
			away++
			out = append(out, "AWAY "+c.id+" "+c.away)
		}
	}
	out = append(out,
		fmt.Sprintf("TOTAL clients %d registered %d invisible %d away %d", len(s.clients), registered, invisible,
			away))
	return out
}
func (s *Server) statLines() []string {
	pending := 0
	for _, c := range s.clients {
		pending += len(c.queue)
	}
	numCount := 0
	var numericKeys []int
	for n, count := range s.numerics {
		numCount += count
		numericKeys = append(numericKeys, n)
	}
	out := []string{fmt.Sprintf("END %d",
		s.end), fmt.Sprintf("LINES total %d connect %d disconnect %d messages %d", len(s.traffic), s.connectLines,
		s.disconnectLines, s.messageLines), fmt.Sprintf("MESSAGES dropped %d queued %d processed %d discarded %d pending %d empty %d",
		s.dropped, s.queued, s.processed, s.discarded, pending, s.empty), fmt.Sprintf("SENT lines %d numerics %d pings %d errors %d",
		len(s.sent), numCount, s.pings, s.errors)}
	var commands []string
	for cmd := range s.commands {
		commands = append(commands,
			cmd)
	}
	sort.Strings(commands)
	for _, cmd := range commands {
		out = append(out, fmt.Sprintf("COMMAND %s %d",
			cmd, s.commands[cmd]))
	}
	sort.Ints(numericKeys)
	for _, n := range numericKeys {
		out = append(out, fmt.Sprintf("NUMERIC %03d %d",
			n, s.numerics[n]))
	}
	out = append(out, fmt.Sprintf("PEAK connections %d at %d", s.peakConnections, s.peakConnectionsAt),
		fmt.Sprintf("PEAK registered %d at %d", s.peakRegistered, s.peakRegisteredAt), fmt.Sprintf("DISCONNECTS quit %d closed %d flood %d timeout %d",
			s.disconnects["quit"], s.disconnects["closed"], s.disconnects["flood"], s.disconnects["timeout"]))
	return append(out,
		s.gone...)
}
func main() {
	s := &Server{config: map[string]string{}, byID: map[string]*Client{}, commands: map[string]int{},
		numerics: map[int]int{}, disconnects: map[string]int{}}
	for _, line := range readLines("input/server.txt") {
		a := strings.SplitN(line,
			" ", 2)
		if a[0] == "MOTD" {
			s.motd = append(s.motd, a[1])
		} else {
			s.config[a[0]] = a[1]
		}
	}
	for _, line := range readLines("input/traffic.txt") {
		a := strings.SplitN(line,
			" ", 3)
		t := number(a[0])
		s.traffic = append(s.traffic, Traffic{t, a[1], a[2]})
		s.end = t
	}
	s.run()
	if e := os.MkdirAll("output",
		0755); e != nil {
		panic(e)
	}
	reports := map[string][]string{"sent.txt": s.sent, "channels.txt": s.channelLines(),
		"clients.txt": s.clientLines(), "stats.txt": s.statLines()}
	for name, lines := range reports {
		text := ""
		if len(lines) > 0 {
			text = strings.Join(lines,
				"\n") + "\n"
		}
		if e := os.WriteFile("output/"+name, []byte(text), 0644); e != nil {
			panic(e)
		}
	}
}
