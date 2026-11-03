class Minstd(seed: Int) {
    var state=seed.toLong();
    var draws=0;
    fun draw(): Int {
        state=48271*state%2147483647;
        draws++;
        return state.toInt()
    };
    fun between(minimum: Int,maximum: Int)=minimum+draw()%(maximum-minimum+1)
}
