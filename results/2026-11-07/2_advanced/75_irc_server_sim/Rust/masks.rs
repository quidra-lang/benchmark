use crate::protocol::fold;
pub fn matches(mask: &str, value: &str) -> bool {
    let mask = fold(mask).into_bytes();
    let value = fold(value).into_bytes();
    let (mut m,mut v) = (0,0);
    let mut star = None;
    let mut retry = 0;
    while v < value.len() {
        if m < mask.len() && (mask[m] == b'?' || mask[m] == value[v]) {
            m += 1;
            v += 1;
        } else if m < mask.len() && mask[m] == b'*' {
            star = Some(m);
            m += 1;
            retry = v;
        } else if let Some(position) = star {
            retry += 1;
            v = retry;
            m = position+1;
        } else {
            return false;
        }
    }
    while m < mask.len() && mask[m] == b'*' {
        m += 1;
    }
    m == mask.len()
}
pub fn normalize(value: &str) -> String {
    match (value.contains('!'),value.contains('@')) {
        (true,true) => value.to_owned(),(false,true) => format!("*!{}",value),(true,false) => format!("{}@*",value),_ => if value.contains('.') {
            format!("*!*@{}",value)
        } else {
            format!("{}!*@*",value)
        }
    }
}
