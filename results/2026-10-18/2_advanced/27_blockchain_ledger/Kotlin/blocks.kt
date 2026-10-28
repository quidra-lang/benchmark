class Block(val height: Int, val previous: String, val merkle: String, val timestamp: Int, val difficulty: Int, val nonce: Int, val transactions: List<Transaction>) {
    val hash = Hashing.digest(Blocks.header(height, previous, merkle, timestamp, difficulty, nonce))
    val size get() = transactions.drop(1).sumOf {
        it.size
    }
    val txids get() = transactions.map {
        it.txid
    }
}
object Blocks {
    fun header(height: Int, previous: String, merkle: String, timestamp: Int, difficulty: Int, nonce: Int): String = "$height|$previous|$merkle|$timestamp|$difficulty|$nonce"
    fun parse(fields: List<String>, texts: List<String>): Block = Block(fields[3].toInt(), fields[4], fields[5], fields[6].toInt(), fields[7].toInt(), fields[8].toInt(), texts.map(Transactions::parse))
    fun mine(height: Int, previous: String, transactions: List<Transaction>, timestamp: Int, difficulty: Int): Block {
        val merkle = Hashing.merkle(transactions.map {
            it.txid
        })
        var nonce = 0
        while (!Hashing.digest(header(height, previous, merkle, timestamp, difficulty, nonce)).startsWith("0".repeat(difficulty))) nonce++
        return Block(height, previous, merkle, timestamp, difficulty, nonce, transactions)
    }
    fun error(block: Block, maximum: Int): String? {
        if (!block.hash.startsWith("0".repeat(block.difficulty))) return "bad-pow"
        if (Hashing.merkle(block.txids) != block.merkle) return "bad-merkle"
        val first = block.transactions.first()
        if (!first.coinbase || first.coinbaseHeight != block.height || block.transactions.drop(1).any {
            it.coinbase
        }) return "bad-structure"
        return if (block.size > maximum) "too-large" else null
    }
}
