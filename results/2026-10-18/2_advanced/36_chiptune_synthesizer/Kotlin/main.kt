import java.nio.file.Files
import java.nio.file.Path
import java.nio.charset.StandardCharsets
import kotlin.math.abs
val effectOrder = listOf("0","1","2","3","4","5","6","7","A","B","C","D","E1","E2","E9","EA","EB","EC","ED","EE","F","P","Q","R","V")
val tonics = listOf("C","C#","D","D#","E","F","F#","G","G#","A","A#","B")
val major = intArrayOf(64,22,35,23,44,41,25,52,24,37,23,29);
val minor = intArrayOf(64,27,35,54,27,35,25,48,40,27,34,32)
class Channel {
    var instrument: SongParser.Instrument? = null;
    var note = -1;
    var portamentoSpeed = 0;
    var slideSpeed = 0;
    var detune = 0;
    var vibratoSpeed = 0;
    var vibratoDepth = 0;
    var vibratoPosition = 0;
    var tremoloSpeed = 0;
    var tremoloDepth = 0;
    var tremoloPosition = 0;
    var volume = 15;
    var mode = 0;
    var phase = 0;
    var shift = 1;
    var age = 0;
    var releaseAge = 0;
    var releaseValue = 0;
    var envelope = 0;
    var outputVolume = 0;
    var amplitude = 0;
    var increment = 0;
    var frequency = 0L;
    var target = 0L;
    var outputFrequency = 0L;
    var off = false;
    var sounding = false;
    var effect = SongParser.effect("...");
    var cell = SongParser.cell("... .. . ...");
    var record: Note? = null
}
class Note(val serial: Int, val channel: Int, val position: Int, val row: Int, val instrument: Int, val note: Int, val start: Int) {
    var length = 0;
    var release = -1;
    var reason = ""
}
data class Row(val position: Int, val row: Int, val start: Int, val speed: Int, val tempo: Int, val notes: IntArray)
fun output(c: Channel, tick: Int, rate: Int) {
    c.sounding = c.note >= 0;
    if (!c.sounding) return
    val instrument = c.instrument!!;
    var semitones = if (c.effect.name == "0") {
        when (tick % 3) {
            1 -> c.effect.x;
            2 -> c.effect.y;
            else -> 0
        }
    } else 0
    if (instrument.arpeggio.isNotEmpty()) semitones += instrument.arpeggio[c.age % instrument.arpeggio.size]
    var frequency = Instruments.transpose(c.frequency,semitones) + c.detune
    if (c.effect.name in listOf("4","6")) frequency += Instruments.oscillate(c.vibratoPosition,c.vibratoDepth,4)
    if (instrument.vibratoDelay >= 0 && c.age >= instrument.vibratoDelay) frequency += Instruments.oscillate((c.age - instrument.vibratoDelay) * instrument.vibratoSpeed % 64,instrument.vibratoDepth,4)
    c.outputFrequency = Instruments.clamp(frequency,1000,50L * rate);
    c.envelope = Instruments.envelope(instrument,c.age,c.off,c.releaseAge,c.releaseValue);
    c.outputVolume = if (c.effect.name == "7") Instruments.clamp((c.volume + Instruments.oscillate(c.tremoloPosition,c.tremoloDepth,255)).toLong(),0,15).toInt() else c.volume;
    c.amplitude = c.envelope * c.outputVolume;
    c.increment = (c.outputFrequency * 65536 / (100L * rate)).toInt()
}
class Player(val song: SongParser.Song, val settings: SongParser.Settings) {
    val channels = Array(4) {
        Channel()
    };
    val mixer = Mixer(settings.integer("max_samples"),4,song.gain,settings.numbers("mute"));
    val notes = mutableListOf<Note>();
    val rows = mutableListOf<Row>();
    val warnings = mutableListOf<String>();
    val log = mutableListOf<String>();
    val retriggers = LongArray(4);
    val cuts = LongArray(4);
    val active = LongArray(4);
    val audible = LongArray(4);
    val instrumentTicks = mutableMapOf<Int,Long>();
    val effects = mutableMapOf<String,Int>();
    var position = 0;
    var row = 0;
    var speed = song.speed;
    var tempo = song.tempo;
    var delay = 0;
    var ticks = 0;
    var reason = "finished";
    var loopStart = -1
    fun warning(channel: Int, message: String) {
        warnings.add("warning ${Report.hex2(position)}:${Report.hex2(row)} ch${channel + 1} $message")
    }
    fun finish(channel: Channel, reason: String) {
        channel.record?.let {
            it.length = mixer.size - it.start;
            it.reason = reason
        };
        channel.record = null
    }
    fun noteOn(index: Int, note: Int) {
        val c = channels[index];
        finish(c,"next");
        c.frequency = Instruments.frequency(note);
        c.target = c.frequency;
        c.phase = 0;
        c.age = 0;
        c.vibratoPosition = 0;
        c.tremoloPosition = 0;
        c.off = false;
        c.note = note;
        val record = Note(notes.size + 1,index + 1,position,row,c.instrument!!.number,note,mixer.size);
        notes.add(record);
        c.record = record
    }
    fun content(index: Int, portamento: Boolean) {
        val c = channels[index];
        val cell = c.cell
        if (cell.instrument != 0) {
            val instrument = song.instruments[cell.instrument];
            if (instrument == null) warning(index,"undefined instrument ${Report.hex2(cell.instrument)}") else {
                c.instrument = instrument;
                c.volume = 15;
                c.mode = instrument.mode
            }
        }
        if (cell.volume >= 0) c.volume = cell.volume
        if (cell.note == -1) {
            if (c.note >= 0 && !c.off) {
                c.off = true;
                c.releaseAge = c.age;
                c.releaseValue = c.envelope;
                c.record?.let {
                    it.release = mixer.size - it.start
                }
            } else warning(index,"key off without note")
        }
        else if (cell.note >= 0) {
            if (c.instrument == null) warning(index,"note without instrument") else if (portamento && c.note >= 0) {
                c.target = Instruments.frequency(cell.note);
                c.note = cell.note
            } else {
                if (portamento && c.note < 0) warning(index,"portamento without note");
                noteOn(index,cell.note)
            }
        }
    }
    fun tickZero(index: Int) {
        val c = channels[index];
        val e = c.effect;
        val argument = e.argument;
        val x = e.x;
        val y = e.y
        when (e.name) {
            "3" -> if (argument > 0) c.portamentoSpeed = argument
            "4" -> {
                if (x > 0) c.vibratoSpeed = x;
                if (y > 0) c.vibratoDepth = y
            }
            "7" -> {
                if (x > 0) c.tremoloSpeed = x;
                if (y > 0) c.tremoloDepth = y
            }
            "C" -> c.volume = minOf(argument,15)
            "E1" -> c.frequency = Instruments.clamp(c.frequency + 10 * y,1000,50L * song.rate)
            "E2" -> c.frequency = Instruments.clamp(c.frequency - 10 * y,1000,50L * song.rate)
            "EA" -> c.volume = minOf(c.volume + y,15)
            "EB" -> c.volume = maxOf(c.volume - y,0)
            "EE" -> delay = y
            "F" -> if (argument in 1..31) speed = argument else if (argument >= 32) tempo = argument
            "P" -> c.detune = argument - 128
            "Q","R" -> if (c.note < 0) warning(index,"slide without note") else {
                c.note = if (e.name == "Q") minOf(c.note + y,95) else maxOf(c.note - y,12);
                c.target = Instruments.frequency(c.note);
                c.slideSpeed = 2 * x + 1
            }
            "V" -> {
                val instrument = c.instrument;
                if (instrument != null && (instrument.wave == "PULSE" && argument <= 3 || instrument.wave == "NOISE" && argument <= 1)) c.mode = argument else warning(index,"invalid mode ${Report.hex2(argument)}")
            }
        }
    }
    fun startRow(cells: Array<SongParser.Cell>): Int {
        delay = 0;
        for (i in 0..3) {
            val c = channels[i];
            c.cell = cells[i];
            c.effect = cells[i].effect;
            c.slideSpeed = 0;
            if (c.effect.name.isNotEmpty()) effects[c.effect.name] = effects.getOrDefault(c.effect.name,0) + 1;
            if (c.effect.name != "ED" || c.effect.y == 0) content(i,c.effect.name in listOf("3","5"));
            tickZero(i)
        };
        val count = speed * (1 + delay);
        for (i in 0..3) {
            val e = channels[i].effect;
            if (e.name == "EC" && e.y >= count) warning(i,"cut beyond row");
            if (e.name == "ED" && e.y >= count) warning(i,"delay beyond row")
        };
        return count
    }
    fun approach(c: Channel, step: Int) {
        c.frequency = if (c.frequency < c.target) minOf(c.frequency + step,c.target) else maxOf(c.frequency - step,c.target)
    }
    fun tick(tick: Int) {
        for (i in 0..3) {
            val c = channels[i];
            val e = c.effect;
            val name = e.name
            if (c.note >= 0 && c.age >= 1 && c.instrument!!.sweep != 0) c.frequency = Instruments.clamp(c.frequency + 10 * c.instrument!!.sweep,1000,50L * song.rate)
            if (tick >= 1) {
                if (name == "1") c.frequency = Instruments.clamp(c.frequency + 10 * e.argument,1000,50L * song.rate) else if (name == "2") c.frequency = Instruments.clamp(c.frequency - 10 * e.argument,1000,50L * song.rate);
                if (name in listOf("3","5")) approach(c,10 * c.portamentoSpeed);
                if (name in listOf("Q","R") && c.slideSpeed != 0) approach(c,10 * c.slideSpeed);
                if (name in listOf("5","6","A")) c.volume = Instruments.clamp((c.volume + e.x - e.y).toLong(),0,15).toInt()
            }
            if (name == "ED" && e.y >= 1 && tick == e.y) content(i,false)
            if (name == "E9" && e.y >= 1 && tick >= 1 && tick % e.y == 0 && c.note >= 0) {
                c.phase = 0;
                c.age = 0;
                c.off = false;
                retriggers[i]++
            }
            if (name == "EC" && tick == e.y && c.note >= 0) {
                finish(c,"cut");
                c.note = -1;
                cuts[i]++
            }
            output(c,tick,song.rate);
            if (c.sounding) {
                active[i]++;
                if (c.amplitude > 0) audible[i]++;
                val instrument = c.instrument!!.number;
                instrumentTicks[instrument] = instrumentTicks.getOrDefault(instrument,0L) + 1
            }
        }
    }
    fun channelText(c: Channel) = if (c.note < 0) "--- --       - - ${Report.hex1(c.volume)} ${c.effect.text}" else "${SongParser.noteName(c.note)} ${Report.hex2(c.instrument!!.number)} ${Report.aligned(c.outputFrequency,7)} ${Report.hex1(c.envelope)} ${Report.hex1(c.outputVolume)} ${c.effect.text}"
    fun tickText(c: Channel) = if (c.sounding) "${Report.aligned(c.outputFrequency,7)} ${Report.aligned(c.increment,5)} ${Report.hex1(c.envelope)}${Report.hex1(c.outputVolume)}" else "      -     - --"
    fun play() {
        val counts = IntArray(song.order.size * 64);
        val first = IntArray(counts.size) {
            -1
        };
        var done = false
        while (!done) {
            var key = position * 64 + row;
            if (first[key] < 0) first[key] = mixer.size;
            counts[key]++;
            val cells = song.patterns.getValue(song.order[position])[row];
            val start = mixer.size;
            val count = startRow(cells);
            val spt = Sequencer.samplesPerTick(song.rate,tempo)
            for (t in 0 until count) {
                tick(t);
                if (t == 0) {
                    val pitches = IntArray(4) {
                        channels[it].note
                    };
                    val text = "${Report.hex2(position)} ${Report.hex2(song.order[position])} ${Report.hex2(row)} ${Report.aligned(start,7)} ${Report.aligned(speed,2)} ${Report.aligned(tempo,3)}" + channels.joinToString("") {
                        " | ${channelText(it)}"
                    };
                    log.add(text);
                    rows.add(Row(position,row,start,speed,tempo,pitches))
                };
                if (key in settings.traces) log.add("  tick ${Report.aligned(t,3)} ${Report.aligned(mixer.size,7)}" + channels.joinToString("") {
                    " | ${tickText(it)}"
                });
                mixer.generate(channels,minOf(spt,settings.integer("max_samples") - mixer.size));
                ticks++
                for (c in channels) {
                    if (c.note >= 0) c.age++;
                    if (c.effect.name in listOf("4","6")) c.vibratoPosition = (c.vibratoPosition + c.vibratoSpeed) % 64;
                    if (c.effect.name == "7") c.tremoloPosition = (c.tremoloPosition + c.tremoloSpeed) % 64
                }
                if (mixer.size == settings.integer("max_samples")) {
                    reason = "limit";
                    done = true;
                    break
                }
            }
            if (done) break
            if (cells.any {
                it.effect.name == "F" && it.effect.argument == 0
            }) {
                reason = "stop order=${Report.hex2(position)} row=${Report.hex2(row)}";
                break
            }
            val next = Sequencer.next(position,row,cells,song.order.size);
            if (next == null) {
                reason = "finished";
                break
            };
            key = next.order * 64 + next.row
            if (counts[key] >= settings.integer("loops")) {
                loopStart = first[key];
                reason = "loop order=${Report.hex2(next.order)} row=${Report.hex2(next.row)}";
                break
            };
            position = next.order;
            row = next.row
        }
        for (channel in channels) finish(channel,"end");
        if ((reason == "limit" || reason.startsWith("loop")) && settings.integer("fade") > 0) mixer.fade(settings.integer("fade"))
    }
}
fun noteLines(p: Player): List<String> {
    val result = mutableListOf<String>();
    for (note in p.notes) {
        var peak = 0;
        var cycles = 0;
        val lane = p.mixer.lanes[note.channel - 1];
        for (i in note.start until note.start + note.length) {
            peak = maxOf(peak,abs(lane[i]));
            if (i > note.start && lane[i - 1] < 0 && lane[i] >= 0) cycles++
        };
        result.add("${Report.aligned(note.serial,4)} ch=${note.channel} at=${Report.hex2(note.position)}:${Report.hex2(note.row)} ins=${Report.hex2(note.instrument)} note=${SongParser.noteName(note.note)} start=${note.start} length=${note.length} release=${if (note.release < 0) "-" else note.release.toString()} end=${note.reason} peak=$peak cycles=$cycles")
    };
    return result
}
fun rollLines(p: Player): List<String> {
    val options = p.settings.numbers("roll");
    val rows = p.rows.drop(options[0]).take(options[1]);
    val pitches = rows.flatMap {
        it.notes.toList()
    }.filter {
        it >= 0
    }.distinct().sortedDescending();
    val result = mutableListOf("ROLL start=${options[0]} rows=${rows.size} pitches=${pitches.size}");
    for (note in pitches) {
        val text = rows.joinToString("") {
            row -> val channels = row.notes.indices.filter {
                row.notes[it] == note
            };
            if (channels.isEmpty()) " " else if (channels.size == 1) (channels[0] + 1).toString() else "*"
        };
        result.add("${SongParser.noteName(note)} |$text|")
    };
    result.add("    +" + rows.indices.joinToString("") {
        if (it % 16 == 0) "+" else "-"
    }
    + "+");
    return result
}
fun records(p: Player, channel: Int, instrument: Int) = p.notes.filter {
    (channel == 0 || it.channel == channel) && (instrument == 0 || it.instrument == instrument)
}
fun range(records: List<Note>) = if (records.isEmpty()) "none" else SongParser.noteName(records.minOf {
    it.note
}) + ".." + SongParser.noteName(records.maxOf {
    it.note
})
fun numbers(numbers: List<Int>) = if (numbers.isEmpty()) "none" else numbers.joinToString(" ") {
    Report.hex2(it)
}
fun keyName(key: Int) = tonics[key % 12] + if (key < 12) " major" else " minor"
fun statsLines(p: Player): List<String> {
    val song = p.song;
    val mixer = p.mixer;
    val n = mixer.size;
    val stats = Report.statistics(mixer.samples,0,n,128);
    val result = mutableListOf("title=${song.title}","rate=${song.rate}","samples=$n","duration_ms=${n.toLong() * 1000 / song.rate}","end=${p.reason}","loop_start=${if (p.loopStart < 0) "-" else p.loopStart.toString()}","loop_length=${if (p.loopStart < 0) "-" else (n - p.loopStart).toString()}","rows=${p.rows.size}","ticks=${p.ticks}","clipped=${mixer.clipped}","peak=${stats.peak}","min=${stats.minimum}","max=${stats.maximum}","rms=${stats.rms}","zero_crossings=${stats.crossings}","adler32=${Report.hex8(Report.adler(mixer.samples,n))}")
    val path = mutableListOf<String>();
    var previousPosition = -1;
    for (row in p.rows) if (row.position != previousPosition) {
        path.add(Report.hex2(row.position));
        previousPosition = row.position
    };
    result.add("path " + path.joinToString(" "));
    var previousRow: Row? = null
    for (row in p.rows) {
        val previous = previousRow;
        if (previous == null || row.speed != previous.speed || row.tempo != previous.tempo) result.add("timing sample=${row.start} order=${Report.hex2(row.position)} row=${Report.hex2(row.row)} speed=${row.speed} tempo=${row.tempo}");
        previousRow = row
    }
    for (c in 0..3) {
        val lane = Report.statistics(mixer.lanes[c],0,n,0);
        result.add("channel ${c + 1} notes=${records(p,c + 1,0).size} retriggers=${p.retriggers[c]} cuts=${p.cuts[c]} active=${p.active[c]} audible=${p.audible[c]} peak=${lane.peak} rms=${lane.rms}")
    }
    val unusedInstruments = mutableListOf<Int>();
    val unusedPatterns = mutableListOf<Int>();
    val unreached = mutableListOf<Int>()
    for (instrument in song.instruments.values) {
        val notes = records(p,0,instrument.number);
        val total = notes.sumOf {
            it.length.toLong()
        };
        result.add("instrument ${Report.hex2(instrument.number)} ${instrument.name} ${instrument.wave} notes=${notes.size} ticks=${p.instrumentTicks.getOrDefault(instrument.number,0L)} range=${range(notes)} average=${if (notes.isEmpty()) "-" else (total / notes.size).toString()}");
        if (notes.isEmpty()) unusedInstruments.add(instrument.number)
    }
    for ((number,pattern) in song.patterns) {
        var rows = 0;
        var notes = 0;
        for (row in pattern) {
            if (row.any {
                !it.empty()
            }) rows++;
            notes += row.count {
                it.note != -2
            }
        };
        val orders = song.order.count {
            it == number
        };
        result.add("pattern ${Report.hex2(number)} rows=$rows notes=$notes orders=$orders");
        if (orders == 0) unusedPatterns.add(number)
    }
    val reachable = Sequencer.reachable(song)
    for (position in song.order.indices) {
        val rows = p.rows.filter {
            it.position == position
        };
        var dead = 0;
        for (r in 0..63) if (position * 64 + r !in reachable && song.patterns.getValue(song.order[position])[r].any {
            it.note != -2
        }) dead++;
        result.add("order ${Report.hex2(position)} pattern=${Report.hex2(song.order[position])} rows=${rows.size} first=${rows.firstOrNull()?.start?.toString() ?: "-"} dead=$dead");
        if (rows.isEmpty()) unreached.add(position)
    }
    val noteCounts = IntArray(96);
    val duration = LongArray(12);
    for (note in p.notes) {
        noteCounts[note.note]++;
        if (song.instruments.getValue(note.instrument).wave != "NOISE") duration[note.note % 12] += note.length
    }
    for (note in 12 until 96) if (noteCounts[note] > 0) result.add("note ${SongParser.noteName(note)} count=${noteCounts[note]}")
    val effects = effectOrder.filter {
        it in p.effects
    };
    result.add(if (effects.isEmpty()) "effects none" else "effects" + effects.joinToString("") {
        " $it=${p.effects.getValue(it)}"
    });
    result.add("unused_instruments=${numbers(unusedInstruments)}");
    result.add("unused_patterns=${numbers(unusedPatterns)}");
    result.add("unreached_orders=${numbers(unreached)}");
    result.add("pitch_classes" + (0..11).joinToString("") {
        " ${tonics[it]}=${duration[it]}"
    })
    val scores = LongArray(24);
    for (key in 0..23) for (j in 0..11) scores[key] += (if (key < 12) major else minor)[Math.floorMod(j - key % 12,12)] * duration[j];
    val keys = (0..23).sortedWith(compareByDescending<Int> {
        scores[it]
    }.thenBy {
        it
    });
    result.add("key=${keyName(keys[0])} score=${scores[keys[0]]} runner_up=${keyName(keys[1])} score=${scores[keys[1]]}")
    for (c in 1..4) result.add("usage ch$c range=${range(records(p,c,0))}" + song.instruments.keys.joinToString("") {
        " ${Report.hex2(it)}=${records(p,c,it).size}"
    });
    result.addAll(p.warnings);
    return result
}
fun plotRow(value: Int, low: Int, high: Int, height: Int) = (2 * (high - value) * (height - 1) + high - low) / (2 * (high - low))
fun plot(values: IntArray, start: Int, length: Int, width: Int, height: Int, low: Int, high: Int, middle: Int): List<String> {
    val cells = Array(height) {
        CharArray(width)
    };
    val center = plotRow(middle,low,high,height)
    for (c in 0 until width) {
        var top = Int.MIN_VALUE;
        var bottom = Int.MAX_VALUE;
        for (j in c * length / width until (c + 1) * length / width) {
            top = maxOf(top,values[start + j]);
            bottom = minOf(bottom,values[start + j])
        };
        val first = plotRow(top,low,high,height);
        val last = plotRow(bottom,low,high,height);
        for (r in 0 until height) cells[r][c] = if (r in first..last) '#' else if (r == center) '-' else ' '
    }
    return (0 until height).map {
        r -> val label = if (r == 0) high.toString() else if (r == center) middle.toString() else if (r == height - 1) low.toString() else "";
        label.padStart(5) + " |" + String(cells[r]) + "|"
    }
}
fun axes(start: Int, length: Int, width: Int, rate: Int): List<String> {
    val first = "      +" + (0 until width).joinToString("") {
        if (it % 10 == 0) "+" else "-"
    }
    + "+";
    val second = StringBuilder("    ms");
    for (c in 0 until width step 10) {
        while (second.length < 7 + c) second.append(' ');
        second.append((start + c * length / width).toLong() * 1000 / rate)
    };
    return listOf(first,second.toString())
}
fun waveformLines(p: Player): List<String> {
    val options = p.settings.numbers("window");
    val start = options[0];
    val length = options[1];
    val width = options[2];
    val height = options[3];
    val scope = options[4];
    val result = mutableListOf("MIX start=$start length=$length width=$width height=$height");
    result.addAll(plot(p.mixer.samples,start,length,width,height,0,255,128));
    result.addAll(axes(start,length,width,p.song.rate));
    for (c in 0..3) {
        result.add("CHANNEL ${c + 1}");
        result.addAll(plot(p.mixer.lanes[c],start,length,width,scope,-3375,3375,0))
    };
    result.addAll(axes(start,length,width,p.song.rate));
    return result
}
fun previewLines(song: SongParser.Song, settings: SongParser.Settings): List<String> {
    val options = settings.entries.getValue("preview");
    val note = SongParser.note(options[0]);
    val ticks = options[1].toInt();
    val release = options[2].toInt();
    val spt = Sequencer.samplesPerTick(song.rate,song.tempo);
    val result = mutableListOf<String>()
    for (instrument in song.instruments.values) {
        val c = Channel();
        c.instrument = instrument;
        c.mode = instrument.mode;
        c.note = note;
        c.frequency = Instruments.frequency(note);
        c.target = c.frequency;
        val mixer = Mixer(ticks * spt,1,song.gain,intArrayOf(0));
        val envelope = StringBuilder();
        val frequencies = mutableListOf<String>()
        for (t in 0 until ticks) {
            c.age = t;
            if (t == release) {
                c.off = true;
                c.releaseAge = t;
                c.releaseValue = c.envelope
            };
            if (t >= 1 && instrument.sweep != 0) c.frequency = Instruments.clamp(c.frequency + 10 * instrument.sweep,1000,50L * song.rate);
            output(c,t,song.rate);
            envelope.append(Report.hex1(c.envelope));
            frequencies.add(c.outputFrequency.toString());
            mixer.generate(arrayOf(c),spt)
        }
        val stats = Report.statistics(mixer.samples,0,mixer.size,128);
        result.add("instrument ${Report.hex2(instrument.number)} ${instrument.name} wave=${instrument.wave} samples=${mixer.size} peak=${stats.peak} rms=${stats.rms} adler32=${Report.hex8(Report.adler(mixer.samples,mixer.size))}");
        result.add("  env $envelope");
        result.add("  freq " + frequencies.joinToString(" "))
    }
    return result
}
fun write(name: String, lines: List<String>) {
    Files.writeString(Path.of("output",name),if (lines.isEmpty()) "" else lines.joinToString("\n") + "\n",StandardCharsets.US_ASCII)
}
fun main() {
    val song = SongParser.song();
    val settings = SongParser.settings();
    val player = Player(song,settings);
    player.play();
    Files.createDirectories(Path.of("output"));
    write("samples.txt",Report.dump(player.mixer.samples,player.mixer.size));
    write("channel_log.txt",player.log);
    write("notes.txt",noteLines(player));
    write("roll.txt",rollLines(player));
    write("stats.txt",statsLines(player));
    write("waveform.txt",waveformLines(player));
    write("instruments.txt",previewLines(song,settings))
}
