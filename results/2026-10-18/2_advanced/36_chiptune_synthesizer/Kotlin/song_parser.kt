import java.nio.file.Files
import java.nio.file.Path
import java.nio.charset.StandardCharsets
import java.util.TreeMap
object SongParser {
    val pitches = listOf("C-","C#","D-","D#","E-","F-","F#","G-","G#","A-","A#","B-")
    fun hex(text: String) = text.toInt(16)
    fun note(text: String) = 12 * (text[2] - '0') + pitches.indexOf(text.substring(0,2))
    fun noteName(number: Int) = pitches[number % 12] + number / 12
    data class Effect(val text: String, val name: String, val argument: Int, val x: Int, val y: Int)
    fun effect(text: String): Effect {
        if (text == "...") return Effect(text,"",0,0,0);
        val argument = hex(text.substring(1));
        return Effect(text,if (text.startsWith("E")) text.substring(0,2) else text.substring(0,1),argument,argument / 16,argument % 16)
    }
    data class Cell(val note: Int, val instrument: Int, val volume: Int, val effect: Effect) {
        fun empty() = note == -2 && instrument == 0 && volume < 0 && effect.name.isEmpty()
    }
    fun cell(text: String): Cell {
        val noteText = text.substring(0,3);
        val instrument = text.substring(4,6);
        val volume = text.substring(7,8);
        return Cell(if (noteText == "...") -2 else if (noteText == "OFF") -1 else note(noteText),
            if (instrument == "..") 0 else hex(instrument),if (volume == ".") -1 else hex(volume),
            effect(text.substring(9)))
    }
    class Instrument {
        var number = 0;
        var name = "";
        var wave = "";
        var mode = 0;
        var attack = 0;
        var decay = 0;
        var sustain = 0;
        var release = 0;
        var vibratoDelay = -1;
        var vibratoSpeed = 0;
        var vibratoDepth = 0;
        var sweep = 0;
        var arpeggio = intArrayOf();
        var table = intArrayOf()
    }
    class Song {
        var title = "";
        var rate = 0;
        var speed = 0;
        var tempo = 0;
        var gain = 0;
        var order = intArrayOf();
        val instruments = TreeMap<Int,Instrument>();
        val patterns = TreeMap<Int,Array<Array<Cell>>>()
    }
    class Settings {
        val entries = mutableMapOf<String,List<String>>();
        val traces = mutableSetOf<Int>();
        fun integer(key: String) = entries.getValue(key)[0].toInt();
        fun numbers(key: String) = entries.getValue(key).map(String::toInt).toIntArray()
    }
    fun song(): Song {
        val lines = Files.readAllLines(Path.of("input/song.txt"),StandardCharsets.US_ASCII).filter {
            it.isNotEmpty() && !it.startsWith("#")
        };
        val song = Song();
        song.title = lines[0].substring(6);
        song.rate = lines[1].split(' ')[1].toInt();
        song.speed = lines[2].split(' ')[1].toInt();
        song.tempo = lines[3].split(' ')[1].toInt();
        song.gain = lines[4].split(' ')[1].toInt();
        var i = 5
        while (i < lines.size) {
            val parts = lines[i++].split(' ')
            if (parts[0] == "ORDER") song.order = parts.drop(1).map {
                hex(it)
            }.toIntArray()
            else if (parts[0] == "INSTRUMENT") {
                val instrument = Instrument();
                instrument.number = hex(parts[1]);
                instrument.name = parts[2]
                while (lines[i] != "END") {
                    val attributes = lines[i++].split(' ');
                    when (attributes[0]) {
                        "WAVE" -> {
                            instrument.wave = attributes[1];
                            if (instrument.wave == "PULSE") instrument.mode = listOf("12","25","50","75").indexOf(attributes[2]);
                            if (instrument.wave == "NOISE") instrument.mode = if (attributes[2] == "SHORT") 1 else 0;
                            if (instrument.wave == "TABLE") instrument.table = IntArray(32) {
                                hex(attributes[2].substring(it,it + 1))
                            }
                        }
                        "ENVELOPE" -> {
                            instrument.attack = attributes[1].toInt();
                            instrument.decay = attributes[2].toInt();
                            instrument.sustain = attributes[3].toInt();
                            instrument.release = attributes[4].toInt()
                        }
                        "VIBRATO" -> {
                            instrument.vibratoDelay = attributes[1].toInt();
                            instrument.vibratoSpeed = attributes[2].toInt();
                            instrument.vibratoDepth = attributes[3].toInt()
                        }
                        "ARPEGGIO" -> instrument.arpeggio = attributes.drop(1).map(String::toInt).toIntArray()
                        else -> instrument.sweep = attributes[1].toInt()
                    }
                };
                i++;
                song.instruments[instrument.number] = instrument
            } else {
                val number = hex(parts[1]);
                val pattern = Array(64) {
                    Array(4) {
                        cell("... .. . ...")
                    }
                };
                while (lines[i] != "END") {
                    val line = lines[i++];
                    val row = hex(line.substring(0,2));
                    val cells = line.substring(3).split(" | ");
                    for (channel in 0..3) pattern[row][channel] = cell(cells[channel])
                };
                i++;
                song.patterns[number] = pattern
            }
        }
        return song
    }
    fun settings(): Settings {
        val settings = Settings();
        for (line in Files.readAllLines(Path.of("input/params.txt"),StandardCharsets.US_ASCII)) {
            val parts = line.split(' ');
            if (parts[0] == "trace") settings.traces.add(hex(parts[1]) * 64 + hex(parts[2])) else settings.entries[parts[0]] = parts.drop(1)
        };
        return settings
    }
}
