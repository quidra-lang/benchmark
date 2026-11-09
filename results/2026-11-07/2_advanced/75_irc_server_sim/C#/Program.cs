using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
public static class Program {
    public static Dictionary<string, string> settings = new();
    public static List<string> motd = new();
    public static List<Traffic> traffic = new();
    public static Dictionary<string, Clients.Client> clients = new();
    public static Dictionary<string, Channels.Channel> channels = new();
    public static List<Clients.Client> clientOrder = new();
    public static List<Channels.Channel> channelOrder = new();
    public static List<string> sent = new();
    public static SortedDictionary<string, int> commands = new(StringComparer.Ordinal);
    public static SortedDictionary<int, int> numerics = new();
    public static Dictionary<string, int> lineCounts = new(), statistics = new(),
                                          disconnections = new();
    public static List<Gone> gone = new();
    public static int time, end, peakConnections, peakConnectionsTime, peakRegistered,
        peakRegisteredTime;
    public record Traffic(int time, string identifier, string kind, string body) {}
    public record Gone(int time, string identifier, string addressee, string reason) {}
    public static int Setting(string key) { return int.Parse(settings[key]); }
    public static void Add<K>(IDictionary<K, int> counts, K key, int amount) {
        counts.AddCount(key, amount);
    }
    public static int Stat(string key) { return statistics.GetValueOrDefault(key, 0); }
    public static string Number(int value) {
        return value.ToString("D3", CultureInfo.InvariantCulture);
    }
    public static void Send(Clients.Client client, string line) {
        sent.Add(time + " " + client.identifier + " " + line);
        client.sent++;
    }
    public static void Reply(Clients.Client client, int number, string content) {
        Add(numerics, number, 1);
        Send(client, ":" + settings["NAME"] + " " + Number(number) + " " + client.addressee + " " +
                         content);
    }
    public static void Error(Clients.Client client, int number, params string[] a) {
        string x = a.Length > 0 ? a[0] : "";
        string content = number switch {
            401 => x + " :No such nick/channel",
            403 => x + " :No such channel",
            404 => x + " :Cannot send to channel",
            405 => x + " :You have joined too many channels",
            409 => ":No origin specified",
            411 => ":No recipient given (" + x + ")",
            412 => ":No text to send",
            421 => x + " :Unknown command",
            431 => ":No nickname given",
            432 => x + " :Erroneous nickname",
            433 => x + " :Nickname is already in use",
            441 => x + " " + a[1] + " :They aren't on that channel",
            442 => x + " :You're not on that channel",
            443 => x + " " + a[1] + " :is already on channel",
            451 => ":You have not registered",
            461 => x + " :Not enough parameters",
            462 => ":You may not reregister",
            467 => x + " :Channel key already set",
            471 => x + " :Cannot join channel (+l)",
            472 => x + " :is unknown mode char to me for " + a[1],
            473 => x + " :Cannot join channel (+i)",
            474 => x + " :Cannot join channel (+b)",
            475 => x + " :Cannot join channel (+k)",
            482 => x + " :You're not channel operator",
            501 => ":Unknown MODE flag",
            502 => ":Cannot change mode for other users",
            _ => throw new ArgumentException(),
        };
        Reply(client, number, content);
    }
    public static void Broadcast(Channels.Channel channel, string line, Clients.Client exclude) {
        foreach (Channels.Member member in channel.members)
            if (member.client != exclude)
                Send(member.client, line);
    }
    public static void Peers(Clients.Client client, string line) {
        HashSet<Clients.Client> peers = new();
        foreach (Channels.Channel channel in client.channels)
            foreach (Channels.Member member in channel.members)
                peers.Add(member.client);
        foreach (Clients.Client other in clientOrder)
            if (other != client && peers.Contains(other))
                Send(other, line);
    }
    public static Clients.Client FindUser(string nickname) {
        string name = Protocol.Fold(nickname);
        foreach (Clients.Client client in clientOrder)
            if (client.registered && Protocol.Fold(client.nickname).Equals(name))
                return client;
        return null;
    }
    public static Channels.Channel FindChannel(string name) {
        return channels.GetValueOrDefault(Protocol.Fold(name));
    }
    public static string Joined(Clients.Client client, string separator) {
        List<string> names = new();
        foreach (Channels.Channel channel in client.channels)
            names.Add(channel.FindMember(client).status + channel.name);
        return string.Join(separator, names);
    }
    public static void RemoveMember(Clients.Client client, Channels.Channel channel) {
        channel.Remove(client);
        if (channel.members.Count == 0) {
            channels.Remove(Protocol.Fold(channel.name));
            channelOrder.Remove(channel);
            foreach (Clients.Client other in clientOrder)
                other.invites.Remove(channel);
        }
    }
    public static void Disconnect(Clients.Client client, string reason, string kind) {
        if (!kind.Equals("closed")) {
            Send(client, "ERROR :Closing Link: " + client.addressee + "[" + client.hostname +
                             "] (" + reason + ")");
            Add(statistics, "errors", 1);
        }
        if (client.registered)
            Peers(client, ":" + client.prefix + " QUIT :" + reason);
        foreach (Channels.Channel channel in new List<Channels.Channel>(client.channels))
            RemoveMember(client, channel);
        Add(statistics, "discarded", client.queue.Count);
        client.queue.Clear();
        clients.Remove(client.identifier);
        clientOrder.Remove(client);
        client.active = false;
        gone.Add(new Gone(time, client.identifier, client.addressee, reason));
        Add(disconnections, kind, 1);
    }
    public static void CompleteRegistration(Clients.Client client) {
        if (client.registered || client.nickname == null || client.username == null)
            return;
        client.registered = true;
        client.registrationTime = client.lastSpeaking = time;
        int registered = 0;
        foreach (Clients.Client other in clientOrder)
            if (other.registered)
                registered++;
        if (registered > peakRegistered) {
            peakRegistered = registered;
            peakRegisteredTime = time;
        }
        string server = settings["NAME"], version = settings["VERSION"];
        Reply(client, 1, ":Welcome to the Internet Relay Network " + client.prefix);
        Reply(client, 2, ":Your host is " + server + ", running version " + version);
        Reply(client, 3, ":This server was created " + settings["CREATED"]);
        Reply(client, 4, server + " " + version + " i biklmnotv");
        Reply(client, 5,
              "CASEMAPPING=rfc1459 CHANTYPES=# NICKLEN=" + Setting("NICKLEN") +
                  " CHANNELLEN=" + Setting("CHANNELLEN") + " TOPICLEN=" + Setting("TOPICLEN") +
                  " CHANLIMIT=#:" + Setting("MAXCHANNELS") +
                  " CHANMODES=b,k,l,imnt PREFIX=(ov)@+ :are supported by this server");
        Reply(client, 375, ":- " + server + " Message of the day -");
        foreach (string line in motd)
            Reply(client, 372, ":- " + line);
        Reply(client, 376, ":End of /MOTD command.");
        if (client.invisible)
            Send(client, ":" + client.nickname + " MODE " + client.nickname + " :+i");
    }
    public static bool Require(Clients.Client client, List<string> parameters, int count,
                               string command) {
        if (parameters.Count >= count)
            return true;
        Error(client, 461, command);
        return false;
    }
    public static void Nick(Clients.Client client, List<string> p) {
        if (p.Count == 0 || p[0].Length == 0) {
            Error(client, 431);
            return;
        }
        string nickname = p[0].Substring(0, Math.Min(Setting("NICKLEN"), p[0].Length) - (0));
        if (!Protocol.ValidNickname(nickname)) {
            Error(client, 432, nickname);
            return;
        }
        if (nickname.Equals(client.nickname))
            return;
        string folded = Protocol.Fold(nickname);
        foreach (Clients.Client other in clientOrder)
            if (other != client && other.nickname != null &&
                Protocol.Fold(other.nickname).Equals(folded)) {
                Error(client, 433, nickname);
                return;
            }
        if (client.registered) {
            string line = ":" + client.prefix + " NICK :" + nickname;
            Send(client, line);
            Peers(client, line);
        }
        client.nickname = nickname;
        CompleteRegistration(client);
    }
    public static void User(Clients.Client client, List<string> p) {
        if (client.username != null) {
            Error(client, 462);
            return;
        }
        if (!Require(client, p, 4, "USER"))
            return;
        client.username = p[0];
        client.realname = p[3];
        string mode = p[1];
        client.invisible =
            Protocol.Digits(mode) && mode.Length <= 3 && (int.Parse(mode) / 8) % 2 == 1;
        CompleteRegistration(client);
    }
    public static void Ping(Clients.Client client, List<string> p) {
        if (p.Count == 0 || p[0].Length == 0) {
            Error(client, 409);
            return;
        }
        string server = settings["NAME"];
        Send(client, ":" + server + " PONG " + server + " :" + p[0]);
    }
    public static void NamesReply(Clients.Client client, Channels.Channel channel) {
        string names = channel.NameList(client);
        if (names.Length != 0)
            Reply(client, 353, "= " + channel.name + " :" + names);
        Reply(client, 366, channel.name + " :End of /NAMES list.");
    }
    public static void TopicReplies(Clients.Client client, Channels.Channel channel) {
        Reply(client, 332, channel.name + " :" + channel.topic);
        Reply(client, 333, channel.name + " " + channel.topicSetter + " " + channel.topicTime);
    }
    public static void Join(Clients.Client client, List<string> p) {
        if (!Require(client, p, 1, "JOIN"))
            return;
        if (p[0].Equals("0")) {
            foreach (Channels.Channel channel in new List<Channels.Channel>(client.channels)) {
                Broadcast(channel, ":" + client.prefix + " PART " + channel.name, null);
                RemoveMember(client, channel);
            }
            return;
        }
        string[] names = p[0].Split(","), keys = p.Count >= 2 ? p[1].Split(",") : new string[0];
        for (int i = 0; i < names.Length; i++) {
            string name = names[i], key = i < keys.Length ? keys[i] : "";
            if (!Protocol.ValidChannel(name, Setting("CHANNELLEN"))) {
                Error(client, 403, name);
                continue;
            }
            Channels.Channel channel = FindChannel(name);
            if (channel != null && channel.FindMember(client) != null)
                continue;
            if (client.channels.Count >= Setting("MAXCHANNELS")) {
                Error(client, 405, name);
                continue;
            }
            if (channel == null) {
                channel = new Channels.Channel(name, time);
                channels[Protocol.Fold(name)] = channel;
                channelOrder.Add(channel);
            } else {
                bool invited = client.invites.Contains(channel);
                int failure = channel.Banned(client) && !invited                            ? 474
                              : channel.flags.Contains('i') && !invited                     ? 473
                              : channel.key.Length != 0 && !key.Equals(channel.key)         ? 475
                              : channel.limit > 0 && channel.members.Count >= channel.limit ? 471
                                                                                            : 0;
                if (failure != 0) {
                    Error(client, failure, channel.name);
                    continue;
                }
            }
            client.invites.Remove(channel);
            channel.Add(client, channel.members.Count == 0);
            Broadcast(channel, ":" + client.prefix + " JOIN " + channel.name, null);
            if (channel.topic.Length != 0)
                TopicReplies(client, channel);
            NamesReply(client, channel);
        }
    }
    public static void Part(Clients.Client client, List<string> p) {
        if (!Require(client, p, 1, "PART"))
            return;
        string suffix = p.Count >= 2 && p[1].Length != 0 ? " :" + p[1] : "";
        foreach (string name in p[0].Split(",")) {
            Channels.Channel channel = FindChannel(name);
            if (channel == null)
                Error(client, 403, name);
            else if (channel.FindMember(client) == null)
                Error(client, 442, channel.name);
            else {
                Broadcast(channel, ":" + client.prefix + " PART " + channel.name + suffix, null);
                RemoveMember(client, channel);
            }
        }
    }
    public static void Message(Clients.Client client, List<string> p, string command) {
        bool replies = command.Equals("PRIVMSG");
        if (replies)
            client.lastSpeaking = time;
        if (p.Count == 0 || p[0].Length == 0) {
            if (replies)
                Error(client, 411, command);
            return;
        }
        if (p.Count < 2 || p[1].Length == 0) {
            if (replies)
                Error(client, 412);
            return;
        }
        string text = p[1];
        foreach (string target in p[0].Split(","))
            if (target.StartsWith("#")) {
                Channels.Channel channel = FindChannel(target);
                if (channel == null) {
                    if (replies)
                        Error(client, 401, target);
                } else if (!channel.CanSpeak(client)) {
                    if (replies)
                        Error(client, 404, channel.name);
                } else {
                    channel.messages++;
                    Broadcast(channel,
                              ":" + client.prefix + " " + command + " " + channel.name + " :" +
                                  text,
                              client);
                }
            } else {
                Clients.Client user = FindUser(target);
                if (user == null) {
                    if (replies)
                        Error(client, 401, target);
                    continue;
                }
                Send(user, ":" + client.prefix + " " + command + " " + user.nickname + " :" + text);
                if (replies && user.away.Length != 0)
                    Reply(client, 301, user.nickname + " :" + user.away);
            }
    }
    public static void Topic(Clients.Client client, List<string> p) {
        if (!Require(client, p, 1, "TOPIC"))
            return;
        Channels.Channel channel = FindChannel(p[0]);
        if (channel == null) {
            Error(client, 403, p[0]);
            return;
        }
        Channels.Member member = channel.FindMember(client);
        if (member == null) {
            Error(client, 442, channel.name);
            return;
        }
        if (p.Count == 1) {
            if (channel.topic.Length == 0)
                Reply(client, 331, channel.name + " :No topic is set");
            else
                TopicReplies(client, channel);
            return;
        }
        if (channel.flags.Contains('t') && !member.op) {
            Error(client, 482, channel.name);
            return;
        }
        channel.topic = p[1].Substring(0, Math.Min(Setting("TOPICLEN"), p[1].Length) - (0));
        channel.topicSetter = client.nickname;
        channel.topicTime = time;
        Broadcast(channel, ":" + client.prefix + " TOPIC " + channel.name + " :" + channel.topic,
                  null);
    }
    public static void Names(Clients.Client client, List<string> p) {
        if (p.Count == 0) {
            Reply(client, 366, "* :End of /NAMES list.");
            return;
        }
        foreach (string name in p[0].Split(",")) {
            Channels.Channel channel = FindChannel(name);
            if (channel == null)
                Reply(client, 366, name + " :End of /NAMES list.");
            else
                NamesReply(client, channel);
        }
    }
    public static void Whois(Clients.Client client, List<string> p) {
        if (p.Count == 0) {
            Error(client, 431);
            return;
        }
        Clients.Client user = FindUser(p[0]);
        if (user == null) {
            Error(client, 401, p[0]);
            Reply(client, 318, p[0] + " :End of /WHOIS list.");
            return;
        }
        Reply(client, 311,
              user.nickname + " " + user.username + " " + user.hostname + " * :" + user.realname);
        if (user.channels.Count != 0)
            Reply(client, 319, user.nickname + " :" + Joined(user, " "));
        Reply(client, 312, user.nickname + " " + settings["NAME"] + " :" + settings["DESCRIPTION"]);
        if (user.away.Length != 0)
            Reply(client, 301, user.nickname + " :" + user.away);
        Reply(client, 317,
              user.nickname + " " + (time - user.lastSpeaking) + " " + user.registrationTime +
                  " :seconds idle, signon time");
        Reply(client, 318, user.nickname + " :End of /WHOIS list.");
    }
    public static void Away(Clients.Client client, List<string> p) {
        client.away = p.Count == 0 ? "" : p[0];
        Reply(client, client.away.Length == 0 ? 305 : 306,
              client.away.Length == 0 ? ":You are no longer marked as being away"
                                      : ":You have been marked as being away");
    }
    public static void Invite(Clients.Client client, List<string> p) {
        if (!Require(client, p, 2, "INVITE"))
            return;
        Clients.Client user = FindUser(p[0]);
        if (user == null) {
            Error(client, 401, p[0]);
            return;
        }
        Channels.Channel channel = FindChannel(p[1]);
        if (channel == null) {
            Error(client, 403, p[1]);
            return;
        }
        Channels.Member member = channel.FindMember(client);
        if (member == null) {
            Error(client, 442, channel.name);
            return;
        }
        if (channel.FindMember(user) != null) {
            Error(client, 443, user.nickname, channel.name);
            return;
        }
        if (channel.flags.Contains('i') && !member.op) {
            Error(client, 482, channel.name);
            return;
        }
        if (!user.invites.Contains(channel))
            user.invites.Add(channel);
        Reply(client, 341, user.nickname + " " + channel.name);
        if (user.away.Length != 0)
            Reply(client, 301, user.nickname + " :" + user.away);
        Send(user, ":" + client.prefix + " INVITE " + user.nickname + " :" + channel.name);
    }
    public static void Kick(Clients.Client client, List<string> p) {
        if (!Require(client, p, 2, "KICK"))
            return;
        Channels.Channel channel = FindChannel(p[0]);
        if (channel == null) {
            Error(client, 403, p[0]);
            return;
        }
        Channels.Member member = channel.FindMember(client);
        if (member == null) {
            Error(client, 442, channel.name);
            return;
        }
        if (!member.op) {
            Error(client, 482, channel.name);
            return;
        }
        Clients.Client user = FindUser(p[1]);
        if (user == null) {
            Error(client, 401, p[1]);
            return;
        }
        if (channel.FindMember(user) == null) {
            Error(client, 441, user.nickname, channel.name);
            return;
        }
        string reason = p.Count >= 3 && p[2].Length != 0 ? p[2] : client.nickname;
        Broadcast(channel,
                  ":" + client.prefix + " KICK " + channel.name + " " + user.nickname + " :" +
                      reason,
                  null);
        RemoveMember(user, channel);
    }
    public static void UserMode(Clients.Client client, List<string> p) {
        Clients.Client user = FindUser(p[0]);
        if (user == null) {
            Error(client, 401, p[0]);
            return;
        }
        if (user != client) {
            Error(client, 502);
            return;
        }
        if (p.Count == 1) {
            Reply(client, 221, client.mode);
            return;
        }
        char sign = '+';
        bool unknown = false;
        List<Modes.Item> changes = new();
        foreach (char c in p[1].ToCharArray())
            if (c == '+' || c == '-')
                sign = c;
            else if (c == 'i') {
                bool desired = sign == '+';
                if (client.invisible != desired) {
                    client.invisible = desired;
                    changes.Add(new Modes.Item(sign, c, null));
                }
            } else
                unknown = true;
        if (changes.Count != 0)
            Send(client, ":" + client.nickname + " MODE " + client.nickname + " :" +
                             Modes.ChangeString(changes));
        if (unknown)
            Error(client, 501);
    }
    public static Modes.Item ApplyMode(Clients.Client client, Channels.Channel channel,
                                       Modes.Item item) {
        char sign = item.sign, c = item.character;
        string argument = item.argument, changeArgument = null;
        bool adding = sign == '+', changed = false;
        if (c == 'o' || c == 'v') {
            Clients.Client user = FindUser(argument);
            if (user == null) {
                Error(client, 401, argument);
                return null;
            }
            Channels.Member member = channel.FindMember(user);
            if (member == null) {
                Error(client, 441, user.nickname, channel.name);
                return null;
            }
            bool old = c == 'o' ? member.op : member.voice;
            if (old != adding) {
                if (c == 'o')
                    member.op = adding;
                else
                    member.voice = adding;
                changed = true;
                changeArgument = user.nickname;
            }
        } else if (c == 'b') {
            string mask = Masks.Normalize(argument), folded = Protocol.Fold(mask);
            int found = -1;
            for (int i = 0; i < channel.bans.Count; i++)
                if (Protocol.Fold(channel.bans[i].mask).Equals(folded)) {
                    found = i;
                    break;
                }
            if (adding && found < 0) {
                channel.bans.Add(new Channels.Ban(mask, client.nickname, time));
                changed = true;
                changeArgument = mask;
            } else if (!adding && found >= 0) {
                changeArgument = channel.bans.PopAt(found).mask;
                changed = true;
            }
        } else if (c == 'k') {
            if (adding) {
                if (channel.key.Length != 0)
                    Error(client, 467, channel.name);
                else {
                    channel.key = argument;
                    changed = true;
                    changeArgument = argument;
                }
            } else if (channel.key.Length != 0) {
                channel.key = "";
                changed = true;
                changeArgument = "*";
            }
        } else if (c == 'l') {
            if (adding) {
                int limit = int.Parse(argument);
                if (channel.limit != limit) {
                    channel.limit = limit;
                    changed = true;
                    changeArgument = Convert.ToString(limit);
                }
            } else if (channel.limit != 0) {
                channel.limit = 0;
                changed = true;
            }
        } else if (adding)
            changed = channel.flags.Add(c);
        else
            changed = channel.flags.Remove(c);
        return changed ? new Modes.Item(sign, c, changeArgument) : null;
    }
    public static void ChannelMode(Clients.Client client, List<string> p) {
        Channels.Channel channel = FindChannel(p[0]);
        if (channel == null) {
            Error(client, 403, p[0]);
            return;
        }
        if (p.Count == 1) {
            Reply(client, 324,
                  channel.name + " " + channel.ModeDisplay(channel.FindMember(client) != null));
            Reply(client, 329, channel.name + " " + channel.created);
            return;
        }
        List<Modes.Item> items = Modes.ChannelItems(p[1], p.GetRange(2, p.Count - 2)),
                         changes = new();
        Channels.Member member = channel.FindMember(client);
        bool authorized = member != null && member.op, bansSent = false, denialSent = false;
        foreach (Modes.Item item in items) {
            char sign = item.sign, c = item.character;
            string argument = item.argument;
            if ("biklmnotv".IndexOf(c) < 0) {
                Error(client, 472, c.ToString(), channel.name);
                continue;
            }
            if (c == 'b' && argument == null) {
                if (sign == '+' && !bansSent) {
                    foreach (Channels.Ban ban in channel.bans)
                        Reply(client, 367,
                              channel.name + " " + ban.mask + " " + ban.setter + " " + ban.time);
                    Reply(client, 368, channel.name + " :End of channel ban list");
                    bansSent = true;
                }
                continue;
            }
            if (argument == null && (c == 'o' || c == 'v' || sign == '+' && (c == 'k' || c == 'l')))
                continue;
            if (!authorized) {
                if (!denialSent) {
                    Error(client, 482, channel.name);
                    denialSent = true;
                }
                continue;
            }
            Modes.Item change = ApplyMode(client, channel, item);
            if (change != null)
                changes.Add(change);
        }
        if (changes.Count != 0)
            Broadcast(channel,
                      ":" + client.prefix + " MODE " + channel.name + " " +
                          Modes.ChangeString(changes),
                      null);
    }
    public static void Process(Clients.Client client, string raw) {
        Add(statistics, "processed", 1);
        Protocol.Message message = Protocol.Parse(raw);
        string command = message.command;
        List<string> p = message.parameters;
        if (command.Length == 0) {
            Add(statistics, "empty", 1);
            return;
        }
        Add(commands, command, 1);
        if (!client.registered &&
            !new HashSet<string> { "NICK", "USER", "PING", "PONG", "QUIT" }.Contains(command)) {
            Error(client, 451);
            return;
        }
        switch (command) {
        case "NICK":
            Nick(client, p);
            break;
        case "USER":
            User(client, p);
            break;
        case "PING":
            Ping(client, p);
            break;
        case "PONG":
            break;
        case "QUIT":
            Disconnect(client, p.Count != 0 && p[0].Length != 0 ? "Quit: " + p[0] : "Client Quit",
                       "quit");
            break;
        case "JOIN":
            Join(client, p);
            break;
        case "PART":
            Part(client, p);
            break;
        case "PRIVMSG":
        case "NOTICE":
            Message(client, p, command);
            break;
        case "TOPIC":
            Topic(client, p);
            break;
        case "NAMES":
            Names(client, p);
            break;
        case "WHOIS":
            Whois(client, p);
            break;
        case "AWAY":
            Away(client, p);
            break;
        case "INVITE":
            Invite(client, p);
            break;
        case "KICK":
            Kick(client, p);
            break;
        case "MODE":
            if (Require(client, p, 1, "MODE")) {
                if (p[0].StartsWith("#"))
                    ChannelMode(client, p);
                else
                    UserMode(client, p);
            }
            break;
        default:
            Error(client, 421, command);
            break;
        }
    }
    public static void Arrival(Traffic record) {
        string kind = record.kind;
        if (kind.Equals("connect")) {
            Clients.Client connectedClient = new Clients.Client(
                record.identifier, record.body.Substring(8), time, Setting("BUCKET"));
            clients[connectedClient.identifier] = connectedClient;
            clientOrder.Add(connectedClient);
            if (clients.Count > peakConnections) {
                peakConnections = clients.Count;
                peakConnectionsTime = time;
            }
            return;
        }
        Clients.Client client = clients.GetValueOrDefault(record.identifier);
        if (kind.Equals("disconnect")) {
            if (client != null)
                Disconnect(client, "Remote host closed the connection", "closed");
            return;
        }
        if (client == null) {
            Add(statistics, "dropped", 1);
            return;
        }
        client.received++;
        client.lastReceived = time;
        client.pingSent = -1;
        if (client.queue.Count == 0 && client.tokens >= 1) {
            client.UseToken(time, Setting("BUCKET"), Setting("REFILL"));
            Process(client, record.body);
        } else if (client.queue.Count >= Setting("QUEUE")) {
            Add(statistics, "discarded", 1);
            Disconnect(client, "Excess Flood", "flood");
        } else {
            client.queue.Enqueue(record.body);
            Add(statistics, "queued", 1);
        }
    }
    public static void Run() {
        int position = 0;
        for (time = 0; time <= end; time++) {
            foreach (Clients.Client client in new List<Clients.Client>(clientOrder)) {
                client.Refill(time, Setting("BUCKET"), Setting("REFILL"));
                while (client.active && client.queue.Count != 0 && client.tokens >= 1) {
                    client.UseToken(time, Setting("BUCKET"), Setting("REFILL"));
                    Process(client, client.queue.Dequeue());
                }
            }
            while (position < traffic.Count && traffic[position].time == time)
                Arrival(traffic[position++]);
            foreach (Clients.Client client in new List<Clients.Client>(clientOrder))
                if (client.pingSent >= 0) {
                    if (time - client.pingSent >= Setting("TIMEOUT"))
                        Disconnect(client,
                                   "Ping timeout: " + (time - client.lastReceived) + " seconds",
                                   "timeout");
                } else if (time - client.lastReceived >= Setting("PINGFREQ")) {
                    Send(client, "PING :" + settings["NAME"]);
                    Add(statistics, "pings", 1);
                    client.pingSent = time;
                }
        }
    }
    public static List<string> ChannelReport() {
        List<string> lines = new();
        int members = 0, bans = 0;
        foreach (Channels.Channel channel in channelOrder) {
            members += channel.members.Count;
            bans += channel.bans.Count;
            lines.Add("CHANNEL " + channel.name + " created " + channel.created + " members " +
                      channel.members.Count + " peak " + channel.peak + " messages " +
                      channel.messages + " modes " + channel.ModeDisplay(true));
            lines.Add(channel.topic.Length == 0 ? "TOPIC none"
                                                : "TOPIC " + channel.topicSetter + " " +
                                                      channel.topicTime + " " + channel.topic);
            foreach (Channels.Ban ban in channel.bans)
                lines.Add("BAN " + ban.mask + " " + ban.setter + " " + ban.time);
            List<string> names = new();
            foreach (Channels.Member member in channel.members)
                names.Add(member.display);
            lines.Add("MEMBERS " + string.Join(" ", names));
        }
        lines.Add("TOTAL channels " + channels.Count + " members " + members + " bans " + bans);
        return lines;
    }
    public static List<string> ClientReport() {
        List<string> lines = new();
        int registered = 0, invisible = 0, away = 0;
        foreach (Clients.Client client in clientOrder) {
            if (client.registered)
                registered++;
            if (client.invisible)
                invisible++;
            if (client.away.Length != 0)
                away++;
            string joined = Joined(client, ",");
            List<string> invites = new();
            foreach (Channels.Channel channel in client.invites)
                invites.Add(channel.name);
            lines.Add("CLIENT " + client.identifier + " " + client.addressee + " " +
                      (client.username == null ? "*" : client.username) + " " + client.hostname +
                      " " + client.mode + " connected " + client.connectionTime + " signon " +
                      (client.registered ? Convert.ToString(client.registrationTime) : "-") +
                      " received " + client.received + " sent " + client.sent + " tokens " +
                      client.tokens + " queue " + client.queue.Count + " channels " +
                      (joined.Length == 0 ? "none" : joined) + " invites " +
                      (invites.Count == 0 ? "none" : string.Join(",", invites)));
            if (client.away.Length != 0)
                lines.Add("AWAY " + client.identifier + " " + client.away);
        }
        lines.Add("TOTAL clients " + clients.Count + " registered " + registered + " invisible " +
                  invisible + " away " + away);
        return lines;
    }
    public static List<string> StatisticsReport() {
        List<string> lines = new();
        int pending = 0, numericTotal = 0;
        foreach (Clients.Client client in clientOrder)
            pending += client.queue.Count;
        foreach (int count in numerics.Values)
            numericTotal += count;
        lines.Add("END " + end);
        lines.Add("LINES total " + traffic.Count + " connect " +
                  lineCounts.GetValueOrDefault("connect", 0) + " disconnect " +
                  lineCounts.GetValueOrDefault("disconnect", 0) + " messages " +
                  lineCounts.GetValueOrDefault("messages", 0));
        lines.Add("MESSAGES dropped " + Stat("dropped") + " queued " + Stat("queued") +
                  " processed " + Stat("processed") + " discarded " + Stat("discarded") +
                  " pending " + pending + " empty " + Stat("empty"));
        lines.Add("SENT lines " + sent.Count + " numerics " + numericTotal + " pings " +
                  Stat("pings") + " errors " + Stat("errors"));
        foreach (var entry in commands)
            lines.Add("COMMAND " + entry.Key + " " + entry.Value);
        foreach (var entry in numerics)
            lines.Add("NUMERIC " + Number(entry.Key) + " " + entry.Value);
        lines.Add("PEAK connections " + peakConnections + " at " + peakConnectionsTime);
        lines.Add("PEAK registered " + peakRegistered + " at " + peakRegisteredTime);
        List<string> kinds = new();
        foreach (string kind in new List<string> { "quit", "closed", "flood", "timeout" })
            kinds.Add(kind + " " + disconnections.GetValueOrDefault(kind, 0));
        lines.Add("DISCONNECTS " + string.Join(" ", kinds));
        foreach (Gone record in gone)
            lines.Add("GONE " + record.time + " " + record.identifier + " " + record.addressee +
                      " " + record.reason);
        return lines;
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name),
                          string.Join("\n", lines) + (lines.Count == 0 ? "" : "\n"));
    }
    public static void Main(string[] args) {
        foreach (string line in File.ReadAllLines(Path.Combine("input", "server.txt")).ToList()) {
            int separator = line.IndexOf(' ');
            string key = line.Substring(0, separator - (0)), value = line.Substring(separator + 1);
            if (key.Equals("MOTD"))
                motd.Add(value);
            else
                settings[key] = value;
        }
        foreach (string line in File.ReadAllLines(Path.Combine("input", "traffic.txt")).ToList()) {
            string[] fields = line.Split(" ", 3);
            string body = fields[2], kind = "messages";
            if (body.StartsWith("CONNECT ") && body.Substring(8).Matches("[A-Za-z0-9.-]{1,63}"))
                kind = "connect";
            else if (body.Equals("DISCONNECT"))
                kind = "disconnect";
            traffic.Add(new Traffic(int.Parse(fields[0]), fields[1], kind, body));
            Add(lineCounts, kind, 1);
        }
        end = traffic[^1].time;
        Run();
        Directory.CreateDirectory(Path.Combine("output"));
        Write("sent.txt", sent);
        Write("channels.txt", ChannelReport());
        Write("clients.txt", ClientReport());
        Write("stats.txt", StatisticsReport());
    }
}
public static class CollectionHelpers {
    public static void AddCount<K>(this IDictionary<K, int> map, K key, int amount) {
        map.TryGetValue(key, out int old);
        map[key] = old + amount;
    }
    public static bool Matches(this string text,
                               string pattern) => Regex.IsMatch(text, "\\A(?:" + pattern + ")\\z");
    public static T PopAt<T>(this List<T> values, int index) {
        T value = values[index];
        values.RemoveAt(index);
        return value;
    }
}
