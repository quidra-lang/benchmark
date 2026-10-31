module Spectrum
  def read_signal
    lines = File.readlines('input/signal.csv', chomp: true)
    fs, n = lines.shift.split(',').map(&:to_i)
    raise ArgumentError, 'incorrect sample count' unless lines.length == n
    channels = lines.map { |line| line.split(',').map(&:to_f) }.transpose
    [fs, *channels]
  end

  def read_params
    raw = File.readlines('input/params.txt', chomp: true).to_h do |line|
      key, *values = line.split(' ')
      [key.to_sym, values]
    end
    p = {}
    %i[main_length peak_count max_lag block_length].each { |key| p[key] = raw[key][0].to_i }
    %i[peak_threshold_db onset_factor].each { |key| p[key] = raw[key][0].to_f }
    p[:main_window] = raw[:main_window][0]
    p[:fundamental] = [raw[:fundamental][0].to_f, raw[:fundamental][1].to_i]
    p[:welch] = [raw[:welch][0].to_i, raw[:welch][1]]
    p[:spectrogram] = raw[:spectrogram].first(3).map(&:to_i) + [raw[:spectrogram][3]]
    %i[pitch_range bandpass notch envelope_band zoom bands third_octave].each { |key| p[key] = raw[key].map(&:to_i) }
    p[:fir] = raw[:fir].map(&:to_f)
    p
  end
end
