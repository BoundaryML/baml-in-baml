// Hand-written pieces the generated family (family.baml) refers to.

enum Freshness {
    Fresh,
    Regular,
}

type LitValue = int | string | bool;

// A deep narrowing met a variant the target member does not include.
class NarrowError {
    variant: string,
    into: string,
}

// The InferTy hash-cons pool: a handle is an index into `kinds`. Entries are
// one level deep (children are handles), so `index` hashes shallowly.
class InferPool {
    kinds: InferTy[],
    flags: int[],
    index: map<InferTy, int>,

    function new() -> Self {
        InferPool { kinds: [], flags: [], index: {} }
    }

    function add(self, k: InferTy) -> int {
        let found = self.index.get(k);
        if (found != null) {
            return found;
        }
        let h = self.kinds.length();
        self.kinds.push(k);
        self.flags.push(infer_flags(self, k));
        self.index.set(k, h);
        h
    }

    function has_infer(self, h: int) -> bool {
        (self.flags[h] & HAS_INFER) != 0
    }

    function has_error(self, h: int) -> bool {
        (self.flags[h] & HAS_ERROR) != 0
    }

    function has_typevar(self, h: int) -> bool {
        (self.flags[h] & HAS_TYPEVAR) != 0
    }
}
