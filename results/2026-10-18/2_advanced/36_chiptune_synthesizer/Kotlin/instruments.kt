object Instruments {
    val tones = intArrayOf(26163,27718,29366,31113,32963,34923,36999,39200,41530,44000,46616,49388)
    val sine = intArrayOf(0,24,49,74,97,120,141,161,180,197,212,224,235,244,250,253,255,253,250,244,235,224,212,197,180,161,141,120,97,74,49,24)
    fun floor(value: Long, divisor: Long) = Math.floorDiv(value,divisor)
    fun clamp(value: Long, low: Long, high: Long) = minOf(maxOf(value,low),high)
    fun frequency(note: Int): Long {
        val octave = note / 12;
        val pitch = note % 12;
        return if (octave >= 4) tones[pitch].toLong() * (1L shl (octave - 4)) else tones[pitch] / (1L shl (4 - octave))
    }
    fun transpose(frequency: Long, semitones: Int) = frequency * tones[semitones % 12] / tones[0] * (1L shl (semitones / 12))
    fun oscillate(position: Int, depth: Int, divisor: Int): Int {
        val value = sine[position % 32] * depth / divisor;
        return if (position < 32) value else -value
    }
    fun envelope(instrument: SongParser.Instrument, age: Int, off: Boolean, releaseAge: Int, releaseValue: Int): Int {
        if (off) {
            val w = age - releaseAge;
            return if (w < instrument.release) releaseValue * (instrument.release - 1 - w) / instrument.release else 0
        };
        if (age < instrument.attack) return 15 * (age + 1) / instrument.attack;
        if (age < instrument.attack + instrument.decay) return 15 - (15 - instrument.sustain) * (age - instrument.attack + 1) / instrument.decay;
        return instrument.sustain
    }
    fun wave(instrument: SongParser.Instrument, mode: Int, phase: Int, shift: Int): Int = when (instrument.wave) {
        "PULSE" -> if (phase / 8192 < intArrayOf(1,2,4,6)[mode]) 15 else 0;
        "TRIANGLE" -> if (phase / 2048 < 16) 15 - phase / 2048 else phase / 2048 - 16;
        "SAW" -> phase / 4096;
        "TABLE" -> instrument.table[phase / 2048];
        else -> if (shift % 2 == 0) 15 else 0
    }
    fun clock(shift: Int, mode: Int): Int {
        val bit = (shift and 1) xor ((shift shr if (mode == 0) 1 else 6) and 1);
        return shift / 2 + bit * 16384
    }
}
