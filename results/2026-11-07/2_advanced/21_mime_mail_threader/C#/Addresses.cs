using System;
using System.Collections.Generic;
using System.Text;

abstract record Address;
sealed record Mailbox(string Name, string AddressText) : Address;
sealed record AddressGroup(List<Address> Mailboxes) : Address;
sealed record AddressList(List<Address> Addresses, bool EncodingError);
sealed class AddressFailure : Exception {}
sealed class Addresses {
    static readonly HashSet<string> Phrase = ["word", "quoted", "."], DotAtomKinds = ["word", "."];
    readonly List<Token> tokens;
    int position;
    bool encodingError;
    Addresses(List<Token> tokens) { this.tokens = tokens; }
    string Peek() => position < tokens.Count ? tokens[position].Kind : "";
    void Expect(string kind) { if (Peek() != kind) throw new AddressFailure(); position++; }
    List<Token> Run(HashSet<string> kinds) {
        int start = position;
        while (kinds.Contains(Peek())) position++;
        return tokens.GetRange(start, position - start);
    }
    static bool DotAtom(List<Token> tokens) {
        if (tokens.Count % 2 == 0) return false;
        for (int i = 0; i < tokens.Count; i++) if (tokens[i].Kind != (i % 2 == 0 ? "word" : ".")) return false;
        return true;
    }
    static string AddressString(List<Token> local, List<Token> domain) {
        if (!DotAtom(local) || !DotAtom(domain)) throw new AddressFailure();
        StringBuilder result = new();
        foreach (Token token in local) result.Append(token.Text);
        result.Append('@');
        foreach (Token token in domain) result.Append(token.Text);
        return result.ToString().ToLowerInvariant();
    }
    string DisplayName(List<Token> phrase) {
        StringBuilder result = new();
        bool previous = false;
        for (int i = 0; i < phrase.Count; i++) {
            Token token = phrase[i];
            DecodedWord decoded = token.Kind == "word" ? Headers.DecodeWord(token.Text) : new DecodedWord(token.Text, false, false);
            encodingError |= decoded.Error;
            if (i > 0 && token.Spaced && !(previous && decoded.Decoded)) result.Append(' ');
            result.Append(decoded.Text); previous = decoded.Decoded;
        }
        return Headers.Collapse(result.ToString());
    }
    Address ParseAddress(bool inGroup) {
        List<Token> phrase = Run(Phrase);
        string following = Peek();
        if (following == "<") {
            position++;
            List<Token> local = Run(DotAtomKinds);
            Expect("@");
            List<Token> domain = Run(DotAtomKinds);
            Expect(">");
            return new Mailbox(DisplayName(phrase), AddressString(local, domain));
        }
        if (following == "@") { position++; return new Mailbox("", AddressString(phrase, Run(DotAtomKinds))); }
        if (following == ":" && phrase.Count > 0 && !inGroup) {
            position++;
            List<Address> mailboxes = new();
            if (Peek() != ";") {
                mailboxes.Add(ParseAddress(true));
                while (Peek() == ",") { position++; mailboxes.Add(ParseAddress(true)); }
            }
            Expect(";");
            return new AddressGroup(mailboxes);
        }
        throw new AddressFailure();
    }
    List<Address> ParseList() {
        List<Address> addresses = [ParseAddress(false)];
        while (Peek() == ",") { position++; addresses.Add(ParseAddress(false)); }
        if (position != tokens.Count) throw new AddressFailure();
        return addresses;
    }
    public static AddressList Parse(string value) {
        List<Token> tokens = Headers.Tokenize(value, false);
        if (tokens == null || tokens.Count == 0) return null;
        Addresses parser = new(tokens);
        try { List<Address> addresses = parser.ParseList(); return new AddressList(addresses, parser.encodingError); }
        catch (AddressFailure) { return null; }
    }
}
