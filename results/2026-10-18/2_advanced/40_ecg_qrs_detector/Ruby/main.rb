require_relative "signal_io"
require_relative "filters"
require_relative "detector"
require_relative "hrv"
require_relative "report"

module ECG
  extend Report

  LABELS = %w[N V A].freeze
  PEAK_CLASSES = %w[qrs searchback twave refractory noise].freeze
  LEVELS = %i[spki npki spkf npkf].freeze
  Beat = Struct.new(:number, :sample, :rr, :width, :label, :method, :reference, :offset,
                    :nn, :previous_total, keyword_init: true)
  Segment = Data.define(:start_ms, :end_ms, :beats, :annotations, :peaks)

  class AdaptiveDetector
    attr_reader :peaks, :initial, :levels, :registered, :average1, :average2

    def initialize(signals, params)
      @peaks = Detector.find_peaks(signals)
      @length = signals[:integrated].length
      @params = params
      @initial = Detector.initial_levels(signals)
      @levels = @initial.dup
      @registered, @intervals = [], []
      @average1 = @average2 = 200
    end

    def thresholds
      [@levels[:npki] + (@levels[:spki] - @levels[:npki]) / 4,
       @levels[:npkf] + (@levels[:spkf] - @levels[:npkf]) / 4]
    end

    def register(peak)
      unless @registered.empty?
        interval = peak.time - @registered.last.time
        @intervals << interval
        @intervals.shift if @intervals.length > 8
        @average1 = @intervals.reduce(0, :+) / @intervals.length
        @average2 = @average1 if (100 * interval).between?(92 * @average1, 116 * @average1)
      end
      @registered << peak
    end

    def update(peak, category)
      integrated, band = category == :noise ? %i[npki npkf] : %i[spki spkf]
      weight, divisor = category == :searchback ? [3, 4] : [7, 8]
      @levels[integrated] = (peak.peak_i + weight * @levels[integrated]) / divisor
      @levels[band] = (peak.peak_f + weight * @levels[band]) / divisor
    end

    def search_back(time)
      loop do
        last_time = @registered.empty? ? 0 : @registered.last.time
        break if time - last_time <= @average2 * @params[:searchback_percent] / 100

        thi, thf = thresholds
        candidates = @peaks.select do |peak|
          peak.kind == "noise" && last_time < peak.time && peak.time < time &&
            peak.peak_i > thi / 2 && peak.peak_f > thf / 2
        end
        chosen = candidates.min_by { |peak| [-peak.peak_i, peak.time] }
        break if chosen.nil?

        update(chosen, :searchback)
        chosen.kind = "searchback"
        register(chosen)
      end
    end

    def run
      refractory, twave = @params[:refractory_ms] / 5, @params[:twave_ms] / 5
      @peaks.each do |peak|
        search_back(peak.time)
        peak.thr_i, peak.thr_f = thresholds
        last = @registered.last
        if last && peak.time - last.time < refractory
          peak.kind = "refractory"
        elsif peak.peak_i > peak.thr_i && peak.peak_f > peak.thr_f
          if last && peak.time - last.time < twave && 2 * peak.slope < last.slope
            peak.kind = "twave"
            update(peak, :noise)
          else
            peak.kind = "qrs"
            update(peak, :signal)
            register(peak)
          end
        else
          peak.kind = "noise"
          update(peak, :noise)
        end
      end
      search_back(@length)
    end
  end

  module_function

  def build_beats(registered, band, params)
    beats = []
    registered.each do |peak|
      number = beats.length + 1
      sample = [0, peak.r - 21].max
      rr = beats.empty? ? nil : 5 * (sample - beats.last.sample)
      width = Detector.width_ms(band, peak.r)
      label, previous_total = "N", nil
      if number >= 10
        previous_total = beats[-8, 8].reduce(0) { |total, beat| total + beat.rr }
        if 800 * rr < params[:premature_percent] * previous_total
          label = width > params[:qrs_width_ms] ? "V" : "A"
        end
      end
      beats << Beat.new(number: number, sample: sample, rr: rr, width: width, label: label,
                        method: peak.kind == "qrs" ? "threshold" : "searchback",
                        nn: false, previous_total: previous_total)
    end
    beats.each_cons(2) do |previous, current|
      current.nn = current.number >= 3 && previous.label == "N" && current.label == "N" &&
                   5 * (current.rr - previous.rr).abs <= previous.rr
    end
    beats
  end

  def match_annotations(beats, annotations, tolerance)
    beats.each do |beat|
      candidates = annotations.select do |annotation|
        annotation.beat.nil? && (annotation.sample - beat.sample).abs <= tolerance
      end
      chosen = candidates.min_by { |annotation| [(annotation.sample - beat.sample).abs, annotation.sample] }
      next if chosen.nil?

      chosen.beat = beat
      beat.reference = chosen
      beat.offset = 5 * (beat.sample - chosen.sample)
    end
  end

  def make_segments(length, params, beats, annotations, peaks)
    size = params[:segment_ms] / 5
    (0...length).step(size).map do |start|
      finish = [start + size, length].min
      Segment.new(5 * start, 5 * finish,
                  beats.select { |beat| start <= beat.sample && beat.sample < finish },
                  annotations.select { |annotation| start <= annotation.sample && annotation.sample < finish },
                  peaks.select { |peak| start <= peak.time && peak.time < finish })
    end
  end

  def beat_lines(beats)
    header = "beat,sample,time_ms,rr_ms,hr_bpm,width_ms,label,method,ref_sample,ref_label"
    rows = beats.map do |beat|
      rate = beat.rr.nil? ? "-" : two(rdiv(6_000_000, beat.rr))
      [beat.number, beat.sample, 5 * beat.sample, missing(beat.rr), rate, beat.width,
       beat.label, beat.method, missing(beat.reference&.sample), missing(beat.reference&.label)].join(",")
    end
    [header] + rows
  end

  def peak_lines(peaks)
    rows = peaks.each_with_index.map do |peak, index|
      [index + 1, peak.time, peak.r, peak.peak_i, peak.peak_f, peak.slope,
       peak.thr_i, peak.thr_f, peak.kind].join(",")
    end
    ["peak,sample,r_sample,peak_i,peak_f,slope,thr_i,thr_f,class"] + rows
  end

  def matching_lines(beats, annotations)
    entries = annotations.map do |annotation|
      beat = annotation.beat
      row = if beat.nil?
              [annotation.sample, annotation.label, "-", "-", "-", "-", "FN", "-"]
            else
              [annotation.sample, annotation.label, beat.number, beat.sample, beat.label,
               beat.offset, "TP", beat.label == annotation.label ? "yes" : "no"]
            end
      [annotation.sample, 0, row.join(",")]
    end
    beats.each do |beat|
      next unless beat.reference.nil?

      entries << [beat.sample, 1, "-,-,#{beat.number},#{beat.sample},#{beat.label},-,FP,-"]
    end
    ["ref_sample,ref_label,beat,beat_sample,beat_label,offset_ms,status,agree"] +
      entries.sort_by { |sample, order, _| [sample, order] }.map(&:last)
  end

  def signal_lines(signals, params)
    names = %i[ecg lowpass bandpass derivative squared integrated]
    rows = (0...(params[:excerpt_ms] / 5)).map do |sample|
      ([sample] + names.map { |name| signals[name][sample] }).join(",")
    end
    ["sample,#{names.join(',')}"] + rows
  end

  def matching_errors(beats, annotations)
    errors = beats.filter_map do |beat|
      next unless beat.reference.nil?

      [beat.sample, 0, "false_positive beat=#{beat.number} sample=#{beat.sample} " \
        "time_ms=#{5 * beat.sample} label=#{beat.label}"]
    end
    annotations.each do |annotation|
      next unless annotation.beat.nil?

      errors << [annotation.sample, 1, "false_negative sample=#{annotation.sample} " \
        "time_ms=#{5 * annotation.sample} label=#{annotation.label}"]
    end
    errors.sort_by { |sample, order, _| [sample, order] }.map(&:last)
  end

  def label_counts(items, labels = LABELS)
    labels.map { |label| "#{label}=#{items.count { |item| item.label == label }}" }.join(" ")
  end

  def performance_lines(detector, beats, annotations, segments, params, length)
    matched, extra = beats.partition { |beat| !beat.reference.nil? }
    missed = annotations.select { |annotation| annotation.beat.nil? }
    classes = PEAK_CLASSES.map { |kind| "#{kind}=#{detector.peaks.count { |peak| peak.kind == kind }}" }
    thi, thf = detector.thresholds
    lines = [
      "DETECTOR", "samples #{length}", "duration_ms #{5 * length}",
      "peaks #{detector.peaks.length} #{classes.join(' ')}",
      "initial_levels #{LEVELS.map { |name| "#{name}=#{detector.initial[name]}" }.join(' ')}",
      "final_levels #{LEVELS.map { |name| "#{name}=#{detector.levels[name]}" }.join(' ')}",
      "final_thresholds thr_i=#{thi} thr_f=#{thf}",
      "final_rr_averages rravg1_ms=#{5 * detector.average1} rravg2_ms=#{5 * detector.average2}",
      "MATCHING", "tolerance_ms #{params[:match_ms]}",
      "references #{annotations.length} #{label_counts(annotations)}",
      "detections #{beats.length} #{label_counts(beats)}",
      "true_positives #{matched.length}", "false_positives #{extra.length}", "false_negatives #{missed.length}",
      "sensitivity #{ratio(matched.length, matched.length + missed.length)}",
      "positive_predictivity #{ratio(matched.length, beats.length)}",
      "detection_error_rate #{ratio(extra.length + missed.length, annotations.length)}"
    ]
    methods = %w[threshold searchback].map do |method|
      "#{method}=#{matched.count { |beat| beat.method == method }}/#{beats.count { |beat| beat.method == method }}"
    end
    lines << "by_method #{methods.join(' ')}"
    if matched.empty?
      lines << "offset_ms none"
    else
      offsets = matched.map(&:offset)
      absolute = offsets.map(&:abs)
      lines << "offset_ms mean=#{two(rdiv(100 * offsets.reduce(0, :+), offsets.length))} " \
        "mean_abs=#{two(rdiv(100 * absolute.reduce(0, :+), offsets.length))} max_abs=#{absolute.max}"
    end
    lines.concat(["CONFUSION", "ref  #{LABELS.map { |label| label.rjust(6) }.join}  miss"])
    LABELS.each do |label|
      counts = LABELS.map do |predicted|
        matched.count { |beat| beat.reference.label == label && beat.label == predicted }.to_s.rjust(6)
      end
      lines << label + "    " + counts.join + missed.count { |annotation| annotation.label == label }.to_s.rjust(6)
    end
    lines << "extra" + LABELS.map { |label| extra.count { |beat| beat.label == label }.to_s.rjust(6) }.join
    [["V", "veb"], ["A", "sveb"]].each do |label, prefix|
      hits = matched.count { |beat| beat.label == label && beat.reference.label == label }
      lines << "#{prefix}_sensitivity #{ratio(hits, annotations.count { |annotation| annotation.label == label })}"
      lines << "#{prefix}_positive_predictivity #{ratio(hits, beats.count { |beat| beat.label == label })}"
    end
    lines << "SEGMENTS segment_ms=#{params[:segment_ms]} segments=#{segments.length}"
    segments.each do |segment|
      tp = segment.annotations.count { |annotation| !annotation.beat.nil? }
      fp = segment.beats.count { |beat| beat.reference.nil? }
      noise = segment.peaks.count { |peak| peak.kind == "noise" }
      lines << format("%6d-%6d", segment.start_ms, segment.end_ms) +
        " refs=#{segment.annotations.length} tp=#{tp} fp=#{fp} fn=#{segment.annotations.length - tp} noise_peaks=#{noise}"
    end
    lines << "ERRORS count=#{extra.length + missed.length}"
    lines + matching_errors(beats, annotations)
  end

  def premature_lines(beats)
    premature = beats.select { |beat| beat.label != "N" }
    lines = ["PREMATURE count=#{premature.length} #{label_counts(premature, %w[V A])}"]
    premature.each do |beat|
      total = beat.previous_total
      next_rr = beats[beat.number]&.rr
      compensation = if next_rr.nil?
                       "-"
                     else
                       pair = beat.rr + next_rr
                       if 10 * (4 * pair - total).abs <= total
                         "full"
                       elsif 4 * pair < total
                         "partial"
                       else
                         "long"
                       end
                     end
      lines << "beat=#{beat.number} sample=#{beat.sample} label=#{beat.label} rr_ms=#{beat.rr} " \
        "next_rr_ms=#{missing(next_rr)} mean_ms=#{two(rdiv(100 * total, 8))} " \
        "prematurity=#{two(rdiv(80_000 * beat.rr, total))}% compensation=#{compensation} " \
        "width_ms=#{beat.width} ref=#{missing(beat.reference&.label)}"
    end
    lines
  end

  def run_lines(beats)
    runs = []
    %w[V A].each do |label|
      HRV.ranges(beats) { |beat| beat.label == label }.each do |first, last|
        length = last - first + 1
        kind = length == 1 ? "isolated" : length == 2 ? "couplet" : "run"
        runs << [first, "#{label} #{kind} beats=#{beats[first].number}-#{beats[last].number} " \
          "length=#{length} start_ms=#{5 * beats[first].sample}"]
      end
    end
    runs.sort_by(&:first).map(&:last)
  end

  def event_lines(beats, params)
    lines = []
    beats.drop(1).each do |beat|
      next unless beat.rr > params[:pause_ms]

      previous = beats[beat.number - 2]
      lines << "pause beats=#{previous.number}-#{beat.number} rr_ms=#{beat.rr} start_ms=#{5 * previous.sample}"
    end
    [["bradycardia", params[:brady_ms]], ["tachycardia", params[:tachy_ms]]].each do |kind, threshold|
      ranges = HRV.ranges(beats) do |beat|
        !beat.rr.nil? && (kind == "bradycardia" ? beat.rr > threshold : beat.rr < threshold)
      end
      ranges.each do |first, last|
        count = last - first + 1
        next if count < 3

        rate = HRV.mean_heart_rate(beats[first..last].map(&:rr))
        lines << "#{kind} beats=#{beats[first - 1].number}-#{beats[last].number} intervals=#{count} " \
          "mean_hr=#{two(rate)} start_ms=#{5 * beats[first - 1].sample}"
      end
    end
    ventricular = beats.each_index.select { |index| beats[index].label == "V" }
    [["bigeminy", 2], ["trigeminy", 3]].each do |kind, spacing|
      ventricular.chunk_while do |left, right|
        right == left + spacing && beats[(left + 1)...right].all? { |beat| beat.label == "N" }
      end.each do |chain|
        next if chain.length < 3

        first, last = beats[chain.first], beats[chain.last]
        lines << "#{kind} beats=#{first.number}-#{last.number} cycles=#{chain.length} start_ms=#{5 * first.sample}"
      end
    end
    lines
  end

  def hrv_lines(beats, segments, params)
    rr = beats.drop(1).map(&:rr)
    nn = beats.select(&:nn).map(&:rr)
    pairs = beats.each_cons(2).filter_map { |a, b| [a.rr, b.rr] if a.nn && b.nn }
    stats = HRV.statistics(rr, nn, pairs)
    lines = ["RR", "beats #{beats.length}", "intervals #{rr.length}",
             "mean_rr_ms #{maybe_two(stats[:mean_rr])}"]
    if rr.empty?
      lines.concat(["min_rr_ms none", "max_rr_ms none"])
    else
      shortest = beats.drop(1).min_by { |beat| [beat.rr, beat.number] }
      longest = beats.drop(1).min_by { |beat| [-beat.rr, beat.number] }
      lines.concat(["min_rr_ms #{shortest.rr} beat=#{shortest.number}",
                    "max_rr_ms #{longest.rr} beat=#{longest.number}"])
    end
    lines.concat([
      "mean_hr_bpm #{maybe_two(stats[:mean_hr])}", "NN", "intervals #{nn.length}",
      "mean_nn_ms #{maybe_two(stats[:mean_nn])}", "sdnn_ms #{maybe_two(stats[:sdnn])}",
      "differences #{pairs.length}", "rmssd_ms #{maybe_two(stats[:rmssd])}",
      "sdsd_ms #{maybe_two(stats[:sdsd])}", "nn50 #{stats[:nn50]}",
      stats[:pnn50].nil? ? "pnn50 none" : "pnn50 #{two(stats[:pnn50])}%",
      "sd1_ms #{maybe_two(stats[:sd1])}", "sd2_ms #{maybe_two(stats[:sd2])}"
    ])
    histogram = HRV.histogram(nn)
    maximum = histogram.map(&:last).max || 0
    lines << "HISTOGRAM bin_ms=7.8125 bins=#{histogram.length} max=#{maximum}"
    histogram.each do |bin, count|
      lines << format("%10s %10s %3d |%s", four(78_125 * bin), four(78_125 * (bin + 1)), count, "#" * count)
    end
    lines << if nn.empty?
               "triangular_index none"
             else
               "triangular_index #{fraction(nn.length, maximum)} #{two(rdiv(100 * nn.length, maximum))}"
             end
    lines.concat(premature_lines(beats))
    runs = run_lines(beats)
    lines.concat(["RUNS count=#{runs.length}"] + runs)
    events = event_lines(beats, params)
    lines.concat(["EVENTS count=#{events.length}"] + events)
    lines << "TREND segment_ms=#{params[:segment_ms]} segments=#{segments.length}"
    segments.each do |segment|
      intervals = segment.beats.filter_map(&:rr)
      prefix = format("%6d-%6d beats=%d", segment.start_ms, segment.end_ms, segment.beats.length)
      if intervals.empty?
        lines << "#{prefix} mean_hr=none min_hr=none max_hr=none |"
      else
        mean = HRV.mean_heart_rate(intervals)
        lines << "#{prefix} mean_hr=#{two(mean)} min_hr=#{two(rdiv(6_000_000, intervals.max))} " \
          "max_hr=#{two(rdiv(6_000_000, intervals.min))} |#{'#' * rdiv(mean, 500)}"
      end
    end
    lines
  end

  def scale(value, top, bottom, height)
    top > bottom ? rdiv((top - value) * (height - 1), top - bottom) : 0
  end

  def waveform(upper, lower, height)
    top, bottom = upper.max, lower.min
    zero = bottom <= 0 && top >= 0 ? scale(0, top, bottom, height) : nil
    high_rows = upper.map { |value| scale(value, top, bottom, height) }
    low_rows = lower.map { |value| scale(value, top, bottom, height) }
    height.times.map do |row|
      label = if row.zero?
                top
              elsif row == height - 1
                bottom
              elsif row == zero
                0
              else
                ""
              end
      cells = high_rows.each_with_index.map do |high, column|
        if high <= row && row <= low_rows[column]
          "#"
        elsif row == zero
          "-"
        else
          " "
        end
      end
      "#{label.to_s.rjust(6)} |#{cells.join}|"
    end
  end

  def axis_row(columns)
    "       +" + columns.times.map { |column| yield(column) ? "+" : "-" }.join + "+"
  end

  def label_row(heading, labels)
    line = heading.rjust(6) + "  "
    labels.each { |column, value| line = line.ljust(8 + column) + value.to_s }
    line.rstrip
  end

  def interval_charts(beats, params)
    rr = beats.drop(1).map(&:rr)
    return ["TACHOGRAM intervals=0", "POINCARE points=0"] if rr.empty?

    low, high, height = rr.min, rr.max, params[:chart_rows]
    lines = ["TACHOGRAM intervals=#{rr.length} min_ms=#{low} max_ms=#{high} rows=#{height}"]
    positions = rr.map { |value| scale(value, high, low, height) }
    height.times do |row|
      label = row.zero? ? high : row == height - 1 ? low : ""
      cells = positions.map { |position| position == row ? "*" : " " }.join
      lines << "#{label.to_s.rjust(6)} |#{cells}|"
    end
    labels = rr.each_index.filter_map { |column| [column, column + 2] if ((column + 2) % 10).zero? }
    lines.concat([axis_row(rr.length) { |column| ((column + 2) % 10).zero? }, label_row("beat", labels),
                  " label |#{beats.drop(1).map(&:label).join}|"])
    size = params[:poincare_size]
    cells = Array.new(size) { Array.new(size, 0) }
    rr.each_cons(2) do |a, b|
      column = high > low ? rdiv((a - low) * (size - 1), high - low) : 0
      cells[scale(b, high, low, size)][column] += 1
    end
    lines << "POINCARE points=#{rr.length - 1} size=#{size} min_ms=#{low} max_ms=#{high}"
    size.times do |row|
      label = row.zero? ? high : row == size - 1 ? low : ""
      characters = cells[row].map { |count| count.zero? ? "." : count <= 9 ? count.to_s : "#" }.join
      lines << "#{label.to_s.rjust(6)} |#{characters}|"
    end
    lines << axis_row(size) { false }
    lines << ("        #{low}").ljust(8 + size - high.to_s.length) + high.to_s
    lines
  end

  def average_template(samples, beats, label, height)
    chosen = beats.select { |beat| beat.label == label && beat.sample.between?(60, samples.length - 100) }
    return ["TEMPLATE #{label} beats=0"] if chosen.empty?

    baselines = chosen.map { |beat| samples[beat.sample - 60, 10].reduce(0, :+) }
    averaged = (-60..99).map do |offset|
      total = 0
      chosen.each_with_index { |beat, index| total += 10 * samples[beat.sample + offset] - baselines[index] }
      rdiv(total, 10 * chosen.length)
    end
    top, bottom = averaged.max, averaged.min
    lines = ["TEMPLATE #{label} beats=#{chosen.length} max_uv=#{top} max_ms=#{5 * (averaged.index(top) - 60)} " \
      "min_uv=#{bottom} min_ms=#{5 * (averaged.index(bottom) - 60)} rows=#{height}"]
    pairs = averaged.each_slice(2).to_a
    lines.concat(waveform(pairs.map(&:max), pairs.map(&:min), height))
    lines << axis_row(80) { |column| (column % 10).zero? }
    lines << label_row("ms", (0...80).step(10).map { |column| [column, 10 * column - 300] })
    lines
  end

  def chart_lines(samples, beats, params)
    templates = LABELS.flat_map do |label|
      average_template(samples, beats, label, params[:chart_rows])
    end
    interval_charts(beats, params) + templates
  end

  def rhythm_lines(samples, beats, annotations, params)
    start, length = params[:strip_start_ms] / 5, params[:strip_ms] / 5
    columns, height = length / 10, params[:strip_rows]
    excerpt = samples[start, length]
    groups = excerpt.each_slice(10).to_a
    lines = ["RHYTHM start_ms=#{params[:strip_start_ms]} end_ms=#{params[:strip_start_ms] + params[:strip_ms]} " \
      "columns=#{columns} rows=#{height} max_uv=#{excerpt.max} min_uv=#{excerpt.min}"]
    lines.concat(waveform(groups.map(&:max), groups.map(&:min), height))
    lines << axis_row(columns) { |column| (column % 20).zero? }
    labels = (0...columns).step(20).map { |column| [column, (params[:strip_start_ms] + 50 * column) / 1000] }
    lines << label_row("s", labels)
    beat_marks, ref_marks = Array.new(columns, " "), Array.new(columns, " ")
    beats.each do |beat|
      beat_marks[(beat.sample - start) / 10] = beat.label if start <= beat.sample && beat.sample < start + length
    end
    annotations.each do |annotation|
      if start <= annotation.sample && annotation.sample < start + length
        ref_marks[(annotation.sample - start) / 10] = annotation.label
      end
    end
    lines.concat([" beats |#{beat_marks.join}|", "  refs |#{ref_marks.join}|"])
  end

  def main
    samples = SignalIO.read_ecg
    annotations = SignalIO.read_annotations
    params = SignalIO.read_params
    signals = Filters.filter_ecg(samples)
    detector = AdaptiveDetector.new(signals, params)
    detector.run
    beats = build_beats(detector.registered, signals[:bandpass], params)
    match_annotations(beats, annotations, params[:match_ms] / 5)
    segments = make_segments(samples.length, params, beats, annotations, detector.peaks)
    outputs = {
      "beats.csv" => beat_lines(beats), "peaks.csv" => peak_lines(detector.peaks),
      "matching.csv" => matching_lines(beats, annotations), "signals_excerpt.csv" => signal_lines(signals, params),
      "performance.txt" => performance_lines(detector, beats, annotations, segments, params, samples.length),
      "hrv.txt" => hrv_lines(beats, segments, params), "charts.txt" => chart_lines(samples, beats, params),
      "rhythm_strip.txt" => rhythm_lines(samples, beats, annotations, params)
    }
    outputs.each { |name, lines| SignalIO.write_lines(name, lines) }
  end
end

ECG.main if $PROGRAM_NAME == __FILE__
