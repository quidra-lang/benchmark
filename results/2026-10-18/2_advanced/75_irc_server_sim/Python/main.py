from collections import Counter
from pathlib import Path

from channels import Channel
from clients import Client
from masks import normalize
from modes import change_string, channel_items
from protocol import LETTERS, digits, fold, parse, valid_channel, valid_nickname


NUMERICS = {
    1: ":Welcome to the Internet Relay Network {client.prefix}",
    2: ":Your host is {settings[NAME]}, running version {settings[VERSION]}",
    3: ":This server was created {settings[CREATED]}",
    4: "{settings[NAME]} {settings[VERSION]} i biklmnotv",
    5: ("CASEMAPPING=rfc1459 CHANTYPES=# NICKLEN={settings[NICKLEN]} "
        "CHANNELLEN={settings[CHANNELLEN]} TOPICLEN={settings[TOPICLEN]} "
        "CHANLIMIT=#:{settings[MAXCHANNELS]} CHANMODES=b,k,l,imnt PREFIX=(ov)@+ "
        ":are supported by this server"),
    221: "{client.mode}",
    301: "{user.nickname} :{user.away}",
    305: ":You are no longer marked as being away",
    306: ":You have been marked as being away",
    311: "{user.nickname} {user.username} {user.hostname} * :{user.realname}",
    312: "{user.nickname} {settings[NAME]} :{settings[DESCRIPTION]}",
    317: "{user.nickname} {idle} {user.registration_time} :seconds idle, signon time",
    318: "{x} :End of /WHOIS list.",
    319: "{user.nickname} :{channel_list}",
    324: "{channel.name} {display}",
    329: "{channel.name} {channel.created}",
    331: "{channel.name} :No topic is set",
    332: "{channel.name} :{channel.topic}",
    333: "{channel.name} {channel.topic_setter} {channel.topic_time}",
    341: "{user.nickname} {channel.name}",
    353: "= {channel.name} :{name_list}",
    366: "{x} :End of /NAMES list.",
    367: "{channel.name} {ban[0]} {ban[1]} {ban[2]}",
    368: "{channel.name} :End of channel ban list",
    372: ":- {motd}",
    375: ":- {settings[NAME]} Message of the day -",
    376: ":End of /MOTD command.",
    401: "{x} :No such nick/channel",
    403: "{x} :No such channel",
    404: "{channel.name} :Cannot send to channel",
    405: "{x} :You have joined too many channels",
    409: ":No origin specified",
    411: ":No recipient given ({command})",
    412: ":No text to send",
    421: "{command} :Unknown command",
    431: ":No nickname given",
    432: "{x} :Erroneous nickname",
    433: "{x} :Nickname is already in use",
    441: "{user.nickname} {channel.name} :They aren't on that channel",
    442: "{channel.name} :You're not on that channel",
    443: "{user.nickname} {channel.name} :is already on channel",
    451: ":You have not registered",
    461: "{command} :Not enough parameters",
    462: ":You may not reregister",
    467: "{channel.name} :Channel key already set",
    471: "{channel.name} :Cannot join channel (+l)",
    472: "{character} :is unknown mode char to me for {channel.name}",
    473: "{channel.name} :Cannot join channel (+i)",
    474: "{channel.name} :Cannot join channel (+b)",
    475: "{channel.name} :Cannot join channel (+k)",
    482: "{channel.name} :You're not channel operator",
    501: ":Unknown MODE flag",
    502: ":Cannot change mode for other users",
}


def read_inputs():
    settings = {"MOTD": []}
    integers = {"NICKLEN", "CHANNELLEN", "TOPICLEN", "MAXCHANNELS", "BUCKET",
                "REFILL", "QUEUE", "PINGFREQ", "TIMEOUT"}
    for line in Path("input/server.txt").read_text(encoding="ascii").splitlines():
        key, value = line.split(" ", 1)
        if key == "MOTD":
            settings[key].append(value)
        else:
            settings[key] = int(value) if key in integers else value
    traffic = []
    for line in Path("input/traffic.txt").read_text(encoding="ascii").splitlines():
        time, identifier, body = line.split(" ", 2)
        kind = "messages"
        if body.startswith("CONNECT "):
            host = body[8:]
            if 1 <= len(host) <= 63 and all(character in LETTERS + "0123456789.-" for character in host):
                kind = "connect"
        elif body == "DISCONNECT":
            kind = "disconnect"
        traffic.append((int(time), identifier, kind, body))
    return settings, traffic


class Server:
    def __init__(self, settings, traffic):
        self.settings = settings
        self.traffic = traffic
        self.end = traffic[-1][0]
        self.time = 0
        self.clients = {}
        self.channels = {}
        self.sent = []
        self.commands = Counter()
        self.numeric_counts = Counter()
        self.line_counts = Counter(kind for time, identifier, kind, body in traffic)
        self.statistics = Counter()
        self.disconnections = Counter()
        self.gone = []
        self.peak_connections = (0, 0)
        self.peak_registered = (0, 0)
        self.handlers = {
            "NICK": self.nick, "USER": self.user, "PING": self.ping, "PONG": self.pong,
            "QUIT": self.quit, "JOIN": self.join, "PART": self.part, "TOPIC": self.topic,
            "NAMES": self.names, "WHOIS": self.whois, "AWAY": self.away, "INVITE": self.invite,
            "KICK": self.kick, "MODE": self.mode,
        }

    def send(self, client, line):
        self.sent.append(f"{self.time} {client.identifier} {line}")
        client.sent += 1

    def numeric(self, client, number, **values):
        content = NUMERICS[number].format(client=client, settings=self.settings, **values)
        self.numeric_counts[number] += 1
        self.send(client, f":{self.settings['NAME']} {number:03d} {client.addressee} {content}")

    def broadcast(self, channel, line, exclude=None):
        for member in channel.members:
            if member.client is not exclude:
                self.send(member.client, line)

    def send_peers(self, client, line):
        peers = {member.client for channel in client.channels for member in channel.members}
        for other in self.clients.values():
            if other is not client and other in peers:
                self.send(other, line)

    def find_user(self, nickname):
        name = fold(nickname)
        return next((client for client in self.clients.values()
                     if client.registered and fold(client.nickname) == name), None)

    def find_channel(self, name):
        return self.channels.get(fold(name))

    def joined_channels(self, client, separator):
        return separator.join(channel.member(client).status + channel.name for channel in client.channels)

    def remove_member(self, client, channel):
        channel.remove(client)
        if not channel.members:
            del self.channels[fold(channel.name)]
            for other in self.clients.values():
                if channel in other.invites:
                    other.invites.remove(channel)

    def disconnect(self, client, reason, kind):
        if kind != "closed":
            self.send(client, f"ERROR :Closing Link: {client.addressee}[{client.hostname}] ({reason})")
            self.statistics["errors"] += 1
        if client.registered:
            self.send_peers(client, f":{client.prefix} QUIT :{reason}")
        for channel in list(client.channels):
            self.remove_member(client, channel)
        self.statistics["discarded"] += len(client.queue)
        client.queue.clear()
        del self.clients[client.identifier]
        client.active = False
        self.gone.append((self.time, client.identifier, client.addressee, reason))
        self.disconnections[kind] += 1

    def complete_registration(self, client):
        if client.registered or client.nickname is None or client.username is None:
            return
        client.registered = True
        client.registration_time = self.time
        client.last_speaking = self.time
        registered = sum(other.registered for other in self.clients.values())
        if registered > self.peak_registered[0]:
            self.peak_registered = registered, self.time
        for number in (1, 2, 3, 4, 5, 375):
            self.numeric(client, number)
        for line in self.settings["MOTD"]:
            self.numeric(client, 372, motd=line)
        self.numeric(client, 376)
        if client.invisible:
            self.send(client, f":{client.nickname} MODE {client.nickname} :+i")

    def arrival(self, record):
        time, identifier, kind, body = record
        if kind == "connect":
            self.clients[identifier] = Client(identifier, body[8:], self.time, self.settings["BUCKET"])
            if len(self.clients) > self.peak_connections[0]:
                self.peak_connections = len(self.clients), self.time
            return
        client = self.clients.get(identifier)
        if kind == "disconnect":
            if client is not None:
                self.disconnect(client, "Remote host closed the connection", "closed")
            return
        if client is None:
            self.statistics["dropped"] += 1
            return
        client.received += 1
        client.last_received = self.time
        client.ping_sent = None
        if not client.queue and client.tokens >= 1:
            client.use_token(self.time, self.settings["BUCKET"], self.settings["REFILL"])
            self.process(client, body)
        elif len(client.queue) >= self.settings["QUEUE"]:
            self.statistics["discarded"] += 1
            self.disconnect(client, "Excess Flood", "flood")
        else:
            client.queue.append(body)
            self.statistics["queued"] += 1

    def run(self):
        position = 0
        for time in range(self.end + 1):
            self.time = time
            for client in list(self.clients.values()):
                client.refill(time, self.settings["BUCKET"], self.settings["REFILL"])
                while client.active and client.queue and client.tokens >= 1:
                    client.use_token(time, self.settings["BUCKET"], self.settings["REFILL"])
                    raw = client.queue.popleft()
                    self.process(client, raw)
            while position < len(self.traffic) and self.traffic[position][0] == time:
                self.arrival(self.traffic[position])
                position += 1
            for client in list(self.clients.values()):
                if client.ping_sent is not None:
                    if time - client.ping_sent >= self.settings["TIMEOUT"]:
                        reason = f"Ping timeout: {time - client.last_received} seconds"
                        self.disconnect(client, reason, "timeout")
                elif time - client.last_received >= self.settings["PINGFREQ"]:
                    self.send(client, f"PING :{self.settings['NAME']}")
                    self.statistics["pings"] += 1
                    client.ping_sent = time

    def process(self, client, raw):
        self.statistics["processed"] += 1
        command, parameters = parse(raw)
        if not command:
            self.statistics["empty"] += 1
            return
        self.commands[command] += 1
        if not client.registered and command not in ("NICK", "USER", "PING", "PONG", "QUIT"):
            self.numeric(client, 451)
            return
        if command in ("PRIVMSG", "NOTICE"):
            self.message(client, parameters, command)
        elif command in self.handlers:
            self.handlers[command](client, parameters)
        else:
            self.numeric(client, 421, command=command)

    def require(self, client, parameters, count, command):
        if len(parameters) < count:
            self.numeric(client, 461, command=command)
            return False
        return True

    def nick(self, client, parameters):
        if not parameters or not parameters[0]:
            self.numeric(client, 431)
            return
        nickname = parameters[0][:self.settings["NICKLEN"]]
        if not valid_nickname(nickname):
            self.numeric(client, 432, x=nickname)
            return
        if nickname == client.nickname:
            return
        folded = fold(nickname)
        if any(other is not client and other.nickname is not None and fold(other.nickname) == folded
               for other in self.clients.values()):
            self.numeric(client, 433, x=nickname)
            return
        if client.registered:
            line = f":{client.prefix} NICK :{nickname}"
            self.send(client, line)
            self.send_peers(client, line)
        client.nickname = nickname
        self.complete_registration(client)

    def user(self, client, parameters):
        if client.username is not None:
            self.numeric(client, 462)
            return
        if not self.require(client, parameters, 4, "USER"):
            return
        client.username = parameters[0]
        client.realname = parameters[3]
        mode = parameters[1]
        client.invisible = digits(mode) and len(mode) <= 3 and (int(mode) // 8) % 2 == 1
        self.complete_registration(client)

    def ping(self, client, parameters):
        if not parameters or not parameters[0]:
            self.numeric(client, 409)
            return
        server = self.settings["NAME"]
        self.send(client, f":{server} PONG {server} :{parameters[0]}")

    def pong(self, client, parameters):
        return

    def quit(self, client, parameters):
        reason = "Quit: " + parameters[0] if parameters and parameters[0] else "Client Quit"
        self.disconnect(client, reason, "quit")

    def names_reply(self, client, channel):
        names = channel.name_list(client)
        if names:
            self.numeric(client, 353, channel=channel, name_list=names)
        self.numeric(client, 366, x=channel.name)

    def join(self, client, parameters):
        if not self.require(client, parameters, 1, "JOIN"):
            return
        if parameters[0] == "0":
            for channel in list(client.channels):
                self.broadcast(channel, f":{client.prefix} PART {channel.name}")
                self.remove_member(client, channel)
            return
        keys = parameters[1].split(",") if len(parameters) >= 2 else []
        for index, name in enumerate(parameters[0].split(",")):
            key = keys[index] if index < len(keys) else ""
            if not valid_channel(name, self.settings["CHANNELLEN"]):
                self.numeric(client, 403, x=name)
                continue
            channel = self.find_channel(name)
            if channel is not None and channel.member(client) is not None:
                continue
            if len(client.channels) >= self.settings["MAXCHANNELS"]:
                self.numeric(client, 405, x=name)
                continue
            if channel is None:
                channel = Channel(name, self.time)
                self.channels[fold(name)] = channel
            else:
                invited = channel in client.invites
                failure = None
                if channel.banned(client) and not invited:
                    failure = 474
                elif "i" in channel.flags and not invited:
                    failure = 473
                elif channel.key and key != channel.key:
                    failure = 475
                elif channel.limit and len(channel.members) >= channel.limit:
                    failure = 471
                if failure is not None:
                    self.numeric(client, failure, channel=channel)
                    continue
            if channel in client.invites:
                client.invites.remove(channel)
            channel.add(client, operator=not channel.members)
            self.broadcast(channel, f":{client.prefix} JOIN {channel.name}")
            if channel.topic:
                self.numeric(client, 332, channel=channel)
                self.numeric(client, 333, channel=channel)
            self.names_reply(client, channel)

    def part(self, client, parameters):
        if not self.require(client, parameters, 1, "PART"):
            return
        suffix = " :" + parameters[1] if len(parameters) >= 2 and parameters[1] else ""
        for name in parameters[0].split(","):
            channel = self.find_channel(name)
            if channel is None:
                self.numeric(client, 403, x=name)
            elif channel.member(client) is None:
                self.numeric(client, 442, channel=channel)
            else:
                self.broadcast(channel, f":{client.prefix} PART {channel.name}{suffix}")
                self.remove_member(client, channel)

    def message(self, client, parameters, command):
        replies = command == "PRIVMSG"
        if replies:
            client.last_speaking = self.time
        if not parameters or not parameters[0]:
            if replies:
                self.numeric(client, 411, command=command)
            return
        if len(parameters) < 2 or not parameters[1]:
            if replies:
                self.numeric(client, 412)
            return
        text = parameters[1]
        for target in parameters[0].split(","):
            if target.startswith("#"):
                channel = self.find_channel(target)
                if channel is None:
                    if replies:
                        self.numeric(client, 401, x=target)
                elif not channel.can_speak(client):
                    if replies:
                        self.numeric(client, 404, channel=channel)
                else:
                    channel.messages += 1
                    self.broadcast(channel, f":{client.prefix} {command} {channel.name} :{text}", exclude=client)
            else:
                user = self.find_user(target)
                if user is None:
                    if replies:
                        self.numeric(client, 401, x=target)
                    continue
                self.send(user, f":{client.prefix} {command} {user.nickname} :{text}")
                if replies and user.away:
                    self.numeric(client, 301, user=user)

    def topic(self, client, parameters):
        if not self.require(client, parameters, 1, "TOPIC"):
            return
        channel = self.find_channel(parameters[0])
        if channel is None:
            self.numeric(client, 403, x=parameters[0])
            return
        member = channel.member(client)
        if member is None:
            self.numeric(client, 442, channel=channel)
            return
        if len(parameters) == 1:
            self.numeric(client, 332 if channel.topic else 331, channel=channel)
            if channel.topic:
                self.numeric(client, 333, channel=channel)
            return
        if "t" in channel.flags and not member.operator:
            self.numeric(client, 482, channel=channel)
            return
        channel.topic = parameters[1][:self.settings["TOPICLEN"]]
        channel.topic_setter = client.nickname
        channel.topic_time = self.time
        self.broadcast(channel, f":{client.prefix} TOPIC {channel.name} :{channel.topic}")

    def names(self, client, parameters):
        if not parameters:
            self.numeric(client, 366, x="*")
            return
        for name in parameters[0].split(","):
            channel = self.find_channel(name)
            if channel is None:
                self.numeric(client, 366, x=name)
            else:
                self.names_reply(client, channel)

    def whois(self, client, parameters):
        if not parameters:
            self.numeric(client, 431)
            return
        user = self.find_user(parameters[0])
        if user is None:
            self.numeric(client, 401, x=parameters[0])
            self.numeric(client, 318, x=parameters[0])
            return
        self.numeric(client, 311, user=user)
        if user.channels:
            self.numeric(client, 319, user=user, channel_list=self.joined_channels(user, " "))
        self.numeric(client, 312, user=user)
        if user.away:
            self.numeric(client, 301, user=user)
        self.numeric(client, 317, user=user, idle=self.time - user.last_speaking)
        self.numeric(client, 318, x=user.nickname)

    def away(self, client, parameters):
        client.away = parameters[0] if parameters and parameters[0] else ""
        self.numeric(client, 306 if client.away else 305)

    def invite(self, client, parameters):
        if not self.require(client, parameters, 2, "INVITE"):
            return
        user = self.find_user(parameters[0])
        if user is None:
            self.numeric(client, 401, x=parameters[0])
            return
        channel = self.find_channel(parameters[1])
        if channel is None:
            self.numeric(client, 403, x=parameters[1])
            return
        member = channel.member(client)
        if member is None:
            self.numeric(client, 442, channel=channel)
            return
        if channel.member(user) is not None:
            self.numeric(client, 443, user=user, channel=channel)
            return
        if "i" in channel.flags and not member.operator:
            self.numeric(client, 482, channel=channel)
            return
        if channel not in user.invites:
            user.invites.append(channel)
        self.numeric(client, 341, user=user, channel=channel)
        if user.away:
            self.numeric(client, 301, user=user)
        self.send(user, f":{client.prefix} INVITE {user.nickname} :{channel.name}")

    def kick(self, client, parameters):
        if not self.require(client, parameters, 2, "KICK"):
            return
        channel = self.find_channel(parameters[0])
        if channel is None:
            self.numeric(client, 403, x=parameters[0])
            return
        member = channel.member(client)
        if member is None:
            self.numeric(client, 442, channel=channel)
            return
        if not member.operator:
            self.numeric(client, 482, channel=channel)
            return
        user = self.find_user(parameters[1])
        if user is None:
            self.numeric(client, 401, x=parameters[1])
            return
        if channel.member(user) is None:
            self.numeric(client, 441, user=user, channel=channel)
            return
        reason = parameters[2] if len(parameters) >= 3 and parameters[2] else client.nickname
        self.broadcast(channel, f":{client.prefix} KICK {channel.name} {user.nickname} :{reason}")
        self.remove_member(user, channel)

    def mode(self, client, parameters):
        if not self.require(client, parameters, 1, "MODE"):
            return
        if parameters[0].startswith("#"):
            self.channel_mode(client, parameters)
        else:
            self.user_mode(client, parameters)

    def user_mode(self, client, parameters):
        user = self.find_user(parameters[0])
        if user is None:
            self.numeric(client, 401, x=parameters[0])
            return
        if user is not client:
            self.numeric(client, 502)
            return
        if len(parameters) == 1:
            self.numeric(client, 221)
            return
        sign = "+"
        changes = []
        unknown = False
        for character in parameters[1]:
            if character in "+-":
                sign = character
            elif character == "i":
                desired = sign == "+"
                if client.invisible != desired:
                    client.invisible = desired
                    changes.append((sign, character, None))
            else:
                unknown = True
        if changes:
            self.send(client, f":{client.nickname} MODE {client.nickname} :{change_string(changes)}")
        if unknown:
            self.numeric(client, 501)

    def channel_mode(self, client, parameters):
        channel = self.find_channel(parameters[0])
        if channel is None:
            self.numeric(client, 403, x=parameters[0])
            return
        if len(parameters) == 1:
            display = channel.mode_display(include_key=channel.member(client) is not None)
            self.numeric(client, 324, channel=channel, display=display)
            self.numeric(client, 329, channel=channel)
            return
        items = channel_items(parameters[1], parameters[2:])
        member = channel.member(client)
        authorized = member is not None and member.operator
        bans_sent = False
        denial_sent = False
        changes = []
        for sign, character, argument in items:
            if character not in "biklmnotv":
                self.numeric(client, 472, character=character, channel=channel)
                continue
            if character == "b" and argument is None:
                if sign == "+" and not bans_sent:
                    for ban in channel.bans:
                        self.numeric(client, 367, channel=channel, ban=ban)
                    self.numeric(client, 368, channel=channel)
                    bans_sent = True
                continue
            if argument is None and (character in "ov" or sign == "+" and character in "kl"):
                continue
            if not authorized:
                if not denial_sent:
                    self.numeric(client, 482, channel=channel)
                    denial_sent = True
                continue
            change = self.apply_channel_mode(client, channel, sign, character, argument)
            if change is not None:
                changes.append(change)
        if changes:
            self.broadcast(channel, f":{client.prefix} MODE {channel.name} {change_string(changes)}")

    def apply_channel_mode(self, client, channel, sign, character, argument):
        adding = sign == "+"
        changed = False
        change_argument = None
        if character in "ov":
            user = self.find_user(argument)
            if user is None:
                self.numeric(client, 401, x=argument)
                return None
            member = channel.member(user)
            if member is None:
                self.numeric(client, 441, user=user, channel=channel)
                return None
            attribute = "operator" if character == "o" else "voice"
            if getattr(member, attribute) != adding:
                setattr(member, attribute, adding)
                changed = True
                change_argument = user.nickname
        elif character == "b":
            mask = normalize(argument)
            folded = fold(mask)
            found = next((index for index, ban in enumerate(channel.bans) if fold(ban[0]) == folded), None)
            if adding and found is None:
                channel.bans.append((mask, client.nickname, self.time))
                changed = True
                change_argument = mask
            elif not adding and found is not None:
                change_argument = channel.bans.pop(found)[0]
                changed = True
        elif character == "k":
            if adding:
                if channel.key:
                    self.numeric(client, 467, channel=channel)
                else:
                    channel.key = argument
                    changed = True
                    change_argument = argument
            elif channel.key:
                channel.key = ""
                changed = True
                change_argument = "*"
        elif character == "l":
            if adding:
                limit = int(argument)
                if channel.limit != limit:
                    channel.limit = limit
                    changed = True
                    change_argument = str(limit)
            elif channel.limit:
                channel.limit = 0
                changed = True
        elif adding and character not in channel.flags:
            channel.flags.add(character)
            changed = True
        elif not adding and character in channel.flags:
            channel.flags.remove(character)
            changed = True
        return (sign, character, change_argument) if changed else None

    def channel_report(self):
        lines = []
        for channel in self.channels.values():
            lines.append(
                f"CHANNEL {channel.name} created {channel.created} members {len(channel.members)} "
                f"peak {channel.peak} messages {channel.messages} modes {channel.mode_display()}"
            )
            if channel.topic:
                lines.append(f"TOPIC {channel.topic_setter} {channel.topic_time} {channel.topic}")
            else:
                lines.append("TOPIC none")
            for mask, setter, time in channel.bans:
                lines.append(f"BAN {mask} {setter} {time}")
            lines.append("MEMBERS " + " ".join(member.display for member in channel.members))
        members = sum(len(channel.members) for channel in self.channels.values())
        bans = sum(len(channel.bans) for channel in self.channels.values())
        lines.append(f"TOTAL channels {len(self.channels)} members {members} bans {bans}")
        return lines

    def client_report(self):
        lines = []
        for client in self.clients.values():
            username = client.username if client.username is not None else "*"
            signon = client.registration_time if client.registered else "-"
            channels = self.joined_channels(client, ",") or "none"
            invites = ",".join(channel.name for channel in client.invites) or "none"
            lines.append(
                f"CLIENT {client.identifier} {client.addressee} {username} {client.hostname} {client.mode} "
                f"connected {client.connection_time} signon {signon} received {client.received} sent {client.sent} "
                f"tokens {client.tokens} queue {len(client.queue)} channels {channels} invites {invites}"
            )
            if client.away:
                lines.append(f"AWAY {client.identifier} {client.away}")
        registered = sum(client.registered for client in self.clients.values())
        invisible = sum(client.invisible for client in self.clients.values())
        away = sum(bool(client.away) for client in self.clients.values())
        lines.append(f"TOTAL clients {len(self.clients)} registered {registered} invisible {invisible} away {away}")
        return lines

    def statistics_report(self):
        counts = self.statistics
        pending = sum(len(client.queue) for client in self.clients.values())
        lines = [f"END {self.end}",
                 f"LINES total {len(self.traffic)} connect {self.line_counts['connect']} "
                 f"disconnect {self.line_counts['disconnect']} messages {self.line_counts['messages']}",
                 f"MESSAGES dropped {counts['dropped']} queued {counts['queued']} processed {counts['processed']} "
                 f"discarded {counts['discarded']} pending {pending} empty {counts['empty']}",
                 f"SENT lines {len(self.sent)} numerics {sum(self.numeric_counts.values())} "
                 f"pings {counts['pings']} errors {counts['errors']}"]
        for command, count in sorted(self.commands.items()):
            lines.append(f"COMMAND {command} {count}")
        for number, count in sorted(self.numeric_counts.items()):
            lines.append(f"NUMERIC {number:03d} {count}")
        for kind, peak in (("connections", self.peak_connections), ("registered", self.peak_registered)):
            lines.append(f"PEAK {kind} {peak[0]} at {peak[1]}")
        lines.append("DISCONNECTS " + " ".join(f"{kind} {self.disconnections[kind]}"
                                              for kind in ("quit", "closed", "flood", "timeout")))
        for time, identifier, addressee, reason in self.gone:
            lines.append(f"GONE {time} {identifier} {addressee} {reason}")
        return lines

    def write_outputs(self):
        outputs = {"sent.txt": self.sent, "channels.txt": self.channel_report(),
                   "clients.txt": self.client_report(), "stats.txt": self.statistics_report()}
        directory = Path("output")
        directory.mkdir(parents=True, exist_ok=True)
        for filename, lines in outputs.items():
            text = "\n".join(lines) + ("\n" if lines else "")
            (directory / filename).write_text(text, encoding="ascii", newline="\n")


def main():
    server = Server(*read_inputs())
    server.run()
    server.write_outputs()


if __name__ == "__main__":
    main()
