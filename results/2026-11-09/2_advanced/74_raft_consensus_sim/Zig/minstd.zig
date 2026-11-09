pub const Minstd = struct {
    state: i64,
    draws: usize = 0,
    pub fn draw(self: *Minstd) i64 {
        self.state = @mod(48271 * self.state, 2147483647);
        self.draws += 1;
        return self.state;
    }
    pub fn between(self: *Minstd, minimum: i64, maximum: i64) i64 {
        return minimum + @mod(self.draw(), maximum - minimum + 1);
    }
};
