pub struct Field {
    powers: [u8;255],
    logarithms: [usize;256]
}
pub struct Correction {
    pub syndromes: Vec<u8>,
    pub codewords: Option<Vec<u8>>,
    pub positions: Vec<usize>
}
impl Field {
    pub fn new() -> Self {
        let mut powers = [0;255];
        let mut logarithms = [0;256];
        let mut value = 1usize;
        for i in 0..255 {
            powers[i] = value as u8;
            logarithms[value] = i;
            value *= 2;
            if value >= 256 {
                value ^= 285;
            }
        }
        Self {
            powers,
            logarithms
        }
    }
    pub fn power(&self, exponent: usize) -> u8 {
        self.powers[exponent%255]
    }
    pub fn multiply(&self, a: u8, b: u8) -> u8 {
        if a == 0 || b == 0 {
            0
        } else {
            self.power(self.logarithms[a as usize]+self.logarithms[b as usize])
        }
    }
    pub fn divide(&self, a: u8, b: u8) -> u8 {
        if a == 0 {
            0
        } else {
            self.power(self.logarithms[a as usize]+255-self.logarithms[b as usize])
        }
    }
    fn evaluate(&self, polynomial: &[u8], x: u8) -> u8 {
        polynomial.iter().rev().fold(0,|v,&coefficient| self.multiply(v,x)^coefficient)
    }
    pub fn generator(&self, degree: usize) -> Vec<u8> {
        let mut generator = vec![1];
        for exponent in 0..degree {
            let mut next = vec![0;generator.len()+1];
            for (i,&coefficient) in generator.iter().enumerate() {
                next[i] ^= coefficient;
                next[i+1] ^= self.multiply(coefficient,self.power(exponent));
            }
            generator = next;
        }
        generator
    }
    pub fn error_correction(&self, data: &[u8], degree: usize) -> Vec<u8> {
        let generator = self.generator(degree);
        let mut working = data.to_vec();
        working.resize(data.len()+degree,0);
        for i in 0..data.len() {
            let coefficient = working[i];
            for j in 0..=degree {
                working[i+j] ^= self.multiply(coefficient,generator[j]);
            }
        }
        working[data.len()..].to_vec()
    }
    pub fn syndromes(&self, words: &[u8], degree: usize) -> Vec<u8> {
        (0..degree).map(|j| words.iter().fold(0,|sum,&word| self.multiply(sum,self.power(j))^word)).collect()
    }
    pub fn correct(&self, words: &[u8], degree: usize) -> Correction {
        let syndromes = self.syndromes(words,degree);
        if syndromes.iter().all(|&s| s == 0) {
            return Correction {
                syndromes,
                codewords: Some(words.to_vec()),
                positions: Vec::new()
            };
        }
        let mut locator = vec![0;degree+1];
        locator[0] = 1;
        let mut previous = locator.clone();
        let mut length = 0;
        let mut shift = 1;
        let mut beta = 1;
        for q in 0..degree {
            let mut delta = syndromes[q];
            for i in 1..=length {
                delta ^= self.multiply(locator[i],syndromes[q-i]);
            }
            if delta == 0 {
                shift += 1;
                continue;
            }
            let original = locator.clone();
            let scale = self.divide(delta,beta);
            for i in 0..previous.len() {
                if i+shift < locator.len() {
                    locator[i+shift] ^= self.multiply(scale,previous[i]);
                }
            }
            if 2*length <= q {
                length = q+1-length;
                previous = original;
                beta = delta;
                shift = 1;
            } else {
                shift += 1;
            }
        }
        let mut corrected = words.to_vec();
        let mut positions = Vec::new();
        let mut good = length <= degree/2;
        if good {
            for i in 0..words.len() {
                let inverse = self.power((255-(words.len()-1-i))%255);
                if self.evaluate(&locator[..=length],inverse) == 0 {
                    positions.push(i);
                }
            }
            good = positions.len() == length;
        }
        if good {
            let mut omega = vec![0;degree];
            for i in 0..degree {
                for j in 0..=length {
                    if i+j < degree {
                        omega[i+j] ^= self.multiply(syndromes[i],locator[j]);
                    }
                }
            }
            let mut derivative = vec![0;length.max(1)];
            for j in (1..=length).step_by(2) {
                derivative[j-1] = locator[j];
            }
            for &i in &positions {
                let x = self.power(words.len()-1-i);
                let z = self.power((255-(words.len()-1-i))%255);
                let denominator = self.evaluate(&derivative,z);
                if denominator == 0 {
                    good = false;
                    break;
                }
                corrected[i] ^= self.multiply(x,self.divide(self.evaluate(&omega,z),denominator));
            }
            if good {
                good = self.syndromes(&corrected,degree).iter().all(|&s| s == 0);
            }
        }
        Correction {
            syndromes,
            codewords: if good {
                Some(corrected)
            } else {
                None
            },
            positions: if good {
                positions
            } else {
                Vec::new()
            }
        }
    }
}
