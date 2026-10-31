import java.nio.file.*;
import java.util.*;
public class Main {
    static Map<String, String> settings = new HashMap<>();
    static List<String> motd = new ArrayList<>();
    static List<Traffic> traffic = new ArrayList<>();
    static LinkedHashMap<String, Clients.Client> clients = new LinkedHashMap<>();
    static LinkedHashMap<String, Channels.Channel> channels = new LinkedHashMap<>();
    static List<String> sent = new ArrayList<>();
    static TreeMap<String, Integer> commands = new TreeMap<>();
    static TreeMap<Integer, Integer> numerics = new TreeMap<>();
    static Map<String, Integer> lineCounts = new HashMap<>(), statistics = new HashMap<>(),
                                disconnections = new HashMap<>();
    static List<Gone> gone = new ArrayList<>();
    static int time, end, peakConnections, peakConnectionsTime, peakRegistered, peakRegisteredTime;
    record Traffic(int time, String identifier, String kind, String body) {}
    record Gone(int time, String identifier, String addressee, String reason) {}
    static int setting(String key) { return Integer.parseInt(settings.get(key)); }
    static <K> void add(Map<K, Integer> counts, K key, int amount) {
        counts.merge(key, amount, Integer::sum);
    }
    static int stat(String key) { return statistics.getOrDefault(key, 0); }
    static String number(int value) { return String.format(Locale.ROOT, "%03d", value); }
    static void send(Clients.Client client, String line) {
        sent.add(time + " " + client.identifier + " " + line);
        client.sent++;
    }
    static void reply(Clients.Client client, int number, String content) {
        add(numerics, number, 1);
        send(client, ":" + settings.get("NAME") + " " + number(number) + " " + client.addressee() +
                         " " + content);
    }
    static void error(Clients.Client client, int number, String... a) {
        String x = a.length > 0 ? a[0] : "";
        String content = switch (number) {
            case 401 -> x + " :No such nick/channel";
            case 403 -> x + " :No such channel";
            case 404 -> x + " :Cannot send to channel";
            case 405 -> x + " :You have joined too many channels";
            case 409 -> ":No origin specified";
            case 411 -> ":No recipient given (" + x + ")";
            case 412 -> ":No text to send";
            case 421 -> x + " :Unknown command";
            case 431 -> ":No nickname given";
            case 432 -> x + " :Erroneous nickname";
            case 433 -> x + " :Nickname is already in use";
            case 441 -> x + " " + a[1] + " :They aren't on that channel";
            case 442 -> x + " :You're not on that channel";
            case 443 -> x + " " + a[1] + " :is already on channel";
            case 451 -> ":You have not registered";
            case 461 -> x + " :Not enough parameters";
            case 462 -> ":You may not reregister";
            case 467 -> x + " :Channel key already set";
            case 471 -> x + " :Cannot join channel (+l)";
            case 472 -> x + " :is unknown mode char to me for " + a[1];
            case 473 -> x + " :Cannot join channel (+i)";
            case 474 -> x + " :Cannot join channel (+b)";
            case 475 -> x + " :Cannot join channel (+k)";
            case 482 -> x + " :You're not channel operator";
            case 501 -> ":Unknown MODE flag";
            case 502 -> ":Cannot change mode for other users";
            default -> throw new IllegalArgumentException();
        };
        reply(client, number, content);
    }
    static void broadcast(Channels.Channel channel, String line, Clients.Client exclude) {
        for (Channels.Member member : channel.members)
            if (member.client != exclude)
                send(member.client, line);
    }
    static void peers(Clients.Client client, String line) {
        Set<Clients.Client> peers = new HashSet<>();
        for (Channels.Channel channel : client.channels)
            for (Channels.Member member : channel.members)
                peers.add(member.client);
        for (Clients.Client other : clients.values())
            if (other != client && peers.contains(other))
                send(other, line);
    }
    static Clients.Client findUser(String nickname) {
        String name = Protocol.fold(nickname);
        for (Clients.Client client : clients.values())
            if (client.registered && Protocol.fold(client.nickname).equals(name))
                return client;
        return null;
    }
    static Channels.Channel findChannel(String name) { return channels.get(Protocol.fold(name)); }
    static String joined(Clients.Client client, String separator) {
        List<String> names = new ArrayList<>();
        for (Channels.Channel channel : client.channels)
            names.add(channel.member(client).status() + channel.name);
        return String.join(separator, names);
    }
    static void removeMember(Clients.Client client, Channels.Channel channel) {
        channel.remove(client);
        if (channel.members.isEmpty()) {
            channels.remove(Protocol.fold(channel.name));
            for (Clients.Client other : clients.values())
                other.invites.remove(channel);
        }
    }
    static void disconnect(Clients.Client client, String reason, String kind) {
        if (!kind.equals("closed")) {
            send(client, "ERROR :Closing Link: " + client.addressee() + "[" + client.hostname +
                             "] (" + reason + ")");
            add(statistics, "errors", 1);
        }
        if (client.registered)
            peers(client, ":" + client.prefix() + " QUIT :" + reason);
        for (Channels.Channel channel : new ArrayList<>(client.channels))
            removeMember(client, channel);
        add(statistics, "discarded", client.queue.size());
        client.queue.clear();
        clients.remove(client.identifier);
        client.active = false;
        gone.add(new Gone(time, client.identifier, client.addressee(), reason));
        add(disconnections, kind, 1);
    }
    static void completeRegistration(Clients.Client client) {
        if (client.registered || client.nickname == null || client.username == null)
            return;
        client.registered = true;
        client.registrationTime = client.lastSpeaking = time;
        int registered = 0;
        for (Clients.Client other : clients.values())
            if (other.registered)
                registered++;
        if (registered > peakRegistered) {
            peakRegistered = registered;
            peakRegisteredTime = time;
        }
        String server = settings.get("NAME"), version = settings.get("VERSION");
        reply(client, 1, ":Welcome to the Internet Relay Network " + client.prefix());
        reply(client, 2, ":Your host is " + server + ", running version " + version);
        reply(client, 3, ":This server was created " + settings.get("CREATED"));
        reply(client, 4, server + " " + version + " i biklmnotv");
        reply(client, 5,
              "CASEMAPPING=rfc1459 CHANTYPES=# NICKLEN=" + setting("NICKLEN") +
                  " CHANNELLEN=" + setting("CHANNELLEN") + " TOPICLEN=" + setting("TOPICLEN") +
                  " CHANLIMIT=#:" + setting("MAXCHANNELS") +
                  " CHANMODES=b,k,l,imnt PREFIX=(ov)@+ :are supported by this server");
        reply(client, 375, ":- " + server + " Message of the day -");
        for (String line : motd)
            reply(client, 372, ":- " + line);
        reply(client, 376, ":End of /MOTD command.");
        if (client.invisible)
            send(client, ":" + client.nickname + " MODE " + client.nickname + " :+i");
    }
    static boolean require(Clients.Client client, List<String> parameters, int count,
                           String command) {
        if (parameters.size() >= count)
            return true;
        error(client, 461, command);
        return false;
    }
    static void nick(Clients.Client client, List<String> p) {
        if (p.isEmpty() || p.getFirst().isEmpty()) {
            error(client, 431);
            return;
        }
        String nickname =
            p.getFirst().substring(0, Math.min(setting("NICKLEN"), p.getFirst().length()));
        if (!Protocol.validNickname(nickname)) {
            error(client, 432, nickname);
            return;
        }
        if (nickname.equals(client.nickname))
            return;
        String folded = Protocol.fold(nickname);
        for (Clients.Client other : clients.values())
            if (other != client && other.nickname != null &&
                Protocol.fold(other.nickname).equals(folded)) {
                error(client, 433, nickname);
                return;
            }
        if (client.registered) {
            String line = ":" + client.prefix() + " NICK :" + nickname;
            send(client, line);
            peers(client, line);
        }
        client.nickname = nickname;
        completeRegistration(client);
    }
    static void user(Clients.Client client, List<String> p) {
        if (client.username != null) {
            error(client, 462);
            return;
        }
        if (!require(client, p, 4, "USER"))
            return;
        client.username = p.get(0);
        client.realname = p.get(3);
        String mode = p.get(1);
        client.invisible =
            Protocol.digits(mode) && mode.length() <= 3 && (Integer.parseInt(mode) / 8) % 2 == 1;
        completeRegistration(client);
    }
    static void ping(Clients.Client client, List<String> p) {
        if (p.isEmpty() || p.getFirst().isEmpty()) {
            error(client, 409);
            return;
        }
        String server = settings.get("NAME");
        send(client, ":" + server + " PONG " + server + " :" + p.getFirst());
    }
    static void namesReply(Clients.Client client, Channels.Channel channel) {
        String names = channel.nameList(client);
        if (!names.isEmpty())
            reply(client, 353, "= " + channel.name + " :" + names);
        reply(client, 366, channel.name + " :End of /NAMES list.");
    }
    static void topicReplies(Clients.Client client, Channels.Channel channel) {
        reply(client, 332, channel.name + " :" + channel.topic);
        reply(client, 333, channel.name + " " + channel.topicSetter + " " + channel.topicTime);
    }
    static void join(Clients.Client client, List<String> p) {
        if (!require(client, p, 1, "JOIN"))
            return;
        if (p.getFirst().equals("0")) {
            for (Channels.Channel channel : new ArrayList<>(client.channels)) {
                broadcast(channel, ":" + client.prefix() + " PART " + channel.name, null);
                removeMember(client, channel);
            }
            return;
        }
        String[] names = p.getFirst().split(","), keys = p.size() >= 2 ? p.get(1).split(",")
                                                                       : new String[0];
        for (int i = 0; i < names.length; i++) {
            String name = names[i], key = i < keys.length ? keys[i] : "";
            if (!Protocol.validChannel(name, setting("CHANNELLEN"))) {
                error(client, 403, name);
                continue;
            }
            Channels.Channel channel = findChannel(name);
            if (channel != null && channel.member(client) != null)
                continue;
            if (client.channels.size() >= setting("MAXCHANNELS")) {
                error(client, 405, name);
                continue;
            }
            if (channel == null) {
                channel = new Channels.Channel(name, time);
                channels.put(Protocol.fold(name), channel);
            } else {
                boolean invited = client.invites.contains(channel);
                int failure = channel.banned(client) && !invited                             ? 474
                              : channel.flags.contains('i') && !invited                      ? 473
                              : !channel.key.isEmpty() && !key.equals(channel.key)           ? 475
                              : channel.limit > 0 && channel.members.size() >= channel.limit ? 471
                                                                                             : 0;
                if (failure != 0) {
                    error(client, failure, channel.name);
                    continue;
                }
            }
            client.invites.remove(channel);
            channel.add(client, channel.members.isEmpty());
            broadcast(channel, ":" + client.prefix() + " JOIN " + channel.name, null);
            if (!channel.topic.isEmpty())
                topicReplies(client, channel);
            namesReply(client, channel);
        }
    }
    static void part(Clients.Client client, List<String> p) {
        if (!require(client, p, 1, "PART"))
            return;
        String suffix = p.size() >= 2 && !p.get(1).isEmpty() ? " :" + p.get(1) : "";
        for (String name : p.getFirst().split(",")) {
            Channels.Channel channel = findChannel(name);
            if (channel == null)
                error(client, 403, name);
            else if (channel.member(client) == null)
                error(client, 442, channel.name);
            else {
                broadcast(channel, ":" + client.prefix() + " PART " + channel.name + suffix, null);
                removeMember(client, channel);
            }
        }
    }
    static void message(Clients.Client client, List<String> p, String command) {
        boolean replies = command.equals("PRIVMSG");
        if (replies)
            client.lastSpeaking = time;
        if (p.isEmpty() || p.getFirst().isEmpty()) {
            if (replies)
                error(client, 411, command);
            return;
        }
        if (p.size() < 2 || p.get(1).isEmpty()) {
            if (replies)
                error(client, 412);
            return;
        }
        String text = p.get(1);
        for (String target : p.getFirst().split(","))
            if (target.startsWith("#")) {
                Channels.Channel channel = findChannel(target);
                if (channel == null) {
                    if (replies)
                        error(client, 401, target);
                } else if (!channel.canSpeak(client)) {
                    if (replies)
                        error(client, 404, channel.name);
                } else {
                    channel.messages++;
                    broadcast(channel,
                              ":" + client.prefix() + " " + command + " " + channel.name + " :" +
                                  text,
                              client);
                }
            } else {
                Clients.Client user = findUser(target);
                if (user == null) {
                    if (replies)
                        error(client, 401, target);
                    continue;
                }
                send(user,
                     ":" + client.prefix() + " " + command + " " + user.nickname + " :" + text);
                if (replies && !user.away.isEmpty())
                    reply(client, 301, user.nickname + " :" + user.away);
            }
    }
    static void topic(Clients.Client client, List<String> p) {
        if (!require(client, p, 1, "TOPIC"))
            return;
        Channels.Channel channel = findChannel(p.getFirst());
        if (channel == null) {
            error(client, 403, p.getFirst());
            return;
        }
        Channels.Member member = channel.member(client);
        if (member == null) {
            error(client, 442, channel.name);
            return;
        }
        if (p.size() == 1) {
            if (channel.topic.isEmpty())
                reply(client, 331, channel.name + " :No topic is set");
            else
                topicReplies(client, channel);
            return;
        }
        if (channel.flags.contains('t') && !member.op) {
            error(client, 482, channel.name);
            return;
        }
        channel.topic = p.get(1).substring(0, Math.min(setting("TOPICLEN"), p.get(1).length()));
        channel.topicSetter = client.nickname;
        channel.topicTime = time;
        broadcast(channel, ":" + client.prefix() + " TOPIC " + channel.name + " :" + channel.topic,
                  null);
    }
    static void names(Clients.Client client, List<String> p) {
        if (p.isEmpty()) {
            reply(client, 366, "* :End of /NAMES list.");
            return;
        }
        for (String name : p.getFirst().split(",")) {
            Channels.Channel channel = findChannel(name);
            if (channel == null)
                reply(client, 366, name + " :End of /NAMES list.");
            else
                namesReply(client, channel);
        }
    }
    static void whois(Clients.Client client, List<String> p) {
        if (p.isEmpty()) {
            error(client, 431);
            return;
        }
        Clients.Client user = findUser(p.getFirst());
        if (user == null) {
            error(client, 401, p.getFirst());
            reply(client, 318, p.getFirst() + " :End of /WHOIS list.");
            return;
        }
        reply(client, 311,
              user.nickname + " " + user.username + " " + user.hostname + " * :" + user.realname);
        if (!user.channels.isEmpty())
            reply(client, 319, user.nickname + " :" + joined(user, " "));
        reply(client, 312,
              user.nickname + " " + settings.get("NAME") + " :" + settings.get("DESCRIPTION"));
        if (!user.away.isEmpty())
            reply(client, 301, user.nickname + " :" + user.away);
        reply(client, 317,
              user.nickname + " " + (time - user.lastSpeaking) + " " + user.registrationTime +
                  " :seconds idle, signon time");
        reply(client, 318, user.nickname + " :End of /WHOIS list.");
    }
    static void away(Clients.Client client, List<String> p) {
        client.away = p.isEmpty() ? "" : p.getFirst();
        reply(client, client.away.isEmpty() ? 305 : 306,
              client.away.isEmpty() ? ":You are no longer marked as being away"
                                    : ":You have been marked as being away");
    }
    static void invite(Clients.Client client, List<String> p) {
        if (!require(client, p, 2, "INVITE"))
            return;
        Clients.Client user = findUser(p.getFirst());
        if (user == null) {
            error(client, 401, p.getFirst());
            return;
        }
        Channels.Channel channel = findChannel(p.get(1));
        if (channel == null) {
            error(client, 403, p.get(1));
            return;
        }
        Channels.Member member = channel.member(client);
        if (member == null) {
            error(client, 442, channel.name);
            return;
        }
        if (channel.member(user) != null) {
            error(client, 443, user.nickname, channel.name);
            return;
        }
        if (channel.flags.contains('i') && !member.op) {
            error(client, 482, channel.name);
            return;
        }
        if (!user.invites.contains(channel))
            user.invites.add(channel);
        reply(client, 341, user.nickname + " " + channel.name);
        if (!user.away.isEmpty())
            reply(client, 301, user.nickname + " :" + user.away);
        send(user, ":" + client.prefix() + " INVITE " + user.nickname + " :" + channel.name);
    }
    static void kick(Clients.Client client, List<String> p) {
        if (!require(client, p, 2, "KICK"))
            return;
        Channels.Channel channel = findChannel(p.getFirst());
        if (channel == null) {
            error(client, 403, p.getFirst());
            return;
        }
        Channels.Member member = channel.member(client);
        if (member == null) {
            error(client, 442, channel.name);
            return;
        }
        if (!member.op) {
            error(client, 482, channel.name);
            return;
        }
        Clients.Client user = findUser(p.get(1));
        if (user == null) {
            error(client, 401, p.get(1));
            return;
        }
        if (channel.member(user) == null) {
            error(client, 441, user.nickname, channel.name);
            return;
        }
        String reason = p.size() >= 3 && !p.get(2).isEmpty() ? p.get(2) : client.nickname;
        broadcast(channel,
                  ":" + client.prefix() + " KICK " + channel.name + " " + user.nickname + " :" +
                      reason,
                  null);
        removeMember(user, channel);
    }

    static void userMode(Clients.Client client, List<String> p) {
        Clients.Client user = findUser(p.getFirst());
        if (user == null) {
            error(client, 401, p.getFirst());
            return;
        }
        if (user != client) {
            error(client, 502);
            return;
        }
        if (p.size() == 1) {
            reply(client, 221, client.mode());
            return;
        }
        char sign = '+';
        boolean unknown = false;
        List<Modes.Item> changes = new ArrayList<>();
        for (char c : p.get(1).toCharArray())
            if (c == '+' || c == '-')
                sign = c;
            else if (c == 'i') {
                boolean desired = sign == '+';
                if (client.invisible != desired) {
                    client.invisible = desired;
                    changes.add(new Modes.Item(sign, c, null));
                }
            } else
                unknown = true;
        if (!changes.isEmpty())
            send(client, ":" + client.nickname + " MODE " + client.nickname + " :" +
                             Modes.changeString(changes));
        if (unknown)
            error(client, 501);
    }
    static Modes.Item applyMode(Clients.Client client, Channels.Channel channel, Modes.Item item) {
        char sign = item.sign(), c = item.character();
        String argument = item.argument(), changeArgument = null;
        boolean adding = sign == '+', changed = false;
        if (c == 'o' || c == 'v') {
            Clients.Client user = findUser(argument);
            if (user == null) {
                error(client, 401, argument);
                return null;
            }
            Channels.Member member = channel.member(user);
            if (member == null) {
                error(client, 441, user.nickname, channel.name);
                return null;
            }
            boolean old = c == 'o' ? member.op : member.voice;
            if (old != adding) {
                if (c == 'o')
                    member.op = adding;
                else
                    member.voice = adding;
                changed = true;
                changeArgument = user.nickname;
            }
        } else if (c == 'b') {
            String mask = Masks.normalize(argument), folded = Protocol.fold(mask);
            int found = -1;
            for (int i = 0; i < channel.bans.size(); i++)
                if (Protocol.fold(channel.bans.get(i).mask()).equals(folded)) {
                    found = i;
                    break;
                }
            if (adding && found < 0) {
                channel.bans.add(new Channels.Ban(mask, client.nickname, time));
                changed = true;
                changeArgument = mask;
            } else if (!adding && found >= 0) {
                changeArgument = channel.bans.remove(found).mask();
                changed = true;
            }
        } else if (c == 'k') {
            if (adding) {
                if (!channel.key.isEmpty())
                    error(client, 467, channel.name);
                else {
                    channel.key = argument;
                    changed = true;
                    changeArgument = argument;
                }
            } else if (!channel.key.isEmpty()) {
                channel.key = "";
                changed = true;
                changeArgument = "*";
            }
        } else if (c == 'l') {
            if (adding) {
                int limit = Integer.parseInt(argument);
                if (channel.limit != limit) {
                    channel.limit = limit;
                    changed = true;
                    changeArgument = Integer.toString(limit);
                }
            } else if (channel.limit != 0) {
                channel.limit = 0;
                changed = true;
            }
        } else if (adding)
            changed = channel.flags.add(c);
        else
            changed = channel.flags.remove(c);
        return changed ? new Modes.Item(sign, c, changeArgument) : null;
    }
    static void channelMode(Clients.Client client, List<String> p) {
        Channels.Channel channel = findChannel(p.getFirst());
        if (channel == null) {
            error(client, 403, p.getFirst());
            return;
        }
        if (p.size() == 1) {
            reply(client, 324,
                  channel.name + " " + channel.modeDisplay(channel.member(client) != null));
            reply(client, 329, channel.name + " " + channel.created);
            return;
        }
        List<Modes.Item> items = Modes.channelItems(p.get(1), p.subList(2, p.size())),
                         changes = new ArrayList<>();
        Channels.Member member = channel.member(client);
        boolean authorized = member != null && member.op, bansSent = false, denialSent = false;
        for (Modes.Item item : items) {
            char sign = item.sign(), c = item.character();
            String argument = item.argument();
            if ("biklmnotv".indexOf(c) < 0) {
                error(client, 472, Character.toString(c), channel.name);
                continue;
            }
            if (c == 'b' && argument == null) {
                if (sign == '+' && !bansSent) {
                    for (Channels.Ban ban : channel.bans)
                        reply(client, 367,
                              channel.name + " " + ban.mask() + " " + ban.setter() + " " +
                                  ban.time());
                    reply(client, 368, channel.name + " :End of channel ban list");
                    bansSent = true;
                }
                continue;
            }
            if (argument == null && (c == 'o' || c == 'v' || sign == '+' && (c == 'k' || c == 'l')))
                continue;
            if (!authorized) {
                if (!denialSent) {
                    error(client, 482, channel.name);
                    denialSent = true;
                }
                continue;
            }
            Modes.Item change = applyMode(client, channel, item);
            if (change != null)
                changes.add(change);
        }
        if (!changes.isEmpty())
            broadcast(channel,
                      ":" + client.prefix() + " MODE " + channel.name + " " +
                          Modes.changeString(changes),
                      null);
    }
    static void process(Clients.Client client, String raw) {
        add(statistics, "processed", 1);
        Protocol.Message message = Protocol.parse(raw);
        String command = message.command();
        List<String> p = message.parameters();
        if (command.isEmpty()) {
            add(statistics, "empty", 1);
            return;
        }
        add(commands, command, 1);
        if (!client.registered &&
            !Set.of("NICK", "USER", "PING", "PONG", "QUIT").contains(command)) {
            error(client, 451);
            return;
        }
        switch (command) {
        case "NICK":
            nick(client, p);
            break;
        case "USER":
            user(client, p);
            break;
        case "PING":
            ping(client, p);
            break;
        case "PONG":
            break;
        case "QUIT":
            disconnect(client,
                       !p.isEmpty() && !p.getFirst().isEmpty() ? "Quit: " + p.getFirst()
                                                               : "Client Quit",
                       "quit");
            break;
        case "JOIN":
            join(client, p);
            break;
        case "PART":
            part(client, p);
            break;
        case "PRIVMSG", "NOTICE":
            message(client, p, command);
            break;
        case "TOPIC":
            topic(client, p);
            break;
        case "NAMES":
            names(client, p);
            break;
        case "WHOIS":
            whois(client, p);
            break;
        case "AWAY":
            away(client, p);
            break;
        case "INVITE":
            invite(client, p);
            break;
        case "KICK":
            kick(client, p);
            break;
        case "MODE":
            if (require(client, p, 1, "MODE")) {
                if (p.getFirst().startsWith("#"))
                    channelMode(client, p);
                else
                    userMode(client, p);
            }
            break;
        default:
            error(client, 421, command);
        }
    }
    static void arrival(Traffic record) {
        String kind = record.kind();
        if (kind.equals("connect")) {
            Clients.Client client = new Clients.Client(
                record.identifier(), record.body().substring(8), time, setting("BUCKET"));
            clients.put(client.identifier, client);
            if (clients.size() > peakConnections) {
                peakConnections = clients.size();
                peakConnectionsTime = time;
            }
            return;
        }
        Clients.Client client = clients.get(record.identifier());
        if (kind.equals("disconnect")) {
            if (client != null)
                disconnect(client, "Remote host closed the connection", "closed");
            return;
        }
        if (client == null) {
            add(statistics, "dropped", 1);
            return;
        }
        client.received++;
        client.lastReceived = time;
        client.pingSent = -1;
        if (client.queue.isEmpty() && client.tokens >= 1) {
            client.useToken(time, setting("BUCKET"), setting("REFILL"));
            process(client, record.body());
        } else if (client.queue.size() >= setting("QUEUE")) {
            add(statistics, "discarded", 1);
            disconnect(client, "Excess Flood", "flood");
        } else {
            client.queue.addLast(record.body());
            add(statistics, "queued", 1);
        }
    }
    static void run() {
        int position = 0;
        for (time = 0; time <= end; time++) {
            for (Clients.Client client : new ArrayList<>(clients.values())) {
                client.refill(time, setting("BUCKET"), setting("REFILL"));
                while (client.active && !client.queue.isEmpty() && client.tokens >= 1) {
                    client.useToken(time, setting("BUCKET"), setting("REFILL"));
                    process(client, client.queue.removeFirst());
                }
            }
            while (position < traffic.size() && traffic.get(position).time() == time)
                arrival(traffic.get(position++));
            for (Clients.Client client : new ArrayList<>(clients.values()))
                if (client.pingSent >= 0) {
                    if (time - client.pingSent >= setting("TIMEOUT"))
                        disconnect(client,
                                   "Ping timeout: " + (time - client.lastReceived) + " seconds",
                                   "timeout");
                } else if (time - client.lastReceived >= setting("PINGFREQ")) {
                    send(client, "PING :" + settings.get("NAME"));
                    add(statistics, "pings", 1);
                    client.pingSent = time;
                }
        }
    }
    static List<String> channelReport() {
        List<String> lines = new ArrayList<>();
        int members = 0, bans = 0;
        for (Channels.Channel channel : channels.values()) {
            members += channel.members.size();
            bans += channel.bans.size();
            lines.add("CHANNEL " + channel.name + " created " + channel.created + " members " +
                      channel.members.size() + " peak " + channel.peak + " messages " +
                      channel.messages + " modes " + channel.modeDisplay(true));
            lines.add(channel.topic.isEmpty() ? "TOPIC none"
                                              : "TOPIC " + channel.topicSetter + " " +
                                                    channel.topicTime + " " + channel.topic);
            for (Channels.Ban ban : channel.bans)
                lines.add("BAN " + ban.mask() + " " + ban.setter() + " " + ban.time());
            List<String> names = new ArrayList<>();
            for (Channels.Member member : channel.members)
                names.add(member.display());
            lines.add("MEMBERS " + String.join(" ", names));
        }
        lines.add("TOTAL channels " + channels.size() + " members " + members + " bans " + bans);
        return lines;
    }
    static List<String> clientReport() {
        List<String> lines = new ArrayList<>();
        int registered = 0, invisible = 0, away = 0;
        for (Clients.Client client : clients.values()) {
            if (client.registered)
                registered++;
            if (client.invisible)
                invisible++;
            if (!client.away.isEmpty())
                away++;
            String joined = joined(client, ",");
            List<String> invites = new ArrayList<>();
            for (Channels.Channel channel : client.invites)
                invites.add(channel.name);
            lines.add("CLIENT " + client.identifier + " " + client.addressee() + " " +
                      (client.username == null ? "*" : client.username) + " " + client.hostname +
                      " " + client.mode() + " connected " + client.connectionTime + " signon " +
                      (client.registered ? Integer.toString(client.registrationTime) : "-") +
                      " received " + client.received + " sent " + client.sent + " tokens " +
                      client.tokens + " queue " + client.queue.size() + " channels " +
                      (joined.isEmpty() ? "none" : joined) + " invites " +
                      (invites.isEmpty() ? "none" : String.join(",", invites)));
            if (!client.away.isEmpty())
                lines.add("AWAY " + client.identifier + " " + client.away);
        }
        lines.add("TOTAL clients " + clients.size() + " registered " + registered + " invisible " +
                  invisible + " away " + away);
        return lines;
    }
    static List<String> statisticsReport() {
        List<String> lines = new ArrayList<>();
        int pending = 0, numericTotal = 0;
        for (Clients.Client client : clients.values())
            pending += client.queue.size();
        for (int count : numerics.values())
            numericTotal += count;
        lines.add("END " + end);
        lines.add("LINES total " + traffic.size() + " connect " +
                  lineCounts.getOrDefault("connect", 0) + " disconnect " +
                  lineCounts.getOrDefault("disconnect", 0) + " messages " +
                  lineCounts.getOrDefault("messages", 0));
        lines.add("MESSAGES dropped " + stat("dropped") + " queued " + stat("queued") +
                  " processed " + stat("processed") + " discarded " + stat("discarded") +
                  " pending " + pending + " empty " + stat("empty"));
        lines.add("SENT lines " + sent.size() + " numerics " + numericTotal + " pings " +
                  stat("pings") + " errors " + stat("errors"));
        for (var entry : commands.entrySet())
            lines.add("COMMAND " + entry.getKey() + " " + entry.getValue());
        for (var entry : numerics.entrySet())
            lines.add("NUMERIC " + number(entry.getKey()) + " " + entry.getValue());
        lines.add("PEAK connections " + peakConnections + " at " + peakConnectionsTime);
        lines.add("PEAK registered " + peakRegistered + " at " + peakRegisteredTime);
        List<String> kinds = new ArrayList<>();
        for (String kind : List.of("quit", "closed", "flood", "timeout"))
            kinds.add(kind + " " + disconnections.getOrDefault(kind, 0));
        lines.add("DISCONNECTS " + String.join(" ", kinds));
        for (Gone record : gone)
            lines.add("GONE " + record.time() + " " + record.identifier() + " " +
                      record.addressee() + " " + record.reason());
        return lines;
    }
    static void write(String name, List<String> lines) throws Exception {
        Files.writeString(Path.of("output", name),
                          String.join("\n", lines) + (lines.isEmpty() ? "" : "\n"));
    }
    public static void main(String[] args) throws Exception {
        for (String line : Files.readAllLines(Path.of("input", "server.txt"))) {
            int separator = line.indexOf(' ');
            String key = line.substring(0, separator), value = line.substring(separator + 1);
            if (key.equals("MOTD"))
                motd.add(value);
            else
                settings.put(key, value);
        }
        for (String line : Files.readAllLines(Path.of("input", "traffic.txt"))) {
            String[] fields = line.split(" ", 3);
            String body = fields[2], kind = "messages";
            if (body.startsWith("CONNECT ") && body.substring(8).matches("[A-Za-z0-9.-]{1,63}"))
                kind = "connect";
            else if (body.equals("DISCONNECT"))
                kind = "disconnect";
            traffic.add(new Traffic(Integer.parseInt(fields[0]), fields[1], kind, body));
            add(lineCounts, kind, 1);
        }
        end = traffic.getLast().time();
        run();
        Files.createDirectories(Path.of("output"));
        write("sent.txt", sent);
        write("channels.txt", channelReport());
        write("clients.txt", clientReport());
        write("stats.txt", statisticsReport());
    }
}
