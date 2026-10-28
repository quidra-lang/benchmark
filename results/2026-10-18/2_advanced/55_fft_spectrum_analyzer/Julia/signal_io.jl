function read_signal()
    rows = split.(readlines(joinpath("input","signal.csv")),',')
    fs,n = parse.(Int,rows[1])
    fs,[parse(Float64,row[1]) for row in rows[2:end]],[parse(Float64,row[2]) for row in rows[2:end]]
end
function read_params()
    raw = Dict(String(row[1])=>String.(row[2:end]) for row in split.(readlines(joinpath(
        "input",
        "params.txt"
    ))))
    integer(key) = parse(Int,raw[key][1])
    integer_list(key) = parse.(Int,raw[key])
    (main_length=integer("main_length"),main_window=raw["main_window"][1],peak_threshold_db=parse(Float64,raw["peak_threshold_db"][1]),peak_count=integer("peak_count"),
        fundamental=(
            parse(Float64,raw["fundamental"][1]),
            parse(Int,raw["fundamental"][2])
        ),welch=(parse(Int,raw["welch"][1]),raw["welch"][2]),
        spectrogram=(
            parse(Int,raw["spectrogram"][1]),
            parse(Int,raw["spectrogram"][2]),
            parse(Int,raw["spectrogram"][3]),
            raw["spectrogram"][4]
        ),onset_factor=parse(Float64,raw["onset_factor"][1]),
        pitch_range=integer_list("pitch_range"),bandpass=integer_list("bandpass"),notch=integer_list("notch"),envelope_band=integer_list("envelope_band"),zoom=integer_list("zoom"),
        fir=parse.(
            Float64,
            raw["fir"]
        ),max_lag=integer("max_lag"),bands=integer_list("bands"),third_octave=integer_list("third_octave"),block_length=integer("block_length"))
end
