"""Input parsing for the two-channel vibration spectrum analyzer."""

from pathlib import Path


def read_signal(path="input/signal.csv"):
    lines = Path(path).read_text(encoding="ascii").splitlines()
    sample_rate, count = map(int, lines[0].split(","))
    if len(lines) != count + 1:
        raise ValueError("signal.csv does not contain the declared number of samples")
    first, second = [], []
    for line in lines[1:]:
        x, y = line.split(",")
        first.append(float(x))
        second.append(float(y))
    return sample_rate, first, second


def read_params(path="input/params.txt"):
    lines = Path(path).read_text(encoding="ascii").splitlines()
    fields = [line.split(" ") for line in lines]
    expected = (
        "main_length", "main_window", "peak_threshold_db", "peak_count",
        "fundamental", "welch", "spectrogram", "onset_factor", "pitch_range",
        "bandpass", "notch", "envelope_band", "zoom", "fir", "max_lag",
        "bands", "third_octave", "block_length",
    )
    if len(fields) != len(expected) or [row[0] for row in fields] != list(expected):
        raise ValueError("unexpected parameter layout")
    values = [row[1:] for row in fields]
    return {
        "main_length": int(values[0][0]),
        "main_window": values[1][0],
        "peak_threshold_db": float(values[2][0]),
        "peak_count": int(values[3][0]),
        "fundamental": (float(values[4][0]), int(values[4][1])),
        "welch": (int(values[5][0]), values[5][1]),
        "spectrogram": (int(values[6][0]), int(values[6][1]),
                        int(values[6][2]), values[6][3]),
        "onset_factor": float(values[7][0]),
        "pitch_range": tuple(map(int, values[8])),
        "bandpass": tuple(map(int, values[9])),
        "notch": tuple(map(int, values[10])),
        "envelope_band": tuple(map(int, values[11])),
        "zoom": (int(values[12][0]), int(values[12][1]), int(values[12][2])),
        "fir": list(map(float, values[13])),
        "max_lag": int(values[14][0]),
        "bands": list(map(int, values[15])),
        "third_octave": tuple(map(int, values[16])),
        "block_length": int(values[17][0]),
    }
