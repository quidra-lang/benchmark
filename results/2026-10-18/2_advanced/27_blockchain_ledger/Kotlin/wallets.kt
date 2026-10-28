import java.nio.file.Files
import java.nio.file.Path

data class Wallet(val name: String, val secret: String, val address: String)

object Wallets {
    fun address(secret: String): String = Hashing.digest("addr:$secret").take(16)
    fun sign(secret: String, index: Int, body: String): String = Hashing.digest("$secret:$index:$body").take(16)
    fun read(): List<Wallet> = Files.readAllLines(Path.of("input/wallets.txt")).map {
        val fields = it.split(" ")
        Wallet(fields[0], fields[1], address(fields[1]))
    }
}
