#include "mail.hpp"
#include <stdexcept>

class AddressParser {
    const Tokens& tokens;
    std::size_t position = 0;
    bool encodingError = false;
    std::string peek() const { return position < tokens.size() ? tokens[position].kind : ""; }
    void expect(const std::string& kind) { if (peek() != kind) throw std::runtime_error("address"); ++position; }
    Tokens run(bool phrase) {
        Tokens result;
        while (peek() == "word" || peek() == "." || (phrase && peek() == "quoted")) result.push_back(tokens[position++]);
        return result;
    }
    std::string atom(const Tokens& sequence) const {
        if (sequence.size() % 2 == 0) throw std::runtime_error("address");
        std::string result;
        for (std::size_t i = 0; i < sequence.size(); ++i) { if (sequence[i].kind != (i % 2 ? "." : "word")) throw std::runtime_error("address"); result += sequence[i].text; }
        return result;
    }
    std::string displayName(const Tokens& phrase) {
        std::string result; bool previous = false;
        for (std::size_t i = 0; i < phrase.size(); ++i) {
            DecodedWord decoded{phrase[i].text, false, false};
            if (phrase[i].kind == "word") decoded = decodeWord(phrase[i].text);
            if (i && phrase[i].spaced && !(previous && decoded.decoded)) result += ' ';
            result += decoded.text; previous = decoded.decoded; encodingError = encodingError || decoded.error;
        }
        return collapse(result);
    }
    Address address(bool inGroup) {
        Tokens phrase = run(true);
        if (peek() == "<") {
            ++position; Tokens local = run(false); expect("@"); Tokens domain = run(false); expect(">");
            std::string mailbox = lower(atom(local) + '@' + atom(domain));
            return {false, {{displayName(phrase), mailbox}}};
        }
        if (peek() == "@") { ++position; Tokens domain = run(false); return {false, {{"", lower(atom(phrase) + '@' + atom(domain))}}}; }
        if (peek() == ":" && !phrase.empty() && !inGroup) {
            ++position; Address group; group.group = true;
            if (peek() != ";") {
                Address first = address(true); group.mailboxes.insert(group.mailboxes.end(), first.mailboxes.begin(), first.mailboxes.end());
                while (peek() == ",") { ++position; Address next = address(true); group.mailboxes.insert(group.mailboxes.end(), next.mailboxes.begin(), next.mailboxes.end()); }
            }
            expect(";"); return group;
        }
        throw std::runtime_error("address");
    }
public:
    explicit AddressParser(const Tokens& tokens) : tokens(tokens) {}
    AddressList parse() {
        AddressList result; result.addresses.push_back(address(false));
        while (peek() == ",") { ++position; result.addresses.push_back(address(false)); }
        if (position != tokens.size()) throw std::runtime_error("address");
        result.encodingError = encodingError; return result;
    }
};
std::optional<AddressList> parseAddressList(const std::string& value) {
    std::optional<Tokens> tokens = tokenize(value, false);
    if (!tokens || tokens->empty()) return std::nullopt;
    try { return AddressParser(*tokens).parse(); } catch (const std::runtime_error&) { return std::nullopt; }
}
