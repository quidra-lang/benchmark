const std = @import("std");
const p = @import("protocol.zig");
const Client = @import("clients.zig").Client;
const channel_model = @import("channels.zig");
const Channel = channel_model.Channel;
const Member = channel_model.Member;
const modes = @import("modes.zig");
const Change = modes.Change;
const masks = @import("masks.zig");
const Names = []const []const u8;
const Settings = struct {
    name: []const u8,
    version: []const u8,
    created: []const u8,
    description: []const u8,
    nicklen: usize,
    channellen: usize,
    topiclen: usize,
    maxchannels: usize,
    bucket: i64,
    refill: i64,
    queue: usize,
    pingfreq: i64,
    timeout: i64,
    motd: Names,
};
const TrafficKind = enum { connect, disconnect, message };
const Traffic = struct { time: i64, identifier: []const u8, body: []const u8, kind: TrafficKind };
const DisconnectKind = enum { quit, closed, flood, timeout };
const Gone = struct { time: i64, identifier: []const u8, addressee: []const u8, reason: []const u8 };
const CommandCount = struct { command: []const u8, count: i64 = 1 };
const Statistics = struct { dropped: i64 = 0, queued: i64 = 0, processed: i64 = 0, discarded: i64 = 0,
     empty: i64 = 0, pings: i64 = 0, errors: i64 = 0 };
const Peak = struct { count: i64 = 0, time: i64 = 0 };
fn number3(value: anytype) []const u8 {
    return p.fmt("{d:0>3}", .{value});
}
fn value(line: []const u8) []const u8 {
    return line[(std.mem.indexOfScalar(u8, line, ' ') orelse unreachable) + 1 ..];
}
const Server = struct {
    settings: Settings = undefined,
    traffic: std.ArrayList(Traffic) = .empty,
    end: i64 = 0,
    time: i64 = 0,
    clients: std.ArrayList(*Client) = .empty,
    channels: std.ArrayList(*Channel) = .empty,
    sent: p.Lines = .{},
    commands: std.ArrayList(CommandCount) = .empty,
    numeric_counts: [1000]i64 = @splat(0),
    line_counts: [3]i64 = @splat(0),
    disconnections: [4]i64 = @splat(0),
    statistics: Statistics = .{},
    gone: std.ArrayList(Gone) = .empty,
    peak_connections: Peak = .{},
    peak_registered: Peak = .{},
    fn readInputs(self: *Server, io: std.Io) !void {
        const lines = try p.readLines(io, "input/server.txt");
        var motd: std.ArrayList([]const u8) = .empty;
        for (lines[13..]) |line| p.append([]const u8, &motd, value(line));
        self.settings = .{ .name = value(lines[0]), .version = value(lines[1]), .created = value(lines[2]),
             .description = value(lines[3]), .nicklen = p.u(p.number(value(lines[4]))), .channellen = p.u(p.number(value(lines[5]))),
             .topiclen = p.u(p.number(value(lines[6]))), .maxchannels = p.u(p.number(value(lines[7]))),
             .bucket = p.number(value(lines[8])), .refill = p.number(value(lines[9])), .queue = p.u(p.number(value(lines[10]))),
             .pingfreq = p.number(value(lines[11])), .timeout = p.number(value(lines[12])),
             .motd = motd.items };
        for (try p.readLines(io, "input/traffic.txt")) |line| {
            const first = std.mem.indexOfScalar(u8, line, ' ').?;
            const second = first + 1 + std.mem.indexOfScalar(u8, line[first + 1 ..], ' ').?;
            const body = line[second + 1 ..];
            var kind: TrafficKind = .message;
            if (p.eq(body, "DISCONNECT")) kind = .disconnect else if (std.mem.startsWith(u8, body, "CONNECT ")) {
                const host = body[8..];
                var valid = host.len >= 1 and host.len <= 63;
                for (host) |c| if (!p.letter(c) and !(c >= '0' and c <= '9') and c != '.' and c != '-') {
                    valid = false;
                };
                if (valid) kind = .connect;
            }
            self.line_counts[@intFromEnum(kind)] += 1;
            p.append(Traffic, &self.traffic, .{ .time = p.number(line[0..first]), .identifier = line[first + 1 .. second],
                 .body = body, .kind = kind });
        }
        self.end = self.traffic.items[self.traffic.items.len - 1].time;
    }
    fn send(self: *Server, client: *Client, text: []const u8) void {
        self.sent.add("{d} {s} {s}", .{ self.time, client.identifier, text });
        client.sent += 1;
    }
    fn numeric(self: *Server, client: *Client, code: usize, content: []const u8) void {
        self.numeric_counts[code] += 1;
        self.send(client, p.fmt(":{s} {s} {s} {s}", .{ self.settings.name, number3(code), client.addressee(),
             content }));
    }
    fn err(self: *Server, client: *Client, code: usize, text: []const u8) void {
        const content = switch (code) {
            401 => p.fmt("{s} :No such nick/channel", .{text}),
            403 => p.fmt("{s} :No such channel", .{text}),
            404 => p.fmt("{s} :Cannot send to channel", .{text}),
            405 => p.fmt("{s} :You have joined too many channels", .{text}),
            409 => ":No origin specified",
            411 => p.fmt(":No recipient given ({s})", .{text}),
            412 => ":No text to send",
            421 => p.fmt("{s} :Unknown command", .{text}),
            431 => ":No nickname given",
            432 => p.fmt("{s} :Erroneous nickname", .{text}),
            433 => p.fmt("{s} :Nickname is already in use", .{text}),
            442 => p.fmt("{s} :You're not on that channel", .{text}),
            451 => ":You have not registered",
            461 => p.fmt("{s} :Not enough parameters", .{text}),
            462 => ":You may not reregister",
            467 => p.fmt("{s} :Channel key already set", .{text}),
            471 => p.fmt("{s} :Cannot join channel (+l)", .{text}),
            473 => p.fmt("{s} :Cannot join channel (+i)", .{text}),
            474 => p.fmt("{s} :Cannot join channel (+b)", .{text}),
            475 => p.fmt("{s} :Cannot join channel (+k)", .{text}),
            482 => p.fmt("{s} :You're not channel operator", .{text}),
            501 => ":Unknown MODE flag",
            502 => ":Cannot change mode for other users",
            else => unreachable,
        };
        self.numeric(client, code, content);
    }
    fn require(self: *Server, client: *Client, params: Names, count: usize, command: []const u8) bool {
        if (params.len >= count) return true;
        self.err(client, 461, command);
        return false;
    }
    fn broadcast(self: *Server, channel: *Channel, text: []const u8, exclude: ?*Client) void {
        for (channel.members.items) |entry| if (entry.client != exclude) self.send(entry.client, text);
    }
    fn sendPeers(self: *Server, client: *Client, text: []const u8) void {
        for (self.clients.items) |other| {
            if (!other.active or other == client) continue;
            for (client.channels.items) |index| if (self.channels.items[index].member(other) != null) {
                self.send(other, text);
                break;
            };
        }
    }
    fn findConnection(self: *Server, identifier: []const u8) ?*Client {
        for (self.clients.items) |client| if (client.active and p.eq(client.identifier, identifier)) return client;
        return null;
    }
    fn findUser(self: *Server, nickname: []const u8) ?*Client {
        for (self.clients.items) |client| if (client.active and client.registered and p.same(client.nickname.?,
             nickname)) return client;
        return null;
    }
    fn findChannel(self: *Server, name: []const u8) ?*Channel {
        for (self.channels.items) |channel| if (channel.active and p.same(channel.name, name)) return channel;
        return null;
    }
    fn joinedChannels(self: *Server, client: *Client, separator: []const u8) []const u8 {
        var names: std.ArrayList([]const u8) = .empty;
        for (client.channels.items) |index| {
            const channel = self.channels.items[index];
            p.append([]const u8, &names, p.fmt("{s}{s}", .{ channel.member(client).?.status(), channel.name }));
        }
        return p.join(names.items, separator);
    }
    fn removeMember(self: *Server, client: *Client, channel: *Channel) void {
        channel.remove(client);
        if (channel.members.items.len == 0) {
            channel.active = false;
            for (self.clients.items) |other| if (other.active) p.erase(&other.invites, channel.index);
        }
    }
    fn disconnect(self: *Server, client: *Client, reason: []const u8, kind: DisconnectKind) void {
        if (kind != .closed) {
            self.send(client, p.fmt("ERROR :Closing Link: {s}[{s}] ({s})", .{ client.addressee(),
                 client.hostname, reason }));
            self.statistics.errors += 1;
        }
        if (client.registered) self.sendPeers(client, p.fmt(":{s} QUIT :{s}", .{ client.prefix(), reason }));
        while (client.channels.items.len > 0) self.removeMember(client, self.channels.items[client.channels.items[0]]);
        self.statistics.discarded += p.n(client.queue.items.len);
        client.queue.clearRetainingCapacity();
        client.active = false;
        p.append(Gone, &self.gone, .{ .time = self.time, .identifier = client.identifier, .addressee = client.addressee(),
             .reason = reason });
        self.disconnections[@intFromEnum(kind)] += 1;
    }
    fn completeRegistration(self: *Server, client: *Client) void {
        if (client.registered or client.nickname == null or client.username == null) return;
        client.registered = true;
        client.registration_time = self.time;
        client.last_speaking = self.time;
        var registered: i64 = 0;
        for (self.clients.items) |other| if (other.active and other.registered) {
            registered += 1;
        };
        if (registered > self.peak_registered.count) self.peak_registered = .{ .count = registered, .time = self.time };
        const s = self.settings;
        self.numeric(client, 1, p.fmt(":Welcome to the Internet Relay Network {s}", .{client.prefix()}));
        self.numeric(client, 2, p.fmt(":Your host is {s}, running version {s}", .{ s.name, s.version }));
        self.numeric(client, 3, p.fmt(":This server was created {s}", .{s.created}));
        self.numeric(client, 4, p.fmt("{s} {s} i biklmnotv", .{ s.name, s.version }));
        self.numeric(client, 5, p.fmt("CASEMAPPING=rfc1459 CHANTYPES=# NICKLEN={d} CHANNELLEN={d} TOPICLEN={d} CHANLIMIT=#:{d} CHANMODES=b,k,l,imnt PREFIX=(ov)@+ :are supported by this server",
             .{ s.nicklen, s.channellen, s.topiclen, s.maxchannels }));
        self.numeric(client, 375, p.fmt(":- {s} Message of the day -", .{s.name}));
        for (s.motd) |line| self.numeric(client, 372, p.fmt(":- {s}", .{line}));
        self.numeric(client, 376, ":End of /MOTD command.");
        if (client.invisible) self.send(client, p.fmt(":{s} MODE {s} :+i", .{ client.nickname.?, client.nickname.? }));
    }
    fn namesReply(self: *Server, client: *Client, channel: *Channel) void {
        const names = channel.nameList(client);
        if (names.len > 0) self.numeric(client, 353, p.fmt("= {s} :{s}", .{ channel.name, names }));
        self.numeric(client, 366, p.fmt("{s} :End of /NAMES list.", .{channel.name}));
    }
    fn topicReplies(self: *Server, client: *Client, channel: *Channel) void {
        self.numeric(client, 332, p.fmt("{s} :{s}", .{ channel.name, channel.topic }));
        self.numeric(client, 333, p.fmt("{s} {s} {d}", .{ channel.name, channel.topic_setter, channel.topic_time }));
    }
    fn awayReply(self: *Server, client: *Client, target: *Client) void {
        self.numeric(client, 301, p.fmt("{s} :{s}", .{ target.nickname.?, target.away }));
    }
    fn nick(self: *Server, client: *Client, params: Names) void {
        if (params.len == 0 or params[0].len == 0) {
            self.err(client, 431, "");
            return;
        }
        const nickname = params[0][0..@min(params[0].len, self.settings.nicklen)];
        if (!p.validNickname(nickname)) {
            self.err(client, 432, nickname);
            return;
        }
        if (client.nickname) |old| if (p.eq(old, nickname)) return;
        for (self.clients.items) |other| if (other.active and other != client) {
            if (other.nickname) |name| if (p.same(name, nickname)) {
                self.err(client, 433, nickname);
                return;
            };
        };
        if (client.registered) {
            const text = p.fmt(":{s} NICK :{s}", .{ client.prefix(), nickname });
            self.send(client, text);
            self.sendPeers(client, text);
        }
        client.nickname = nickname;
        self.completeRegistration(client);
    }
    fn user(self: *Server, client: *Client, params: Names) void {
        if (client.username != null) {
            self.err(client, 462, "");
            return;
        }
        if (!self.require(client, params, 4, "USER")) return;
        client.username = params[0];
        client.realname = params[3];
        client.invisible = p.digits(params[1]) and params[1].len <= 3 and @mod(@divTrunc(p.number(params[1]),
             8), 2) == 1;
        self.completeRegistration(client);
    }
    fn joinChannels(self: *Server, client: *Client, params: Names) void {
        if (!self.require(client, params, 1, "JOIN")) return;
        if (p.eq(params[0], "0")) {
            while (client.channels.items.len > 0) {
                const channel = self.channels.items[client.channels.items[0]];
                self.broadcast(channel, p.fmt(":{s} PART {s}", .{ client.prefix(), channel.name }), null);
                self.removeMember(client, channel);
            }
            return;
        }
        const names = p.split(params[0], ',');
        const keys: Names = if (params.len > 1) p.split(params[1], ',') else &.{};
        for (names, 0..) |name, i| {
            const key = if (i < keys.len) keys[i] else "";
            if (!p.validChannel(name, self.settings.channellen)) {
                self.err(client, 403, name);
                continue;
            }
            var channel = self.findChannel(name);
            if (channel) |ch| if (ch.member(client) != null) continue;
            if (client.channels.items.len >= self.settings.maxchannels) {
                self.err(client, 405, name);
                continue;
            }
            if (channel == null) {
                const created = p.create(Channel, .{ .index = self.channels.items.len, .name = name,
                     .created = self.time });
                p.append(*Channel, &self.channels, created);
                channel = created;
            } else {
                const ch = channel.?;
                const invited = p.contains(client.invites.items, ch.index);
                const failure: usize = if (ch.banned(client) and !invited) 474 else if (ch.flag_i and !invited) 473 else if (ch.key.len > 0 and !p.eq(ch.key,
                     key)) 475 else if (ch.limit > 0 and ch.members.items.len >= p.u(ch.limit)) 471 else 0;
                if (failure != 0) {
                    self.err(client, failure, ch.name);
                    continue;
                }
            }
            const ch = channel.?;
            p.erase(&client.invites, ch.index);
            ch.add(client, ch.members.items.len == 0);
            self.broadcast(ch, p.fmt(":{s} JOIN {s}", .{ client.prefix(), ch.name }), null);
            if (ch.topic.len > 0) self.topicReplies(client, ch);
            self.namesReply(client, ch);
        }
    }
    fn part(self: *Server, client: *Client, params: Names) void {
        if (!self.require(client, params, 1, "PART")) return;
        const suffix = if (params.len > 1 and params[1].len > 0) p.fmt(" :{s}", .{params[1]}) else "";
        for (p.split(params[0], ',')) |name| {
            const channel = self.findChannel(name) orelse {
                self.err(client, 403, name);
                continue;
            };
            if (channel.member(client) == null) self.err(client, 442, channel.name) else {
                self.broadcast(channel, p.fmt(":{s} PART {s}{s}", .{ client.prefix(), channel.name, suffix }), null);
                self.removeMember(client, channel);
            }
        }
    }
    fn message(self: *Server, client: *Client, params: Names, command: []const u8) void {
        const replies = p.eq(command, "PRIVMSG");
        if (replies) client.last_speaking = self.time;
        if (params.len == 0 or params[0].len == 0) {
            if (replies) self.err(client, 411, command);
            return;
        }
        if (params.len < 2 or params[1].len == 0) {
            if (replies) self.err(client, 412, "");
            return;
        }
        for (p.split(params[0], ',')) |target| {
            if (target.len > 0 and target[0] == '#') {
                const channel = self.findChannel(target) orelse {
                    if (replies) self.err(client, 401, target);
                    continue;
                };
                if (!channel.canSpeak(client)) {
                    if (replies) self.err(client, 404, channel.name);
                } else {
                    channel.messages += 1;
                    self.broadcast(channel, p.fmt(":{s} {s} {s} :{s}", .{ client.prefix(),
                         command, channel.name, params[1] }), client);
                }
            } else {
                const recipient = self.findUser(target) orelse {
                    if (replies) self.err(client, 401, target);
                    continue;
                };
                self.send(recipient, p.fmt(":{s} {s} {s} :{s}", .{ client.prefix(), command,
                     recipient.nickname.?, params[1] }));
                if (replies and recipient.away.len > 0) self.awayReply(client, recipient);
            }
        }
    }
    fn topic(self: *Server, client: *Client, params: Names) void {
        if (!self.require(client, params, 1, "TOPIC")) return;
        const channel = self.findChannel(params[0]) orelse {
            self.err(client, 403, params[0]);
            return;
        };
        const member = channel.member(client) orelse {
            self.err(client, 442, channel.name);
            return;
        };
        if (params.len == 1) {
            if (channel.topic.len == 0) self.numeric(client, 331, p.fmt("{s} :No topic is set",
                 .{channel.name})) else self.topicReplies(client, channel);
            return;
        }
        if (channel.flag_t and !member.op) {
            self.err(client, 482, channel.name);
            return;
        }
        channel.topic = params[1][0..@min(params[1].len, self.settings.topiclen)];
        channel.topic_setter = client.nickname.?;
        channel.topic_time = self.time;
        self.broadcast(channel, p.fmt(":{s} TOPIC {s} :{s}", .{ client.prefix(), channel.name, channel.topic }), null);
    }
    fn names(self: *Server, client: *Client, params: Names) void {
        if (params.len == 0) {
            self.numeric(client, 366, "* :End of /NAMES list.");
            return;
        }
        for (p.split(params[0], ',')) |name| {
            if (self.findChannel(name)) |channel| self.namesReply(client, channel) else self.numeric(client,
                 366, p.fmt("{s} :End of /NAMES list.", .{name}));
        }
    }
    fn whois(self: *Server, client: *Client, params: Names) void {
        if (params.len == 0) {
            self.err(client, 431, "");
            return;
        }
        const target = self.findUser(params[0]) orelse {
            self.err(client, 401, params[0]);
            self.numeric(client, 318, p.fmt("{s} :End of /WHOIS list.", .{params[0]}));
            return;
        };
        self.numeric(client, 311, p.fmt("{s} {s} {s} * :{s}", .{ target.nickname.?, target.username.?,
             target.hostname, target.realname }));
        if (target.channels.items.len > 0) self.numeric(client, 319, p.fmt("{s} :{s}", .{ target.nickname.?,
             self.joinedChannels(target, " ") }));
        self.numeric(client, 312, p.fmt("{s} {s} :{s}", .{ target.nickname.?, self.settings.name,
             self.settings.description }));
        if (target.away.len > 0) self.awayReply(client, target);
        self.numeric(client, 317, p.fmt("{s} {d} {d} :seconds idle, signon time", .{ target.nickname.?,
             self.time - target.last_speaking.?, target.registration_time.? }));
        self.numeric(client, 318, p.fmt("{s} :End of /WHOIS list.", .{target.nickname.?}));
    }
    fn invite(self: *Server, client: *Client, params: Names) void {
        if (!self.require(client, params, 2, "INVITE")) return;
        const target = self.findUser(params[0]) orelse {
            self.err(client, 401, params[0]);
            return;
        };
        const channel = self.findChannel(params[1]) orelse {
            self.err(client, 403, params[1]);
            return;
        };
        const member = channel.member(client) orelse {
            self.err(client, 442, channel.name);
            return;
        };
        if (channel.member(target) != null) {
            self.numeric(client, 443, p.fmt("{s} {s} :is already on channel", .{ target.nickname.?, channel.name }));
            return;
        }
        if (channel.flag_i and !member.op) {
            self.err(client, 482, channel.name);
            return;
        }
        if (!p.contains(target.invites.items, channel.index)) p.append(usize, &target.invites, channel.index);
        self.numeric(client, 341, p.fmt("{s} {s}", .{ target.nickname.?, channel.name }));
        if (target.away.len > 0) self.awayReply(client, target);
        self.send(target, p.fmt(":{s} INVITE {s} :{s}", .{ client.prefix(), target.nickname.?, channel.name }));
    }
    fn kick(self: *Server, client: *Client, params: Names) void {
        if (!self.require(client, params, 2, "KICK")) return;
        const channel = self.findChannel(params[0]) orelse {
            self.err(client, 403, params[0]);
            return;
        };
        const member = channel.member(client) orelse {
            self.err(client, 442, channel.name);
            return;
        };
        if (!member.op) {
            self.err(client, 482, channel.name);
            return;
        }
        const target = self.findUser(params[1]) orelse {
            self.err(client, 401, params[1]);
            return;
        };
        if (channel.member(target) == null) {
            self.numeric(client, 441, p.fmt("{s} {s} :They aren't on that channel", .{ target.nickname.?,
                 channel.name }));
            return;
        }
        const reason = if (params.len > 2 and params[2].len > 0) params[2] else client.nickname.?;
        self.broadcast(channel, p.fmt(":{s} KICK {s} {s} :{s}", .{ client.prefix(), channel.name,
             target.nickname.?, reason }), null);
        self.removeMember(target, channel);
    }
    fn userMode(self: *Server, client: *Client, params: Names) void {
        const target = self.findUser(params[0]) orelse {
            self.err(client, 401, params[0]);
            return;
        };
        if (target != client) {
            self.err(client, 502, "");
            return;
        }
        if (params.len == 1) {
            self.numeric(client, 221, client.mode());
            return;
        }
        var sign: u8 = '+';
        var unknown = false;
        var changes: std.ArrayList(Change) = .empty;
        for (params[1]) |c| {
            if (c == '+' or c == '-') sign = c else if (c == 'i') {
                const desired = sign == '+';
                if (client.invisible != desired) {
                    client.invisible = desired;
                    p.append(Change, &changes, .{ .sign = sign, .character = c });
                }
            } else unknown = true;
        }
        if (changes.items.len > 0) self.send(client, p.fmt(":{s} MODE {s} :{s}", .{ client.nickname.?,
             client.nickname.?, modes.changeString(changes.items) }));
        if (unknown) self.err(client, 501, "");
    }
    fn applyChannelMode(self: *Server, client: *Client, channel: *Channel, item: Change) ?Change {
        const adding = item.sign == '+';
        const c = item.character;
        var changed = false;
        var argument: ?[]const u8 = null;
        if (c == 'o' or c == 'v') {
            const target = self.findUser(item.argument.?) orelse {
                self.err(client, 401, item.argument.?);
                return null;
            };
            const member = channel.member(target) orelse {
                self.numeric(client, 441, p.fmt("{s} {s} :They aren't on that channel", .{ target.nickname.?,
                     channel.name }));
                return null;
            };
            const privilege = if (c == 'o') &member.op else &member.voice;
            if (privilege.* != adding) {
                privilege.* = adding;
                changed = true;
                argument = target.nickname.?;
            }
        } else if (c == 'b') {
            const mask = masks.normalize(item.argument.?);
            var found: ?usize = null;
            for (channel.bans.items, 0..) |ban, i| if (p.same(ban.mask, mask)) {
                found = i;
                break;
            };
            if (adding and found == null) {
                p.append(channel_model.Ban, &channel.bans, .{ .mask = mask, .setter = client.nickname.?,
                     .time = self.time });
                changed = true;
                argument = mask;
            } else if (!adding and found != null) {
                argument = channel.bans.orderedRemove(found.?).mask;
                changed = true;
            }
        } else if (c == 'k') {
            if (adding) {
                if (channel.key.len > 0) self.err(client, 467, channel.name) else {
                    channel.key = item.argument.?;
                    changed = true;
                    argument = item.argument.?;
                }
            } else if (channel.key.len > 0) {
                channel.key = "";
                changed = true;
                argument = "*";
            }
        } else if (c == 'l') {
            if (adding) {
                const limit = p.number(item.argument.?);
                if (channel.limit != limit) {
                    channel.limit = limit;
                    changed = true;
                    argument = p.fmt("{d}", .{limit});
                }
            } else if (channel.limit != 0) {
                channel.limit = 0;
                changed = true;
            }
        } else if (channel.flag(c) != adding) {
            channel.setFlag(c, adding);
            changed = true;
        }
        return if (changed) .{ .sign = item.sign, .character = c, .argument = argument } else null;
    }
    fn channelMode(self: *Server, client: *Client, params: Names) void {
        const channel = self.findChannel(params[0]) orelse {
            self.err(client, 403, params[0]);
            return;
        };
        if (params.len == 1) {
            self.numeric(client, 324, p.fmt("{s} {s}", .{ channel.name, channel.modeDisplay(channel.member(client) != null) }));
            self.numeric(client, 329, p.fmt("{s} {d}", .{ channel.name, channel.created }));
            return;
        }
        const member = channel.member(client);
        const authorized = if (member) |m| m.op else false;
        var bans_sent = false;
        var denial_sent = false;
        var changes: std.ArrayList(Change) = .empty;
        for (modes.channelItems(params[1], params[2..])) |item| {
            const c = item.character;
            if (std.mem.indexOfScalar(u8, "biklmnotv", c) == null) {
                self.numeric(client, 472, p.fmt("{c} :is unknown mode char to me for {s}", .{ c, channel.name }));
                continue;
            }
            if (c == 'b' and item.argument == null) {
                if (item.sign == '+' and !bans_sent) {
                    for (channel.bans.items) |ban| self.numeric(client, 367, p.fmt("{s} {s} {s} {d}",
                         .{ channel.name, ban.mask, ban.setter, ban.time }));
                    self.numeric(client, 368, p.fmt("{s} :End of channel ban list", .{channel.name}));
                    bans_sent = true;
                }
                continue;
            }
            if (item.argument == null and (c == 'o' or c == 'v' or (item.sign == '+' and (c == 'k' or c == 'l')))) continue;
            if (!authorized) {
                if (!denial_sent) {
                    self.err(client, 482, channel.name);
                    denial_sent = true;
                }
                continue;
            }
            if (self.applyChannelMode(client, channel, item)) |change| p.append(Change, &changes, change);
        }
        if (changes.items.len > 0) self.broadcast(channel, p.fmt(":{s} MODE {s} {s}", .{ client.prefix(),
             channel.name, modes.changeString(changes.items) }), null);
    }
    fn process(self: *Server, client: *Client, raw: []const u8) void {
        self.statistics.processed += 1;
        const parsed = p.parse(raw);
        const command = parsed.command;
        const params = parsed.params();
        if (command.len == 0) {
            self.statistics.empty += 1;
            return;
        }
        var counted = false;
        for (self.commands.items) |*entry| if (p.eq(entry.command, command)) {
            entry.count += 1;
            counted = true;
            break;
        };
        if (!counted) p.append(CommandCount, &self.commands, .{ .command = command });
        if (!client.registered and !p.eq(command, "NICK") and !p.eq(command, "USER") and !p.eq(command,
             "PING") and !p.eq(command, "PONG") and !p.eq(command, "QUIT")) {
            self.err(client, 451, "");
            return;
        }
        if (p.eq(command, "NICK")) self.nick(client, params) else if (p.eq(command, "USER")) self.user(client,
             params) else if (p.eq(command, "PING")) {
            if (params.len == 0 or params[0].len == 0) self.err(client, 409, "") else self.send(client,
                 p.fmt(":{s} PONG {s} :{s}", .{ self.settings.name, self.settings.name, params[0] }));
        } else if (p.eq(command, "PONG")) return else if (p.eq(command, "QUIT")) self.disconnect(client,
             if (params.len == 0 or params[0].len == 0) "Client Quit" else p.fmt("Quit: {s}",
             .{params[0]}), .quit) else if (p.eq(command, "JOIN")) self.joinChannels(client,
             params) else if (p.eq(command, "PART")) self.part(client, params) else if (p.eq(command,
             "PRIVMSG") or p.eq(command, "NOTICE")) self.message(client, params, command) else if (p.eq(command,
             "TOPIC")) self.topic(client, params) else if (p.eq(command, "NAMES")) self.names(client,
             params) else if (p.eq(command, "WHOIS")) self.whois(client, params) else if (p.eq(command,
             "AWAY")) {
            client.away = if (params.len == 0) "" else params[0];
            self.numeric(client, if (client.away.len == 0) 305 else 306, if (client.away.len == 0) ":You are no longer marked as being away" else ":You have been marked as being away");
        } else if (p.eq(command, "INVITE")) self.invite(client, params) else if (p.eq(command,
             "KICK")) self.kick(client, params) else if (p.eq(command, "MODE")) {
            if (self.require(client, params, 1, "MODE")) {
                if (params[0].len > 0 and params[0][0] == '#') self.channelMode(client, params) else self.userMode(client,
                     params);
            }
        } else self.err(client, 421, command);
    }
    fn arrival(self: *Server, record: Traffic) void {
        if (record.kind == .connect) {
            p.append(*Client, &self.clients, p.create(Client, .{ .identifier = record.identifier,
                 .hostname = record.body[8..], .connection_time = self.time, .last_received = self.time,
                 .tokens = self.settings.bucket }));
            var count: i64 = 0;
            for (self.clients.items) |client| if (client.active) {
                count += 1;
            };
            if (count > self.peak_connections.count) self.peak_connections = .{ .count = count, .time = self.time };
            return;
        }
        const found = self.findConnection(record.identifier);
        if (record.kind == .disconnect) {
            if (found) |client| self.disconnect(client, "Remote host closed the connection", .closed);
            return;
        }
        const client = found orelse {
            self.statistics.dropped += 1;
            return;
        };
        client.received += 1;
        client.last_received = self.time;
        client.ping_sent = null;
        if (client.queue.items.len == 0 and client.tokens >= 1) {
            client.useToken(self.time, self.settings.bucket, self.settings.refill);
            self.process(client, record.body);
        } else if (client.queue.items.len >= self.settings.queue) {
            self.statistics.discarded += 1;
            self.disconnect(client, "Excess Flood", .flood);
        } else {
            p.append([]const u8, &client.queue, record.body);
            self.statistics.queued += 1;
        }
    }
    fn channelReport(self: *Server) p.Lines {
        var out: p.Lines = .{};
        var count: usize = 0;
        var members: usize = 0;
        var bans: usize = 0;
        for (self.channels.items) |channel| if (channel.active) {
            count += 1;
            members += channel.members.items.len;
            bans += channel.bans.items.len;
            out.add("CHANNEL {s} created {d} members {d} peak {d} messages {d} modes {s}",
                 .{ channel.name, channel.created, channel.members.items.len, channel.peak,
                 channel.messages, channel.modeDisplay(true) });
            if (channel.topic.len == 0) out.add("TOPIC none", .{}) else out.add("TOPIC {s} {d} {s}",
                 .{ channel.topic_setter, channel.topic_time, channel.topic });
            for (channel.bans.items) |ban| out.add("BAN {s} {s} {d}", .{ ban.mask, ban.setter, ban.time });
            var names_list: std.ArrayList([]const u8) = .empty;
            for (channel.members.items) |entry| p.append([]const u8, &names_list, entry.display());
            out.add("MEMBERS {s}", .{p.join(names_list.items, " ")});
        };
        out.add("TOTAL channels {d} members {d} bans {d}", .{ count, members, bans });
        return out;
    }
    fn clientReport(self: *Server) p.Lines {
        var out: p.Lines = .{};
        var count: usize = 0;
        var registered: usize = 0;
        var invisible: usize = 0;
        var away: usize = 0;
        for (self.clients.items) |client| if (client.active) {
            count += 1;
            registered += @intFromBool(client.registered);
            invisible += @intFromBool(client.invisible);
            away += @intFromBool(client.away.len > 0);
            const joined = self.joinedChannels(client, ",");
            var invites: std.ArrayList([]const u8) = .empty;
            for (client.invites.items) |index| p.append([]const u8, &invites, self.channels.items[index].name);
            out.add("CLIENT {s} {s} {s} {s} {s} connected {d} signon {s} received {d} sent {d} tokens {d} queue {d} channels {s} invites {s}",
                 .{ client.identifier, client.addressee(), client.username orelse "*", client.hostname,
                 client.mode(), client.connection_time, if (client.registered) p.fmt("{d}",
                 .{client.registration_time.?}) else "-", client.received, client.sent, client.tokens,
                 client.queue.items.len, if (joined.len > 0) joined else "none", if (invites.items.len > 0) p.join(invites.items,
                 ",") else "none" });
            if (client.away.len > 0) out.add("AWAY {s} {s}", .{ client.identifier, client.away });
        };
        out.add("TOTAL clients {d} registered {d} invisible {d} away {d}", .{ count, registered, invisible, away });
        return out;
    }
    fn statisticsReport(self: *Server) p.Lines {
        var out: p.Lines = .{};
        var pending: usize = 0;
        var numerics: i64 = 0;
        for (self.clients.items) |client| if (client.active) {
            pending += client.queue.items.len;
        };
        for (self.numeric_counts) |count| numerics += count;
        out.add("END {d}", .{self.end});
        out.add("LINES total {d} connect {d} disconnect {d} messages {d}", .{ self.traffic.items.len,
             self.line_counts[0], self.line_counts[1], self.line_counts[2] });
        const s = self.statistics;
        out.add("MESSAGES dropped {d} queued {d} processed {d} discarded {d} pending {d} empty {d}",
             .{ s.dropped, s.queued, s.processed, s.discarded, pending, s.empty });
        out.add("SENT lines {d} numerics {d} pings {d} errors {d}", .{ self.sent.data.items.len,
             numerics, s.pings, s.errors });
        std.mem.sort(CommandCount, self.commands.items, {}, struct {
            fn less(_: void, a: CommandCount, b: CommandCount) bool {
                return std.mem.lessThan(u8, a.command, b.command);
            }
        }.less);
        for (self.commands.items) |entry| out.add("COMMAND {s} {d}", .{ entry.command, entry.count });
        for (self.numeric_counts, 0..) |count, code| if (count > 0) out.add("NUMERIC {s} {d}",
             .{ number3(code), count });
        out.add("PEAK connections {d} at {d}", .{ self.peak_connections.count, self.peak_connections.time });
        out.add("PEAK registered {d} at {d}", .{ self.peak_registered.count, self.peak_registered.time });
        out.add("DISCONNECTS quit {d} closed {d} flood {d} timeout {d}", .{ self.disconnections[0],
             self.disconnections[1], self.disconnections[2], self.disconnections[3] });
        for (self.gone.items) |record| out.add("GONE {d} {s} {s} {s}", .{ record.time, record.identifier,
             record.addressee, record.reason });
        return out;
    }
    fn write(io: std.Io, name: []const u8, lines: p.Lines) !void {
        var text: p.Text = .{};
        for (lines.data.items) |line| text.add("{s}\n", .{line});
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = p.fmt("output/{s}", .{name}), .data = text.value() });
    }
    fn run(self: *Server, io: std.Io) !void {
        try self.readInputs(io);
        var position: usize = 0;
        while (self.time <= self.end) : (self.time += 1) {
            for (self.clients.items) |client| if (client.active) {
                client.refill(self.time, self.settings.bucket, self.settings.refill);
                while (client.active and client.queue.items.len > 0 and client.tokens >= 1) {
                    client.useToken(self.time, self.settings.bucket, self.settings.refill);
                    const raw = client.queue.orderedRemove(0);
                    self.process(client, raw);
                }
            };
            while (position < self.traffic.items.len and self.traffic.items[position].time == self.time) : (position += 1) self.arrival(self.traffic.items[position]);
            for (self.clients.items) |client| if (client.active) {
                if (client.ping_sent) |sent_time| {
                    if (self.time - sent_time >= self.settings.timeout) self.disconnect(client,
                         p.fmt("Ping timeout: {d} seconds", .{self.time - client.last_received}),
                         .timeout);
                } else if (self.time - client.last_received >= self.settings.pingfreq) {
                    self.send(client, p.fmt("PING :{s}", .{self.settings.name}));
                    self.statistics.pings += 1;
                    client.ping_sent = self.time;
                }
            };
        }
        try std.Io.Dir.cwd().createDirPath(io, "output");
        try write(io, "sent.txt", self.sent);
        try write(io, "channels.txt", self.channelReport());
        try write(io, "clients.txt", self.clientReport());
        try write(io, "stats.txt", self.statisticsReport());
    }
};
pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena.deinit();
    p.allocator = arena.allocator();
    var server: Server = .{};
    try server.run(init.io);
}
