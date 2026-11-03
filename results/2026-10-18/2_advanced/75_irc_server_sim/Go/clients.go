package main

type Client struct {
	id, host, nick, user, real, away string
	connected, signon, lastReceived, lastSpeaking,
	pingAt, tokens, refill, received, sent int
	invisible, registered, pinging, alive bool
	queue                                 []string
	channels,
	invites []*Channel
}

func newClient(id, host string, t, bucket int) *Client {
	return &Client{id: id, host: host, connected: t, lastReceived: t, tokens: bucket, refill: -1, signon: -1, alive: true}
}
func (c *Client) addressee() string {
	if c.nick == "" {
		return "*"
	}
	return c.nick
}
func (c *Client) prefix() string { return c.nick + "!" + c.user + "@" + c.host }
func (c *Client) mode() string {
	if c.invisible {
		return "+i"
	}
	return "+"
}
func (c *Client) use(t, bucket, interval int) {
	if c.tokens == bucket {
		c.refill = t + interval
	}
	c.tokens--
}
func (c *Client) refillTokens(t, bucket, interval int) {
	if c.refill == t {
		c.tokens++
		if c.tokens < bucket {
			c.refill = t + interval
		} else {
			c.refill = -1
		}
	}
}
func containsChannel(a []*Channel, ch *Channel) bool {
	for _, v := range a {
		if v == ch {
			return true
		}
	}
	return false
}
func removeChannel(a []*Channel, ch *Channel) []*Channel {
	for i, v := range a {
		if v == ch {
			return append(a[:i], a[i+1:]...)
		}
	}
	return a
}
