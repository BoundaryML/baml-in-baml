// port: baml_compiler2_mir/src/optimize/effects.rs @ d9be6853b
//
// Evaluation-site proofs for dead-code elimination. Facts are intersected at
// joins and invalidated by writes/calls; a proof never classifies a whole
// local as nontrapping across its other definitions or uses.
//
// Namespace `mir.optimize` (Rust's private module `optimize::effects`); MIR
// items are `root.mir.<name>`.
//
// Restructured (BAML forces it):
// - Rust's `i64` bounds are BAML `int`s, one bit narrower. `Range::arithmetic`
//   computes in `bigint` where Rust widens to `i128`. Where Rust lets an
//   intermediate bound step one past `Int63` (`lo + 1` at `MAX`, `hi - 1`
//   at `MIN`, `saturating_add` of a length offset), the range it builds is
//   empty and constraining by it changes nothing; the port skips that call
//   (or clamps a bound the intersection discards) instead of overflowing.
// - `Facts.reads` is keyed by `read_key_string` (an injective spelling of
//   the `ReadKey`; Rust derives `Hash`), and each entry keeps the key itself
//   for `read_key_depends_on`: `(key, local)`.
// - `Range` is a `Copy` value in Rust: a `Range` here is never mutated, only
//   rebuilt. `Facts::clone` copies every map; their values are never
//   mutated either.
// - `Facts::merge` reports a change by tracking what it drops or widens
//   instead of comparing against a clone (`*self != before`); it only
//   removes entries and rewrites ranges, so the two agree.
// - `Analysis::new` seeds its worklist with the handlers in block order;
//   Rust walks a `HashSet` of them.

// port: baml_compiler2_mir/src/optimize/effects.rs::Range::INT @ d9be6853b
const RANGE_INT: Range = Range { lo: root.types.INT63_MIN, hi: root.types.INT63_MAX };

// port: baml_compiler2_mir/src/optimize/effects.rs::Range::LENGTH @ d9be6853b
const RANGE_LENGTH: Range = Range { lo: 0, hi: root.types.INT63_MAX };

// port: baml_compiler2_mir/src/optimize/effects.rs::Range @ d9be6853b
class Range {
    lo: int,
    hi: int,

    // port: baml_compiler2_mir/src/optimize/effects.rs::Range::exact @ d9be6853b
    function exact(n: int) -> Range throws never {
        Range { lo: n, hi: n }
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Range::intersect @ d9be6853b
    function intersect(self, other: Range) -> Range? throws never {
        let result = Range { lo: self.lo.max(other.lo), hi: self.hi.min(other.hi) };
        if (result.lo <= result.hi) {
            result
        } else {
            null
        }
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Range::join @ d9be6853b
    function join(self, other: Range, widen: bool, domain: Range) -> Range throws never {
        Range {
            lo: if (widen && other.lo < self.lo) {
                domain.lo
            } else {
                self.lo.min(other.lo)
            },
            hi: if (widen && other.hi > self.hi) {
                domain.hi
            } else {
                self.hi.max(other.hi)
            },
        }
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Range::arithmetic @ d9be6853b
    // Restructured: Rust's `i128` corners are `bigint`s.
    function arithmetic(self, op: root.mir.BinOp, rhs: Range) -> Range? throws never {
        let min = root.types.INT63_MIN;
        let divides = op == root.mir.BinOp.Div || op == root.mir.BinOp.Mod;
        if (
            divides
                && (
                    (rhs.lo <= 0 && rhs.hi >= 0)
                        || (self.lo == min && rhs.lo <= -1 && rhs.hi >= -1)
                )
        ) {
            return null;
        }
        if (op == root.mir.BinOp.Mod) {
            return RANGE_INT;
        }
        let lo: bigint? = null;
        let hi: bigint? = null;
        for (let a in [0n + self.lo, 0n + self.hi]) {
            for (let b in [0n + rhs.lo, 0n + rhs.hi]) {
                let n = match (op) {
                    root.mir.BinOp.Add => a + b,
                    root.mir.BinOp.Sub => a - b,
                    root.mir.BinOp.Mul => a * b,
                    root.mir.BinOp.Div => a / b,
                    _ => {
                        return null;
                    },
                };
                if (lo == null || n < lo) {
                    lo = n;
                }
                if (hi == null || n > hi) {
                    hi = n;
                }
            }
        }
        let low = root.types.int63_new(lo ?? 0n)
            ?? return null;
        let high = root.types.int63_new(hi ?? 0n)
            ?? return null;
        Range { lo: low, hi: high }
    }
}

// port: baml_compiler2_mir/src/optimize/effects.rs::Number @ d9be6853b
type Number = NumberConstant | NumberLocal | NumberLength;

class NumberConstant {
    value: int,
}

class NumberLocal {
    value: int,
}

// Rust's `Length(Local, i64)`: the current length of container `local` minus
// the nonnegative constant `offset`.
class NumberLength {
    local: int,
    offset: int,
}

// port: baml_compiler2_mir/src/optimize/effects.rs::ReadKey @ d9be6853b
type ReadKey = ReadKeyLocal | ReadKeyField | ReadKeyIndex;

class ReadKeyLocal {
    value: int,
}

// Rust's `Field(Box<Self>, usize)`.
class ReadKeyField {
    base: ReadKey,
    field: int,
}

// Rust's `Index(Box<Self>, Number, IndexKind)`.
class ReadKeyIndex {
    base: ReadKey,
    index: Number,
    kind: root.mir.IndexKind,
}

// port: baml_compiler2_mir/src/optimize/effects.rs::ReadKey (derived Hash) @ d9be6853b
// The map key of a `ReadKey`: one spelling per key, none shared. Every
// component has a leading tag and a base is parenthesized, so it parses back
// uniquely.
function read_key_string(read_key: ReadKey) -> string throws never {
    match (read_key) {
        let k: ReadKeyLocal => `l${k.value}`,
        let k: ReadKeyField => `f${k.field}(${read_key_string(k.base)})`,
        let k: ReadKeyIndex => {
            let kind = match (k.kind) {
                root.mir.IndexKind.Array => "a",
                root.mir.IndexKind.Map => "m",
                root.mir.IndexKind.Tuple => "t",
            };
            let index = match (k.index) {
                let n: NumberConstant => `c${n.value}`,
                let n: NumberLocal => `l${n.value}`,
                let n: NumberLength => `n${n.local},${n.offset}`,
            };
            `i${kind}${index}(${read_key_string(k.base)})`
        },
    }
}

// port: baml_compiler2_mir/src/optimize/effects.rs::ReadKey::depends_on @ d9be6853b
function read_key_depends_on(read_key: ReadKey, local: int) -> bool throws never {
    match (read_key) {
        let k: ReadKeyLocal => k.value == local,
        let k: ReadKeyField => read_key_depends_on(k.base, local),
        let k: ReadKeyIndex => {
            read_key_depends_on(k.base, local) || number_depends_on(k.index, local)
        },
    }
}

// port: baml_compiler2_mir/src/optimize/effects.rs::Number::depends_on @ d9be6853b
function number_depends_on(number: Number, local: int) -> bool throws never {
    match (number) {
        NumberConstant => false,
        let n: NumberLocal => n.value == local,
        let n: NumberLength => n.local == local,
    }
}

// port: baml_compiler2_mir/src/optimize/effects.rs::Condition @ d9be6853b
class Condition {
    op: root.mir.BinOp,
    left: Number,
    right: Number,
}

// port: baml_compiler2_mir/src/optimize/effects.rs::Facts @ d9be6853b
class Facts {
    // Copies refer to the same current value only until either slot is
    // written.
    aliases: map<int, int>,
    // Keyed by `read_key_string`; the entry is `(key, local)`.
    reads: map<string, (ReadKey, int)>,
    integers: map<int, Range>,
    lengths: map<int, Range>,
    length_values: map<int, (int, int)>,
    conditions: map<int, Condition>,

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts (derived Default) @ d9be6853b
    function default() -> Facts throws never {
        Facts {
            aliases: {},
            reads: {},
            integers: {},
            lengths: {},
            length_values: {},
            conditions: {},
        }
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts (derived Clone) @ d9be6853b
    // A copy of every map; the values are shared, and never mutated.
    function clone(self) -> Facts throws never {
        let out = Facts.default();
        for (let key in self.aliases.keys()) {
            out.aliases.set(key, self.aliases[key]);
        }
        for (let key in self.reads.keys()) {
            out.reads.set(key, self.reads[key]);
        }
        for (let key in self.integers.keys()) {
            out.integers.set(key, self.integers[key]);
        }
        for (let key in self.lengths.keys()) {
            out.lengths.set(key, self.lengths[key]);
        }
        for (let key in self.length_values.keys()) {
            out.length_values.set(key, self.length_values[key]);
        }
        for (let key in self.conditions.keys()) {
            out.conditions.set(key, self.conditions[key]);
        }
        out
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::root @ d9be6853b
    function root(self, local: int) -> int throws never {
        self.aliases.get(local) ?? local
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::read_key @ d9be6853b
    function read_key(
        self,
        place: root.mir.Place,
        body: root.mir.MirFunctionBody,
    ) -> ReadKey? throws never {
        let key: ReadKey = match (place) {
            // A bare captured local is its cell pointer, which no value read
            // names.
            let p: root.mir.PlaceLocal => {
                return ReadKeyLocal { value: self.root(p.value) };
            },
            // The value in a cell may change under any call or closure: no
            // key. A bare capture is a pointer, never a value read.
            root.mir.PlaceDeref | root.mir.PlaceCapture => {
                return null;
            },
            let p: root.mir.PlaceField => {
                let base = self.read_key(p.base, body)
                    ?? return null;
                ReadKeyField { base: base, field: p.field }
            },
            let p: root.mir.PlaceIndex => {
                let index = self.number(root.mir.operand_copy_local(p.index), body)
                    ?? return null;
                let range = self.range(index);
                if (range.lo == range.hi) {
                    index = NumberConstant { value: range.lo };
                }
                let base = self.read_key(p.base, body)
                    ?? return null;
                ReadKeyIndex { base: base, index: index, kind: p.kind }
            },
        };
        let known = self.reads.get(read_key_string(key));
        if (known != null) {
            ReadKeyLocal { value: known.1 }
        } else {
            key
        }
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::number @ d9be6853b
    function number(
        self,
        operand: root.mir.Operand,
        body: root.mir.MirFunctionBody,
    ) -> Number? throws never {
        match (operand) {
            root.mir.OperandConstant { value: root.mir.ConstantInt { value: let n } } => {
                NumberConstant { value: n }
            },
            root.mir.OperandCopy { value: root.mir.PlaceLocal { value: let read } }
                | root.mir.OperandMove { value: root.mir.PlaceLocal { value: let read } } =>
            {
                let local = self.root(read);
                let length = self.length_values.get(local);
                if (length != null) {
                    return NumberLength { local: length.0, offset: length.1 };
                }
                let integer_ty = match (body.locals[local].ty) {
                    root.types.TyInt | root.types.TyLiteral { value: root.base.LiteralInt } => true,
                    _ => false,
                };
                if (self.integers.has(local) || integer_ty) {
                    NumberLocal { value: local }
                } else {
                    null
                }
            },
            _ => null,
        }
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::range @ d9be6853b
    function range(self, number: Number) -> Range throws never {
        match (number) {
            let n: NumberConstant => Range.exact(n.value),
            let n: NumberLocal => self.integers.get(n.value) ?? RANGE_INT,
            let n: NumberLength => {
                let range = self.lengths.get(n.local) ?? RANGE_LENGTH;
                Range { lo: range.lo - n.offset, hi: range.hi - n.offset }
            },
        }
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::length_value @ d9be6853b
    // Restructured: Rust's `offset.checked_add(rhs.lo)` may exceed `Int63`
    // (then `offset <= MAX` rejects it); the sum is formed only once it is
    // known to fit.
    function length_value(
        self,
        value: root.mir.Rvalue,
        body: root.mir.MirFunctionBody,
    ) -> (int, int)? throws never {
        match (value) {
            let v: root.mir.RvalueLen => {
                match (self.read_key(v.value, body)) {
                    let k: ReadKeyLocal => (k.value, 0),
                    _ => null,
                }
            },
            let v: root.mir.RvalueUse => {
                match (self.number(v.value, body)) {
                    let n: NumberLength => (n.local, n.offset),
                    _ => null,
                }
            },
            root.mir.RvalueBinaryOp { op: root.mir.BinOp.Sub, left: let left, right: let right } => {
                let length = match (self.number(left, body)) {
                    let n: NumberLength => n,
                    _ => {
                        return null;
                    },
                };
                let number = self.number(right, body)
                    ?? return null;
                let rhs = self.range(number);
                if (rhs.lo == rhs.hi && rhs.lo >= 0 && length.offset <= root.types.INT63_MAX - rhs.lo) {
                    (length.local, length.offset + rhs.lo)
                } else {
                    null
                }
            },
            _ => null,
        }
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::integer_value @ d9be6853b
    function integer_value(
        self,
        value: root.mir.Rvalue,
        body: root.mir.MirFunctionBody,
    ) -> Range? throws never {
        match (value) {
            let v: root.mir.RvalueUse => {
                let number = self.number(v.value, body)
                    ?? return null;
                self.range(number)
            },
            root.mir.RvalueLen => RANGE_LENGTH,
            let v: root.mir.RvalueBinaryOp => {
                let left = self.number(v.left, body)
                    ?? return null;
                let right = self.number(v.right, body)
                    ?? return null;
                self.range(left).arithmetic(v.op, self.range(right))
            },
            root.mir.RvalueUnaryOp { op: root.mir.UnaryOp.Neg, operand: let operand } => {
                let number = self.number(operand, body)
                    ?? return null;
                Range.exact(0).arithmetic(root.mir.BinOp.Sub, self.range(number))
            },
            _ => null,
        }
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::condition @ d9be6853b
    function condition(self, operand: root.mir.Operand) -> Condition? throws never {
        match (operand) {
            root.mir.OperandCopy { value: root.mir.PlaceLocal { value: let local } }
                | root.mir.OperandMove { value: root.mir.PlaceLocal { value: let local } } =>
            {
                self.conditions.get(local)
            },
            _ => null,
        }
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::forget @ d9be6853b
    function forget(self, local: int) -> void throws never {
        for (let dest in self.aliases.keys()) {
            if (dest == local || self.aliases[dest] == local) {
                self.aliases.delete(dest);
            }
        }
        for (let key in self.reads.keys()) {
            let entry = self.reads[key];
            if (entry.1 == local || read_key_depends_on(entry.0, local)) {
                self.reads.delete(key);
            }
        }
        self.integers.delete(local);
        self.lengths.delete(local);
        for (let dest in self.length_values.keys()) {
            if (dest == local || self.length_values[dest].0 == local) {
                self.length_values.delete(dest);
            }
        }
        for (let dest in self.conditions.keys()) {
            let condition = self.conditions[dest];
            if (
                dest == local
                    || number_depends_on(condition.left, local)
                    || number_depends_on(condition.right, local)
            ) {
                self.conditions.delete(dest);
            }
        }
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::statement @ d9be6853b
    function statement(
        self,
        statement: root.mir.StatementKind,
        body: root.mir.MirFunctionBody,
    ) -> void throws never {
        match (statement) {
            root.mir.StatementKindAssign {
                destination: root.mir.PlaceLocal { value: let local },
                value: let value,
            } =>
            {
                self.statement_assign(local, value, body)
            },
            let s: root.mir.StatementKindFreshCell => self.forget(s.local),
            // Aliasing writes may invalidate both a container and references
            // obtained through it. Do not try to infer disjointness here.
            root.mir.StatementKindAssign
                | root.mir.StatementKindVirtualFieldStore
                | root.mir.StatementKindIntrinsic =>
            {
                self.aliases = {};
                self.reads = {};
                self.integers = {};
                self.lengths = {};
                self.length_values = {};
                self.conditions = {};
            },
            root.mir.StatementKindDrop | root.mir.StatementKindNop => {},
        }
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::statement @ d9be6853b
    // Restructured: the arm for `local = value` (a plain local destination).
    function statement_assign(
        self,
        local: int,
        value: root.mir.Rvalue,
        body: root.mir.MirFunctionBody,
    ) -> void throws never {
        let read = match (value) {
            root.mir.RvalueUse { value: root.mir.OperandCopy { value: let place } }
                | root.mir.RvalueUse { value: root.mir.OperandMove { value: let place } } =>
            {
                self.read_key(place, body)
            },
            _ => null,
        };
        let integer = self.integer_value(value, body);
        let length_value = self.length_value(value, body);
        let condition = match (value) {
            let v: root.mir.RvalueUse => self.condition(v.value),
            let v: root.mir.RvalueBinaryOp if is_comparison(v.op) => {
                let left = self.number(v.left, body);
                let right = self.number(v.right, body);
                if (left != null && right != null) {
                    Condition { op: v.op, left: left, right: right }
                } else {
                    null
                }
            },
            root.mir.RvalueUnaryOp { op: root.mir.UnaryOp.Not, operand: let operand } => {
                let inner = self.condition(operand);
                if (inner != null) {
                    Condition { op: invert(inner.op), left: inner.left, right: inner.right }
                } else {
                    null
                }
            },
            _ => null,
        };
        let length = match (value) {
            let v: root.mir.RvalueArray => Range.exact(v.elements.length()),
            let v: root.mir.RvalueUint8Array => Range.exact(v.value.length()),
            root.mir.RvalueUse {
                value: root.mir.OperandCopy { value: root.mir.PlaceLocal { value: let source } },
            }
                | root.mir.RvalueUse {
                value: root.mir.OperandMove { value: root.mir.PlaceLocal { value: let source } },
            } =>
            {
                self.lengths.get(source)
            },
            _ => null,
        };
        self.forget(local);
        if (read != null && !read_key_depends_on(read, local)) {
            match (read) {
                let source: ReadKeyLocal => {
                    self.aliases.set(local, source.value);
                },
                _ => {
                    self.reads.set(read_key_string(read), (read, local));
                },
            }
        }
        if (integer != null) {
            self.integers.set(local, integer);
        }
        if (length_value != null && length_value.0 != local) {
            self.length_values.set(local, length_value);
        }
        if (
            condition != null
                && !number_depends_on(condition.left, local)
                && !number_depends_on(condition.right, local)
        ) {
            self.conditions.set(local, condition);
        }
        if (length != null) {
            self.lengths.set(local, length);
        }
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::constrain @ d9be6853b
    // Restructured: Rust's `saturating_add` of a length offset can pass
    // `Int63::MAX` without saturating `i64`; a lower bound past it leaves
    // the intersection empty (nothing to do), an upper bound past it is
    // clamped by the intersection anyway.
    function constrain(self, number: Number, range: Range) -> void throws never {
        match (number) {
            NumberConstant => {},
            let n: NumberLocal => {
                let narrowed = self.range(number).intersect(range);
                if (narrowed != null) {
                    self.integers.set(n.value, narrowed);
                }
            },
            let n: NumberLength => {
                let max = root.types.INT63_MAX;
                if (range.lo > max - n.offset) {
                    return;
                }
                let bounds = Range {
                    lo: range.lo + n.offset,
                    hi: if (range.hi > max - n.offset) {
                        max
                    } else {
                        range.hi + n.offset
                    },
                };
                let old = self.lengths.get(n.local) ?? RANGE_LENGTH;
                let narrowed = old.intersect(bounds);
                if (narrowed != null) {
                    self.lengths.set(n.local, narrowed);
                }
            },
        }
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::branch @ d9be6853b
    // Restructured: a bound one past `Int63` (`lo + 1` at `MAX`, `hi - 1`
    // at `MIN`) makes an empty range, which constrains nothing, so that call
    // is skipped.
    function branch(self, condition: Condition, taken: bool) -> void throws never {
        let min = root.types.INT63_MIN;
        let max = root.types.INT63_MAX;
        let op = if (taken) {
            condition.op
        } else {
            invert(condition.op)
        };
        let left = self.range(condition.left);
        let right = self.range(condition.right);
        match (op) {
            root.mir.BinOp.Eq => {
                self.constrain(condition.left, right);
                self.constrain(condition.right, left);
            },
            root.mir.BinOp.Ne => {
                for (let side in [(condition.left, left, right), (condition.right, right, left)]) {
                    let range = side.1;
                    let excluded = side.2;
                    if (excluded.lo == excluded.hi) {
                        if (range.lo == excluded.lo) {
                            if (range.lo < max) {
                                self.constrain(side.0, Range { lo: range.lo + 1, hi: range.hi });
                            }
                        } else if (range.hi == excluded.lo) {
                            if (range.hi > min) {
                                self.constrain(side.0, Range { lo: range.lo, hi: range.hi - 1 });
                            }
                        }
                    }
                }
            },
            root.mir.BinOp.Lt | root.mir.BinOp.Le => {
                let strict = if (op == root.mir.BinOp.Lt) {
                    1
                } else {
                    0
                };
                if (!(strict == 1 && right.hi == min)) {
                    self.constrain(condition.left, Range { lo: min, hi: right.hi - strict });
                }
                if (!(strict == 1 && left.lo == max)) {
                    self.constrain(condition.right, Range { lo: left.lo + strict, hi: max });
                }
            },
            root.mir.BinOp.Gt | root.mir.BinOp.Ge => {
                self.branch(
                    Condition {
                        op: if (op == root.mir.BinOp.Gt) {
                            root.mir.BinOp.Lt
                        } else {
                            root.mir.BinOp.Le
                        },
                        left: condition.right,
                        right: condition.left,
                    },
                    true,
                )
            },
            _ => {},
        }
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::in_bounds @ d9be6853b
    function in_bounds(
        self,
        place: root.mir.Place,
        body: root.mir.MirFunctionBody,
    ) -> bool throws never {
        let index_place = match (place) {
            let p: root.mir.PlaceIndex if p.kind == root.mir.IndexKind.Array => p,
            _ => {
                return false;
            },
        };
        // A completed read can be repeated without trapping until a
        // dependency changes, even when we cannot express its successful
        // bounds test.
        if (self.read_key(place, body) is ReadKeyLocal) {
            return true;
        }
        let array = match (self.read_key(index_place.base, body)) {
            let k: ReadKeyLocal => k.value,
            _ => {
                return false;
            },
        };
        let length = self.lengths.get(array) ?? RANGE_LENGTH;
        let index = self.number(root.mir.operand_copy_local(index_place.index), body)
            ?? return false;
        match (index) {
            let n: NumberLength if n.local == array => {
                return n.offset > 0 && n.offset <= length.lo;
            },
            _ => {},
        }
        let range = self.range(index);
        // BAML accepts negative array indices relative to the end.
        range.lo >= 0 - length.lo && range.hi < length.lo
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::can_discard @ d9be6853b
    function can_discard(
        self,
        value: root.mir.Rvalue,
        body: root.mir.MirFunctionBody,
    ) -> bool throws never {
        let arithmetic = match (value) {
            root.mir.RvalueBinaryOp | root.mir.RvalueUnaryOp { op: root.mir.UnaryOp.Neg } => true,
            _ => false,
        };
        root.mir.rvalue_can_discard(value, in_bounds = (place) -> {
            self.in_bounds(place, body)
        })
            || arithmetic
            && self.integer_value(value, body) != null
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::merge @ d9be6853b
    function merge(self, other: Facts, widen: bool) -> bool throws never {
        let changed = false;
        for (let local in self.aliases.keys()) {
            if (other.aliases.get(local) != self.aliases[local]) {
                self.aliases.delete(local);
                changed = true;
            }
        }
        for (let key in self.reads.keys()) {
            let theirs = other.reads.get(key);
            if (theirs == null || theirs.1 != self.reads[key].1) {
                self.reads.delete(key);
                changed = true;
            }
        }
        for (
            let pair in [
                (self.integers, other.integers, RANGE_INT),
                (self.lengths, other.lengths, RANGE_LENGTH),
            ]
        ) {
            let mine = pair.0;
            for (let local in mine.keys()) {
                let theirs = pair.1.get(local);
                if (theirs == null) {
                    mine.delete(local);
                    changed = true;
                    continue;
                }
                let range = mine[local];
                let joined = range.join(theirs, widen, pair.2);
                if (joined.lo != range.lo || joined.hi != range.hi) {
                    mine.set(local, joined);
                    changed = true;
                }
            }
        }
        for (let local in self.length_values.keys()) {
            if (other.length_values.get(local) != self.length_values[local]) {
                self.length_values.delete(local);
                changed = true;
            }
        }
        for (let local in self.conditions.keys()) {
            if (other.conditions.get(local) != self.conditions[local]) {
                self.conditions.delete(local);
                changed = true;
            }
        }
        changed
    }
}

// port: baml_compiler2_mir/src/optimize/effects.rs::Facts::statement @ d9be6853b
// The comparisons `statement` records a branch fact for (its `matches!`).
function is_comparison(op: root.mir.BinOp) -> bool throws never {
    match (op) {
        root.mir.BinOp.Eq
            | root.mir.BinOp.Ne
            | root.mir.BinOp.Lt
            | root.mir.BinOp.Le
            | root.mir.BinOp.Gt
            | root.mir.BinOp.Ge =>
        {
            true
        },
        _ => false,
    }
}

// port: baml_compiler2_mir/src/optimize/effects.rs::invert @ d9be6853b
function invert(op: root.mir.BinOp) -> root.mir.BinOp throws never {
    match (op) {
        root.mir.BinOp.Eq => root.mir.BinOp.Ne,
        root.mir.BinOp.Ne => root.mir.BinOp.Eq,
        root.mir.BinOp.Lt => root.mir.BinOp.Ge,
        root.mir.BinOp.Le => root.mir.BinOp.Gt,
        root.mir.BinOp.Gt => root.mir.BinOp.Le,
        root.mir.BinOp.Ge => root.mir.BinOp.Lt,
        _ => baml.sys.panic("only comparisons have branch facts"),
    }
}

// port: baml_compiler2_mir/src/optimize/effects.rs::Analysis @ d9be6853b
class Analysis {
    discardable: bool[][],

    // port: baml_compiler2_mir/src/optimize/effects.rs::Analysis::new @ d9be6853b
    function new(body: root.mir.MirFunctionBody) -> Analysis throws never {
        let handlers: map<int, bool> = {};
        for (let handler in body.handlers()) {
            handlers.set(handler.0, true);
        }
        let clobber_model = root.mir.ClobberModel.for_body(body);
        let entries: (Facts?)[] = baml.Array.filled(body.blocks.length(), null);
        let work: int[] = [];
        for (let entry in [body.entry].concat(handlers.keys())) {
            entries[entry] = Facts.default();
            work.push(entry);
        }
        while let id: int = work.shift() {
            let facts = (entries[id] ?? baml.sys.panic("a queued block has facts")).clone();
            let block = body.blocks[id];
            for (let statement in block.statements) {
                facts.statement(statement.kind, body);
            }
            let term = block.terminator;
            if (term == null) {
                continue;
            }
            // Anything that may run code this frame cannot see writes every
            // heap location, and every fact here is about one.
            if (root.mir.terminator_clobbers(clobber_model, term).heap) {
                facts = Facts.default();
            } else {
                match (term) {
                    let t: root.mir.TerminatorShortCircuit => {
                        match (t.destination) {
                            let p: root.mir.PlaceLocal => facts.forget(p.value),
                            _ => {
                                facts = Facts.default();
                            },
                        }
                    },
                    let t: root.mir.TerminatorNarrowBind => facts.forget(t.destination),
                    _ => {},
                }
            }
            for (let target in root.mir.terminator_successors(term)) {
                if (target == body.entry || handlers.has(target)) {
                    continue;
                }
                let outgoing = facts.clone();
                match (term) {
                    let t: root.mir.TerminatorBranch if t.then_block != t.else_block => {
                        let condition = facts.condition(t.condition);
                        if (condition != null) {
                            outgoing.branch(condition, target == t.then_block);
                        }
                    },
                    _ => {},
                }
                let previous = entries[target];
                let changed = if (previous != null) {
                    // Every cycle includes a backwards-numbered edge. Widen
                    // growing ranges there, so loop trip counts do not bound
                    // analysis time. Acyclic backward edges only lose
                    // precision.
                    previous.merge(outgoing, target <= id)
                } else {
                    entries[target] = outgoing;
                    true
                };
                if (changed) {
                    work.push(target);
                }
            }
        }
        let discardable = body.blocks.map((block) -> {
            let start = entries[block.id];
            let facts = if (start != null) {
                start.clone()
            } else {
                Facts.default()
            };
            block.statements.map((statement) -> {
                let safe = match (statement.kind) {
                    let s: root.mir.StatementKindAssign => facts.can_discard(s.value, body),
                    let s: root.mir.StatementKindDrop => {
                        facts.can_discard(
                            root.mir.RvalueUse { value: root.mir.OperandCopy { value: s.value } },
                            body,
                        )
                    },
                    _ => false,
                };
                facts.statement(statement.kind, body);
                safe
            })
        });
        Analysis { discardable: discardable }
    }
}

// port: baml_compiler2_mir/src/optimize/effects.rs::remove_trivial_drops @ d9be6853b
// A local read used only to discard its result has no effect itself.
// Removing these sinks lets DCE reconsider their producers; potentially
// trapping producers will get an explicit discard again in
// `eliminate_dead_locals`. Restructured: `retain` builds a fresh statement
// array.
function remove_trivial_drops(body: root.mir.MirFunctionBody) -> void throws never {
    let analysis = Analysis.new(body);
    for (let block in body.blocks) {
        let row = analysis.discardable[block.id];
        let kept: root.mir.Statement[] = [];
        for (let index = 0; index < block.statements.length(); index += 1) {
            let statement = block.statements[index];
            let remove = statement.kind is root.mir.StatementKindDrop && row[index];
            if (!remove) {
                kept.push(statement);
            }
        }
        block.statements = kept;
    }
}
