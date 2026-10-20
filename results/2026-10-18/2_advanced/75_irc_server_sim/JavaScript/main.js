'use strict';

const fs = require('node:fs');
const protocol = require('./protocol');
const masks = require('./masks');
const modes = require('./modes');
const {Client} = require('./clients');
const {Channel} = require('./channels');

function readInputs() {
  const lines = path => fs.readFileSync(path, 'ascii').slice(0, -1).split('\n');
  const settings = {MOTD: []};
  for (const line of lines('input/server.txt')) {
    const separator = line.indexOf(' ');
    const key = line.slice(0, separator);
    const value = line.slice(separator + 1);
    if (key === 'MOTD') settings.MOTD.push(value);
    else if (['NAME', 'VERSION', 'CREATED', 'DESCRIPTION'].includes(key)) settings[key] = value;
    else settings[key] = Number(value);
  }
  const traffic = lines('input/traffic.txt').map(line => {
    const first = line.indexOf(' ');
    const second = line.indexOf(' ', first + 1);
    const body = line.slice(second + 1);
    const kind = body.startsWith('CONNECT ') ? 'connect' :
      body === 'DISCONNECT' ? 'disconnect' : 'messages';
    return {time: Number(line.slice(0, first)), id: line.slice(first + 1, second), body, kind};
  });
  return {settings, traffic};
}

class Simulator {
  constructor(settings, traffic) {
    this.settings = settings;
    this.traffic = traffic;
    this.endTime = traffic.at(-1).time;
    this.time = 0;
    this.clients = new Map();
    this.channels = new Map();
    this.sent = [];
    this.commands = new Map();
    this.numerics = new Map();
    this.gone = [];
    this.lines = {total: traffic.length, connect: 0, disconnect: 0, messages: 0};
    for (const record of traffic) this.lines[record.kind]++;
    this.messages = {dropped: 0, queued: 0, processed: 0, discarded: 0, empty: 0};
    this.sentCounts = {numerics: 0, pings: 0, errors: 0};
    this.disconnections = {quit: 0, closed: 0, flood: 0, timeout: 0};
    this.registeredCount = 0;
    this.connectionPeak = {count: 0, time: 0};
    this.registrationPeak = {count: 0, time: 0};
  }

  run() {
    let next = 0;
    for (this.time = 0; this.time <= this.endTime; this.time++) {
      for (const client of Array.from(this.clients.values())) {
        client.refill(this.time, this.settings);
        while (client.active && client.queue.length > 0 && client.tokens >= 1) {
          client.useToken(this.time, this.settings);
          this.process(client, client.queue.shift());
        }
      }
      while (next < this.traffic.length && this.traffic[next].time === this.time) {
        this.arrive(this.traffic[next++]);
      }
      for (const client of Array.from(this.clients.values())) {
        if (client.pingSent && this.time - client.pingTime >= this.settings.TIMEOUT) {
          this.disconnect(client, `Ping timeout: ${this.time - client.lastReceived} seconds`, 'timeout');
        } else if (!client.pingSent && this.time - client.lastReceived >= this.settings.PINGFREQ) {
          this.send(client, `PING :${this.settings.NAME}`);
          this.sentCounts.pings++;
          client.pingSent = true;
          client.pingTime = this.time;
        }
      }
    }
  }

  arrive(record) {
    if (record.kind === 'connect') {
      const client = new Client(record.id, record.body.slice(8), this.time, this.settings.BUCKET);
      this.clients.set(client.id, client);
      if (this.clients.size > this.connectionPeak.count) {
        this.connectionPeak = {count: this.clients.size, time: this.time};
      }
      return;
    }
    const client = this.clients.get(record.id);
    if (record.kind === 'disconnect') {
      if (client) this.disconnect(client, 'Remote host closed the connection', 'closed');
      return;
    }
    if (!client) {
      this.messages.dropped++;
      return;
    }
    client.received++;
    client.lastReceived = this.time;
    client.pingSent = false;
    if (client.queue.length === 0 && client.tokens >= 1) {
      client.useToken(this.time, this.settings);
      this.process(client, record.body);
    } else if (client.queue.length >= this.settings.QUEUE) {
      this.messages.discarded++;
      this.disconnect(client, 'Excess Flood', 'flood');
    } else {
      client.queue.push(record.body);
      this.messages.queued++;
    }
  }

  send(client, line) {
    this.sent.push(`${this.time} ${client.id} ${line}`);
    client.sent++;
  }

  numeric(client, number, context = {}) {
    const {target, channel, user, command, character, ban, names, motd} = context;
    const server = this.settings;
    let content;
    switch (number) {
      case 1: content = `:Welcome to the Internet Relay Network ${client.prefix()}`; break;
      case 2: content = `:Your host is ${server.NAME}, running version ${server.VERSION}`; break;
      case 3: content = `:This server was created ${server.CREATED}`; break;
      case 4: content = `${server.NAME} ${server.VERSION} i biklmnotv`; break;
      case 5:
        content = `CASEMAPPING=rfc1459 CHANTYPES=# NICKLEN=${server.NICKLEN} ` +
          `CHANNELLEN=${server.CHANNELLEN} TOPICLEN=${server.TOPICLEN} ` +
          `CHANLIMIT=#:${server.MAXCHANNELS} CHANMODES=b,k,l,imnt PREFIX=(ov)@+ ` +
          ':are supported by this server';
        break;
      case 221: content = client.mode(); break;
      case 301: content = `${user.nickname} :${user.away}`; break;
      case 305: content = ':You are no longer marked as being away'; break;
      case 306: content = ':You have been marked as being away'; break;
      case 311: content = `${user.nickname} ${user.username} ${user.host} * :${user.realName}`; break;
      case 312: content = `${user.nickname} ${server.NAME} :${server.DESCRIPTION}`; break;
      case 317:
        content = `${user.nickname} ${this.time - user.lastSpeaking} ${user.registrationTime} ` +
          ':seconds idle, signon time';
        break;
      case 318: content = `${target} :End of /WHOIS list.`; break;
      case 319: content = `${user.nickname} :${user.channels.map(ch => ch.labelFor(user)).join(' ')}`; break;
      case 324: content = `${channel.name} ${channel.modeDisplay(channel.member(client) !== undefined)}`; break;
      case 329: content = `${channel.name} ${channel.creationTime}`; break;
      case 331: content = `${channel.name} :No topic is set`; break;
      case 332: content = `${channel.name} :${channel.topic}`; break;
      case 333: content = `${channel.name} ${channel.topicSetter} ${channel.topicTime}`; break;
      case 341: content = `${user.nickname} ${channel.name}`; break;
      case 353: content = `= ${channel.name} :${names}`; break;
      case 366: content = `${target} :End of /NAMES list.`; break;
      case 367: content = `${channel.name} ${ban.mask} ${ban.setter} ${ban.time}`; break;
      case 368: content = `${channel.name} :End of channel ban list`; break;
      case 372: content = `:- ${motd}`; break;
      case 375: content = `:- ${server.NAME} Message of the day -`; break;
      case 376: content = ':End of /MOTD command.'; break;
      case 401: content = `${target} :No such nick/channel`; break;
      case 403: content = `${target} :No such channel`; break;
      case 404: content = `${channel.name} :Cannot send to channel`; break;
      case 405: content = `${target} :You have joined too many channels`; break;
      case 409: content = ':No origin specified'; break;
      case 411: content = `:No recipient given (${command})`; break;
      case 412: content = ':No text to send'; break;
      case 421: content = `${command} :Unknown command`; break;
      case 431: content = ':No nickname given'; break;
      case 432: content = `${target} :Erroneous nickname`; break;
      case 433: content = `${target} :Nickname is already in use`; break;
      case 441: content = `${user.nickname} ${channel.name} :They aren't on that channel`; break;
      case 442: content = `${channel.name} :You're not on that channel`; break;
      case 443: content = `${user.nickname} ${channel.name} :is already on channel`; break;
      case 451: content = ':You have not registered'; break;
      case 461: content = `${command} :Not enough parameters`; break;
      case 462: content = ':You may not reregister'; break;
      case 467: content = `${channel.name} :Channel key already set`; break;
      case 471: content = `${channel.name} :Cannot join channel (+l)`; break;
      case 472: content = `${character} :is unknown mode char to me for ${channel.name}`; break;
      case 473: content = `${channel.name} :Cannot join channel (+i)`; break;
      case 474: content = `${channel.name} :Cannot join channel (+b)`; break;
      case 475: content = `${channel.name} :Cannot join channel (+k)`; break;
      case 482: content = `${channel.name} :You're not channel operator`; break;
      case 501: content = ':Unknown MODE flag'; break;
      case 502: content = ':Cannot change mode for other users'; break;
    }
    const code = String(number).padStart(3, '0');
    this.send(client, `:${server.NAME} ${code} ${client.addressee()} ${content}`);
    this.sentCounts.numerics++;
    this.numerics.set(number, (this.numerics.get(number) || 0) + 1);
  }

  broadcast(channel, line, except = null) {
    for (const member of channel.members) {
      if (member.client !== except) this.send(member.client, line);
    }
  }

  sendPeers(client, line) {
    const peers = new Set();
    for (const channel of client.channels) {
      for (const member of channel.members) {
        if (member.client !== client) peers.add(member.client);
      }
    }
    for (const peer of this.clients.values()) {
      if (peers.has(peer)) this.send(peer, line);
    }
  }

  removeMember(channel, client) {
    if (!channel.remove(client)) return;
    this.channels.delete(protocol.fold(channel.name));
    for (const other of this.clients.values()) {
      other.invites = other.invites.filter(invite => invite !== channel);
    }
  }

  disconnect(client, reason, kind) {
    if (kind !== 'closed') {
      this.send(client, `ERROR :Closing Link: ${client.addressee()}[${client.host}] (${reason})`);
      this.sentCounts.errors++;
    }
    if (client.registered) this.sendPeers(client, `:${client.prefix()} QUIT :${reason}`);
    for (const channel of client.channels.slice()) this.removeMember(channel, client);
    this.messages.discarded += client.queue.length;
    client.queue.length = 0;
    this.clients.delete(client.id);
    client.active = false;
    if (client.registered) this.registeredCount--;
    this.gone.push({time: this.time, id: client.id, addressee: client.addressee(), reason});
    this.disconnections[kind]++;
  }

  register(client) {
    if (client.registered || client.nickname === null || client.username === null) return;
    client.registered = true;
    client.registrationTime = this.time;
    client.lastSpeaking = this.time;
    this.registeredCount++;
    if (this.registeredCount > this.registrationPeak.count) {
      this.registrationPeak = {count: this.registeredCount, time: this.time};
    }
    for (const number of [1, 2, 3, 4, 5, 375]) this.numeric(client, number);
    for (const motd of this.settings.MOTD) this.numeric(client, 372, {motd});
    this.numeric(client, 376);
    if (client.invisible) this.send(client, `:${client.nickname} MODE ${client.nickname} :+i`);
  }

  findUser(name) {
    const folded = protocol.fold(name);
    for (const client of this.clients.values()) {
      if (client.registered && protocol.fold(client.nickname) === folded) return client;
    }
    return undefined;
  }

  findChannel(name) {
    return this.channels.get(protocol.fold(name));
  }

  namesReply(client, channel) {
    const names = channel.nameList(client);
    if (names !== '') this.numeric(client, 353, {channel, names});
    this.numeric(client, 366, {target: channel.name});
  }

  topicReply(client, channel) {
    this.numeric(client, 332, {channel});
    this.numeric(client, 333, {channel});
  }

  process(client, raw) {
    this.messages.processed++;
    const parsed = protocol.parse(raw);
    if (parsed === null) {
      this.messages.empty++;
      return;
    }
    const {command, parameters} = parsed;
    this.commands.set(command, (this.commands.get(command) || 0) + 1);
    if (!client.registered && !['NICK', 'USER', 'PING', 'PONG', 'QUIT'].includes(command)) {
      return this.numeric(client, 451);
    }
    switch (command) {
      case 'NICK': return this.nick(client, parameters);
      case 'USER': return this.user(client, parameters);
      case 'PING':
        if (!parameters.length || parameters[0] === '') return this.numeric(client, 409);
        return this.send(client, `:${this.settings.NAME} PONG ${this.settings.NAME} :${parameters[0]}`);
      case 'PONG': return;
      case 'QUIT':
        return this.disconnect(client, parameters[0] ? `Quit: ${parameters[0]}` : 'Client Quit', 'quit');
      case 'JOIN': return this.join(client, parameters);
      case 'PART': return this.part(client, parameters);
      case 'PRIVMSG':
      case 'NOTICE': return this.message(client, command, parameters);
      case 'TOPIC': return this.topic(client, parameters);
      case 'NAMES':
        if (!parameters.length) return this.numeric(client, 366, {target: '*'});
        for (const target of parameters[0].split(',')) {
          const channel = this.findChannel(target);
          if (channel) this.namesReply(client, channel);
          else this.numeric(client, 366, {target});
        }
        return;
      case 'WHOIS': return this.whois(client, parameters);
      case 'AWAY':
        client.away = parameters[0] || '';
        return this.numeric(client, client.away ? 306 : 305);
      case 'INVITE': return this.invite(client, parameters);
      case 'KICK': return this.kick(client, parameters);
      case 'MODE':
        if (!parameters.length) return this.numeric(client, 461, {command});
        return parameters[0].startsWith('#') ?
          this.channelMode(client, parameters) : this.userMode(client, parameters);
      default: return this.numeric(client, 421, {command});
    }
  }

  nick(client, parameters) {
    if (!parameters.length || parameters[0] === '') return this.numeric(client, 431);
    const target = parameters[0].slice(0, this.settings.NICKLEN);
    if (!protocol.validNickname(target)) return this.numeric(client, 432, {target});
    if (target === client.nickname) return;
    for (const other of this.clients.values()) {
      if (other !== client && other.nickname !== null &&
          protocol.fold(other.nickname) === protocol.fold(target)) {
        return this.numeric(client, 433, {target});
      }
    }
    if (client.registered) {
      const line = `:${client.prefix()} NICK :${target}`;
      this.send(client, line);
      this.sendPeers(client, line);
    }
    client.nickname = target;
    if (!client.registered) this.register(client);
  }

  user(client, parameters) {
    if (client.username !== null) return this.numeric(client, 462);
    if (parameters.length < 4) return this.numeric(client, 461, {command: 'USER'});
    client.username = parameters[0];
    client.realName = parameters[3];
    client.invisible = parameters[1].length <= 3 && protocol.digits(parameters[1]) &&
      Math.floor(Number(parameters[1]) / 8) % 2 === 1;
    this.register(client);
  }

  join(client, parameters) {
    if (!parameters.length) return this.numeric(client, 461, {command: 'JOIN'});
    if (parameters[0] === '0') {
      for (const channel of client.channels.slice()) {
        this.broadcast(channel, `:${client.prefix()} PART ${channel.name}`);
        this.removeMember(channel, client);
      }
      return;
    }
    const names = parameters[0].split(',');
    const keys = parameters.length > 1 ? parameters[1].split(',') : [];
    for (let index = 0; index < names.length; index++) {
      const target = names[index];
      if (!protocol.validChannel(target, this.settings.CHANNELLEN)) {
        this.numeric(client, 403, {target});
        continue;
      }
      let channel = this.findChannel(target);
      if (channel && channel.member(client)) continue;
      if (client.channels.length >= this.settings.MAXCHANNELS) {
        this.numeric(client, 405, {target});
        continue;
      }
      if (!channel) {
        channel = new Channel(target, this.time);
        this.channels.set(protocol.fold(target), channel);
      } else {
        const invited = client.invites.includes(channel);
        let error = 0;
        if (channel.banned(client) && !invited) error = 474;
        else if (channel.flags.has('i') && !invited) error = 473;
        else if (channel.key && (keys[index] || '') !== channel.key) error = 475;
        else if (channel.limit && channel.members.length >= channel.limit) error = 471;
        if (error) {
          this.numeric(client, error, {channel});
          continue;
        }
      }
      client.invites = client.invites.filter(invite => invite !== channel);
      channel.add(client);
      this.broadcast(channel, `:${client.prefix()} JOIN ${channel.name}`);
      if (channel.topic) this.topicReply(client, channel);
      this.namesReply(client, channel);
    }
  }

  part(client, parameters) {
    if (!parameters.length) return this.numeric(client, 461, {command: 'PART'});
    const suffix = parameters[1] ? ` :${parameters[1]}` : '';
    for (const target of parameters[0].split(',')) {
      const channel = this.findChannel(target);
      if (!channel) this.numeric(client, 403, {target});
      else if (!channel.member(client)) this.numeric(client, 442, {channel});
      else {
        this.broadcast(channel, `:${client.prefix()} PART ${channel.name}${suffix}`);
        this.removeMember(channel, client);
      }
    }
  }

  message(client, command, parameters) {
    const reply = (number, context = {}) => {
      if (command === 'PRIVMSG') this.numeric(client, number, context);
    };
    if (command === 'PRIVMSG') client.lastSpeaking = this.time;
    if (!parameters.length || parameters[0] === '') return reply(411, {command});
    if (parameters.length < 2 || parameters[1] === '') return reply(412);
    for (const target of parameters[0].split(',')) {
      if (target.startsWith('#')) {
        const channel = this.findChannel(target);
        if (!channel) reply(401, {target});
        else if (!channel.canSpeak(client)) reply(404, {channel});
        else {
          channel.messages++;
          this.broadcast(channel, `:${client.prefix()} ${command} ${channel.name} :${parameters[1]}`, client);
        }
      } else {
        const user = this.findUser(target);
        if (!user) reply(401, {target});
        else {
          this.send(user, `:${client.prefix()} ${command} ${user.nickname} :${parameters[1]}`);
          if (user.away) reply(301, {user});
        }
      }
    }
  }

  topic(client, parameters) {
    if (!parameters.length) return this.numeric(client, 461, {command: 'TOPIC'});
    const channel = this.findChannel(parameters[0]);
    if (!channel) return this.numeric(client, 403, {target: parameters[0]});
    const member = channel.member(client);
    if (!member) return this.numeric(client, 442, {channel});
    if (parameters.length === 1) {
      if (channel.topic) this.topicReply(client, channel);
      else this.numeric(client, 331, {channel});
      return;
    }
    if (channel.flags.has('t') && !member.operator) return this.numeric(client, 482, {channel});
    channel.topic = parameters[1].slice(0, this.settings.TOPICLEN);
    channel.topicSetter = client.nickname;
    channel.topicTime = this.time;
    this.broadcast(channel, `:${client.prefix()} TOPIC ${channel.name} :${channel.topic}`);
  }

  whois(client, parameters) {
    if (!parameters.length) return this.numeric(client, 431);
    const user = this.findUser(parameters[0]);
    if (!user) {
      this.numeric(client, 401, {target: parameters[0]});
      this.numeric(client, 318, {target: parameters[0]});
      return;
    }
    this.numeric(client, 311, {user});
    if (user.channels.length) this.numeric(client, 319, {user});
    this.numeric(client, 312, {user});
    if (user.away) this.numeric(client, 301, {user});
    this.numeric(client, 317, {user});
    this.numeric(client, 318, {target: user.nickname});
  }

  invite(client, parameters) {
    if (parameters.length < 2) return this.numeric(client, 461, {command: 'INVITE'});
    const user = this.findUser(parameters[0]);
    if (!user) return this.numeric(client, 401, {target: parameters[0]});
    const channel = this.findChannel(parameters[1]);
    if (!channel) return this.numeric(client, 403, {target: parameters[1]});
    const member = channel.member(client);
    if (!member) return this.numeric(client, 442, {channel});
    if (channel.member(user)) return this.numeric(client, 443, {channel, user});
    if (channel.flags.has('i') && !member.operator) return this.numeric(client, 482, {channel});
    if (!user.invites.includes(channel)) user.invites.push(channel);
    this.numeric(client, 341, {channel, user});
    if (user.away) this.numeric(client, 301, {user});
    this.send(user, `:${client.prefix()} INVITE ${user.nickname} :${channel.name}`);
  }

  kick(client, parameters) {
    if (parameters.length < 2) return this.numeric(client, 461, {command: 'KICK'});
    const channel = this.findChannel(parameters[0]);
    if (!channel) return this.numeric(client, 403, {target: parameters[0]});
    const member = channel.member(client);
    if (!member) return this.numeric(client, 442, {channel});
    if (!member.operator) return this.numeric(client, 482, {channel});
    const user = this.findUser(parameters[1]);
    if (!user) return this.numeric(client, 401, {target: parameters[1]});
    if (!channel.member(user)) return this.numeric(client, 441, {channel, user});
    const reason = parameters[2] || client.nickname;
    this.broadcast(channel, `:${client.prefix()} KICK ${channel.name} ${user.nickname} :${reason}`);
    this.removeMember(channel, user);
  }

  userMode(client, parameters) {
    const user = this.findUser(parameters[0]);
    if (!user) return this.numeric(client, 401, {target: parameters[0]});
    if (user !== client) return this.numeric(client, 502);
    if (parameters.length === 1) return this.numeric(client, 221);
    let sign = '+';
    let unknown = false;
    const changes = [];
    for (const character of parameters[1]) {
      if (character === '+' || character === '-') sign = character;
      else if (character !== 'i') unknown = true;
      else if (client.invisible !== (sign === '+')) {
        client.invisible = sign === '+';
        changes.push({sign, character});
      }
    }
    if (changes.length) {
      this.send(client, `:${client.nickname} MODE ${client.nickname} :${modes.changeString(changes)}`);
    }
    if (unknown) this.numeric(client, 501);
  }

  channelMode(client, parameters) {
    const channel = this.findChannel(parameters[0]);
    if (!channel) return this.numeric(client, 403, {target: parameters[0]});
    if (parameters.length === 1) {
      this.numeric(client, 324, {channel});
      this.numeric(client, 329, {channel});
      return;
    }
    const items = modes.items(parameters[1], parameters.slice(2));
    const operator = channel.member(client)?.operator === true;
    let listedBans = false;
    let denied = false;
    const changes = [];
    for (const {sign, character, argument} of items) {
      if (!'biklmnotv'.includes(character)) {
        this.numeric(client, 472, {channel, character});
      } else if (character === 'b' && argument === undefined) {
        if (sign === '+' && !listedBans) {
          for (const ban of channel.bans) this.numeric(client, 367, {channel, ban});
          this.numeric(client, 368, {channel});
          listedBans = true;
        }
      } else if (argument === undefined &&
          ('ov'.includes(character) || sign === '+' && 'kl'.includes(character))) {
        continue;
      } else if (!operator) {
        if (!denied) this.numeric(client, 482, {channel});
        denied = true;
      } else if (character === 'o' || character === 'v') {
        const user = this.findUser(argument);
        if (!user) this.numeric(client, 401, {target: argument});
        else {
          const member = channel.member(user);
          if (!member) this.numeric(client, 441, {channel, user});
          else {
            const privilege = character === 'o' ? 'operator' : 'voice';
            if (member[privilege] !== (sign === '+')) {
              member[privilege] = sign === '+';
              changes.push({sign, character, argument: user.nickname});
            }
          }
        }
      } else if (character === 'b') {
        const mask = masks.normalize(argument);
        const index = channel.bans.findIndex(ban => protocol.fold(ban.mask) === protocol.fold(mask));
        if (sign === '+' && index < 0) {
          channel.bans.push({mask, setter: client.nickname, time: this.time});
          changes.push({sign, character, argument: mask});
        } else if (sign === '-' && index >= 0) {
          const removed = channel.bans.splice(index, 1)[0];
          changes.push({sign, character, argument: removed.mask});
        }
      } else if (character === 'k') {
        if (sign === '+') {
          if (channel.key) this.numeric(client, 467, {channel});
          else {
            channel.key = argument;
            changes.push({sign, character, argument});
          }
        } else if (channel.key) {
          channel.key = '';
          changes.push({sign, character, argument: '*'});
        }
      } else if (character === 'l') {
        const limit = sign === '+' ? Number(argument) : 0;
        if (channel.limit !== limit) {
          channel.limit = limit;
          changes.push({sign, character, argument: sign === '+' ? String(limit) : undefined});
        }
      } else if (channel.flags.has(character) !== (sign === '+')) {
        if (sign === '+') channel.flags.add(character);
        else channel.flags.delete(character);
        changes.push({sign, character});
      }
    }
    if (changes.length) {
      this.broadcast(channel, `:${client.prefix()} MODE ${channel.name} ${modes.changeString(changes)}`);
    }
  }

  channelReport() {
    const lines = [];
    let members = 0;
    let bans = 0;
    for (const channel of this.channels.values()) {
      lines.push(`CHANNEL ${channel.name} created ${channel.creationTime} members ${channel.members.length} ` +
        `peak ${channel.peak} messages ${channel.messages} modes ${channel.modeDisplay(true)}`);
      lines.push(channel.topic ? `TOPIC ${channel.topicSetter} ${channel.topicTime} ${channel.topic}` : 'TOPIC none');
      for (const ban of channel.bans) lines.push(`BAN ${ban.mask} ${ban.setter} ${ban.time}`);
      lines.push(`MEMBERS ${channel.nameList()}`);
      members += channel.members.length;
      bans += channel.bans.length;
    }
    lines.push(`TOTAL channels ${this.channels.size} members ${members} bans ${bans}`);
    return lines;
  }

  clientReport() {
    const lines = [];
    let registered = 0;
    let invisible = 0;
    let away = 0;
    for (const client of this.clients.values()) {
      const username = client.username === null ? '*' : client.username;
      const signon = client.registered ? client.registrationTime : '-';
      const channels = client.channels.map(channel => channel.labelFor(client)).join(',') || 'none';
      const invites = client.invites.map(channel => channel.name).join(',') || 'none';
      lines.push(`CLIENT ${client.id} ${client.addressee()} ${username} ${client.host} ${client.mode()} ` +
        `connected ${client.connectionTime} signon ${signon} received ${client.received} sent ${client.sent} ` +
        `tokens ${client.tokens} queue ${client.queue.length} channels ${channels} invites ${invites}`);
      if (client.away) lines.push(`AWAY ${client.id} ${client.away}`);
      if (client.registered) registered++;
      if (client.invisible) invisible++;
      if (client.away) away++;
    }
    lines.push(`TOTAL clients ${this.clients.size} registered ${registered} invisible ${invisible} away ${away}`);
    return lines;
  }

  statsReport() {
    let pending = 0;
    for (const client of this.clients.values()) pending += client.queue.length;
    const counts = this.messages;
    const lines = [
      `END ${this.endTime}`,
      `LINES total ${this.lines.total} connect ${this.lines.connect} disconnect ${this.lines.disconnect} ` +
        `messages ${this.lines.messages}`,
      `MESSAGES dropped ${counts.dropped} queued ${counts.queued} processed ${counts.processed} ` +
        `discarded ${counts.discarded} pending ${pending} empty ${counts.empty}`,
      `SENT lines ${this.sent.length} numerics ${this.sentCounts.numerics} ` +
        `pings ${this.sentCounts.pings} errors ${this.sentCounts.errors}`
    ];
    for (const command of Array.from(this.commands.keys()).sort()) {
      lines.push(`COMMAND ${command} ${this.commands.get(command)}`);
    }
    for (const number of Array.from(this.numerics.keys()).sort((a, b) => a - b)) {
      lines.push(`NUMERIC ${String(number).padStart(3, '0')} ${this.numerics.get(number)}`);
    }
    lines.push(`PEAK connections ${this.connectionPeak.count} at ${this.connectionPeak.time}`);
    lines.push(`PEAK registered ${this.registrationPeak.count} at ${this.registrationPeak.time}`);
    lines.push(`DISCONNECTS quit ${this.disconnections.quit} closed ${this.disconnections.closed} ` +
      `flood ${this.disconnections.flood} timeout ${this.disconnections.timeout}`);
    for (const record of this.gone) {
      lines.push(`GONE ${record.time} ${record.id} ${record.addressee} ${record.reason}`);
    }
    return lines;
  }

  writeReports() {
    fs.mkdirSync('output', {recursive: true});
    for (const [name, lines] of [
      ['sent', this.sent], ['channels', this.channelReport()],
      ['clients', this.clientReport()], ['stats', this.statsReport()]
    ]) {
      fs.writeFileSync(`output/${name}.txt`, lines.join('\n') + (lines.length ? '\n' : ''), 'ascii');
    }
  }
}

const {settings, traffic} = readInputs();
const simulation = new Simulator(settings, traffic);
simulation.run();
simulation.writeReports();
