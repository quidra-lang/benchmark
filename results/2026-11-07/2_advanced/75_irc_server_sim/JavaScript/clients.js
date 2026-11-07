'use strict';

class Client {
  constructor(id, host, time, bucket) {
    this.id = id;
    this.host = host;
    this.connectionTime = time;
    this.nickname = null;
    this.username = null;
    this.realName = '';
    this.invisible = false;
    this.registered = false;
    this.registrationTime = null;
    this.lastReceived = time;
    this.lastSpeaking = null;
    this.pingSent = false;
    this.pingTime = null;
    this.tokens = bucket;
    this.refillTime = null;
    this.queue = [];
    this.channels = [];
    this.invites = [];
    this.away = '';
    this.received = 0;
    this.sent = 0;
    this.active = true;
  }

  addressee() {
    return this.nickname === null ? '*' : this.nickname;
  }

  prefix() {
    return `${this.nickname}!${this.username}@${this.host}`;
  }

  mode() {
    return this.invisible ? '+i' : '+';
  }

  useToken(time, settings) {
    if (this.tokens === settings.BUCKET) this.refillTime = time + settings.REFILL;
    this.tokens--;
  }

  refill(time, settings) {
    if (this.refillTime !== time) return;
    this.tokens++;
    this.refillTime = this.tokens < settings.BUCKET ? time + settings.REFILL : null;
  }
}

module.exports = {Client};
