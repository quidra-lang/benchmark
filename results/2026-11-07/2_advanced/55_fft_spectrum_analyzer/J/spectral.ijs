median =: 3 : 0
    ordered =. /:~y
    middle =. <.(#ordered)%2
    if. 2|#ordered do.
        middle{ordered
    else.
        (((middle-1){ordered)+middle{ordered)%2.0
    end.
)
local_maximum =: 4 : 0
    if. (y<1)+.y>:(#x)-1 do.
        0 return.
    end.
    ((y{x)>(y-1){x)*.(y{x)>(y+1){x
)
interpolate =: 4 : 0
    'index logarithmic' =. x
    if. -.y local_maximum index do.
        (0.0+index),index{y return.
    end.
    'a b c' =. (index+_1 0 1){y
    if. logarithmic do.
        'a b c' =. ^.a,b,c
    end.
    delta =. (a-c)%(2.0*((a-2.0*b)+c))
    fitted =. b-((a-c)*delta)%4.0
    if. logarithmic do.
        fitted =. ^fitted
    end.
    (index+delta),fitted
)
amplitude_spectrum =: 4 : 0
    'name length' =. x
    weights =. name window length
    weighted =. (length{.y)*weights
    transformed =. dft weighted
    s1 =. 0.0
    for_value. weights do.
        s1 =. s1+value
    end.
    amplitudes =. i.0
    for_k. i.1+<.length%2 do.
        factor =. 2.0
        if. (k=0)+.(2*k)=length do.
            factor =. 1.0
        end.
        amplitudes =. amplitudes,(factor*|k{transformed)%s1
    end.
    (<weighted),(<transformed),<amplitudes
)
packed_and_error =: 3 : 0
    packed =. packed_real y
    reference =. (#packed){.0 radix2 y
    (<packed),<>./|packed-reference
)
welch_spectra =: 3 : 0
    'first second sample_rate length name' =. y
    weights =. name window length
    energy =. 0.0
    for_value. weights do.
        energy =. energy+value*value
    end.
    step =. <.length%2
    segments =. 1+<.((#first)-length)%step
    count =. 1+step
    pxx =. count$0.0
    pyy =. pxx
    pxy =. count$0j0
    packing_error =. 0.0
    for_block. i.segments do.
        indices =. (block*step)+i.length
        'af ae' =. packed_and_error (indices{first)*weights
        'bf be' =. packed_and_error (indices{second)*weights
        packing_error =. packing_error>.ae>.be
        pxx =. pxx+*:|af
        pyy =. pyy+*:|bf
        pxy =. pxy+(+af)*bf
    end.
    psd =. i.0
    coherence =. i.0
    transfer =. 0$0j0
    for_k. i.count do.
        factor =. 2.0
        if. (k=0)+.k=step do.
            factor =. 1.0
        end.
        psd =. psd,(factor*k{pxx)%((segments*sample_rate)*energy)
        coherence =. coherence,(*:|k{pxy)%((k{pxx)*k{pyy)
        transfer =. transfer,(k{pxy)%k{pxx
    end.
    (<segments),(<psd),(<coherence),(<transfer),<packing_error
)
spectrogram_magnitudes =: 4 : 0
    'length hop name' =. x
    weights =. name window length
    frames =. 1+<.((#y)-length)%hop
    grid =. (0,1+<.length%2)$0.0
    maximum_error =. 0.0
    for_frame. i.frames do.
        samples =. (((frame*hop)+i.length){y)*weights
        'transformed error_value' =. packed_and_error samples
        grid =. grid,|transformed
        maximum_error =. maximum_error>.error_value
    end.
    (<grid),<maximum_error
)
