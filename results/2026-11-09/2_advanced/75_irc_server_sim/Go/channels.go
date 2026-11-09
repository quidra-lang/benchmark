package main

import (
	"strconv"
	"strings"
)

type Member struct {
	client    *Client
	op, voice bool
}
type Ban struct {
	mask, setter string
	time         int
}
type Channel struct {
	name, topic, setter, key                  string
	created, topicTime, limit, peak, messages int
	members                                   []*Member
	bans                                      []Ban
	flags                                     map[string]bool
}

func newChannel(name string, t int) *Channel {
	return &Channel{name: name, created: t, flags: map[string]bool{"n": true, "t": true}}
}
func (ch *Channel) member(c *Client) *Member {
	for _, m := range ch.members {
		if m.client == c {
			return m
		}
	}
	return nil
}
func (ch *Channel) add(c *Client) {
	ch.members = append(ch.members, &Member{client: c, op: len(ch.members) == 0})
	c.channels = append(c.channels,
		ch)
	ch.peak = max(ch.peak, len(ch.members))
}
func (ch *Channel) remove(c *Client) {
	for i, m := range ch.members {
		if m.client == c {
			ch.members = append(ch.members[:i],
				ch.members[i+1:]...)
			break
		}
	}
	c.channels = removeChannel(c.channels, ch)
}
func (m *Member) marker() string {
	if m.op {
		return "@"
	}
	if m.voice {
		return "+"
	}
	return ""
}
func (ch *Channel) names(c *Client) string {
	var names []string
	inside := ch.member(c) != nil
	for _, m := range ch.members {
		if inside || !m.client.invisible {
			names = append(names,
				m.marker()+m.client.nick)
		}
	}
	return strings.Join(names, " ")
}
func (ch *Channel) banned(c *Client) bool {
	for _, b := range ch.bans {
		if matchMask(b.mask, c.prefix()) {
			return true
		}
	}
	return false
}
func (ch *Channel) canSpeak(c *Client) bool {
	m := ch.member(c)
	privileged := m != nil && (m.op || m.voice)
	return (m != nil || !ch.flags["n"]) && (!ch.flags["m"] || privileged) && (privileged || !ch.banned(c))
}
func (ch *Channel) mode(includeKey bool) string {
	out := "+"
	for _, flag := range []string{"i", "k", "l", "m",
		"n", "t"} {
		if flag == "k" && ch.key != "" || flag == "l" && ch.limit > 0 || flag != "k" && flag != "l" && ch.flags[flag] {
			out += flag
		}
	}
	if includeKey && ch.key != "" {
		out += " " + ch.key
	}
	if ch.limit > 0 {
		out += " " + strconv.Itoa(ch.limit)
	}
	return out
}
func channelNames(c *Client, separator string) string {
	var names []string
	for _, ch := range c.channels {
		names = append(names,
			ch.member(c).marker()+ch.name)
	}
	return strings.Join(names, separator)
}
