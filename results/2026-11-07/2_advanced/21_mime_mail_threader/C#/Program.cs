using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed record Sections(List<SourceLine> Header, List<SourceLine> Body);
sealed record SortKey(int InvalidDate, long Seconds, string Id, int Number) : IComparable<SortKey> {
    public int CompareTo(SortKey other) {
        int result = InvalidDate.CompareTo(other.InvalidDate);
        if (result == 0) result = Seconds.CompareTo(other.Seconds);
        if (result == 0) result = StringComparer.Ordinal.Compare(Id, other.Id);
        return result == 0 ? Number.CompareTo(other.Number) : result;
    }
}
sealed class Entity {
    public readonly string Number;
    public string Type = "text", Subtype = "plain", Disposition, Filename, Content = "";
    public Dictionary<string, string> Parameters = new(StringComparer.Ordinal);
    public List<Entity> Children;
    public Entity(string number) { Number = number; }
    public bool Multipart() => Children != null;
    public string Parameter(string name) => Parameters.GetValueOrDefault(name, "");
}
sealed class Message {
    public readonly int Number;
    public readonly List<string> Problems = new();
    public Mailbox Sender;
    public List<string> To = new(), Cc = new(), References = new();
    public string Subject = "", BaseSubject = "", Id = "";
    public bool Reply;
    public long? Date;
    public Entity Body;
    public SortKey SortKey;
    public int Thread, Depth;
    public Message Parent;
    public Message(int number) { Number = number; }
    public void Problem(string text) => Problems.Add(text);
    public void Process(List<SourceLine> lines, Dictionary<string, int> knownIds) {
        Sections sections = Program.SplitSections(lines);
        Header header = Headers.ParseFields(sections.Header);
        foreach (int line in header.Invalid) Problem("bad header line " + line);
        foreach (string name in Program.CheckedFields) if (header.Count(name) > 1) Problem("duplicate " + name);
        ReadSender(header.Value("From")); To = ReadRecipients(header.Value("To"), "To"); Cc = ReadRecipients(header.Value("Cc"), "Cc");
        ReadSubject(header.Value("Subject")); ReadDate(header.Value("Date")); ReadId(header.Value("Message-ID"), knownIds);
        References = Program.ExtractIds(header.Value("References") ?? "");
        List<string> replies = Program.ExtractIds(header.Value("In-Reply-To") ?? "");
        if (replies.Count > 0 && (References.Count == 0 || References[^1] != replies[0])) References.Add(replies[0]);
        bool mime = MimeEnabled(header.Value("MIME-Version"));
        Body = ParseEntity("1", header, sections.Body, mime);
        SortKey = new SortKey(Date.HasValue ? 0 : 1, Date ?? 0, Id, Number);
    }
    void ReadSender(string value) {
        if (value == null) { Problem("missing From"); return; }
        AddressList parsed = Addresses.Parse(value);
        if (parsed == null || parsed.Addresses.Count != 1 || parsed.Addresses[0] is not Mailbox) { Problem("bad From"); return; }
        Sender = (Mailbox)parsed.Addresses[0];
        if (parsed.EncodingError) Problem("bad encoded word in From");
    }
    List<string> ReadRecipients(string value, string name) {
        List<string> recipients = new();
        if (value == null) return recipients;
        AddressList parsed = Addresses.Parse(value);
        if (parsed == null) { Problem("bad " + name); return recipients; }
        foreach (Address address in parsed.Addresses) {
            if (address is Mailbox mailbox) recipients.Add(mailbox.AddressText);
            else foreach (Address member in ((AddressGroup)address).Mailboxes) recipients.Add(((Mailbox)member).AddressText);
        }
        if (parsed.EncodingError) Problem("bad encoded word in " + name);
        return recipients;
    }
    void ReadSubject(string value) {
        DecodedText decoded = Headers.Unstructured(value ?? "");
        Subject = decoded.Text;
        if (decoded.Error) Problem("bad encoded word in Subject");
        BaseSubject = Subject;
        while (BaseSubject.Length >= 3 && BaseSubject[..3].ToLowerInvariant() == "re:") { BaseSubject = BaseSubject[3..].TrimStart(' '); Reply = true; }
    }
    void ReadDate(string value) {
        if (value == null) { Problem("missing Date"); return; }
        DateResult parsed = Dates.Parse(value);
        if (parsed.Error == null) Date = parsed.Seconds; else Problem(parsed.Error);
    }
    void ReadId(string value, Dictionary<string, int> known) {
        if (value == null) Problem("missing Message-ID");
        else if (!Program.MessageId(value)) Problem("bad Message-ID");
        else if (known.TryGetValue(value, out int first)) Problem("Message-ID already used by message " + first);
        else { Id = value; known.Add(value, Number); }
    }
    bool MimeEnabled(string value) {
        if (value == null) return false;
        string text = Headers.RemoveComments(value);
        if (text != null && text.Replace(" ", "").Replace("\t", "") == "1.0") return true;
        Problem("bad MIME-Version");
        return false;
    }
    Entity ParseEntity(string number, Header header, List<SourceLine> lines, bool mime) {
        Entity entity = new(number);
        string contentType = header.Value("Content-Type");
        if (mime && contentType != null) {
            Parameters parsed = Headers.ParseParameters(contentType, true);
            if (parsed == null) Problem("bad Content-Type in part " + number);
            else { entity.Type = parsed.Type; entity.Subtype = parsed.Subtype; entity.Parameters = parsed.Values; }
        }
        string disposition = header.Value("Content-Disposition");
        if (mime && disposition != null) {
            Parameters parsed = Headers.ParseParameters(disposition, false);
            if (parsed == null) Problem("bad Content-Disposition in part " + number);
            else { entity.Disposition = parsed.Type; entity.Filename = parsed.Values.GetValueOrDefault("filename"); }
        }
        if (string.IsNullOrEmpty(entity.Filename)) entity.Filename = entity.Parameters.GetValueOrDefault("name");
        if (entity.Type == "text" && entity.Parameters.TryGetValue("charset", out string charset) && charset.ToLowerInvariant() != "us-ascii") Problem("unsupported charset \"" + charset.ToLowerInvariant() + "\" in part " + number);
        if (mime && entity.Type == "multipart") {
            string boundary = entity.Parameter("boundary");
            if (boundary.Length > 0) { SplitMultipart(entity, lines, boundary); return entity; }
            Problem("missing boundary in part " + number);
        }
        DecodeLeaf(entity, header, lines, mime);
        return entity;
    }
    void SplitMultipart(Entity entity, List<SourceLine> lines, string boundary) {
        List<List<SourceLine>> parts = new();
        bool closed = false;
        foreach (SourceLine line in lines) {
            string text = Headers.Rstrip(line.Text);
            if (text == "--" + boundary + "--") { closed = true; break; }
            if (text == "--" + boundary) parts.Add(new());
            else if (parts.Count > 0) parts[^1].Add(line);
        }
        if (parts.Count == 0) Problem("no parts in part " + entity.Number);
        else if (!closed) Problem("unterminated multipart in part " + entity.Number);
        entity.Children = new();
        for (int i = 0; i < parts.Count; i++) {
            Sections sections = Program.SplitSections(parts[i]);
            Header header = Headers.ParseFields(sections.Header);
            foreach (int line in header.Invalid) Problem("bad header line " + line);
            entity.Children.Add(ParseEntity(entity.Number + "." + (i + 1), header, sections.Body, true));
        }
    }
    void DecodeLeaf(Entity entity, Header header, List<SourceLine> lines, bool mime) {
        string original = string.Join("\n", lines.Select(line => line.Text));
        string transfer = header.Value("Content-Transfer-Encoding"), encoding = mime && transfer != null ? transfer.ToLowerInvariant() : "7bit";
        if (encoding == "base64") {
            entity.Content = Mime.Base64Body(original);
            if (entity.Content == null) { Problem("bad base64 in part " + entity.Number); entity.Content = ""; }
        } else if (encoding == "quoted-printable") {
            DecodedText decoded = Mime.QuotedPrintable(original); entity.Content = decoded.Text;
            if (decoded.Error) Problem("bad quoted-printable in part " + entity.Number);
        } else {
            entity.Content = original;
            if (encoding is not ("7bit" or "8bit" or "binary")) Problem("unknown encoding \"" + encoding + "\" in part " + entity.Number);
        }
    }
}
sealed class LogicalLine {
    public readonly int Depth;
    public string Text;
    public bool Flowing;
    public LogicalLine(int depth, string text, bool flowing = false) { Depth = depth; Text = text; Flowing = flowing; }
}
sealed record Displayed(string Format, List<string> Lines);
sealed record ThreadEntry(Container Container, string Prefix, int Depth);
sealed class MailThread {
    public readonly int Number;
    readonly Container root;
    readonly List<ThreadEntry> entries = new();
    readonly List<Message> messages;
    public MailThread(int number, Container root) {
        Number = number; this.root = root;
        Walk(root, "", "", 0);
        messages = entries.Select(entry => entry.Container.Message).Where(message => message != null).ToList();
    }
    void Walk(Container container, string prefix, string stem, int depth) {
        entries.Add(new ThreadEntry(container, prefix, depth));
        for (int i = 0; i < container.Children.Count; i++) {
            bool last = i + 1 == container.Children.Count;
            Walk(container.Children[i], stem + (last ? "`- " : "+- "), stem + (last ? "   " : "|  "), depth + 1);
        }
    }
    public void PlaceMessages() {
        foreach (ThreadEntry entry in entries) {
            Container container = entry.Container;
            Message message = container.Message;
            if (message != null) { message.Thread = Number; message.Depth = entry.Depth; message.Parent = container.Parent?.Message; }
        }
    }
    public List<string> Report() {
        int depth = entries.Max(entry => entry.Depth);
        HashSet<string> senders = messages.Where(message => message.Sender != null).Select(message => message.Sender.AddressText).ToHashSet(StringComparer.Ordinal);
        List<long> dates = messages.Where(message => message.Date.HasValue).Select(message => message.Date.Value).ToList();
        List<string> lines = ["thread " + Number + " messages " + messages.Count + " depth " + depth + " senders " + senders.Count];
        lines.Add(dates.Count == 0 ? "span -" : "span " + Dates.Format(dates.Min()) + " .. " + Dates.Format(dates.Max()));
        lines.Add("subject " + Program.SubjectNotation(root.Subject ?? Threader.RootSubject(root)));
        foreach (ThreadEntry entry in entries) lines.Add(entry.Prefix + Program.ContainerNotation(entry.Container));
        return lines;
    }
}
sealed class SenderStats {
    public readonly string Address;
    public int Count;
    public readonly HashSet<int> Threads = new();
    public long? First, Last;
    public string Name = "";
    public SenderStats(string address) { Address = address; }
    public void Add(Message message) {
        Count++; Threads.Add(message.Thread);
        if (message.Date.HasValue) {
            if (!First.HasValue || message.Date.Value < First.Value) First = message.Date;
            if (!Last.HasValue || message.Date.Value > Last.Value) Last = message.Date;
        }
        if (message.Sender.Name.Length > 0) Name = message.Sender.Name;
    }
}
static class Program {
    public static readonly string[] CheckedFields = ["From", "To", "Cc", "Subject", "Date", "Message-ID", "In-Reply-To", "References", "MIME-Version", "Content-Type", "Content-Transfer-Encoding", "Content-Disposition"];
    static readonly HashSet<string> HiddenTags = ["head", "style", "script"], ParagraphTags = ["p", "div", "ul", "ol", "table", "tr", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6"];
    static readonly Dictionary<string, string> CharacterReferences = new(StringComparer.Ordinal) { ["amp"] = "&", ["lt"] = "<", ["gt"] = ">", ["quot"] = "\"", ["apos"] = "'", ["nbsp"] = " " };
    static List<string> Read(string name) => File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII).ToList();
    static List<List<SourceLine>> MailboxLines(List<string> lines) {
        List<List<SourceLine>> messages = new();
        for (int i = 0; i < lines.Count; i++) {
            string text = lines[i];
            if (text.StartsWith("From ", StringComparison.Ordinal)) messages.Add(new());
            else if (messages.Count > 0) {
                string unquoted = text.TrimStart('>');
                if (unquoted.Length != text.Length && unquoted.StartsWith("From ", StringComparison.Ordinal)) text = text[1..];
                messages[^1].Add(new SourceLine(i + 1, text));
            }
        }
        foreach (List<SourceLine> message in messages) if (message.Count > 0 && message[^1].Text.Length == 0) message.RemoveAt(message.Count - 1);
        return messages;
    }
    public static Sections SplitSections(List<SourceLine> lines) {
        for (int i = 0; i < lines.Count; i++) if (lines[i].Text.Length == 0) return new Sections(lines.GetRange(0, i), lines.GetRange(i + 1, lines.Count - i - 1));
        return new Sections(lines, new());
    }
    public static bool MessageId(string text) {
        if (text.Length < 3 || !text.StartsWith('<') || !text.EndsWith('>')) return false;
        string inside = text[1..^1];
        if (inside.Count(letter => letter == '@') != 1 || inside.StartsWith('@') || inside.EndsWith('@')) return false;
        return inside.All(letter => letter >= 33 && letter <= 126 && !"<>()\"\\".Contains(letter));
    }
    public static List<string> ExtractIds(string value) {
        List<string> ids = new();
        int start = value.IndexOf('<');
        while (start >= 0) {
            int end = value.IndexOf('>', start + 1);
            if (end < 0) break;
            string id = value[start..(end + 1)];
            if (MessageId(id)) ids.Add(id);
            start = value.IndexOf('<', end + 1);
        }
        return ids;
    }
    static string DateNotation(long? seconds) => seconds.HasValue ? Dates.Format(seconds.Value) : "invalid";
    public static string SubjectNotation(string subject) => subject.Length == 0 ? "(no subject)" : subject;
    static List<Entity> Collect(Entity entity, bool allowHtml) {
        if (!entity.Multipart()) return entity.Disposition != "attachment" && entity.Type == "text" && (entity.Subtype == "plain" || entity.Subtype == "html" && allowHtml) ? [entity] : new();
        if (entity.Subtype == "alternative") {
            foreach (bool html in new[] { false, true }) foreach (Entity child in entity.Children) {
                List<Entity> parts = Collect(child, html);
                if (parts.Count > 0) return parts;
            }
            return new();
        }
        List<Entity> all = new();
        foreach (Entity child in entity.Children) all.AddRange(Collect(child, allowHtml));
        return all;
    }
    static string QuotePrefix(int depth) => depth > 0 ? new string('>', depth) + " " : "";
    static List<string> Wrap(string text, string prefix) {
        List<string> lines = new();
        string current = "";
        foreach (string word in Headers.Words(text)) {
            if (current.Length > 0 && current.Length + 1 + word.Length > 72) { lines.Add(prefix + current); current = word; }
            else current = current.Length == 0 ? word : current + " " + word;
        }
        lines.Add(prefix + current);
        return lines;
    }
    static List<string> Flowed(string content, bool deleteSpace) {
        if (content.Length == 0) return new();
        List<LogicalLine> logical = new();
        foreach (string line in content.Split('\n')) {
            string text = line.TrimStart('>');
            int depth = line.Length - text.Length;
            if (text.StartsWith(' ')) text = text[1..];
            bool flowing = text.EndsWith(' ') && text != "-- ";
            LogicalLine previous = logical.Count == 0 ? null : logical[^1];
            if (previous != null && previous.Flowing && previous.Depth == depth) {
                if (deleteSpace) previous.Text = previous.Text[..^1];
                previous.Text += text; previous.Flowing = flowing;
            } else logical.Add(new LogicalLine(depth, text, flowing));
        }
        List<string> lines = new();
        foreach (LogicalLine line in logical) lines.AddRange(Wrap(line.Text, QuotePrefix(line.Depth)));
        return lines;
    }
    static bool TagCharacter(char letter) => letter >= 'A' && letter <= 'Z' || letter >= 'a' && letter <= 'z' || letter >= '0' && letter <= '9';
    static string TagName(string text) {
        int end = 0;
        while (end < text.Length && TagCharacter(text[end])) end++;
        return text[..end].ToLowerInvariant();
    }
    static string Reference(string name) {
        if (CharacterReferences.TryGetValue(name, out string replacement)) return replacement;
        if (name.StartsWith('#') && Dates.Digits(name[1..], 1, 2, 3)) {
            int value = int.Parse(name[1..]);
            if (value >= 32 && value <= 126) return ((char)value).ToString();
        }
        return null;
    }
    static string ReplaceReferences(string text) {
        StringBuilder result = new();
        int position = 0;
        while (position < text.Length) {
            int end = text[position] == '&' ? text.IndexOf(';', position + 1) : -1;
            string replacement = end < 0 ? null : Reference(text[(position + 1)..end]);
            if (replacement == null) result.Append(text[position++]);
            else { result.Append(replacement); position = end + 1; }
        }
        return result.ToString();
    }
    static List<LogicalLine> HtmlBlocks(string content) {
        List<LogicalLine> blocks = new();
        int depth = 0, position = 0;
        StringBuilder text = new();
        string hide = null;
        while (position < content.Length) {
            char letter = content[position];
            int close = letter == '<' ? content.IndexOf('>', position + 1) : -1;
            if (close < 0) { if (hide == null) text.Append(letter); position++; continue; }
            string inside = content[(position + 1)..close];
            position = close + 1;
            bool endTag = inside.StartsWith('/');
            string name = TagName(endTag ? inside[1..] : inside);
            if (hide != null) { if (endTag && name == hide) hide = null; }
            else if (!endTag && HiddenTags.Contains(name)) hide = name;
            else if (name == "br" || name == "li" && !endTag) {
                blocks.Add(new LogicalLine(depth, text.ToString()));
                text = new StringBuilder(name == "li" ? "* " : "");
            } else if (ParagraphTags.Contains(name)) {
                blocks.Add(new LogicalLine(depth, text.ToString())); blocks.Add(new LogicalLine(depth, ""));
                text = new StringBuilder();
                if (name == "blockquote") depth = endTag ? Math.Max(0, depth - 1) : depth + 1;
            }
        }
        blocks.Add(new LogicalLine(depth, text.ToString()));
        return blocks;
    }
    static List<string> Html(string content) {
        List<string> lines = new();
        foreach (LogicalLine block in HtmlBlocks(content)) {
            string text = ReplaceReferences(Headers.Collapse(block.Text.Replace('\n', ' '))).Trim(' ');
            if (text.Length > 0) lines.AddRange(Wrap(text, QuotePrefix(block.Depth)));
            else if (lines.Count > 0 && lines[^1].Length > 0) lines.Add("");
        }
        while (lines.Count > 0 && lines[^1].Length == 0) lines.RemoveAt(lines.Count - 1);
        return lines;
    }
    static Displayed Display(Entity entity) {
        if (entity.Subtype == "html") return new Displayed("html", Html(entity.Content));
        if (entity.Parameter("format").ToLowerInvariant() == "flowed") return new Displayed("flowed", Flowed(entity.Content, entity.Parameter("delsp").ToLowerInvariant() == "yes"));
        return new Displayed("plain", entity.Content.Length == 0 ? new() : entity.Content.Split('\n').ToList());
    }
    static (int Quoted, int Signature) LineCounts(List<string> lines) {
        int quoted = 0, signature = 0;
        for (int i = 0; i < lines.Count; i++) {
            string line = Headers.Rstrip(lines[i]);
            if (line.StartsWith('>')) quoted++;
            if (line == "--") signature = lines.Count - i - 1;
        }
        return (quoted, signature);
    }
    public static string ContainerNotation(Container container) {
        Message message = container.Message;
        if (message != null) return "[" + message.Number + "] " + DateNotation(message.Date) + " " + (message.Sender == null ? "-" : message.Sender.AddressText) + " " + SubjectNotation(message.Subject);
        return container.Subject == null ? "[missing] " + container.Id : "[subject] " + container.Subject;
    }
    static void CheckParentDates(List<Message> messages) {
        foreach (Message message in messages) if (message.Parent != null && message.Date.HasValue && message.Parent.Date.HasValue && message.Date.Value < message.Parent.Date.Value) message.Problem("dated before parent message " + message.Parent.Number);
    }
    static string SenderNotation(Mailbox sender) => sender == null ? "-" : sender.Name.Length == 0 ? sender.AddressText : sender.Name + " <" + sender.AddressText + ">";
    static void EntityLines(Entity entity, List<string> lines) {
        string line = "part " + entity.Number + " " + entity.Type + "/" + entity.Subtype;
        if (entity.Multipart()) {
            lines.Add(line);
            foreach (Entity child in entity.Children) EntityLines(child, lines);
        } else {
            line += " " + entity.Content.Length;
            if (entity.Disposition != null) line += " " + entity.Disposition;
            if (!string.IsNullOrEmpty(entity.Filename)) line += " \"" + entity.Filename + "\"";
            lines.Add(line);
        }
    }
    static List<string> MessageReport(Message message) {
        List<string> lines = ["message " + message.Number, "id " + (message.Id.Length == 0 ? "-" : message.Id), "date " + DateNotation(message.Date), "from " + SenderNotation(message.Sender),
            "to " + (message.To.Count == 0 ? "-" : string.Join(", ", message.To)), "cc " + (message.Cc.Count == 0 ? "-" : string.Join(", ", message.Cc)), "subject " + SubjectNotation(message.Subject),
            "refs " + (message.References.Count == 0 ? "-" : string.Join(" ", message.References)), "thread " + message.Thread + " depth " + message.Depth + " parent " + (message.Parent == null ? "-" : message.Parent.Number.ToString())];
        EntityLines(message.Body, lines);
        return lines;
    }
    static List<string> BodyReport(string request, Dictionary<string, Message> byId) {
        List<string> lines = ["request " + request];
        if (!byId.TryGetValue(request, out Message message)) { lines.Add("not found"); return lines; }
        List<Entity> parts = Collect(message.Body, true);
        lines.Add("message " + message.Number + " text parts " + parts.Count);
        foreach (Entity part in parts) {
            Displayed display = Display(part);
            var counts = LineCounts(display.Lines);
            lines.Add("part " + part.Number + " " + display.Format + " lines " + display.Lines.Count + " quoted " + counts.Quoted + " signature " + counts.Signature);
            foreach (string line in display.Lines) { string stripped = Headers.Rstrip(line); lines.Add(stripped.Length == 0 ? "|" : "| " + stripped); }
        }
        return lines;
    }
    static string Csv(string text) => text.Contains(',') || text.Contains('"') ? "\"" + text.Replace("\"", "\"\"") + "\"" : text;
    static List<string> SendersReport(List<Message> messages) {
        Dictionary<string, SenderStats> stats = new(StringComparer.Ordinal);
        foreach (Message message in messages) if (message.Sender != null) {
            string address = message.Sender.AddressText;
            if (!stats.TryGetValue(address, out SenderStats entry)) stats[address] = entry = new SenderStats(address);
            entry.Add(message);
        }
        List<string> lines = ["address,name,messages,threads,first,last"];
        foreach (SenderStats entry in stats.Values.OrderByDescending(entry => entry.Count).ThenBy(entry => entry.Address, StringComparer.Ordinal)) {
            string first = entry.First.HasValue ? Dates.Format(entry.First.Value) : "-", last = entry.Last.HasValue ? Dates.Format(entry.Last.Value) : "-";
            lines.Add(entry.Address + "," + Csv(entry.Name) + "," + entry.Count + "," + entry.Threads.Count + "," + first + "," + last);
        }
        return lines;
    }
    static List<string> Malformed(List<Message> messages) {
        int flagged = messages.Count(message => message.Problems.Count > 0), count = messages.Sum(message => message.Problems.Count);
        List<string> lines = ["messages " + messages.Count + " malformed " + flagged + " problems " + count];
        foreach (Message message in messages) foreach (string problem in message.Problems) lines.Add("message " + message.Number + ": " + problem);
        return lines;
    }
    static List<string> Blocks(IEnumerable<List<string>> blocks) {
        List<string> lines = new();
        foreach (List<string> block in blocks) { if (lines.Count > 0) lines.Add(""); lines.AddRange(block); }
        return lines;
    }
    static void Main() {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        List<Message> messages = new();
        Dictionary<string, int> knownIds = new(StringComparer.Ordinal);
        foreach (List<SourceLine> lines in MailboxLines(Read("mailbox.mbox"))) {
            Message message = new(messages.Count + 1); message.Process(lines, knownIds); messages.Add(message);
        }
        List<MailThread> threads = new();
        foreach (Container root in Threader.Build(messages)) threads.Add(new MailThread(threads.Count + 1, root));
        foreach (MailThread thread in threads) thread.PlaceMessages();
        CheckParentDates(messages);
        Dictionary<string, Message> byId = messages.Where(message => message.Id.Length > 0).ToDictionary(message => message.Id, StringComparer.Ordinal);
        List<string> requests = Read("requests.txt");
        Dictionary<string, List<string>> files = new() {
            ["threads.txt"] = Blocks(threads.Select(thread => thread.Report())), ["messages.txt"] = Blocks(messages.Select(MessageReport)),
            ["bodies.txt"] = Blocks(requests.Select(request => BodyReport(request, byId))), ["senders.csv"] = SendersReport(messages), ["malformed.txt"] = Malformed(messages)
        };
        Directory.CreateDirectory("output");
        foreach (var pair in files) File.WriteAllText(Path.Combine("output", pair.Key), string.Join("\n", pair.Value) + "\n", Encoding.ASCII);
    }
}
