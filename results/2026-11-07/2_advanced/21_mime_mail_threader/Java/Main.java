import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

record Sections(List<SourceLine> header, List<SourceLine> body) {}
record SortKey(int invalidDate, long seconds, String id, int number) implements Comparable<SortKey> {
    public int compareTo(SortKey other) {
        int result = Integer.compare(invalidDate, other.invalidDate);
        if (result == 0) result = Long.compare(seconds, other.seconds);
        if (result == 0) result = id.compareTo(other.id);
        return result == 0 ? Integer.compare(number, other.number) : result;
    }
}
final class Entity {
    final String number;
    String type = "text", subtype = "plain", disposition, filename, content = "";
    Map<String, String> parameters = new LinkedHashMap<>();
    List<Entity> children;
    Entity(String number) { this.number = number; }
    boolean multipart() { return children != null; }
    String parameter(String name) { return parameters.getOrDefault(name, ""); }
}
final class Message {
    final int number;
    final List<String> problems = new ArrayList<>();
    Mailbox sender;
    List<String> to = new ArrayList<>(), cc = new ArrayList<>(), references = new ArrayList<>();
    String subject = "", baseSubject = "", id = "";
    boolean reply;
    Long date;
    Entity body;
    SortKey sortKey;
    int thread, depth;
    Message parent;
    Message(int number) { this.number = number; }
    void problem(String text) { problems.add(text); }
    void process(List<SourceLine> lines, Map<String, Integer> knownIds) {
        Sections sections = Main.sections(lines); Header header = Headers.parseFields(sections.header());
        for (int line : header.invalid) problem("bad header line " + line);
        for (String name : Main.CHECKED_FIELDS) if (header.count(name) > 1) problem("duplicate " + name);
        readSender(header.value("From")); to = readRecipients(header.value("To"), "To"); cc = readRecipients(header.value("Cc"), "Cc");
        readSubject(header.value("Subject")); readDate(header.value("Date")); readId(header.value("Message-ID"), knownIds);
        references = Main.extractIds(header.value("References") == null ? "" : header.value("References"));
        List<String> replies = Main.extractIds(header.value("In-Reply-To") == null ? "" : header.value("In-Reply-To"));
        if (!replies.isEmpty() && (references.isEmpty() || !references.getLast().equals(replies.getFirst()))) references.add(replies.getFirst());
        boolean mime = mimeEnabled(header.value("MIME-Version")); body = parseEntity("1", header, sections.body(), mime);
        sortKey = new SortKey(date == null ? 1 : 0, date == null ? 0 : date, id, number);
    }
    void readSender(String value) {
        if (value == null) { problem("missing From"); return; }
        AddressList parsed = Addresses.parse(value);
        if (parsed == null || parsed.addresses().size() != 1 || !(parsed.addresses().getFirst() instanceof Mailbox)) { problem("bad From"); return; }
        sender = (Mailbox) parsed.addresses().getFirst(); if (parsed.encodingError()) problem("bad encoded word in From");
    }
    List<String> readRecipients(String value, String name) {
        List<String> recipients = new ArrayList<>(); if (value == null) return recipients;
        AddressList parsed = Addresses.parse(value);
        if (parsed == null) { problem("bad " + name); return recipients; }
        for (Address address : parsed.addresses()) {
            if (address instanceof Mailbox mailbox) recipients.add(mailbox.address());
            else for (Address member : ((AddressGroup) address).mailboxes()) recipients.add(((Mailbox) member).address());
        }
        if (parsed.encodingError()) problem("bad encoded word in " + name); return recipients;
    }
    void readSubject(String value) {
        DecodedText decoded = Headers.unstructured(value == null ? "" : value); subject = decoded.text(); if (decoded.error()) problem("bad encoded word in Subject");
        baseSubject = subject;
        while (baseSubject.length() >= 3 && Headers.lower(baseSubject.substring(0, 3)).equals("re:")) {
            baseSubject = baseSubject.substring(3); int start = 0; while (start < baseSubject.length() && baseSubject.charAt(start) == ' ') start++;
            baseSubject = baseSubject.substring(start); reply = true;
        }
    }
    void readDate(String value) {
        if (value == null) { problem("missing Date"); return; }
        DateResult parsed = Dates.parse(value); if (parsed.error() == null) date = parsed.seconds(); else problem(parsed.error());
    }
    void readId(String value, Map<String, Integer> known) {
        if (value == null) problem("missing Message-ID");
        else if (!Main.messageId(value)) problem("bad Message-ID");
        else if (known.containsKey(value)) problem("Message-ID already used by message " + known.get(value));
        else { id = value; known.put(value, number); }
    }
    boolean mimeEnabled(String value) {
        if (value == null) return false;
        String text = Headers.removeComments(value);
        if (text != null && text.replace(" ", "").replace("\t", "").equals("1.0")) return true;
        problem("bad MIME-Version"); return false;
    }
    Entity parseEntity(String number, Header header, List<SourceLine> lines, boolean mime) {
        Entity entity = new Entity(number); String contentType = header.value("Content-Type");
        if (mime && contentType != null) {
            Parameters parsed = Headers.parameters(contentType, true);
            if (parsed == null) problem("bad Content-Type in part " + number);
            else { entity.type = parsed.type(); entity.subtype = parsed.subtype(); entity.parameters = parsed.values(); }
        }
        String disposition = header.value("Content-Disposition");
        if (mime && disposition != null) {
            Parameters parsed = Headers.parameters(disposition, false);
            if (parsed == null) problem("bad Content-Disposition in part " + number);
            else { entity.disposition = parsed.type(); entity.filename = parsed.values().get("filename"); }
        }
        if (entity.filename == null || entity.filename.isEmpty()) entity.filename = entity.parameters.get("name");
        String charset = entity.parameters.get("charset");
        if (entity.type.equals("text") && charset != null && !Headers.lower(charset).equals("us-ascii")) problem("unsupported charset \"" + Headers.lower(charset) + "\" in part " + number);
        if (mime && entity.type.equals("multipart")) {
            String boundary = entity.parameter("boundary");
            if (!boundary.isEmpty()) { splitMultipart(entity, lines, boundary); return entity; }
            problem("missing boundary in part " + number);
        }
        decodeLeaf(entity, header, lines, mime); return entity;
    }
    void splitMultipart(Entity entity, List<SourceLine> lines, String boundary) {
        List<List<SourceLine>> parts = new ArrayList<>(); boolean closed = false;
        for (SourceLine line : lines) {
            String text = Headers.rstrip(line.text());
            if (text.equals("--" + boundary + "--")) { closed = true; break; }
            if (text.equals("--" + boundary)) parts.add(new ArrayList<>()); else if (!parts.isEmpty()) parts.getLast().add(line);
        }
        if (parts.isEmpty()) problem("no parts in part " + entity.number); else if (!closed) problem("unterminated multipart in part " + entity.number);
        entity.children = new ArrayList<>();
        for (int i = 0; i < parts.size(); i++) {
            Sections sections = Main.sections(parts.get(i)); Header header = Headers.parseFields(sections.header());
            for (int line : header.invalid) problem("bad header line " + line);
            entity.children.add(parseEntity(entity.number + "." + (i + 1), header, sections.body(), true));
        }
    }
    void decodeLeaf(Entity entity, Header header, List<SourceLine> lines, boolean mime) {
        String original = String.join("\n", lines.stream().map(SourceLine::text).toList());
        String transfer = header.value("Content-Transfer-Encoding"), encoding = mime && transfer != null ? Headers.lower(transfer) : "7bit";
        if (encoding.equals("base64")) { entity.content = Mime.base64Body(original); if (entity.content == null) { problem("bad base64 in part " + entity.number); entity.content = ""; } }
        else if (encoding.equals("quoted-printable")) { DecodedText decoded = Mime.quotedPrintable(original); entity.content = decoded.text(); if (decoded.error()) problem("bad quoted-printable in part " + entity.number); }
        else { entity.content = original; if (!List.of("7bit", "8bit", "binary").contains(encoding)) problem("unknown encoding \"" + encoding + "\" in part " + entity.number); }
    }
}
final class LogicalLine {
    final int depth;
    String text;
    boolean flowing;
    LogicalLine(int depth, String text, boolean flowing) { this.depth = depth; this.text = text; this.flowing = flowing; }
    LogicalLine(int depth, String text) { this(depth, text, false); }
}
record Displayed(String format, List<String> lines) {}
record ThreadEntry(Container container, String prefix, int depth) {}
final class MailThread {
    final int number;
    final Container root;
    final List<ThreadEntry> entries = new ArrayList<>();
    final List<Message> messages;
    MailThread(int number, Container root) { this.number = number; this.root = root; walk(root, "", "", 0); messages = entries.stream().map(entry -> entry.container().message).filter(message -> message != null).toList(); }
    void walk(Container container, String prefix, String stem, int depth) {
        entries.add(new ThreadEntry(container, prefix, depth));
        for (int i = 0; i < container.children.size(); i++) {
            boolean last = i + 1 == container.children.size(); walk(container.children.get(i), stem + (last ? "`- " : "+- "), stem + (last ? "   " : "|  "), depth + 1);
        }
    }
    void placeMessages() {
        for (ThreadEntry entry : entries) {
            Container container = entry.container(); Message message = container.message;
            if (message != null) { message.thread = number; message.depth = entry.depth(); message.parent = container.parent == null ? null : container.parent.message; }
        }
    }
    List<String> report() {
        int depth = entries.stream().mapToInt(ThreadEntry::depth).max().orElse(0); Set<String> senders = new HashSet<>(); List<Long> dates = new ArrayList<>();
        for (Message message : messages) { if (message.sender != null) senders.add(message.sender.address()); if (message.date != null) dates.add(message.date); }
        List<String> lines = new ArrayList<>(List.of("thread " + number + " messages " + messages.size() + " depth " + depth + " senders " + senders.size()));
        lines.add(dates.isEmpty() ? "span -" : "span " + Dates.format(Collections.min(dates)) + " .. " + Dates.format(Collections.max(dates)));
        lines.add("subject " + Main.subjectNotation(root.subject == null ? Threader.rootSubject(root) : root.subject));
        for (ThreadEntry entry : entries) lines.add(entry.prefix() + Main.containerNotation(entry.container())); return lines;
    }
}
final class SenderStats {
    final String address;
    int count;
    final Set<Integer> threads = new HashSet<>();
    Long first, last;
    String name = "";
    SenderStats(String address) { this.address = address; }
    void add(Message message) {
        count++; threads.add(message.thread);
        if (message.date != null) { if (first == null || message.date < first) first = message.date; if (last == null || message.date > last) last = message.date; }
        if (!message.sender.name().isEmpty()) name = message.sender.name();
    }
}
public class Main {
    static final List<String> CHECKED_FIELDS = List.of("From", "To", "Cc", "Subject", "Date", "Message-ID", "In-Reply-To", "References", "MIME-Version", "Content-Type", "Content-Transfer-Encoding", "Content-Disposition");
    static final Set<String> HIDDEN_TAGS = Set.of("head", "style", "script"), PARAGRAPH_TAGS = Set.of("p", "div", "ul", "ol", "table", "tr", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6");
    static final Map<String, String> CHARACTER_REFERENCES = Map.of("amp", "&", "lt", "<", "gt", ">", "quot", "\"", "apos", "'", "nbsp", " ");
    static List<String> read(String name) throws Exception { return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII); }
    static List<List<SourceLine>> mailbox(List<String> lines) {
        List<List<SourceLine>> messages = new ArrayList<>();
        for (int i = 0; i < lines.size(); i++) {
            String text = lines.get(i);
            if (text.startsWith("From ")) messages.add(new ArrayList<>());
            else if (!messages.isEmpty()) {
                int quotes = 0; while (quotes < text.length() && text.charAt(quotes) == '>') quotes++;
                if (quotes > 0 && text.substring(quotes).startsWith("From ")) text = text.substring(1);
                messages.getLast().add(new SourceLine(i + 1, text));
            }
        }
        for (List<SourceLine> message : messages) if (!message.isEmpty() && message.getLast().text().isEmpty()) message.removeLast();
        return messages;
    }
    static Sections sections(List<SourceLine> lines) { for (int i = 0; i < lines.size(); i++) if (lines.get(i).text().isEmpty()) return new Sections(lines.subList(0, i), lines.subList(i + 1, lines.size())); return new Sections(lines, List.of()); }
    static boolean messageId(String text) {
        if (text.length() < 3 || !text.startsWith("<") || !text.endsWith(">")) return false;
        String inside = text.substring(1, text.length() - 1);
        if (inside.chars().filter(letter -> letter == '@').count() != 1 || inside.startsWith("@") || inside.endsWith("@")) return false;
        return inside.chars().allMatch(letter -> letter >= 33 && letter <= 126 && "<>()\"\\".indexOf(letter) < 0);
    }
    static List<String> extractIds(String value) {
        List<String> ids = new ArrayList<>(); int start = value.indexOf('<');
        while (start >= 0) { int end = value.indexOf('>', start + 1); if (end < 0) break; String id = value.substring(start, end + 1); if (messageId(id)) ids.add(id); start = value.indexOf('<', end + 1); }
        return ids;
    }
    static String dateNotation(Long seconds) { return seconds == null ? "invalid" : Dates.format(seconds); }
    static String subjectNotation(String subject) { return subject.isEmpty() ? "(no subject)" : subject; }
    static List<Entity> collect(Entity entity, boolean allowHtml) {
        if (!entity.multipart()) return !"attachment".equals(entity.disposition) && entity.type.equals("text") && (entity.subtype.equals("plain") || entity.subtype.equals("html") && allowHtml) ? List.of(entity) : List.of();
        if (entity.subtype.equals("alternative")) { for (boolean html : new boolean[] {false, true}) for (Entity child : entity.children) { List<Entity> parts = collect(child, html); if (!parts.isEmpty()) return parts; } return List.of(); }
        List<Entity> parts = new ArrayList<>(); for (Entity child : entity.children) parts.addAll(collect(child, allowHtml)); return parts;
    }
    static String quotePrefix(int depth) { return depth > 0 ? ">".repeat(depth) + " " : ""; }
    static List<String> wrap(String text, String prefix) {
        List<String> lines = new ArrayList<>(); String current = "";
        for (String word : Headers.words(text)) {
            if (!current.isEmpty() && current.length() + 1 + word.length() > 72) { lines.add(prefix + current); current = word; }
            else current = current.isEmpty() ? word : current + " " + word;
        }
        lines.add(prefix + current); return lines;
    }
    static List<String> flowed(String content, boolean deleteSpace) {
        if (content.isEmpty()) return List.of(); List<LogicalLine> logical = new ArrayList<>();
        for (String line : content.split("\n", -1)) {
            int depth = 0; while (depth < line.length() && line.charAt(depth) == '>') depth++;
            String text = line.substring(depth); if (text.startsWith(" ")) text = text.substring(1);
            boolean flowing = text.endsWith(" ") && !text.equals("-- "); LogicalLine previous = logical.isEmpty() ? null : logical.getLast();
            if (previous != null && previous.flowing && previous.depth == depth) { if (deleteSpace) previous.text = previous.text.substring(0, previous.text.length() - 1); previous.text += text; previous.flowing = flowing; }
            else logical.add(new LogicalLine(depth, text, flowing));
        }
        List<String> lines = new ArrayList<>(); for (LogicalLine line : logical) lines.addAll(wrap(line.text, quotePrefix(line.depth))); return lines;
    }
    static boolean tagCharacter(char letter) { return letter >= 'A' && letter <= 'Z' || letter >= 'a' && letter <= 'z' || letter >= '0' && letter <= '9'; }
    static String tagName(String text) { int end = 0; while (end < text.length() && tagCharacter(text.charAt(end))) end++; return Headers.lower(text.substring(0, end)); }
    static String reference(String name) {
        if (CHARACTER_REFERENCES.containsKey(name)) return CHARACTER_REFERENCES.get(name);
        if (name.startsWith("#") && Dates.digits(name.substring(1), 1, 2, 3)) { int value = Integer.parseInt(name.substring(1)); if (value >= 32 && value <= 126) return "" + (char) value; }
        return null;
    }
    static String replaceReferences(String text) {
        StringBuilder result = new StringBuilder(); int position = 0;
        while (position < text.length()) {
            int end = text.charAt(position) == '&' ? text.indexOf(';', position + 1) : -1; String replacement = end < 0 ? null : reference(text.substring(position + 1, end));
            if (replacement == null) result.append(text.charAt(position++)); else { result.append(replacement); position = end + 1; }
        }
        return result.toString();
    }
    static List<LogicalLine> htmlBlocks(String content) {
        List<LogicalLine> blocks = new ArrayList<>(); int depth = 0, position = 0; StringBuilder text = new StringBuilder(); String hide = null;
        while (position < content.length()) {
            char letter = content.charAt(position); int close = letter == '<' ? content.indexOf('>', position + 1) : -1;
            if (close < 0) { if (hide == null) text.append(letter); position++; continue; }
            String inside = content.substring(position + 1, close); position = close + 1; boolean endTag = inside.startsWith("/"); String name = tagName(endTag ? inside.substring(1) : inside);
            if (hide != null) { if (endTag && name.equals(hide)) hide = null; }
            else if (!endTag && HIDDEN_TAGS.contains(name)) hide = name;
            else if (name.equals("br") || name.equals("li") && !endTag) { blocks.add(new LogicalLine(depth, text.toString())); text = new StringBuilder(name.equals("li") ? "* " : ""); }
            else if (PARAGRAPH_TAGS.contains(name)) {
                blocks.add(new LogicalLine(depth, text.toString())); blocks.add(new LogicalLine(depth, "")); text = new StringBuilder();
                if (name.equals("blockquote")) depth = endTag ? Math.max(0, depth - 1) : depth + 1;
            }
        }
        blocks.add(new LogicalLine(depth, text.toString())); return blocks;
    }
    static List<String> html(String content) {
        List<String> lines = new ArrayList<>();
        for (LogicalLine block : htmlBlocks(content)) {
            String text = replaceReferences(Headers.collapse(block.text.replace('\n', ' '))); int start = 0, end = text.length();
            while (start < end && text.charAt(start) == ' ') start++; while (end > start && text.charAt(end - 1) == ' ') end--; text = text.substring(start, end);
            if (!text.isEmpty()) lines.addAll(wrap(text, quotePrefix(block.depth))); else if (!lines.isEmpty() && !lines.getLast().isEmpty()) lines.add("");
        }
        while (!lines.isEmpty() && lines.getLast().isEmpty()) lines.removeLast(); return lines;
    }
    static Displayed display(Entity entity) {
        if (entity.subtype.equals("html")) return new Displayed("html", html(entity.content));
        if (Headers.lower(entity.parameter("format")).equals("flowed")) return new Displayed("flowed", flowed(entity.content, Headers.lower(entity.parameter("delsp")).equals("yes")));
        return new Displayed("plain", entity.content.isEmpty() ? List.of() : List.of(entity.content.split("\n", -1)));
    }
    static int[] lineCounts(List<String> lines) {
        int quoted = 0, signature = 0;
        for (int i = 0; i < lines.size(); i++) { String line = Headers.rstrip(lines.get(i)); if (line.startsWith(">")) quoted++; if (line.equals("--")) signature = lines.size() - i - 1; }
        return new int[] {quoted, signature};
    }
    static String containerNotation(Container container) {
        Message message = container.message;
        if (message != null) return "[" + message.number + "] " + dateNotation(message.date) + " " + (message.sender == null ? "-" : message.sender.address()) + " " + subjectNotation(message.subject);
        return container.subject == null ? "[missing] " + container.id : "[subject] " + container.subject;
    }
    static void checkParentDates(List<Message> messages) { for (Message message : messages) if (message.parent != null && message.date != null && message.parent.date != null && message.date < message.parent.date) message.problem("dated before parent message " + message.parent.number); }
    static String senderNotation(Mailbox sender) { return sender == null ? "-" : sender.name().isEmpty() ? sender.address() : sender.name() + " <" + sender.address() + ">"; }
    static void entityLines(Entity entity, List<String> lines) {
        String line = "part " + entity.number + " " + entity.type + "/" + entity.subtype;
        if (entity.multipart()) { lines.add(line); for (Entity child : entity.children) entityLines(child, lines); }
        else { line += " " + entity.content.length(); if (entity.disposition != null) line += " " + entity.disposition; if (entity.filename != null && !entity.filename.isEmpty()) line += " \"" + entity.filename + "\""; lines.add(line); }
    }
    static List<String> messageReport(Message message) {
        List<String> lines = new ArrayList<>(List.of("message " + message.number, "id " + (message.id.isEmpty() ? "-" : message.id), "date " + dateNotation(message.date), "from " + senderNotation(message.sender), "to " + (message.to.isEmpty() ? "-" : String.join(", ", message.to)), "cc " + (message.cc.isEmpty() ? "-" : String.join(", ", message.cc)), "subject " + subjectNotation(message.subject), "refs " + (message.references.isEmpty() ? "-" : String.join(" ", message.references)), "thread " + message.thread + " depth " + message.depth + " parent " + (message.parent == null ? "-" : message.parent.number)));
        entityLines(message.body, lines); return lines;
    }
    static List<String> bodyReport(String request, Map<String, Message> byId) {
        List<String> lines = new ArrayList<>(List.of("request " + request)); Message message = byId.get(request);
        if (message == null) { lines.add("not found"); return lines; }
        List<Entity> parts = collect(message.body, true); lines.add("message " + message.number + " text parts " + parts.size());
        for (Entity part : parts) {
            Displayed display = display(part); int[] counts = lineCounts(display.lines());
            lines.add("part " + part.number + " " + display.format() + " lines " + display.lines().size() + " quoted " + counts[0] + " signature " + counts[1]);
            for (String line : display.lines()) { String stripped = Headers.rstrip(line); lines.add(stripped.isEmpty() ? "|" : "| " + stripped); }
        }
        return lines;
    }
    static String csv(String text) { return text.indexOf(',') >= 0 || text.indexOf('"') >= 0 ? "\"" + text.replace("\"", "\"\"") + "\"" : text; }
    static List<String> sendersReport(List<Message> messages) {
        Map<String, SenderStats> stats = new HashMap<>();
        for (Message message : messages) if (message.sender != null) stats.computeIfAbsent(message.sender.address(), SenderStats::new).add(message);
        List<SenderStats> sorted = stats.values().stream().sorted(Comparator.comparingInt((SenderStats entry) -> entry.count).reversed().thenComparing(entry -> entry.address)).toList();
        List<String> lines = new ArrayList<>(List.of("address,name,messages,threads,first,last"));
        for (SenderStats entry : sorted) lines.add(entry.address + "," + csv(entry.name) + "," + entry.count + "," + entry.threads.size() + "," + (entry.first == null ? "-" : Dates.format(entry.first)) + "," + (entry.last == null ? "-" : Dates.format(entry.last))); return lines;
    }
    static List<String> malformed(List<Message> messages) {
        int flagged = 0, count = 0; for (Message message : messages) { if (!message.problems.isEmpty()) flagged++; count += message.problems.size(); }
        List<String> lines = new ArrayList<>(List.of("messages " + messages.size() + " malformed " + flagged + " problems " + count));
        for (Message message : messages) for (String problem : message.problems) lines.add("message " + message.number + ": " + problem); return lines;
    }
    static List<String> blocks(List<List<String>> blocks) {
        List<String> lines = new ArrayList<>(); for (List<String> block : blocks) { if (!lines.isEmpty()) lines.add(""); lines.addAll(block); } return lines;
    }
    public static void main(String[] args) throws Exception {
        List<Message> messages = new ArrayList<>(); Map<String, Integer> knownIds = new HashMap<>();
        for (List<SourceLine> lines : mailbox(read("mailbox.mbox"))) { Message message = new Message(messages.size() + 1); message.process(lines, knownIds); messages.add(message); }
        List<MailThread> threads = new ArrayList<>(); for (Container root : Threader.build(messages)) threads.add(new MailThread(threads.size() + 1, root));
        for (MailThread thread : threads) thread.placeMessages(); checkParentDates(messages);
        Map<String, Message> byId = new HashMap<>(); for (Message message : messages) if (!message.id.isEmpty()) byId.put(message.id, message);
        List<String> requests = read("requests.txt"); Map<String, List<String>> files = new LinkedHashMap<>();
        files.put("threads.txt", blocks(threads.stream().map(MailThread::report).toList())); files.put("messages.txt", blocks(messages.stream().map(Main::messageReport).toList())); files.put("bodies.txt", blocks(requests.stream().map(request -> bodyReport(request, byId)).toList())); files.put("senders.csv", sendersReport(messages)); files.put("malformed.txt", malformed(messages));
        Files.createDirectories(Path.of("output"));
        for (var entry : files.entrySet()) Files.writeString(Path.of("output", entry.getKey()), String.join("\n", entry.getValue()) + "\n", StandardCharsets.US_ASCII);
    }
}
