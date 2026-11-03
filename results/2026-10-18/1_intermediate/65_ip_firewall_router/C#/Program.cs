using System.Globalization;

class Program
{
    record Prefix(uint Address, int Length)
    {
        public uint Network => Address & Mask(Length);
        public bool Contains(uint value) => (value & Mask(Length)) == Network;
        public override string ToString() => $"{Ip(Address)}/{Length}";
    }
    record Ports(int First, int Last, bool Any)
    {
        public bool Contains(int port) => First <= port && port <= Last;
        public override string ToString() => Any ? "any" : First == Last ? $"{First}" : $"{First}-{Last}";
    }
    class Interface(string name, Prefix prefix)
    {
        public string Name = name, Rpf = "off";
        public Prefix Prefix = prefix;
        public bool Up = true, Outside;
        public int Pool, Rx, Tx, Drop;
        public SortedDictionary<int, Rule>[] Acl = [new(), new()];
        public int[] Defaults = new int[2];
    }
    class Route(char type, Prefix prefix, Interface output, uint? hop, int metric)
    {
        public char Type = type;
        public Prefix Prefix = prefix;
        public Interface Output = output;
        public uint? Hop = hop;
        public int Metric = metric, Hits;
        public override string ToString() => $"{Type} {Prefix}" + (Hop is null ? "" : $" via {Ip(Hop.Value)}") + $" dev {Output.Name} metric {Metric}";
    }
    class Rule
    {
        public int Sequence, Hits;
        public required string Action, Protocol;
        public required Prefix Source, Destination;
        public required Ports SourcePorts, DestinationPorts;
        public bool Established;
    }
    record StaticNat(uint Inside, uint Outside);
    record Forward(Interface Interface, string Protocol, int Port, uint Inside, int InsidePort);
    class Pat(Interface iface, string protocol, uint inside, int insidePort, int port)
    {
        public Interface Interface = iface;
        public string Protocol = protocol;
        public uint Inside = inside;
        public int InsidePort = insidePort, Port = port, Last = clock;
    }
    record PacketTuple(string Protocol, uint Source, int SourcePort, uint Destination, int DestinationPort);
    class Connection
    {
        public int Number, OriginalPackets, ReplyPackets, Last;
        public required PacketTuple Original, Reply;
        public required Interface Input, Output;
        public required string State;
        public bool OriginalFin, ReplyFin;
    }
    class CommandError(string message) : Exception(message);
    static readonly List<Interface> Interfaces = [];
    static readonly List<Route> Routes = [];
    static readonly List<StaticNat> Statics = [];
    static readonly List<Forward> Forwards = [];
    static readonly List<Pat> Pats = [];
    static readonly List<Connection> Connections = [];
    static readonly Dictionary<string, int> Timeouts = new() { ["TCP"] = 300, ["UDP"] = 60, ["ICMP"] = 30 };
    static readonly string[] Reasons = ["down", "martian", "rpf", "invalid", "acl_in", "ttl", "noroute", "acl_out", "exhausted"];
    static readonly int[] Drops = new int[9];
    static int clock, packetNumber, connectionNumber, forwarded, local, errors;
    static uint Mask(int length) => length == 0 ? 0 : uint.MaxValue << (32 - length);
    static string Ip(uint value) => $"{value >> 24}.{(value >> 16) & 255}.{(value >> 8) & 255}.{value & 255}";
    static uint? ParseAddress(string text)
    {
        string[] fields = text.Split('.');
        if (fields.Length != 4) return null;
        uint address = 0;
        foreach (string field in fields)
        {
            if (field.Length is < 1 or > 3 || field.Length > 1 && field[0] == '0' || field.Any(c => c is < '0' or > '9')) return null;
            uint part = uint.Parse(field, CultureInfo.InvariantCulture);
            if (part > 255) return null;
            address = (address << 8) | part;
        }
        return address;
    }
    static uint Address(string text) => ParseAddress(text) ?? throw new CommandError("bad address " + text);
    static Prefix? ParsePrefix(string text)
    {
        string[] parts = text.Split('/');
        if (parts.Length != 2 || parts[1].Length is < 1 or > 2 || parts[1].Length > 1 && parts[1][0] == '0' || parts[1].Any(c => c is < '0' or > '9')) return null;
        uint? address = ParseAddress(parts[0]);
        int length = int.Parse(parts[1]);
        return address is null || length > 32 ? null : new(address.Value, length);
    }
    static Prefix CheckedPrefix(string text, bool any = false)
    {
        if (any && text == "ANY") return new(0, 0);
        Prefix prefix = ParsePrefix(text) ?? throw new CommandError("bad prefix " + text);
        if (prefix.Address != prefix.Network) throw new CommandError("host bits set in " + text);
        return prefix;
    }
    static Interface FindInterface(string name) => Interfaces.Find(iface => iface.Name == name) ?? throw new CommandError("no interface " + name);
    static Interface? LocalAddress(uint address) => Interfaces.Find(iface => iface.Prefix.Address == address);
    static int Range(string text, int minimum, int maximum, string message)
    {
        int value = int.Parse(text);
        if (value < minimum || value > maximum) throw new CommandError(message + " " + text);
        return value;
    }
    static Ports ParsePorts(string text)
    {
        if (text == "ANY") return new(0, 65535, true);
        string[] parts = text.Split('-');
        int first = int.Parse(parts[0]), last = int.Parse(parts[^1]);
        if (first > 65535 || last > 65535 || first > last) throw new CommandError("bad port range " + text);
        return new(first, last, false);
    }
    static Route? SelectRoute(uint address)
    {
        Route? best = null;
        foreach (Route route in Routes)
            if (route.Output.Up && route.Prefix.Contains(address) && (best is null || route.Prefix.Length > best.Prefix.Length || route.Prefix.Length == best.Prefix.Length && route.Metric < best.Metric)) best = route;
        return best;
    }
    static string? EvaluateAcl(Interface iface, int direction, PacketTuple packet, uint source, int sourcePort, uint destination, int destinationPort, bool established)
    {
        var rules = iface.Acl[direction];
        if (rules.Count == 0) return null;
        string dir = direction == 0 ? "in" : "out";
        foreach (Rule rule in rules.Values)
        {
            if (rule.Protocol != "ANY" && rule.Protocol != packet.Protocol || !rule.Source.Contains(source) || !rule.Destination.Contains(destination) || rule.Established && !established) continue;
            if (rule.Protocol is "TCP" or "UDP" && (!rule.SourcePorts.Contains(sourcePort) || !rule.DestinationPorts.Contains(destinationPort))) continue;
            rule.Hits++;
            if (rule.Action == "PERMIT") return null;
            return (rule.Action == "DENY" ? "DROP" : "REJECT") + $" acl {iface.Name} {dir} {rule.Sequence}" + (rule.Action == "REJECT" ? packet.Protocol == "TCP" ? " tcp-reset" : " icmp-prohibited" : "");
        }
        iface.Defaults[direction]++;
        return $"DROP acl {iface.Name} {dir} default";
    }
    static bool Martian(uint value) => value >> 24 is 0 or 127 || value >> 29 == 7;
    static string Drop(Interface input, int reason, string verdict) { Drops[reason]++; input.Drop++; return verdict; }
    static string ProcessPacket(Interface input, PacketTuple packet, string flags, int ttl)
    {
        input.Rx++;
        if (!input.Up) return Drop(input, 0, "DROP down");
        if (Martian(packet.Source) || Martian(packet.Destination) || LocalAddress(packet.Source) is not null) return Drop(input, 1, "DROP martian");
        if (input.Rpf != "off")
        {
            Route? reverse = SelectRoute(packet.Source);
            if (reverse is null || input.Rpf == "strict" && reverse.Output != input) return Drop(input, 2, "DROP rpf");
        }
        bool pureSyn = packet.Protocol == "TCP" && flags == "S";
        Connection? connection = null;
        string direction = "new";
        foreach (Connection candidate in Connections)
        {
            if (candidate.Original == packet) { connection = candidate; direction = "orig"; break; }
            if (candidate.Reply == packet) { connection = candidate; direction = "reply"; break; }
        }
        if (connection is not null && connection.State == "CLOSED" && pureSyn) { Connections.Remove(connection); connection = null; direction = "new"; }
        if (packet.Protocol == "TCP" && connection is null && !pureSyn) return Drop(input, 3, "DROP invalid");
        string? verdict = EvaluateAcl(input, 0, packet, packet.Source, packet.SourcePort, packet.Destination, packet.DestinationPort, connection is not null);
        if (verdict is not null) return Drop(input, 4, verdict);
        uint source = packet.Source, destination = packet.Destination;
        int sourcePort = packet.SourcePort, destinationPort = packet.DestinationPort;
        Pat? used = null;
        if (input.Outside)
        {
            StaticNat? mapping = Statics.Find(entry => entry.Outside == destination);
            if (mapping is not null) destination = mapping.Inside;
            else if (destination == input.Prefix.Address)
            {
                Forward? forward = Forwards.Find(rule => rule.Interface == input && rule.Protocol == packet.Protocol && rule.Port == destinationPort);
                if (forward is not null) { destination = forward.Inside; destinationPort = forward.InsidePort; }
                else
                {
                    used = Pats.Find(entry => entry.Interface == input && entry.Protocol == packet.Protocol && entry.Port == destinationPort);
                    if (used is not null) { destination = used.Inside; destinationPort = used.InsidePort; }
                }
            }
        }
        Interface? target = LocalAddress(destination);
        if (target is not null) { local++; return "LOCAL " + target.Name; }
        if (ttl == 1) return Drop(input, 5, "DROP ttl");
        Route? route = SelectRoute(destination);
        if (route is null) return Drop(input, 6, "DROP noroute");
        Interface output = route.Output;
        verdict = EvaluateAcl(output, 1, packet, source, sourcePort, destination, destinationPort, connection is not null);
        if (verdict is not null) return Drop(input, 7, verdict);
        if (!input.Outside && output.Outside)
        {
            StaticNat? mapping = Statics.Find(entry => entry.Inside == source);
            if (mapping is not null) source = mapping.Outside;
            else
            {
                Forward? forward = Forwards.Find(rule => rule.Interface == output && rule.Protocol == packet.Protocol && rule.Inside == source && rule.InsidePort == sourcePort);
                if (forward is not null) { source = output.Prefix.Address; sourcePort = forward.Port; }
                else if (output.Pool > 0)
                {
                    used = Pats.Find(entry => entry.Interface == output && entry.Protocol == packet.Protocol && entry.Inside == source && entry.InsidePort == sourcePort);
                    if (used is null)
                    {
                        int port;
                        for (port = 20000; port < 20000 + output.Pool; port++)
                            if (!Pats.Any(entry => entry.Interface == output && entry.Port == port) && !Forwards.Any(rule => rule.Interface == output && rule.Port == port)) break;
                        if (port == 20000 + output.Pool) return Drop(input, 8, "DROP exhausted");
                        used = new(output, packet.Protocol, source, sourcePort, port); Pats.Add(used);
                    }
                    source = output.Prefix.Address; sourcePort = used.Port;
                }
            }
        }
        if (used is not null) used.Last = clock;
        if (connection is null)
        {
            connection = new() { Number = ++connectionNumber, Original = packet, Reply = new(packet.Protocol, destination, destinationPort, source, sourcePort), Input = input, Output = output, State = packet.Protocol == "TCP" ? "SYN_SENT" : "UNREPLIED" };
            Connections.Add(connection);
        }
        if (direction == "reply") connection.ReplyPackets++; else connection.OriginalPackets++;
        connection.Last = clock;
        if (packet.Protocol != "TCP") { if (direction == "reply") connection.State = "REPLIED"; }
        else if (flags.Contains('R')) connection.State = "CLOSED";
        else
        {
            if (connection.State == "SYN_SENT" && direction == "reply" && flags.Contains('S') && flags.Contains('A')) connection.State = "ESTABLISHED";
            if (flags.Contains('F') && connection.State is "ESTABLISHED" or "FIN_WAIT")
            {
                if (direction == "reply") connection.ReplyFin = true; else connection.OriginalFin = true;
                connection.State = connection.OriginalFin && connection.ReplyFin ? "CLOSED" : "FIN_WAIT";
            }
        }
        output.Tx++; route.Hits++; forwarded++;
        return $"FORWARD {output.Name}" + (route.Hop is null ? " direct" : " via " + Ip(route.Hop.Value)) + $" ttl={ttl - 1}"
            + (destination != packet.Destination || destinationPort != packet.DestinationPort ? $" dnat={Ip(destination)}:{destinationPort}" : "")
            + (source != packet.Source || sourcePort != packet.SourcePort ? $" snat={Ip(source)}:{sourcePort}" : "")
            + $" conn={connection.Number} {direction}";
    }
    static IEnumerable<Interface> SortedInterfaces() => Interfaces.OrderBy(iface => iface.Name, StringComparer.Ordinal);
    static string AclPrefix(Prefix prefix) => prefix.Length == 0 ? "any" : prefix.ToString();
    static void Show(string what)
    {
        switch (what)
        {
            case "IFACES":
                Console.WriteLine($"show ifaces count={Interfaces.Count}");
                foreach (Interface iface in SortedInterfaces()) Console.WriteLine($"{iface.Name} {iface.Prefix} {(iface.Up ? "up" : "down")} {(iface.Outside ? "outside" : "inside")} rpf={iface.Rpf}" + (iface.Pool == 0 ? "" : $" pat={Pats.Count(mapping => mapping.Interface == iface)}/{iface.Pool}"));
                break;
            case "ROUTES":
                Console.WriteLine($"show routes count={Routes.Count}");
                foreach (Route route in Routes.OrderBy(entry => entry.Prefix.Address).ThenBy(entry => entry.Prefix.Length).ThenBy(entry => entry.Metric)) Console.WriteLine($"{route} hits={route.Hits}" + (route.Output.Up ? "" : " inactive"));
                break;
            case "ACL":
                Console.WriteLine($"show acl count={Interfaces.Sum(iface => iface.Acl.Sum(rules => rules.Count))}");
                foreach (Interface iface in SortedInterfaces()) for (int d = 0; d < 2; d++)
                {
                    if (iface.Acl[d].Count == 0) continue;
                    string dir = d == 0 ? "in" : "out";
                    foreach (Rule rule in iface.Acl[d].Values) Console.WriteLine($"acl {iface.Name} {dir} {rule.Sequence} {rule.Action} {rule.Protocol} {AclPrefix(rule.Source)} {rule.SourcePorts} {AclPrefix(rule.Destination)} {rule.DestinationPorts}" + (rule.Established ? " established" : "") + $" hits={rule.Hits}");
                    Console.WriteLine($"acl {iface.Name} {dir} default DENY hits={iface.Defaults[d]}");
                }
                break;
            case "NAT":
                Console.WriteLine($"show nat static={Statics.Count} forward={Forwards.Count} pat={Pats.Count}");
                foreach (StaticNat mapping in Statics.OrderBy(entry => entry.Inside)) Console.WriteLine($"static {Ip(mapping.Inside)} {Ip(mapping.Outside)}");
                foreach (Forward rule in Forwards.OrderBy(entry => entry.Interface.Name, StringComparer.Ordinal).ThenBy(entry => entry.Port).ThenBy(entry => entry.Protocol, StringComparer.Ordinal)) Console.WriteLine($"forward {rule.Interface.Name} {rule.Protocol} {rule.Port} {Ip(rule.Inside)}:{rule.InsidePort}");
                foreach (Pat mapping in Pats.OrderBy(entry => entry.Interface.Name, StringComparer.Ordinal).ThenBy(entry => entry.Port)) Console.WriteLine($"pat {mapping.Interface.Name} {mapping.Port} {mapping.Protocol} {Ip(mapping.Inside)}:{mapping.InsidePort} idle={clock - mapping.Last}");
                break;
            case "CONNS":
                Console.WriteLine($"show conns count={Connections.Count}");
                foreach (Connection c in Connections) Console.WriteLine($"conn {c.Number} {c.Original.Protocol} {Ip(c.Original.Source)}:{c.Original.SourcePort} > {Ip(c.Original.Destination)}:{c.Original.DestinationPort} reply {Ip(c.Reply.Source)}:{c.Reply.SourcePort} > {Ip(c.Reply.Destination)}:{c.Reply.DestinationPort} in={c.Input.Name} out={c.Output.Name} state={c.State} pkts={c.OriginalPackets}/{c.ReplyPackets} idle={clock - c.Last}");
                break;
            case "COUNTERS":
                int dropped = Drops.Sum();
                Console.WriteLine($"show counters packets={forwarded + local + dropped} forwarded={forwarded} local={local} dropped={dropped} errors={errors}");
                Console.WriteLine("drops " + string.Join(" ", Reasons.Select((reason, index) => $"{reason}={Drops[index]}")));
                foreach (Interface iface in SortedInterfaces()) Console.WriteLine($"iface {iface.Name} rx={iface.Rx} tx={iface.Tx} drop={iface.Drop}");
                break;
        }
    }
    static void Execute(string[] args)
    {
        switch (args[0])
        {
            case "IFACE":
            {
                if (Interfaces.Any(existing => existing.Name == args[1])) throw new CommandError("duplicate interface " + args[1]);
                Prefix? prefix = ParsePrefix(args[2]);
                if (prefix is null || prefix.Length is < 8 or > 30) throw new CommandError("bad prefix " + args[2]);
                uint host = prefix.Address & ~Mask(prefix.Length);
                if (host == 0 || host == ~Mask(prefix.Length)) throw new CommandError("bad host address " + args[2]);
                foreach (Interface existing in Interfaces)
                    if ((prefix.Address & Mask(Math.Min(prefix.Length, existing.Prefix.Length))) == (existing.Prefix.Address & Mask(Math.Min(prefix.Length, existing.Prefix.Length)))) throw new CommandError("subnet overlaps " + existing.Name);
                Interface iface = new(args[1], prefix); Interfaces.Add(iface); Routes.Add(new('C', new(prefix.Network, prefix.Length), iface, null, 0));
                Console.WriteLine($"ok iface {args[1]} {args[2]} network {Ip(prefix.Network)}/{prefix.Length}"); break;
            }
            case "UP": case "DOWN":
            {
                Interface iface = FindInterface(args[1]); bool up = args[0] == "UP";
                if (iface.Up == up) throw new CommandError($"interface {args[1]} already {(up ? "up" : "down")}");
                iface.Up = up; Console.WriteLine($"ok {args[0].ToLowerInvariant()} {args[1]}"); break;
            }
            case "ROUTE":
            {
                Prefix prefix = CheckedPrefix(args[1]); bool via = args[2] == "VIA";
                uint? hop = via ? Address(args[3]) : null;
                Interface? output = via ? null : FindInterface(args[3]);
                int metric = Range(args[4], 1, 255, "bad metric");
                if (via)
                {
                    if (LocalAddress(hop!.Value) is not null) throw new CommandError($"nexthop {args[3]} is local");
                    output = Interfaces.Find(iface => iface.Prefix.Contains(hop.Value));
                    if (output is null) throw new CommandError($"nexthop {args[3]} unreachable");
                }
                if (Routes.Any(route => route.Type == 'S' && route.Prefix == prefix && route.Output == output && route.Hop == hop)) throw new CommandError("duplicate route " + args[1]);
                Route added = new('S', prefix, output!, hop, metric); Routes.Add(added); Console.WriteLine("ok route " + added); break;
            }
            case "NOROUTE":
            {
                Prefix prefix = CheckedPrefix(args[1]);
                if (!Routes.Any(route => route.Type == 'S' && route.Prefix == prefix)) throw new CommandError("no static route " + args[1]);
                int removed = Routes.RemoveAll(route => route.Type == 'S' && route.Prefix == prefix);
                Console.WriteLine($"ok noroute {args[1]} removed={removed}"); break;
            }
            case "LOOKUP": Console.WriteLine($"lookup {args[1]} {SelectRoute(Address(args[1]))?.ToString() ?? "none"}"); break;
            case "ACL":
            {
                Interface iface = FindInterface(args[1]); int direction = args[2] == "IN" ? 0 : 1;
                int sequence = Range(args[3], 1, 9999, "bad sequence");
                Prefix source = CheckedPrefix(args[6], true); Ports sourcePorts = ParsePorts(args[7]);
                Prefix destination = CheckedPrefix(args[8], true); Ports destinationPorts = ParsePorts(args[9]);
                if (args[5] is "ICMP" or "ANY" && (args[7] != "ANY" || args[9] != "ANY")) throw new CommandError("ports not allowed for " + args[5]);
                if (iface.Acl[direction].ContainsKey(sequence)) throw new CommandError("duplicate sequence " + args[3]);
                iface.Acl[direction][sequence] = new() { Sequence = sequence, Action = args[4], Protocol = args[5], Source = source, SourcePorts = sourcePorts, Destination = destination, DestinationPorts = destinationPorts, Established = args.Length == 11 };
                Console.WriteLine($"ok acl {args[1]} {args[2].ToLowerInvariant()} {args[3]}"); break;
            }
            case "NOACL":
            {
                Interface iface = FindInterface(args[1]); int direction = args[2] == "IN" ? 0 : 1;
                if (!iface.Acl[direction].TryGetValue(int.Parse(args[3]), out Rule? rule)) throw new CommandError($"no rule {args[3]} on {args[1]} {args[2].ToLowerInvariant()}");
                iface.Acl[direction].Remove(rule.Sequence); Console.WriteLine($"ok noacl {args[1]} {args[2].ToLowerInvariant()} {args[3]} hits={rule.Hits}"); break;
            }
            case "NAT":
                if (args[1] == "STATIC")
                {
                    uint inside = Address(args[2]), outside = Address(args[3]);
                    if (LocalAddress(inside) is not null) throw new CommandError($"address {args[2]} is local");
                    if (LocalAddress(outside) is not null) throw new CommandError($"address {args[3]} is local");
                    if (Statics.Any(mapping => mapping.Inside == inside)) throw new CommandError("duplicate static " + args[2]);
                    if (Statics.Any(mapping => mapping.Outside == outside)) throw new CommandError("duplicate static " + args[3]);
                    Statics.Add(new(inside, outside)); Console.WriteLine($"ok nat static {args[2]} {args[3]}");
                }
                else
                {
                    Interface iface = FindInterface(args[2]);
                    if (args[1] == "OUTSIDE")
                    {
                        if (iface.Outside) throw new CommandError($"interface {args[2]} already outside");
                        iface.Outside = true; Console.WriteLine("ok nat outside " + args[2]);
                    }
                    else if (args[1] == "PAT")
                    {
                        int count = Range(args[3], 1, 1000, "bad pool size");
                        if (iface.Pool > 0) throw new CommandError("pat already on " + args[2]);
                        iface.Pool = count; iface.Outside = true; Console.WriteLine($"ok nat pat {args[2]} {Ip(iface.Prefix.Address)} 20000-{19999 + count}");
                    }
                    else
                    {
                        int port = Range(args[4], 1, 65535, "bad port"); uint inside = Address(args[5]); int insidePort = Range(args[6], 1, 65535, "bad port");
                        if (!iface.Outside) throw new CommandError($"interface {args[2]} not outside");
                        if (LocalAddress(inside) is not null) throw new CommandError($"address {args[5]} is local");
                        if (Forwards.Any(rule => rule.Interface == iface && rule.Protocol == args[3] && rule.Port == port)) throw new CommandError($"duplicate forward {args[2]} {args[3]} {args[4]}");
                        Forwards.Add(new(iface, args[3], port, inside, insidePort)); Console.WriteLine($"ok nat forward {args[2]} {args[3]} {args[4]} {args[5]}:{args[6]}");
                    }
                }
                break;
            case "RPF":
            {
                Interface iface = FindInterface(args[1]); iface.Rpf = args[2].ToLowerInvariant(); Console.WriteLine($"ok rpf {args[1]} {iface.Rpf}"); break;
            }
            case "TIMEOUT": Timeouts[args[1]] = Range(args[2], 1, 86400, "bad timeout"); Console.WriteLine($"ok timeout {args[1]} {args[2]}"); break;
            case "TICK":
            {
                clock += Range(args[1], 1, 86400, "bad tick");
                int removed = Connections.RemoveAll(connection => clock - connection.Last >= (connection.Original.Protocol == "TCP" ? connection.State switch { "SYN_SENT" or "FIN_WAIT" => 60, "CLOSED" => 10, _ => Timeouts["TCP"] } : Timeouts[connection.Original.Protocol]));
                int mappings = Pats.RemoveAll(mapping => clock - mapping.Last >= Timeouts[mapping.Protocol]);
                Console.WriteLine($"ok tick time={clock} expired conns={removed} nat={mappings}"); break;
            }
            case "PACKET":
            {
                Interface iface = FindInterface(args[1]);
                if (args[2] != "TCP" && args[3] != "-") throw new CommandError("flags not allowed for " + args[2]);
                if (args[2] == "TCP" && args[3] != "-" && (args[3].Any(c => !"SAFR".Contains(c)) || args[3].Distinct().Count() != args[3].Length)) throw new CommandError("bad flags " + args[3]);
                uint source = Address(args[4]); int sourcePort = Range(args[5], 0, 65535, "bad port");
                uint destination = Address(args[6]); int destinationPort = Range(args[7], 0, 65535, "bad port"), ttl = Range(args[8], 1, 255, "bad ttl");
                packetNumber++;
                string verdict = ProcessPacket(iface, new(args[2], source, sourcePort, destination, destinationPort), args[3], ttl);
                Console.WriteLine($"#{packetNumber} {args[2]} {args[3]} {args[4]}:{args[5]} > {args[6]}:{args[7]} {verdict}"); break;
            }
            case "SHOW": Show(args[1]); break;
            case "CLEAR":
                if (args[1] == "CONNS") { Console.WriteLine($"ok clear conns={Connections.Count} nat={Pats.Count}"); Connections.Clear(); Pats.Clear(); }
                else
                {
                    forwarded = local = errors = 0; Array.Clear(Drops);
                    foreach (Interface iface in Interfaces) { iface.Rx = iface.Tx = iface.Drop = 0; Array.Clear(iface.Defaults); foreach (var rules in iface.Acl) foreach (Rule rule in rules.Values) rule.Hits = 0; }
                    foreach (Route route in Routes) route.Hits = 0;
                    Console.WriteLine("ok clear counters");
                }
                break;
        }
    }
    static void Main()
    {
        int count = int.Parse(Console.ReadLine()!);
        for (int i = 0; i < count; i++)
            try { Execute(Console.ReadLine()!.Split(' ')); }
            catch (CommandError error) { errors++; Console.WriteLine("error: " + error.Message); }
    }
}
