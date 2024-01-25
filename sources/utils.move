module movevault::utils {

    public fun safe_sub(a: u64, b: u64): u64 {
        if (b > a) {
            return 0
        };
        a - b
    }

    public fun max(a: u64, b: u64): u64 {
        if (a >= b) {return a};
        b
    }

    public fun min(a: u64, b: u64): u64 {
        if (a < b) {return a};
        b
    }
}