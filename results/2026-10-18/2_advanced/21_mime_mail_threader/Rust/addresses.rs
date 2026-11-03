use crate::headers::{Token, TokenKind, collapse_whitespace, decode_word, tokenize};

#[derive(Clone)]
pub struct Mailbox { pub name: String, pub address: String }
pub enum Address { Mailbox(Mailbox), Group(Vec<Mailbox>) }
struct Parser { tokens: Vec<Token>, position: usize, error: bool }
impl Parser {
    fn peek(&self) -> Option<TokenKind> { self.tokens.get(self.position).map(|token| token.kind) }
    fn expect(&mut self, kind: TokenKind) -> Option<()> {
        if self.peek() != Some(kind) { return None; }
        self.position += 1; Some(())
    }
    fn run(&mut self, quoted: bool) -> (usize, usize) {
        let start = self.position;
        while matches!(self.peek(), Some(TokenKind::Word | TokenKind::Special(b'.'))) || quoted && self.peek() == Some(TokenKind::Quoted) { self.position += 1; }
        (start, self.position)
    }
    fn display_name(&mut self, (start, end): (usize, usize)) -> String {
        let (mut result, mut previous) = (String::new(), false);
        for (index, token) in self.tokens[start..end].iter().enumerate() {
            let (text, decoded, failed) = if token.kind == TokenKind::Word { decode_word(&token.text) } else { (token.text.clone(), false, false) };
            self.error |= failed;
            if index > 0 && token.spaced && !(decoded && previous) { result.push(' '); }
            result.push_str(&text); previous = decoded;
        }
        collapse_whitespace(&result)
    }
    fn atom(&self, (start, end): (usize, usize)) -> Option<String> {
        if (end - start) % 2 == 0 { return None; }
        let mut result = String::new();
        for (index, token) in self.tokens[start..end].iter().enumerate() {
            if token.kind != if index % 2 == 0 { TokenKind::Word } else { TokenKind::Special(b'.') } { return None; }
            result.push_str(&token.text);
        }
        Some(result)
    }
    fn address(&mut self, in_group: bool) -> Option<Address> {
        let phrase = self.run(true);
        match self.peek()? {
            TokenKind::Special(b'<') => {
                self.position += 1;
                let local = self.run(false); self.expect(TokenKind::Special(b'@'))?;
                let domain = self.run(false); self.expect(TokenKind::Special(b'>'))?;
                let address = format!("{}@{}", self.atom(local)?, self.atom(domain)?).to_ascii_lowercase();
                let name = self.display_name(phrase);
                Some(Address::Mailbox(Mailbox { name, address }))
            }
            TokenKind::Special(b'@') => {
                self.position += 1;
                let domain = self.run(false);
                let address = format!("{}@{}", self.atom(phrase)?, self.atom(domain)?).to_ascii_lowercase();
                Some(Address::Mailbox(Mailbox { name: String::new(), address }))
            }
            TokenKind::Special(b':') if phrase.0 < phrase.1 && !in_group => {
                self.position += 1;
                let mut mailboxes = Vec::new();
                if self.peek() != Some(TokenKind::Special(b';')) {
                    loop {
                        let Address::Mailbox(mailbox) = self.address(true)? else { return None; };
                        mailboxes.push(mailbox);
                        if self.peek() != Some(TokenKind::Special(b',')) { break; }
                        self.position += 1;
                    }
                }
                self.expect(TokenKind::Special(b';'))?;
                Some(Address::Group(mailboxes))
            }
            _ => None,
        }
    }
}
pub fn parse_address_list(value: &str) -> Option<(Vec<Address>, bool)> {
    let mut parser = Parser { tokens: tokenize(value, true)?, position: 0, error: false };
    let mut addresses = vec![parser.address(false)?];
    while parser.peek() == Some(TokenKind::Special(b',')) { parser.position += 1; addresses.push(parser.address(false)?); }
    (parser.position == parser.tokens.len()).then_some((addresses, parser.error))
}
