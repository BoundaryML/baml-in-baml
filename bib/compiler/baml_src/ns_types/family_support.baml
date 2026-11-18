// Hand-written pieces the generated family (family.baml) refers to.

// port: baml_type/src/lib.rs::Freshness @ d9be6853b
enum Freshness {
    Fresh,
    Regular,
}

// port: baml_type/src/lib.rs::FunctionParamMode @ d9be6853b
enum FunctionParamMode {
    Required,
    Optional,
}

// port: the `Not<Member>` errors of the conversion matrix, as one class.
// A narrowing met a variant the target member does not include.
class NarrowError {
    variant: string,
    into: string,
}

// port: baml_type/src/interned.rs::TypeFlags @ d9be6853b
// Facts about a type computed once at intern time; the union of each node's
// own bit and all its children's flags.
const HAS_INFER = 1;
const HAS_ERROR = 2;
const HAS_TYPEVAR = 4;
const HAS_PROJECTION = 8;
const HAS_FRESH_LITERAL = 16;
const HAS_UNION = 32;

// A pool entry's own flag bits, before its children's are or'ed in.
function own_flags(k: InferTy) -> int throws never {
    match (k) {
        TyInferVar => HAS_INFER,
        TyError => HAS_ERROR,
        TyTypeVar => HAS_TYPEVAR,
        InferTyAssociatedTypeProjection => HAS_PROJECTION,
        let l: TyLiteral => {
            if (l.freshness == Freshness.Fresh) {
                HAS_FRESH_LITERAL
            } else {
                0
            }
        },
        InferTyUnion => HAS_UNION,
        _ => 0,
    }
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
        let flags = children_infer_ty(k).reduce(
            (acc, c) -> {
                acc | self.flags[c]
            },
            own_flags(k),
        );
        self.kinds.push(k);
        self.flags.push(flags);
        self.index.set(k, h);
        h
    }

    function has(self, h: int, flag: int) -> bool {
        (self.flags[h] & flag) != 0
    }
}
