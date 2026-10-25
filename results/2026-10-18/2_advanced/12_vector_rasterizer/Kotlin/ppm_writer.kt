import java.io.File

fun writePPM(path: String, image: List<Color>, width: Int, height: Int) {
    val lines = listOf("P3", "$width $height", "255") + (0 until height).map { row -> image.subList(row * width, (row + 1) * width).joinToString(" ") { it.rgbText } }
    File(path).writeText(lines.joinToString("\n", postfix = "\n"))
}
fun writePreview(path: String, image: List<Color>, width: Int, height: Int) {
    val ramp = "@%#*+=-:,."
    val lines = (0 until height step 4).map { top -> (0 until width step 2).joinToString("") { left -> var total = 0; for (y in top until top + 4) for (x in left until left + 2) { val color = image[y * width + x]; total += 299 * color.red + 587 * color.green + 114 * color.blue }; ramp[(total / 8000) * 10 / 256].toString() } }
    File(path).writeText(lines.joinToString("\n", postfix = "\n"))
}
