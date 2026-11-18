// port: baml_syntax/src/nodes/types.rs @ d9be6853b
// Generated once by a porting script; edit by hand from here on.

type AnyType = PathType | LiteralType | ParenType | TupleType | FunctionType | OptionalType | ArrayType | UnionType | QualifiedPath | Bogus

// `int`, `map<K, V>`, `baml.Image`, `Self.Item`, `Future<T, E>`.
class PathType {
  span: TokenRange,
  head: Name,
  segments: PathSegment[],
  args: TypeArgs?,
}

// `"a"`, `-1`, `10n`, or a backtick string literal type.
class LiteralType {
  span: TokenRange,
  minus: int?,
  value: AnyLiteralTypeValue,
}

type AnyLiteralTypeValue = AnyLiteralTypeValueScalar | BacktickString | Bogus

// `(A | B)` — grouping only; a parenthesised list with an arrow is a
// [`FunctionType`].
class ParenType {
  span: TokenRange,
  l: int,
  inner: AnyType | Missing,
  r: int | Missing,
}

// `(a: A, B) -> R throws E`
class FunctionType {
  span: TokenRange,
  l: int,
  params: SepItem<FunctionTypeParam>[],
  r: int | Missing,
  arrow: int,
  ret: AnyType | Missing,
  throws_clause: ThrowsClause?,
}

// `T`, or `name: T` / `name?: T` for a named (optionally omittable) parameter.
class FunctionTypeParam {
  span: TokenRange,
  name: FunctionTypeParamName?,
  ty: AnyType | Missing,
}

class FunctionTypeParamName {
  name: Name,
  question: int?,
  colon: int,
}

// `T?`
class OptionalType {
  span: TokenRange,
  inner: AnyType,
  q: int,
}

// `T[]`
class ArrayType {
  span: TokenRange,
  inner: AnyType,
  l: int,
  r: int | Missing,
}

// `A | B | C` — members are never unions themselves.
class UnionType {
  span: TokenRange,
  first: AnyType,
  arms: UnionArm[],
}

class UnionArm {
  pipe: int,
  ty: AnyType | Missing,
}

// `(Base as Interface).item` — the same spelling names an associated type in
// type position and an associated item in expression position, so one node
// serves both.
class QualifiedPath {
  span: TokenRange,
  l: int,
  base: AnyType,
  as_kw: int,
  iface: AnyType | Missing,
  r: int | Missing,
  dot: int | Missing,
  member: Name | Missing,
}

class TupleType {
  span: TokenRange,
  l: int,
  elements: SepItem<AnyType>[],
  r: int | Missing,
}

// A `Token![LiteralTypeToken]` alternative, as its own node.
class AnyLiteralTypeValueScalar {
  token: int,
}
