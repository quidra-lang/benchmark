pub fn dirty(state: u8) -> bool {
    state == b'M' || state == b'O'
}
pub fn request(protocol: &str, state: u8, write: bool) -> (Option<usize>,u8) {
    if protocol == "VI" {
        if write {
            (Some(3),state)
        } else if state == b'I' {
            (Some(0),b'V')
        } else {
            (None,b'V')
        }
    } else if state == b'I' {
        if write {
            (Some(1),b'M')
        } else {
            (Some(0),if protocol == "MSI" {
                b'S'
            } else {
                b'?'
            })
        }
    } else if write {
        match state {
            b'S' | b'O' => (Some(2),b'M'),_ => (None,b'M')
        }
    } else {
        (None,state)
    }
}
pub fn snoop(protocol: &str, state: u8, kind: usize) -> (u8,bool,bool) {
    if protocol == "VI" {
        return (if kind == 3 {
            b'I'
        } else {
            state
        },false,false);
    }
    if kind == 0 {
        match state {
            b'M' => if protocol == "MOESI" {
                (b'O',true,false)
            } else {
                (b'S',true,true)
            },b'O' => (b'O',true,false),b'E' => (b'S',false,false),_ => (state,false,false)
        }
    } else {
        (b'I',dirty(state) && kind == 1,false)
    }
}
