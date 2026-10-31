module Spectrum
  def median(values)
    ordered = values.sort
    n = ordered.length
    n.odd? ? ordered[n / 2] : (ordered[n / 2 - 1] + ordered[n / 2]) / 2.0
  end

  def local_maximum(values, k)
    k > 0 && k < values.length - 1 && values[k] > values[k - 1] && values[k] > values[k + 1]
  end

  def interpolate(values, k, logarithmic = true)
    return [k.to_f, values[k]] unless local_maximum(values, k)
    a, b, c = values[k - 1, 3]
    a, b, c = Math.log(a), Math.log(b), Math.log(c) if logarithmic
    delta = (a - c) / (2 * (a - 2 * b + c))
    fitted = b - (a - c) * delta / 4
    [k + delta, logarithmic ? Math.exp(fitted) : fitted]
  end

  def amplitude_spectrum(signal, name, length)
    weights = window(name, length)
    weighted = Array.new(length) { |n| signal[n] * weights[n] }
    transformed = dft(weighted)
    s1 = ordered_sum(weights)
    amplitudes = Array.new(length / 2 + 1) do |k|
      factor = k.zero? || 2 * k == length ? 1 : 2
      factor * transformed[k].abs / s1
    end
    [weighted, transformed, amplitudes]
  end

  def packed_and_error(samples)
    packed = packed_real(samples)
    reference = radix2(samples)
    [packed, packed.each_with_index.map { |v, k| (v - reference[k]).abs }.max]
  end

  def welch_spectra(x, y, fs, length, name)
    weights = window(name, length)
    energy = ordered_sum(weights.map { |v| v * v })
    step = length / 2
    segments = (x.length - length) / step + 1
    count = length / 2 + 1
    pxx, pyy, pxy = Array.new(count, 0.0), Array.new(count, 0.0), Array.new(count, Complex(0.0, 0.0))
    packing_error = 0.0
    segments.times do |block|
      start = block * step
      xf, ex = packed_and_error(Array.new(length) { |i| x[start + i] * weights[i] })
      yf, ey = packed_and_error(Array.new(length) { |i| y[start + i] * weights[i] })
      packing_error = [packing_error, ex, ey].max
      count.times do |k|
        pxx[k] += xf[k].abs**2
        pyy[k] += yf[k].abs**2
        pxy[k] += xf[k].conj * yf[k]
      end
    end
    psd, coherence, transfer = [], [], []
    count.times do |k|
      factor = k.zero? || k == length / 2 ? 1 : 2
      psd << factor * pxx[k] / (segments * fs * energy)
      coherence << pxy[k].abs**2 / (pxx[k] * pyy[k])
      transfer << pxy[k] / pxx[k]
    end
    {segments: segments, psd: psd, coherence: coherence, transfer: transfer, packing_error: packing_error}
  end

  def spectrogram_magnitudes(signal, length, hop, name)
    weights = window(name, length)
    frames = (signal.length - length) / hop + 1
    grid, error = [], 0.0
    frames.times do |t|
      transformed, frame_error = packed_and_error(Array.new(length) { |i| signal[t * hop + i] * weights[i] })
      grid << transformed.map(&:abs)
      error = [error, frame_error].max
    end
    [grid, error]
  end
end
