import java.io.File

data class Pixel(val x: Int, val y: Int)
data class Image(val name: String, val width: Int, val height: Int, val maxval: Int, val pixels: Array<IntArray>)
object PgmReader {
    fun lines(path: String) = File(path).readLines(Charsets.US_ASCII)
    fun read(path: String): List<Image> {
        val words = mutableListOf<String>()
        for (line in lines(path)) {
            val text = line.substringBefore('#').trim()
            if (text.isNotEmpty()) words.addAll(text.split(Regex(" +")))
        }
        val images = mutableListOf<Image>()
        var position = 0
        while (position < words.size) {
            val name = words[position + 1]
            val width = words[position + 3].toInt()
            val height = words[position + 4].toInt()
            val maxval = words[position + 5].toInt()
            position += 6
            val pixels = Array(height) { IntArray(width) }
            for (y in 0 until height) for (x in 0 until width) pixels[y][x] = words[position++].toInt()
            images.add(Image(name, width, height, maxval, pixels))
        }
        return images
    }
}
