import java.util.Locale

fun main() {
    val names = listOf("Aiko","Kenji","Mika","Ryo","Yuki")
    val heights = intArrayOf(158,172,165,180,150)
    val weights = intArrayOf(45,68,70,101,52)
    for (i in names.indices) {
        val bmi = (weights[i] * 10000).toDouble() / (heights[i] * heights[i])
        val category = when {
            bmi < 18.5 -> "underweight"
            bmi < 25 -> "normal"
            bmi < 30 -> "overweight"
            else -> "obese"
        }
        println("%s: BMI %.1f (%s)".format(Locale.ROOT, names[i], bmi, category))
    }
}
