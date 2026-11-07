'use strict';

const {matches} = require('./masks');

function privilege(member) {
  return member.operator ? '@' : member.voice ? '+' : '';
}

class Channel {
  constructor(name, time) {
    this.name = name;
    this.creationTime = time;
    this.members = [];
    this.topic = '';
    this.topicSetter = null;
    this.topicTime = null;
    this.bans = [];
    this.flags = new Set(['n', 't']);
    this.key = '';
    this.limit = 0;
    this.peak = 0;
    this.messages = 0;
  }

  member(client) {
    return this.members.find(member => member.client === client);
  }

  add(client) {
    this.members.push({client, operator: this.members.length === 0, voice: false});
    client.channels.push(this);
    this.peak = Math.max(this.peak, this.members.length);
  }

  remove(client) {
    this.members.splice(this.members.findIndex(member => member.client === client), 1);
    client.channels.splice(client.channels.indexOf(this), 1);
    return this.members.length === 0;
  }

  nameList(viewer = null) {
    const includeInvisible = viewer === null || this.member(viewer) !== undefined;
    return this.members.filter(member => includeInvisible || !member.client.invisible)
      .map(member => privilege(member) + member.client.nickname).join(' ');
  }

  labelFor(client) {
    return privilege(this.member(client)) + this.name;
  }

  banned(client) {
    return this.bans.some(ban => matches(ban.mask, client.prefix()));
  }

  canSpeak(client) {
    const member = this.member(client);
    const privileged = member !== undefined && (member.operator || member.voice);
    return (member !== undefined || !this.flags.has('n')) &&
      (!this.flags.has('m') || privileged) && (privileged || !this.banned(client));
  }

  modeDisplay(includeKey) {
    let display = '+';
    for (const character of 'iklmnt') {
      if (character === 'k' ? this.key !== '' :
          character === 'l' ? this.limit !== 0 : this.flags.has(character)) {
        display += character;
      }
    }
    if (includeKey && this.key !== '') display += ` ${this.key}`;
    if (this.limit !== 0) display += ` ${this.limit}`;
    return display;
  }
}

module.exports = {Channel};
