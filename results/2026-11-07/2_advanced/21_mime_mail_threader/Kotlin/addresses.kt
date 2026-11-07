sealed interface Address
data class Mailbox(val name: String, val address: String) : Address
data class AddressGroup(val mailboxes: List<Address>) : Address
data class AddressList(val addresses: List<Address>, val encodingError: Boolean)
private class AddressFailure : RuntimeException()
class Addresses private constructor(private val tokens: List<Token>) {
    private var position = 0
    private var encodingError = false
    private fun peek() = tokens.getOrNull(position)?.kind ?: ""
    private fun expect(kind: String) { if (peek() != kind) throw AddressFailure(); position++ }
    private fun run(kinds: Set<String>): List<Token> {
        val start = position
        while (peek() in kinds) position++
        return tokens.subList(start, position)
    }
    private fun displayName(phrase: List<Token>): String {
        val result = StringBuilder()
        var previous = false
        for ((i, token) in phrase.withIndex()) {
            val decoded = if (token.kind == "word") Headers.decodeWord(token.text) else DecodedWord(token.text, false, false)
            encodingError = encodingError || decoded.error
            if (i > 0 && token.spaced && !(previous && decoded.decoded)) result.append(' ')
            result.append(decoded.text)
            previous = decoded.decoded
        }
        return Headers.collapse(result.toString())
    }
    private fun address(inGroup: Boolean): Address {
        val phrase = run(PHRASE)
        val following = peek()
        if (following == "<") {
            position++
            val local = run(DOT_ATOM)
            expect("@")
            val domain = run(DOT_ATOM)
            expect(">")
            return Mailbox(displayName(phrase), addressString(local, domain))
        }
        if (following == "@") { position++; return Mailbox("", addressString(phrase, run(DOT_ATOM))) }
        if (following == ":" && phrase.isNotEmpty() && !inGroup) {
            position++
            val mailboxes = mutableListOf<Address>()
            if (peek() != ";") {
                mailboxes.add(address(true))
                while (peek() == ",") { position++; mailboxes.add(address(true)) }
            }
            expect(";")
            return AddressGroup(mailboxes)
        }
        throw AddressFailure()
    }
    private fun parseList(): List<Address> {
        val addresses = mutableListOf(address(false))
        while (peek() == ",") { position++; addresses.add(address(false)) }
        if (position != tokens.size) throw AddressFailure()
        return addresses
    }
    companion object {
        private val PHRASE = setOf("word", "quoted", ".")
        private val DOT_ATOM = setOf("word", ".")
        private fun dotAtom(tokens: List<Token>) = tokens.size % 2 == 1 && tokens.indices.all { tokens[it].kind == (if (it % 2 == 0) "word" else ".") }
        private fun addressString(local: List<Token>, domain: List<Token>): String {
            if (!dotAtom(local) || !dotAtom(domain)) throw AddressFailure()
            return (local.joinToString("") { it.text } + "@" + domain.joinToString("") { it.text }).lowercase()
        }
        fun parse(value: String): AddressList? {
            val tokens = Headers.tokenize(value, false) ?: return null
            if (tokens.isEmpty()) return null
            val parser = Addresses(tokens)
            return try { val addresses = parser.parseList(); AddressList(addresses, parser.encodingError) } catch (failure: AddressFailure) { null }
        }
    }
}
