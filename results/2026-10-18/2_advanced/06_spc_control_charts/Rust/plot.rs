use crate::variable_charts::Limits;

fn place(band: &mut [u8; 61], position: f64, symbol: u8) { band[position.clamp(0.0, 60.0) as usize] = symbol; }
fn framed_band(center: f64) -> [u8; 61] { let mut band = [b'.'; 61]; place(&mut band,0.0,b':'); place(&mut band,60.0,b':'); place(&mut band,center,b'|'); band }
fn text(band: [u8; 61]) -> String { String::from_utf8(band.to_vec()).unwrap() }

pub fn limits_band(limits: Limits, value: f64, signalled: bool) -> String {
    let span = limits.ucl - limits.lcl;
    let mut band = framed_band((60.0 * ((limits.cl - limits.lcl) / span) + 0.5).floor());
    place(&mut band, (60.0 * ((value - limits.lcl) / span) + 0.5).floor(), if signalled { b'*' } else { b'o' });
    text(band)
}

pub fn cusum_band(upper: f64, lower: f64, threshold: f64, upper_signal: bool, lower_signal: bool) -> String {
    let mut band = framed_band(30.0);
    if lower > 0.0 { place(&mut band, 30.0 - (30.0 * (lower / threshold) + 0.5).floor().min(30.0), if lower_signal { b'*' } else { b'-' }); }
    if upper > 0.0 { place(&mut band, 30.0 + (30.0 * (upper / threshold) + 0.5).floor().min(30.0), if upper_signal { b'*' } else { b'+' }); }
    text(band)
}

pub fn width_band(scale: f64, width: f64, value: f64, center: f64, signalled: bool) -> String {
    let mut band = [b'.'; 61];
    let edge = (30.0 * (width / scale) + 0.5).floor().min(30.0);
    place(&mut band, 30.0, b'|'); place(&mut band, 30.0 - edge, b':'); place(&mut band, 30.0 + edge, b':');
    place(&mut band, 30.0 + (30.0 * ((value - center) / scale) + 0.5).floor(), if signalled { b'*' } else { b'o' });
    text(band)
}

pub fn standard_band(z: f64, ok: bool) -> String {
    let mut band = framed_band(30.0);
    place(&mut band, 30.0 + (10.0 * z + 0.5).floor(), if ok { b'o' } else { b'*' });
    text(band)
}
