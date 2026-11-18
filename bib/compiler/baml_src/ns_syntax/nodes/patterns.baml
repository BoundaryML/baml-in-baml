// port: baml_syntax/src/nodes/patterns.rs @ d9be6853b
// Generated once by a porting script; edit by hand from here on.

type AnyPattern = BindingPattern
    | WildcardPattern
    | DestructurePattern
    | ArrayPattern
    | TypePattern
    | ParenPattern
    | TuplePattern
    | UnionPattern
    | Bogus;

// `let x`, `x`, `let x: int | string`.
class BindingPattern {
    span: TokenRange,
    introducer: int?,
    name: Name,
    ascription: PatternAscription?,
}

// `: pattern` — narrows a binding, or gives a field its sub-pattern.
class PatternAscription {
    colon: int,
    pattern: AnyPattern | Missing,
}

// `_` or `let _`.
class WildcardPattern {
    span: TokenRange,
    introducer: int?,
    underscore: int,
}

// `let Point<T> { x, y: let py }`
class DestructurePattern {
    span: TokenRange,
    introducer: int?,
    path: PathType,
    l: int,
    fields: SepItem<FieldPattern>[],
    r: int | Missing,
}

// `x` (shorthand) or `x: pattern`.
class FieldPattern {
    span: TokenRange,
    name: Name,
    sub: PatternAscription?,
}

// `[a, ..let rest]: T[]`
class ArrayPattern {
    span: TokenRange,
    l: int,
    elements: SepItem<AnyArrayPatternElement>[],
    r: int | Missing,
    ascription: TypeAscription?,
}

type AnyArrayPatternElement = AnyPattern | RestPattern | Bogus;

// `..` or `..pattern`
class RestPattern {
    span: TokenRange,
    dots: int,
    pattern: AnyPattern?,
}

// A type used as a pattern: `int`, `"a"`, `-1`, `Foo<T>[]`.
class TypePattern {
    span: TokenRange,
    ty: AnyType,
}

class ParenPattern {
    span: TokenRange,
    l: int,
    inner: AnyPattern | Missing,
    r: int | Missing,
}

// `A | B | C`
class UnionPattern {
    span: TokenRange,
    first: AnyPattern,
    arms: PatternArm[],
}

class PatternArm {
    pipe: int,
    pattern: AnyPattern | Missing,
}

class TuplePattern {
    span: TokenRange,
    l: int,
    elements: SepItem<AnyPattern>[],
    r: int | Missing,
}
