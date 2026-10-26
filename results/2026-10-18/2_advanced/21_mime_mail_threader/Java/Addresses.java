import java.util.ArrayList;
import java.util.List;
import java.util.Set;

sealed interface Address permits Mailbox, AddressGroup {}
record Mailbox(String name, String address) implements Address {}
record AddressGroup(List<Address> mailboxes) implements Address {}
record AddressList(List<Address> addresses, boolean encodingError) {}
final class AddressFailure extends RuntimeException {}
final class Addresses {
    static final Set<String> PHRASE = Set.of("word", "quoted", "."), DOT_ATOM = Set.of("word", ".");
    final List<Token> tokens;
    int position;
    boolean encodingError;
    Addresses(List<Token> tokens) { this.tokens = tokens; }
    String peek() { return position < tokens.size() ? tokens.get(position).kind() : ""; }
    void expect(String kind) { if (!peek().equals(kind)) throw new AddressFailure(); position++; }
    List<Token> run(Set<String> kinds) { int start = position; while (kinds.contains(peek())) position++; return tokens.subList(start, position); }
    static boolean dotAtom(List<Token> tokens) {
        if (tokens.size() % 2 == 0) return false;
        for (int i = 0; i < tokens.size(); i++) if (!tokens.get(i).kind().equals(i % 2 == 0 ? "word" : ".")) return false;
        return true;
    }
    static String addressString(List<Token> local, List<Token> domain) {
        if (!dotAtom(local) || !dotAtom(domain)) throw new AddressFailure();
        StringBuilder result = new StringBuilder(); for (Token token : local) result.append(token.text()); result.append('@'); for (Token token : domain) result.append(token.text());
        return Headers.lower(result.toString());
    }
    String displayName(List<Token> phrase) {
        StringBuilder result = new StringBuilder(); boolean previous = false;
        for (int i = 0; i < phrase.size(); i++) {
            Token token = phrase.get(i); DecodedWord decoded = token.kind().equals("word") ? Headers.decodeWord(token.text()) : new DecodedWord(token.text(), false, false);
            encodingError |= decoded.error();
            if (i > 0 && token.spaced() && !(previous && decoded.decoded())) result.append(' ');
            result.append(decoded.text()); previous = decoded.decoded();
        }
        return Headers.collapse(result.toString());
    }
    Address address(boolean inGroup) {
        List<Token> phrase = run(PHRASE); String following = peek();
        if (following.equals("<")) {
            position++; List<Token> local = run(DOT_ATOM); expect("@"); List<Token> domain = run(DOT_ATOM); expect(">");
            return new Mailbox(displayName(phrase), addressString(local, domain));
        }
        if (following.equals("@")) { position++; return new Mailbox("", addressString(phrase, run(DOT_ATOM))); }
        if (following.equals(":") && !phrase.isEmpty() && !inGroup) {
            position++; List<Address> mailboxes = new ArrayList<>();
            if (!peek().equals(";")) { mailboxes.add(address(true)); while (peek().equals(",")) { position++; mailboxes.add(address(true)); } }
            expect(";"); return new AddressGroup(mailboxes);
        }
        throw new AddressFailure();
    }
    List<Address> parseList() {
        List<Address> addresses = new ArrayList<>(); addresses.add(address(false));
        while (peek().equals(",")) { position++; addresses.add(address(false)); }
        if (position != tokens.size()) throw new AddressFailure();
        return addresses;
    }
    static AddressList parse(String value) {
        List<Token> tokens = Headers.tokenize(value, false);
        if (tokens == null || tokens.isEmpty()) return null;
        Addresses parser = new Addresses(tokens);
        try { List<Address> addresses = parser.parseList(); return new AddressList(addresses, parser.encodingError); }
        catch (AddressFailure failure) { return null; }
    }
}
