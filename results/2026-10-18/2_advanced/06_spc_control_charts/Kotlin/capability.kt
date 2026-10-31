import kotlin.math.sqrt

data class TargetSample(val number: Int, val subgroup: Int, val value: Long)
data class Capability(val values: Map<String, Double>, val samples: List<TargetSample>, val below: Int, val above: Int) {
    val verdict get() = when { values.getValue("cpk") >= 1.33 -> "capable"; values.getValue("cpk") >= 1.0 -> "marginal"; else -> "incapable" }
}

fun capability(ids: List<Int>, groups: List<Subgroup>, settings: Settings, constants: ControlConstants): Capability {
    val selected = ids.map { groups[it - 1] }
    val samples = selected.flatMap { group -> group.values.mapIndexed { index, value -> TargetSample((group.number - 1) * settings.size + index + 1, group.number, value) } }
    val count = samples.size
    val mean = samples.sumOf { it.value }.toDouble() / count.toDouble()
    val within = selected.sumOf { it.range }.toDouble() / selected.size.toDouble() / constants.d2
    val sbar = realSum(selected.map { it.sd }) / selected.size.toDouble() / constants.c4
    var squared = 0.0
    for (sample in samples) { val difference = sample.value.toDouble() - mean; squared += difference * difference }
    val overall = sqrt(squared / (count - 1).toDouble())
    val cp = (settings.usl - settings.lsl).toDouble() / (6.0 * within)
    val cpu = (settings.usl.toDouble() - mean) / (3.0 * within)
    val cpl = (mean - settings.lsl.toDouble()) / (3.0 * within)
    val cpk = minOf(cpu, cpl)
    val pp = (settings.usl - settings.lsl).toDouble() / (6.0 * overall)
    val ppu = (settings.usl.toDouble() - mean) / (3.0 * overall)
    val ppl = (mean - settings.lsl.toDouble()) / (3.0 * overall)
    val ppk = minOf(ppu, ppl)
    val offset = mean - settings.target.toDouble()
    val cpm = (settings.usl - settings.lsl).toDouble() / (6.0 * sqrt(overall * overall + offset * offset))
    val below = samples.count { it.value < settings.lsl }
    val above = samples.count { it.value > settings.usl }
    return Capability(linkedMapOf("mean" to mean, "sigma_within" to within, "sigma_sbar" to sbar, "sigma_overall" to overall, "cp" to cp, "cpu" to cpu, "cpl" to cpl, "cpk" to cpk, "pp" to pp, "ppu" to ppu, "ppl" to ppl, "ppk" to ppk, "cpm" to cpm, "ppm" to (1000000L * (below + above).toLong()).toDouble() / count.toDouble()), samples, below, above)
}

fun confidence(index: Double, count: Int, z: Double): Pair<Double, Double> {
    val delta = z * sqrt(1.0 / (9.0 * count.toDouble()) + index * index / (2.0 * (count - 1).toDouble()))
    return index - delta to index + delta
}

fun histogram(capability: Capability, settings: Settings): List<String> {
    val values = capability.samples.map { it.value }
    val low = settings.bin * (minOf(values.min(), settings.lsl) / settings.bin)
    val high = settings.bin * (maxOf(values.max(), settings.usl) / settings.bin) + settings.bin
    val counts = values.groupingBy { settings.bin * (it / settings.bin) }.eachCount()
    val top = counts.values.max()
    val lines = mutableListOf<String>()
    var start = low
    while (start < high) {
        val end = start + settings.bin - 1L
        val frequency = counts[start] ?: 0
        val length = (50 * frequency + top - 1) / top
        val parts = mutableListOf("bin", start.toString(), end.toString(), frequency.toString())
        if (length > 0) parts += "#".repeat(length)
        if (settings.lsl in start..end) parts += "lsl"
        if (settings.target in start..end) parts += "target"
        if (settings.usl in start..end) parts += "usl"
        lines += parts.joinToString(" ")
        start += settings.bin
    }
    return lines
}
