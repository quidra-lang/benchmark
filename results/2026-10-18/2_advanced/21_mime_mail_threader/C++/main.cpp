#include "mail.hpp"
#include <filesystem>
#include <fstream>
#include <functional>
#include <stdexcept>

static Lines readLines(const std::string& name) {
    std::ifstream file("input/" + name, std::ios::binary);
    if (!file) throw std::runtime_error("cannot read " + name);
    Lines result; std::string line;
    while (std::getline(file, line)) result.push_back(line);
    if (file.bad()) throw std::runtime_error("cannot read " + name);
    return result;
}
static std::vector<SourceLines> readMailbox() {
    std::vector<SourceLines> messages; Lines lines = readLines("mailbox.mbox");
    for (int i = 0; i < static_cast<int>(lines.size()); ++i) {
        std::string line = lines[i];
        if (line.substr(0, 5) == "From ") messages.push_back({});
        else {
            std::size_t prefix = 0; while (prefix < line.size() && line[prefix] == '>') ++prefix;
            if (prefix && line.substr(prefix, 5) == "From ") line.erase(0, 1);
            messages.back().push_back({i + 1, line});
        }
    }
    for (SourceLines& message : messages) if (!message.empty() && message.back().text.empty()) message.pop_back();
    return messages;
}
static std::pair<SourceLines, SourceLines> sections(const SourceLines& lines) {
    for (std::size_t i = 0; i < lines.size(); ++i) if (lines[i].text.empty()) return {SourceLines(lines.begin(), lines.begin() + i), SourceLines(lines.begin() + i + 1, lines.end())};
    return {lines, {}};
}
static bool validId(const std::string& id) {
    if (id.size() < 3 || id.front() != '<' || id.back() != '>') return false;
    std::string inside = id.substr(1, id.size() - 2);
    if (std::count(inside.begin(), inside.end(), '@') != 1 || inside.front() == '@' || inside.back() == '@') return false;
    for (char character : inside) if (character < 33 || character > 126 || std::string("<>()\"\\").find(character) != std::string::npos) return false;
    return true;
}
static Lines extractIds(const std::string& value) {
    Lines ids; std::size_t start = value.find('<');
    while (start != std::string::npos) { std::size_t end = value.find('>', start + 1); if (end == std::string::npos) break; std::string id = value.substr(start, end - start + 1); if (validId(id)) ids.push_back(id); start = value.find('<', end + 1); }
    return ids;
}
static std::string dateNotation(const std::optional<Integer>& date) { return date ? formatUtc(*date) : "invalid"; }
static std::string subjectNotation(const std::string& subject) { return subject.empty() ? "(no subject)" : subject; }
static void badHeaders(Message& message, const Header& header) { for (int line : header.invalid) add(message.problems, "bad header line ", line); }
static std::unique_ptr<Entity> parseEntity(Message& message, const std::string& number, const Header& header, const SourceLines& lines, bool mime) {
    std::unique_ptr<Entity> entity = std::make_unique<Entity>(); entity->number = number;
    std::optional<std::string> contentType = header.value("Content-Type"), disposition = header.value("Content-Disposition");
    if (mime && contentType) {
        std::optional<Parameters> parsed = parseParameters(*contentType, true);
        if (!parsed) add(message.problems, "bad Content-Type in part ", number);
        else { entity->type = parsed->type; entity->subtype = parsed->subtype; entity->parameters = parsed->values; }
    }
    if (mime && disposition) {
        std::optional<Parameters> parsed = parseParameters(*disposition, false);
        if (!parsed) add(message.problems, "bad Content-Disposition in part ", number);
        else { entity->disposition = parsed->type; std::map<std::string, std::string>::const_iterator filename = parsed->values.find("filename"); if (filename != parsed->values.end()) entity->filename = filename->second; }
    }
    if (entity->filename.empty()) entity->filename = entity->parameter("name");
    std::map<std::string, std::string>::const_iterator charset = entity->parameters.find("charset");
    if (entity->type == "text" && charset != entity->parameters.end() && lower(charset->second) != "us-ascii") add(message.problems, "unsupported charset \"", lower(charset->second), "\" in part ", number);
    if (mime && entity->type == "multipart") {
        std::string boundary = entity->parameter("boundary");
        if (boundary.empty()) add(message.problems, "missing boundary in part ", number);
        else {
            entity->multipart = true; std::vector<SourceLines> parts; bool closed = false;
            for (const SourceLine& line : lines) {
                std::string marker = stripTrailing(line.text);
                if (marker == "--" + boundary + "--") { closed = true; break; }
                if (marker == "--" + boundary) parts.push_back({});
                else if (!parts.empty()) parts.back().push_back(line);
            }
            if (parts.empty()) add(message.problems, "no parts in part ", number);
            else if (!closed) add(message.problems, "unterminated multipart in part ", number);
            for (std::size_t i = 0; i < parts.size(); ++i) {
                std::pair<SourceLines, SourceLines> divided = sections(parts[i]); Header partHeader = parseFields(divided.first); badHeaders(message, partHeader);
                entity->children.push_back(parseEntity(message, text(number, '.', i + 1), partHeader, divided.second, true));
            }
            return entity;
        }
    }
    Lines body; for (const SourceLine& line : lines) body.push_back(line.text);
    std::string original = join(body, "\n"), encoding = mime ? lower(header.value("Content-Transfer-Encoding").value_or("7bit")) : "7bit";
    if (encoding == "base64") { std::optional<std::string> decoded = decodeBase64Body(original); if (decoded) entity->content = *decoded; else add(message.problems, "bad base64 in part ", number); }
    else if (encoding == "quoted-printable") { std::pair<std::string, bool> decoded = decodeQuotedPrintable(original); entity->content = decoded.first; if (decoded.second) add(message.problems, "bad quoted-printable in part ", number); }
    else { entity->content = original; if (encoding != "7bit" && encoding != "8bit" && encoding != "binary") add(message.problems, "unknown encoding \"", encoding, "\" in part ", number); }
    return entity;
}
static Lines recipients(Message& message, const Header& header, const std::string& name) {
    std::optional<std::string> value = header.value(name); Lines result;
    if (!value) return result;
    std::optional<AddressList> parsed = parseAddressList(*value);
    if (!parsed) { add(message.problems, "bad ", name); return result; }
    for (const Address& address : parsed->addresses) for (const Mailbox& mailbox : address.mailboxes) result.push_back(mailbox.address);
    if (parsed->encodingError) add(message.problems, "bad encoded word in ", name);
    return result;
}
static Message processMessage(int number, const SourceLines& lines, std::map<std::string, int>& known) {
    Message message; message.number = number;
    std::pair<SourceLines, SourceLines> divided = sections(lines); Header header = parseFields(divided.first); badHeaders(message, header);
    const Lines checked{"From", "To", "Cc", "Subject", "Date", "Message-ID", "In-Reply-To", "References", "MIME-Version", "Content-Type", "Content-Transfer-Encoding", "Content-Disposition"};
    for (const std::string& name : checked) if (header.count(name) > 1) add(message.problems, "duplicate ", name);
    std::optional<std::string> from = header.value("From");
    if (!from) message.problems.push_back("missing From");
    else {
        std::optional<AddressList> parsed = parseAddressList(*from);
        if (!parsed || parsed->addresses.size() != 1 || parsed->addresses[0].group) message.problems.push_back("bad From");
        else { message.sender = parsed->addresses[0].mailboxes[0]; if (parsed->encodingError) message.problems.push_back("bad encoded word in From"); }
    }
    message.to = recipients(message, header, "To"); message.cc = recipients(message, header, "Cc");
    std::pair<std::string, bool> subject = decodeUnstructured(header.value("Subject").value_or("")); message.subject = subject.first;
    if (subject.second) message.problems.push_back("bad encoded word in Subject");
    message.baseSubject = message.subject;
    while (lower(message.baseSubject.substr(0, 3)) == "re:") { message.reply = true; message.baseSubject.erase(0, 3); while (!message.baseSubject.empty() && message.baseSubject[0] == ' ') message.baseSubject.erase(0, 1); }
    std::optional<std::string> date = header.value("Date");
    if (!date) message.problems.push_back("missing Date"); else { DateResult parsed = parseDate(*date); message.date = parsed.seconds; if (!parsed.seconds) message.problems.push_back(parsed.error); }
    std::optional<std::string> id = header.value("Message-ID");
    if (!id) message.problems.push_back("missing Message-ID");
    else if (!validId(*id)) message.problems.push_back("bad Message-ID");
    else if (known.count(*id)) add(message.problems, "Message-ID already used by message ", known.at(*id));
    else { message.id = *id; known[*id] = number; }
    message.references = extractIds(header.value("References").value_or("")); Lines replies = extractIds(header.value("In-Reply-To").value_or(""));
    if (!replies.empty() && (message.references.empty() || message.references.back() != replies[0])) message.references.push_back(replies[0]);
    bool mime = false; std::optional<std::string> version = header.value("MIME-Version");
    if (version) { std::optional<std::string> uncommented = removeComments(*version); std::string compact; if (uncommented) for (char character : *uncommented) if (!whitespace(character)) compact += character; if (uncommented && compact == "1.0") mime = true; else message.problems.push_back("bad MIME-Version"); }
    message.body = parseEntity(message, "1", header, divided.second, mime); return message;
}
static std::vector<const Entity*> collectText(const Entity& entity, bool html) {
    if (!entity.multipart) { if (entity.disposition != "attachment" && entity.type == "text" && (entity.subtype == "plain" || (entity.subtype == "html" && html))) return {&entity}; return {}; }
    if (entity.subtype == "alternative") {
        for (bool allow : {false, true}) for (const std::unique_ptr<Entity>& child : entity.children) { std::vector<const Entity*> found = collectText(*child, allow); if (!found.empty()) return found; }
        return {};
    }
    std::vector<const Entity*> result;
    for (const std::unique_ptr<Entity>& child : entity.children) { std::vector<const Entity*> found = collectText(*child, html); result.insert(result.end(), found.begin(), found.end()); }
    return result;
}
static std::string quotePrefix(int depth) { return depth ? std::string(depth, '>') + ' ' : ""; }
static Lines wrap(const std::string& value, const std::string& prefix) {
    Lines result; std::string current;
    for (const std::string& word : words(value)) { if (!current.empty() && current.size() + 1 + word.size() > 72) { result.push_back(prefix + current); current = word; } else { if (!current.empty()) current += ' '; current += word; } }
    result.push_back(prefix + current); return result;
}
static void extend(Lines& first, const Lines& second) { first.insert(first.end(), second.begin(), second.end()); }
struct LogicalLine { int depth; std::string text; bool flowing = false; };
static Lines flowedLines(const std::string& content, bool deleteSpace) {
    if (content.empty()) return {};
    std::vector<LogicalLine> logical;
    for (std::string line : split(content, '\n')) {
        int depth = 0; while (depth < static_cast<int>(line.size()) && line[depth] == '>') ++depth; line.erase(0, depth);
        if (!line.empty() && line[0] == ' ') line.erase(0, 1);
        bool flowing = !line.empty() && line.back() == ' ' && line != "-- ";
        if (!logical.empty() && logical.back().flowing && logical.back().depth == depth) { if (deleteSpace) logical.back().text.pop_back(); logical.back().text += line; logical.back().flowing = flowing; }
        else logical.push_back({depth, line, flowing});
    }
    Lines result; for (const LogicalLine& line : logical) extend(result, wrap(line.text, quotePrefix(line.depth))); return result;
}
static std::string replaceReferences(const std::string& value) {
    const std::map<std::string, std::string> names{{"amp", "&"}, {"lt", "<"}, {"gt", ">"}, {"quot", "\""}, {"apos", "'"}, {"nbsp", " "}};
    std::string result;
    for (std::size_t position = 0; position < value.size();) {
        std::optional<std::string> replacement; std::size_t end = std::string::npos;
        if (value[position] == '&') {
            end = value.find(';', position + 1);
            if (end != std::string::npos) {
                std::string name = value.substr(position + 1, end - position - 1); std::map<std::string, std::string>::const_iterator found = names.find(name);
                if (found != names.end()) replacement = found->second;
                else if (name.size() >= 2 && name.size() <= 4 && name[0] == '#') { bool valid = true; int number = 0; for (std::size_t i = 1; i < name.size(); ++i) { if (name[i] < '0' || name[i] > '9') { valid = false; break; } number = number * 10 + name[i] - '0'; } if (valid && number >= 32 && number <= 126) replacement = std::string(1, static_cast<char>(number)); }
            }
        }
        if (replacement) { result += *replacement; position = end + 1; } else result += value[position++];
    }
    return result;
}
static Lines htmlLines(const std::string& content) {
    const std::set<std::string> hidden{"head", "style", "script"}, paragraphs{"p", "div", "ul", "ol", "table", "tr", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6"};
    std::vector<LogicalLine> blocks; int depth = 0; std::string current, hide;
    for (std::size_t position = 0; position < content.size();) {
        char character = content[position]; std::size_t close = character == '<' ? content.find('>', position + 1) : std::string::npos;
        if (close == std::string::npos) { if (hide.empty()) current += character; ++position; continue; }
        std::string inside = content.substr(position + 1, close - position - 1); position = close + 1;
        bool ending = !inside.empty() && inside[0] == '/'; if (ending) inside.erase(0, 1);
        std::size_t length = 0; while (length < inside.size() && ((inside[length] >= 'A' && inside[length] <= 'Z') || (inside[length] >= 'a' && inside[length] <= 'z') || (inside[length] >= '0' && inside[length] <= '9'))) ++length;
        std::string name = lower(inside.substr(0, length));
        if (!hide.empty()) { if (ending && name == hide) hide.clear(); }
        else if (!ending && hidden.count(name)) hide = name;
        else if (name == "br" || (name == "li" && !ending)) { blocks.push_back({depth, current}); current = name == "li" ? "* " : ""; }
        else if (paragraphs.count(name)) { blocks.push_back({depth, current}); blocks.push_back({depth, ""}); current.clear(); if (name == "blockquote") depth = ending ? std::max(0, depth - 1) : depth + 1; }
    }
    blocks.push_back({depth, current}); Lines result;
    for (const LogicalLine& block : blocks) {
        std::string value = block.text; std::replace(value.begin(), value.end(), '\n', ' '); value = strip(replaceReferences(collapse(value)));
        if (!value.empty()) extend(result, wrap(value, quotePrefix(block.depth)));
        else if (!result.empty() && !result.back().empty()) result.push_back("");
    }
    while (!result.empty() && result.back().empty()) result.pop_back();
    return result;
}
static std::pair<std::string, Lines> displayLines(const Entity& entity) {
    if (entity.subtype == "html") return {"html", htmlLines(entity.content)};
    if (lower(entity.parameter("format")) == "flowed") return {"flowed", flowedLines(entity.content, lower(entity.parameter("delsp")) == "yes")};
    return {"plain", entity.content.empty() ? Lines{} : split(entity.content, '\n')};
}
struct Entry { Container* container; std::string prefix; int depth; };
static void walk(Container* container, const std::string& prefix, const std::string& stem, int depth, std::vector<Entry>& entries) {
    entries.push_back({container, prefix, depth});
    for (std::size_t i = 0; i < container->children.size(); ++i) { bool last = i + 1 == container->children.size(); walk(container->children[i], stem + (last ? "`- " : "+- "), stem + (last ? "   " : "|  "), depth + 1, entries); }
}
static Lines threadReport(int number, Container* root, std::vector<Message>& messages) {
    std::vector<Entry> entries; walk(root, "", "", 0, entries); int depth = 0, count = 0; std::set<std::string> senders; std::vector<Integer> dates;
    for (const Entry& entry : entries) {
        depth = std::max(depth, entry.depth);
        if (entry.container->message < 0) continue;
        ++count; Message& message = messages[entry.container->message]; message.thread = number; message.depth = entry.depth; message.parent = entry.container->parent ? entry.container->parent->message : -1;
        if (message.sender) senders.insert(message.sender->address);
        if (message.date) dates.push_back(*message.date);
    }
    Lines result{text("thread ", number, " messages ", count, " depth ", depth, " senders ", senders.size())};
    if (dates.empty()) result.push_back("span -"); else add(result, "span ", formatUtc(*std::min_element(dates.begin(), dates.end())), " .. ", formatUtc(*std::max_element(dates.begin(), dates.end())));
    add(result, "subject ", subjectNotation(root->subject ? *root->subject : rootSubject(root, messages)));
    for (const Entry& entry : entries) {
        Container* container = entry.container;
        if (container->message >= 0) { const Message& message = messages[container->message]; add(result, entry.prefix, '[', message.number, "] ", dateNotation(message.date), ' ', message.sender ? message.sender->address : "-", ' ', subjectNotation(message.subject)); }
        else if (container->subject) add(result, entry.prefix, "[subject] ", *container->subject);
        else add(result, entry.prefix, "[missing] ", container->id);
    }
    return result;
}
static void entityLines(const Entity& entity, Lines& lines) {
    std::string line = text("part ", entity.number, ' ', entity.type, '/', entity.subtype);
    if (entity.multipart) { lines.push_back(line); for (const std::unique_ptr<Entity>& child : entity.children) entityLines(*child, lines); return; }
    line += text(' ', entity.content.size()); if (!entity.disposition.empty()) line += ' ' + entity.disposition; if (!entity.filename.empty()) line += text(" \"", entity.filename, '"'); lines.push_back(line);
}
static Lines messageReport(const Message& message) {
    std::string sender = "-";
    if (message.sender) sender = message.sender->name.empty() ? message.sender->address : text(message.sender->name, " <", message.sender->address, '>');
    Lines lines{text("message ", message.number), text("id ", message.id.empty() ? "-" : message.id), text("date ", dateNotation(message.date)), "from " + sender, "to " + (message.to.empty() ? "-" : join(message.to, ", ")), "cc " + (message.cc.empty() ? "-" : join(message.cc, ", ")), "subject " + subjectNotation(message.subject), "refs " + (message.references.empty() ? "-" : join(message.references, " ")), text("thread ", message.thread, " depth ", message.depth, " parent ", message.parent < 0 ? "-" : std::to_string(message.parent + 1))};
    entityLines(*message.body, lines); return lines;
}
static Lines bodyReport(const std::string& request, const std::map<std::string, int>& byId, const std::vector<Message>& messages) {
    Lines lines{"request " + request}; std::map<std::string, int>::const_iterator found = byId.find(request);
    if (found == byId.end()) { lines.push_back("not found"); return lines; }
    const Message& message = messages[found->second]; std::vector<const Entity*> parts = collectText(*message.body, true); add(lines, "message ", message.number, " text parts ", parts.size());
    for (const Entity* part : parts) {
        std::pair<std::string, Lines> display = displayLines(*part); int quoted = 0, signature = 0;
        for (std::size_t i = 0; i < display.second.size(); ++i) { display.second[i] = stripTrailing(display.second[i]); if (!display.second[i].empty() && display.second[i][0] == '>') ++quoted; if (display.second[i] == "--") signature = static_cast<int>(display.second.size() - i - 1); }
        add(lines, "part ", part->number, ' ', display.first, " lines ", display.second.size(), " quoted ", quoted, " signature ", signature);
        for (const std::string& line : display.second) lines.push_back(line.empty() ? "|" : "| " + line);
    }
    return lines;
}
static std::string csvField(const std::string& value) { if (value.find_first_of(",\"") == std::string::npos) return value; std::string result = "\""; for (char character : value) { result += character; if (character == '"') result += '"'; } return result + '"'; }
static Lines senderReport(const std::vector<Message>& messages) {
    struct Stats { std::string address, name; int count = 0; std::set<int> threads; std::optional<Integer> first, last; };
    std::map<std::string, Stats> stats;
    for (const Message& message : messages) if (message.sender) {
        Stats& entry = stats[message.sender->address]; entry.address = message.sender->address; ++entry.count; entry.threads.insert(message.thread);
        if (message.date) { if (!entry.first || *message.date < *entry.first) entry.first = message.date; if (!entry.last || *message.date > *entry.last) entry.last = message.date; }
        if (!message.sender->name.empty()) entry.name = message.sender->name;
    }
    std::vector<Stats> sorted; for (const std::pair<const std::string, Stats>& entry : stats) sorted.push_back(entry.second);
    std::sort(sorted.begin(), sorted.end(), [](const Stats& first, const Stats& second) { return first.count != second.count ? first.count > second.count : first.address < second.address; });
    Lines lines{"address,name,messages,threads,first,last"};
    for (const Stats& entry : sorted) add(lines, entry.address, ',', csvField(entry.name), ',', entry.count, ',', entry.threads.size(), ',', entry.first ? formatUtc(*entry.first) : "-", ',', entry.last ? formatUtc(*entry.last) : "-");
    return lines;
}
static void block(Lines& target, const Lines& source) { if (!target.empty()) target.push_back(""); extend(target, source); }
static void writeLines(const std::string& name, const Lines& lines) { std::ofstream file("output/" + name, std::ios::binary); if (!file) throw std::runtime_error("cannot write " + name); for (const std::string& line : lines) file << line << '\n'; file.close(); if (!file) throw std::runtime_error("cannot write " + name); }
int main() {
    std::vector<Message> messages; std::map<std::string, int> known;
    for (const SourceLines& lines : readMailbox()) messages.push_back(processMessage(static_cast<int>(messages.size() + 1), lines, known));
    ThreadForest forest = buildThreads(messages); Lines threads, summaries, bodies; int thread = 0;
    for (Container* root : forest.roots) block(threads, threadReport(++thread, root, messages));
    int malformed = 0, problems = 0; std::map<std::string, int> byId;
    for (int index = 0; index < static_cast<int>(messages.size()); ++index) {
        Message& message = messages[index];
        if (message.parent >= 0 && message.date && messages[message.parent].date && *message.date < *messages[message.parent].date) add(message.problems, "dated before parent message ", messages[message.parent].number);
        malformed += !message.problems.empty(); problems += static_cast<int>(message.problems.size());
        if (!message.id.empty()) byId[message.id] = index;
        block(summaries, messageReport(message));
    }
    for (const std::string& request : readLines("requests.txt")) block(bodies, bodyReport(request, byId, messages));
    Lines errors{text("messages ", messages.size(), " malformed ", malformed, " problems ", problems)};
    for (const Message& message : messages) for (const std::string& problem : message.problems) add(errors, "message ", message.number, ": ", problem);
    std::filesystem::create_directories("output"); writeLines("threads.txt", threads); writeLines("messages.txt", summaries); writeLines("bodies.txt", bodies); writeLines("senders.csv", senderReport(messages)); writeLines("malformed.txt", errors);
}
