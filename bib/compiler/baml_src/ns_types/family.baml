// GENERATED from ns_family_gen/spec.baml by `baml run types.family_gen.main`.
// Do not edit by hand: change the spec and regenerate.

// == Shared leaf variants ==================================================

class TyInt {
}

class TyBigint {
}

class TyFloat {
}

class TyString {
}

class TyBool {
}

class TyNull {
}

class TyUint8Array {
}

class TyMedia {
    kind: string,
}

class TyLiteral {
    value: LitValue,
    freshness: Freshness,
}

class TyEnum {
    name: string,
}

class TyEnumVariant {
    name: string,
    variant: string,
}

class TyRustType {
}

class TyType {
}

class TyResource {
}

class TyPromptAst {
}

class TyTypeAlias {
    name: string,
}

class TyTypeVar {
    name: string,
}

class TyUnknown {
}

class TyNever {
}

class TyError {
}

class TyInfer {
}

class TyInferVar {
    id: int,
}

class TyTypeArgRef {
    index: int,
}

// -- Ty --------------------------------------------------------------------

class TyClass {
    name: string,
    args: Ty[],
}

class TyInterface {
    name: string,
    args: Ty[],
    assoc: Ty[],
}

class TyList {
    elem: Ty,
}

class TyMap {
    key: Ty,
    value: Ty,
}

class TyUnion {
    members: Ty[],
}

class TyFunction {
    params: Ty[],
    ret: Ty,
    throws_: Ty,
}

class TyFuture {
    value: Ty,
    error: Ty,
}

class TyProjection {
    base: Ty,
    interface_args: Ty[],
    member: string,
}

class TyTuple {
    items: Ty[],
}

type Ty = TyInt
    | TyBigint
    | TyFloat
    | TyString
    | TyBool
    | TyNull
    | TyUint8Array
    | TyMedia
    | TyLiteral
    | TyClass
    | TyInterface
    | TyEnum
    | TyEnumVariant
    | TyList
    | TyMap
    | TyUnion
    | TyFunction
    | TyFuture
    | TyRustType
    | TyType
    | TyResource
    | TyPromptAst
    | TyTypeAlias
    | TyTypeVar
    | TyProjection
    | TyUnknown
    | TyNever
    | TyError
    | TyTuple;

// -- LoweringTy ------------------------------------------------------------

class LoweringTyClass {
    name: string,
    args: LoweringTy[],
}

class LoweringTyInterface {
    name: string,
    args: LoweringTy[],
    assoc: LoweringTy[],
}

class LoweringTyList {
    elem: LoweringTy,
}

class LoweringTyMap {
    key: LoweringTy,
    value: LoweringTy,
}

class LoweringTyUnion {
    members: LoweringTy[],
}

class LoweringTyFunction {
    params: LoweringTy[],
    ret: LoweringTy,
    throws_: LoweringTy,
}

class LoweringTyFuture {
    value: LoweringTy,
    error: LoweringTy,
}

class LoweringTyProjection {
    base: LoweringTy,
    interface_args: LoweringTy[],
    member: string,
}

class LoweringTyTuple {
    items: LoweringTy[],
}

type LoweringTy = TyInt
    | TyBigint
    | TyFloat
    | TyString
    | TyBool
    | TyNull
    | TyUint8Array
    | TyMedia
    | TyLiteral
    | LoweringTyClass
    | LoweringTyInterface
    | TyEnum
    | TyEnumVariant
    | LoweringTyList
    | LoweringTyMap
    | LoweringTyUnion
    | LoweringTyFunction
    | LoweringTyFuture
    | TyRustType
    | TyType
    | TyResource
    | TyPromptAst
    | TyTypeAlias
    | TyTypeVar
    | LoweringTyProjection
    | TyUnknown
    | TyNever
    | TyError
    | TyInfer
    | LoweringTyTuple;

// -- RuntimeTy -------------------------------------------------------------

class RuntimeTyClass {
    name: string,
    args: RuntimeTy[],
}

class RuntimeTyInterface {
    name: string,
    args: RuntimeTy[],
    assoc: RuntimeTy[],
}

class RuntimeTyList {
    elem: RuntimeTy,
}

class RuntimeTyMap {
    key: RuntimeTy,
    value: RuntimeTy,
}

class RuntimeTyUnion {
    members: RuntimeTy[],
}

class RuntimeTyFunction {
    params: RuntimeTy[],
    ret: RuntimeTy,
    throws_: RuntimeTy,
}

class RuntimeTyFuture {
    value: RuntimeTy,
    error: RuntimeTy,
}

class RuntimeTyProjection {
    base: RuntimeTy,
    interface_args: RuntimeTy[],
    member: string,
}

class RuntimeTyTuple {
    items: RuntimeTy[],
}

type RuntimeTy = TyInt
    | TyBigint
    | TyFloat
    | TyString
    | TyBool
    | TyNull
    | TyUint8Array
    | TyMedia
    | TyLiteral
    | RuntimeTyClass
    | RuntimeTyInterface
    | TyEnum
    | TyEnumVariant
    | RuntimeTyList
    | RuntimeTyMap
    | RuntimeTyUnion
    | RuntimeTyFunction
    | RuntimeTyFuture
    | TyRustType
    | TyType
    | TyResource
    | TyPromptAst
    | TyTypeAlias
    | TyTypeVar
    | RuntimeTyProjection
    | TyUnknown
    | TyNever
    | RuntimeTyTuple;

// -- CodegenTy -------------------------------------------------------------

class CodegenTyClass {
    name: string,
    args: CodegenTy[],
}

class CodegenTyInterface {
    name: string,
    args: CodegenTy[],
    assoc: CodegenTy[],
}

class CodegenTyList {
    elem: CodegenTy,
}

class CodegenTyMap {
    key: CodegenTy,
    value: CodegenTy,
}

class CodegenTyUnion {
    members: CodegenTy[],
}

class CodegenTyFunction {
    params: CodegenTy[],
    ret: CodegenTy,
    throws_: CodegenTy,
}

class CodegenTyFuture {
    value: CodegenTy,
    error: CodegenTy,
}

class CodegenTyTuple {
    items: CodegenTy[],
}

type CodegenTy = TyInt
    | TyBigint
    | TyFloat
    | TyString
    | TyBool
    | TyNull
    | TyUint8Array
    | TyMedia
    | TyLiteral
    | CodegenTyClass
    | CodegenTyInterface
    | TyEnum
    | TyEnumVariant
    | CodegenTyList
    | CodegenTyMap
    | CodegenTyUnion
    | CodegenTyFunction
    | CodegenTyFuture
    | TyRustType
    | TyType
    | TyResource
    | TyPromptAst
    | TyTypeAlias
    | TyTypeVar
    | TyUnknown
    | TyNever
    | CodegenTyTuple;

// -- RealizedTy ------------------------------------------------------------

class RealizedTyClass {
    name: string,
    args: RealizedTy[],
}

class RealizedTyInterface {
    name: string,
    args: RealizedTy[],
    assoc: RealizedTy[],
}

class RealizedTyList {
    elem: RealizedTy,
}

class RealizedTyMap {
    key: RealizedTy,
    value: RealizedTy,
}

class RealizedTyUnion {
    members: RealizedTy[],
}

class RealizedTyFunction {
    params: RealizedTy[],
    ret: RealizedTy,
    throws_: RealizedTy,
}

class RealizedTyFuture {
    value: RealizedTy,
    error: RealizedTy,
}

class RealizedTyTuple {
    items: RealizedTy[],
}

type RealizedTy = TyInt
    | TyBigint
    | TyFloat
    | TyString
    | TyBool
    | TyNull
    | TyUint8Array
    | TyMedia
    | TyLiteral
    | RealizedTyClass
    | RealizedTyInterface
    | TyEnum
    | TyEnumVariant
    | RealizedTyList
    | RealizedTyMap
    | RealizedTyUnion
    | RealizedTyFunction
    | RealizedTyFuture
    | TyRustType
    | TyType
    | TyResource
    | TyPromptAst
    | TyTypeAlias
    | TyUnknown
    | TyNever
    | RealizedTyTuple;

// -- ConcreteTy ------------------------------------------------------------

class ConcreteTyClass {
    name: string,
    args: ConcreteTy[],
}

class ConcreteTyList {
    elem: ConcreteTy,
}

class ConcreteTyMap {
    key: ConcreteTy,
    value: ConcreteTy,
}

class ConcreteTyFunction {
    params: ConcreteTy[],
    ret: ConcreteTy,
    throws_: ConcreteTy,
}

class ConcreteTyFuture {
    value: ConcreteTy,
    error: ConcreteTy,
}

class ConcreteTyTuple {
    items: ConcreteTy[],
}

type ConcreteTy = TyInt
    | TyBigint
    | TyFloat
    | TyString
    | TyBool
    | TyNull
    | TyUint8Array
    | TyMedia
    | ConcreteTyClass
    | TyEnum
    | ConcreteTyList
    | ConcreteTyMap
    | ConcreteTyFunction
    | ConcreteTyFuture
    | TyRustType
    | TyType
    | TyResource
    | TyPromptAst
    | TyNever
    | ConcreteTyTuple;

// -- TyTemplate ------------------------------------------------------------

class TyTemplateClass {
    name: string,
    args: TyTemplate[],
}

class TyTemplateInterface {
    name: string,
    args: TyTemplate[],
    assoc: TyTemplate[],
}

class TyTemplateList {
    elem: TyTemplate,
}

class TyTemplateMap {
    key: TyTemplate,
    value: TyTemplate,
}

class TyTemplateUnion {
    members: TyTemplate[],
}

class TyTemplateFunction {
    params: TyTemplate[],
    ret: TyTemplate,
    throws_: TyTemplate,
}

class TyTemplateFuture {
    value: TyTemplate,
    error: TyTemplate,
}

class TyTemplateProjection {
    base: TyTemplate,
    interface_args: TyTemplate[],
    member: string,
}

class TyTemplateTuple {
    items: TyTemplate[],
}

type TyTemplate = TyInt
    | TyBigint
    | TyFloat
    | TyString
    | TyBool
    | TyNull
    | TyUint8Array
    | TyMedia
    | TyLiteral
    | TyTemplateClass
    | TyTemplateInterface
    | TyEnum
    | TyEnumVariant
    | TyTemplateList
    | TyTemplateMap
    | TyTemplateUnion
    | TyTemplateFunction
    | TyTemplateFuture
    | TyRustType
    | TyType
    | TyResource
    | TyPromptAst
    | TyTypeAlias
    | TyTemplateProjection
    | TyUnknown
    | TyNever
    | TyTypeArgRef
    | TyTemplateTuple;

// -- InferTy ---------------------------------------------------------------

class InferTyClass {
    name: string,
    args: int[],
}

class InferTyInterface {
    name: string,
    args: int[],
    assoc: int[],
}

class InferTyList {
    elem: int,
}

class InferTyMap {
    key: int,
    value: int,
}

class InferTyUnion {
    members: int[],
}

class InferTyFunction {
    params: int[],
    ret: int,
    throws_: int,
}

class InferTyFuture {
    value: int,
    error: int,
}

class InferTyProjection {
    base: int,
    interface_args: int[],
    member: string,
}

class InferTyTuple {
    items: int[],
}

type InferTy = TyInt
    | TyBigint
    | TyFloat
    | TyString
    | TyBool
    | TyNull
    | TyUint8Array
    | TyMedia
    | TyLiteral
    | InferTyClass
    | InferTyInterface
    | TyEnum
    | TyEnumVariant
    | InferTyList
    | InferTyMap
    | InferTyUnion
    | InferTyFunction
    | InferTyFuture
    | TyRustType
    | TyType
    | TyResource
    | TyPromptAst
    | TyTypeAlias
    | TyTypeVar
    | InferTyProjection
    | TyUnknown
    | TyNever
    | TyError
    | TyInferVar
    | InferTyTuple;

// == Widening and narrowing ================================================

// Infallible: every Ty variant is a LoweringTy variant.
function widen_ty_to_lowering_ty(t: Ty) -> LoweringTy throws never {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever
            | TyError =>
        {
            x
        },
        let x: TyClass => {
            LoweringTyClass { name: x.name, args: x.args.map(widen_ty_to_lowering_ty) }
        },
        let x: TyInterface => {
            LoweringTyInterface {
                name: x.name,
                args: x.args.map(widen_ty_to_lowering_ty),
                assoc: x.assoc.map(widen_ty_to_lowering_ty),
            }
        },
        let x: TyList => LoweringTyList { elem: widen_ty_to_lowering_ty(x.elem) },
        let x: TyMap => {
            LoweringTyMap {
                key: widen_ty_to_lowering_ty(x.key),
                value: widen_ty_to_lowering_ty(x.value),
            }
        },
        let x: TyUnion => LoweringTyUnion { members: x.members.map(widen_ty_to_lowering_ty) },
        let x: TyFunction => {
            LoweringTyFunction {
                params: x.params.map(widen_ty_to_lowering_ty),
                ret: widen_ty_to_lowering_ty(x.ret),
                throws_: widen_ty_to_lowering_ty(x.throws_),
            }
        },
        let x: TyFuture => {
            LoweringTyFuture {
                value: widen_ty_to_lowering_ty(x.value),
                error: widen_ty_to_lowering_ty(x.error),
            }
        },
        let x: TyProjection => {
            LoweringTyProjection {
                base: widen_ty_to_lowering_ty(x.base),
                interface_args: x.interface_args.map(widen_ty_to_lowering_ty),
                member: x.member,
            }
        },
        let x: TyTuple => LoweringTyTuple { items: x.items.map(widen_ty_to_lowering_ty) },
    }
}

// Fails if any variant, at any depth, is outside RuntimeTy.
function narrow_ty_to_runtime_ty(t: Ty) -> RuntimeTy throws NarrowError {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: TyClass => RuntimeTyClass { name: x.name, args: x.args.map(narrow_ty_to_runtime_ty) },
        let x: TyInterface => {
            RuntimeTyInterface {
                name: x.name,
                args: x.args.map(narrow_ty_to_runtime_ty),
                assoc: x.assoc.map(narrow_ty_to_runtime_ty),
            }
        },
        let x: TyList => RuntimeTyList { elem: narrow_ty_to_runtime_ty(x.elem) },
        let x: TyMap => {
            RuntimeTyMap {
                key: narrow_ty_to_runtime_ty(x.key),
                value: narrow_ty_to_runtime_ty(x.value),
            }
        },
        let x: TyUnion => RuntimeTyUnion { members: x.members.map(narrow_ty_to_runtime_ty) },
        let x: TyFunction => {
            RuntimeTyFunction {
                params: x.params.map(narrow_ty_to_runtime_ty),
                ret: narrow_ty_to_runtime_ty(x.ret),
                throws_: narrow_ty_to_runtime_ty(x.throws_),
            }
        },
        let x: TyFuture => {
            RuntimeTyFuture {
                value: narrow_ty_to_runtime_ty(x.value),
                error: narrow_ty_to_runtime_ty(x.error),
            }
        },
        let x: TyProjection => {
            RuntimeTyProjection {
                base: narrow_ty_to_runtime_ty(x.base),
                interface_args: x.interface_args.map(narrow_ty_to_runtime_ty),
                member: x.member,
            }
        },
        let x: TyTuple => RuntimeTyTuple { items: x.items.map(narrow_ty_to_runtime_ty) },
        TyError => throw NarrowError { variant: "Error", into: "RuntimeTy" },
    }
}

// Fails if any variant, at any depth, is outside CodegenTy.
function narrow_ty_to_codegen_ty(t: Ty) -> CodegenTy throws NarrowError {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: TyClass => CodegenTyClass { name: x.name, args: x.args.map(narrow_ty_to_codegen_ty) },
        let x: TyInterface => {
            CodegenTyInterface {
                name: x.name,
                args: x.args.map(narrow_ty_to_codegen_ty),
                assoc: x.assoc.map(narrow_ty_to_codegen_ty),
            }
        },
        let x: TyList => CodegenTyList { elem: narrow_ty_to_codegen_ty(x.elem) },
        let x: TyMap => {
            CodegenTyMap {
                key: narrow_ty_to_codegen_ty(x.key),
                value: narrow_ty_to_codegen_ty(x.value),
            }
        },
        let x: TyUnion => CodegenTyUnion { members: x.members.map(narrow_ty_to_codegen_ty) },
        let x: TyFunction => {
            CodegenTyFunction {
                params: x.params.map(narrow_ty_to_codegen_ty),
                ret: narrow_ty_to_codegen_ty(x.ret),
                throws_: narrow_ty_to_codegen_ty(x.throws_),
            }
        },
        let x: TyFuture => {
            CodegenTyFuture {
                value: narrow_ty_to_codegen_ty(x.value),
                error: narrow_ty_to_codegen_ty(x.error),
            }
        },
        let x: TyTuple => CodegenTyTuple { items: x.items.map(narrow_ty_to_codegen_ty) },
        TyProjection => throw NarrowError { variant: "Projection", into: "CodegenTy" },
        TyError => throw NarrowError { variant: "Error", into: "CodegenTy" },
    }
}

// Fails if any variant, at any depth, is outside RealizedTy.
function narrow_ty_to_realized_ty(t: Ty) -> RealizedTy throws NarrowError {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: TyClass => {
            RealizedTyClass { name: x.name, args: x.args.map(narrow_ty_to_realized_ty) }
        },
        let x: TyInterface => {
            RealizedTyInterface {
                name: x.name,
                args: x.args.map(narrow_ty_to_realized_ty),
                assoc: x.assoc.map(narrow_ty_to_realized_ty),
            }
        },
        let x: TyList => RealizedTyList { elem: narrow_ty_to_realized_ty(x.elem) },
        let x: TyMap => {
            RealizedTyMap {
                key: narrow_ty_to_realized_ty(x.key),
                value: narrow_ty_to_realized_ty(x.value),
            }
        },
        let x: TyUnion => RealizedTyUnion { members: x.members.map(narrow_ty_to_realized_ty) },
        let x: TyFunction => {
            RealizedTyFunction {
                params: x.params.map(narrow_ty_to_realized_ty),
                ret: narrow_ty_to_realized_ty(x.ret),
                throws_: narrow_ty_to_realized_ty(x.throws_),
            }
        },
        let x: TyFuture => {
            RealizedTyFuture {
                value: narrow_ty_to_realized_ty(x.value),
                error: narrow_ty_to_realized_ty(x.error),
            }
        },
        let x: TyTuple => RealizedTyTuple { items: x.items.map(narrow_ty_to_realized_ty) },
        TyTypeVar => throw NarrowError { variant: "TypeVar", into: "RealizedTy" },
        TyProjection => throw NarrowError { variant: "Projection", into: "RealizedTy" },
        TyError => throw NarrowError { variant: "Error", into: "RealizedTy" },
    }
}

// Fails if any variant, at any depth, is outside ConcreteTy.
function narrow_ty_to_concrete_ty(t: Ty) -> ConcreteTy throws NarrowError {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyEnum
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyNever =>
        {
            x
        },
        let x: TyClass => {
            ConcreteTyClass { name: x.name, args: x.args.map(narrow_ty_to_concrete_ty) }
        },
        let x: TyList => ConcreteTyList { elem: narrow_ty_to_concrete_ty(x.elem) },
        let x: TyMap => {
            ConcreteTyMap {
                key: narrow_ty_to_concrete_ty(x.key),
                value: narrow_ty_to_concrete_ty(x.value),
            }
        },
        let x: TyFunction => {
            ConcreteTyFunction {
                params: x.params.map(narrow_ty_to_concrete_ty),
                ret: narrow_ty_to_concrete_ty(x.ret),
                throws_: narrow_ty_to_concrete_ty(x.throws_),
            }
        },
        let x: TyFuture => {
            ConcreteTyFuture {
                value: narrow_ty_to_concrete_ty(x.value),
                error: narrow_ty_to_concrete_ty(x.error),
            }
        },
        let x: TyTuple => ConcreteTyTuple { items: x.items.map(narrow_ty_to_concrete_ty) },
        TyLiteral => throw NarrowError { variant: "Literal", into: "ConcreteTy" },
        TyInterface => throw NarrowError { variant: "Interface", into: "ConcreteTy" },
        TyEnumVariant => throw NarrowError { variant: "EnumVariant", into: "ConcreteTy" },
        TyUnion => throw NarrowError { variant: "Union", into: "ConcreteTy" },
        TyTypeAlias => throw NarrowError { variant: "TypeAlias", into: "ConcreteTy" },
        TyTypeVar => throw NarrowError { variant: "TypeVar", into: "ConcreteTy" },
        TyProjection => throw NarrowError { variant: "Projection", into: "ConcreteTy" },
        TyUnknown => throw NarrowError { variant: "Unknown", into: "ConcreteTy" },
        TyError => throw NarrowError { variant: "Error", into: "ConcreteTy" },
    }
}

// Fails if any variant, at any depth, is outside Ty.
function narrow_lowering_ty_to_ty(t: LoweringTy) -> Ty throws NarrowError {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever
            | TyError =>
        {
            x
        },
        let x: LoweringTyClass => {
            TyClass { name: x.name, args: x.args.map(narrow_lowering_ty_to_ty) }
        },
        let x: LoweringTyInterface => {
            TyInterface {
                name: x.name,
                args: x.args.map(narrow_lowering_ty_to_ty),
                assoc: x.assoc.map(narrow_lowering_ty_to_ty),
            }
        },
        let x: LoweringTyList => TyList { elem: narrow_lowering_ty_to_ty(x.elem) },
        let x: LoweringTyMap => {
            TyMap { key: narrow_lowering_ty_to_ty(x.key), value: narrow_lowering_ty_to_ty(x.value) }
        },
        let x: LoweringTyUnion => TyUnion { members: x.members.map(narrow_lowering_ty_to_ty) },
        let x: LoweringTyFunction => {
            TyFunction {
                params: x.params.map(narrow_lowering_ty_to_ty),
                ret: narrow_lowering_ty_to_ty(x.ret),
                throws_: narrow_lowering_ty_to_ty(x.throws_),
            }
        },
        let x: LoweringTyFuture => {
            TyFuture {
                value: narrow_lowering_ty_to_ty(x.value),
                error: narrow_lowering_ty_to_ty(x.error),
            }
        },
        let x: LoweringTyProjection => {
            TyProjection {
                base: narrow_lowering_ty_to_ty(x.base),
                interface_args: x.interface_args.map(narrow_lowering_ty_to_ty),
                member: x.member,
            }
        },
        let x: LoweringTyTuple => TyTuple { items: x.items.map(narrow_lowering_ty_to_ty) },
        TyInfer => throw NarrowError { variant: "Infer", into: "Ty" },
    }
}

// Fails if any variant, at any depth, is outside RuntimeTy.
function narrow_lowering_ty_to_runtime_ty(t: LoweringTy) -> RuntimeTy throws NarrowError {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: LoweringTyClass => {
            RuntimeTyClass { name: x.name, args: x.args.map(narrow_lowering_ty_to_runtime_ty) }
        },
        let x: LoweringTyInterface => {
            RuntimeTyInterface {
                name: x.name,
                args: x.args.map(narrow_lowering_ty_to_runtime_ty),
                assoc: x.assoc.map(narrow_lowering_ty_to_runtime_ty),
            }
        },
        let x: LoweringTyList => RuntimeTyList { elem: narrow_lowering_ty_to_runtime_ty(x.elem) },
        let x: LoweringTyMap => {
            RuntimeTyMap {
                key: narrow_lowering_ty_to_runtime_ty(x.key),
                value: narrow_lowering_ty_to_runtime_ty(x.value),
            }
        },
        let x: LoweringTyUnion => {
            RuntimeTyUnion { members: x.members.map(narrow_lowering_ty_to_runtime_ty) }
        },
        let x: LoweringTyFunction => {
            RuntimeTyFunction {
                params: x.params.map(narrow_lowering_ty_to_runtime_ty),
                ret: narrow_lowering_ty_to_runtime_ty(x.ret),
                throws_: narrow_lowering_ty_to_runtime_ty(x.throws_),
            }
        },
        let x: LoweringTyFuture => {
            RuntimeTyFuture {
                value: narrow_lowering_ty_to_runtime_ty(x.value),
                error: narrow_lowering_ty_to_runtime_ty(x.error),
            }
        },
        let x: LoweringTyProjection => {
            RuntimeTyProjection {
                base: narrow_lowering_ty_to_runtime_ty(x.base),
                interface_args: x.interface_args.map(narrow_lowering_ty_to_runtime_ty),
                member: x.member,
            }
        },
        let x: LoweringTyTuple => {
            RuntimeTyTuple { items: x.items.map(narrow_lowering_ty_to_runtime_ty) }
        },
        TyError => throw NarrowError { variant: "Error", into: "RuntimeTy" },
        TyInfer => throw NarrowError { variant: "Infer", into: "RuntimeTy" },
    }
}

// Fails if any variant, at any depth, is outside CodegenTy.
function narrow_lowering_ty_to_codegen_ty(t: LoweringTy) -> CodegenTy throws NarrowError {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: LoweringTyClass => {
            CodegenTyClass { name: x.name, args: x.args.map(narrow_lowering_ty_to_codegen_ty) }
        },
        let x: LoweringTyInterface => {
            CodegenTyInterface {
                name: x.name,
                args: x.args.map(narrow_lowering_ty_to_codegen_ty),
                assoc: x.assoc.map(narrow_lowering_ty_to_codegen_ty),
            }
        },
        let x: LoweringTyList => CodegenTyList { elem: narrow_lowering_ty_to_codegen_ty(x.elem) },
        let x: LoweringTyMap => {
            CodegenTyMap {
                key: narrow_lowering_ty_to_codegen_ty(x.key),
                value: narrow_lowering_ty_to_codegen_ty(x.value),
            }
        },
        let x: LoweringTyUnion => {
            CodegenTyUnion { members: x.members.map(narrow_lowering_ty_to_codegen_ty) }
        },
        let x: LoweringTyFunction => {
            CodegenTyFunction {
                params: x.params.map(narrow_lowering_ty_to_codegen_ty),
                ret: narrow_lowering_ty_to_codegen_ty(x.ret),
                throws_: narrow_lowering_ty_to_codegen_ty(x.throws_),
            }
        },
        let x: LoweringTyFuture => {
            CodegenTyFuture {
                value: narrow_lowering_ty_to_codegen_ty(x.value),
                error: narrow_lowering_ty_to_codegen_ty(x.error),
            }
        },
        let x: LoweringTyTuple => {
            CodegenTyTuple { items: x.items.map(narrow_lowering_ty_to_codegen_ty) }
        },
        LoweringTyProjection => throw NarrowError { variant: "Projection", into: "CodegenTy" },
        TyError => throw NarrowError { variant: "Error", into: "CodegenTy" },
        TyInfer => throw NarrowError { variant: "Infer", into: "CodegenTy" },
    }
}

// Fails if any variant, at any depth, is outside RealizedTy.
function narrow_lowering_ty_to_realized_ty(t: LoweringTy) -> RealizedTy throws NarrowError {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: LoweringTyClass => {
            RealizedTyClass { name: x.name, args: x.args.map(narrow_lowering_ty_to_realized_ty) }
        },
        let x: LoweringTyInterface => {
            RealizedTyInterface {
                name: x.name,
                args: x.args.map(narrow_lowering_ty_to_realized_ty),
                assoc: x.assoc.map(narrow_lowering_ty_to_realized_ty),
            }
        },
        let x: LoweringTyList => RealizedTyList { elem: narrow_lowering_ty_to_realized_ty(x.elem) },
        let x: LoweringTyMap => {
            RealizedTyMap {
                key: narrow_lowering_ty_to_realized_ty(x.key),
                value: narrow_lowering_ty_to_realized_ty(x.value),
            }
        },
        let x: LoweringTyUnion => {
            RealizedTyUnion { members: x.members.map(narrow_lowering_ty_to_realized_ty) }
        },
        let x: LoweringTyFunction => {
            RealizedTyFunction {
                params: x.params.map(narrow_lowering_ty_to_realized_ty),
                ret: narrow_lowering_ty_to_realized_ty(x.ret),
                throws_: narrow_lowering_ty_to_realized_ty(x.throws_),
            }
        },
        let x: LoweringTyFuture => {
            RealizedTyFuture {
                value: narrow_lowering_ty_to_realized_ty(x.value),
                error: narrow_lowering_ty_to_realized_ty(x.error),
            }
        },
        let x: LoweringTyTuple => {
            RealizedTyTuple { items: x.items.map(narrow_lowering_ty_to_realized_ty) }
        },
        TyTypeVar => throw NarrowError { variant: "TypeVar", into: "RealizedTy" },
        LoweringTyProjection => throw NarrowError { variant: "Projection", into: "RealizedTy" },
        TyError => throw NarrowError { variant: "Error", into: "RealizedTy" },
        TyInfer => throw NarrowError { variant: "Infer", into: "RealizedTy" },
    }
}

// Fails if any variant, at any depth, is outside ConcreteTy.
function narrow_lowering_ty_to_concrete_ty(t: LoweringTy) -> ConcreteTy throws NarrowError {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyEnum
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyNever =>
        {
            x
        },
        let x: LoweringTyClass => {
            ConcreteTyClass { name: x.name, args: x.args.map(narrow_lowering_ty_to_concrete_ty) }
        },
        let x: LoweringTyList => ConcreteTyList { elem: narrow_lowering_ty_to_concrete_ty(x.elem) },
        let x: LoweringTyMap => {
            ConcreteTyMap {
                key: narrow_lowering_ty_to_concrete_ty(x.key),
                value: narrow_lowering_ty_to_concrete_ty(x.value),
            }
        },
        let x: LoweringTyFunction => {
            ConcreteTyFunction {
                params: x.params.map(narrow_lowering_ty_to_concrete_ty),
                ret: narrow_lowering_ty_to_concrete_ty(x.ret),
                throws_: narrow_lowering_ty_to_concrete_ty(x.throws_),
            }
        },
        let x: LoweringTyFuture => {
            ConcreteTyFuture {
                value: narrow_lowering_ty_to_concrete_ty(x.value),
                error: narrow_lowering_ty_to_concrete_ty(x.error),
            }
        },
        let x: LoweringTyTuple => {
            ConcreteTyTuple { items: x.items.map(narrow_lowering_ty_to_concrete_ty) }
        },
        TyLiteral => throw NarrowError { variant: "Literal", into: "ConcreteTy" },
        LoweringTyInterface => throw NarrowError { variant: "Interface", into: "ConcreteTy" },
        TyEnumVariant => throw NarrowError { variant: "EnumVariant", into: "ConcreteTy" },
        LoweringTyUnion => throw NarrowError { variant: "Union", into: "ConcreteTy" },
        TyTypeAlias => throw NarrowError { variant: "TypeAlias", into: "ConcreteTy" },
        TyTypeVar => throw NarrowError { variant: "TypeVar", into: "ConcreteTy" },
        LoweringTyProjection => throw NarrowError { variant: "Projection", into: "ConcreteTy" },
        TyUnknown => throw NarrowError { variant: "Unknown", into: "ConcreteTy" },
        TyError => throw NarrowError { variant: "Error", into: "ConcreteTy" },
        TyInfer => throw NarrowError { variant: "Infer", into: "ConcreteTy" },
    }
}

// Infallible: every RuntimeTy variant is a Ty variant.
function widen_runtime_ty_to_ty(t: RuntimeTy) -> Ty throws never {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: RuntimeTyClass => TyClass { name: x.name, args: x.args.map(widen_runtime_ty_to_ty) },
        let x: RuntimeTyInterface => {
            TyInterface {
                name: x.name,
                args: x.args.map(widen_runtime_ty_to_ty),
                assoc: x.assoc.map(widen_runtime_ty_to_ty),
            }
        },
        let x: RuntimeTyList => TyList { elem: widen_runtime_ty_to_ty(x.elem) },
        let x: RuntimeTyMap => {
            TyMap { key: widen_runtime_ty_to_ty(x.key), value: widen_runtime_ty_to_ty(x.value) }
        },
        let x: RuntimeTyUnion => TyUnion { members: x.members.map(widen_runtime_ty_to_ty) },
        let x: RuntimeTyFunction => {
            TyFunction {
                params: x.params.map(widen_runtime_ty_to_ty),
                ret: widen_runtime_ty_to_ty(x.ret),
                throws_: widen_runtime_ty_to_ty(x.throws_),
            }
        },
        let x: RuntimeTyFuture => {
            TyFuture {
                value: widen_runtime_ty_to_ty(x.value),
                error: widen_runtime_ty_to_ty(x.error),
            }
        },
        let x: RuntimeTyProjection => {
            TyProjection {
                base: widen_runtime_ty_to_ty(x.base),
                interface_args: x.interface_args.map(widen_runtime_ty_to_ty),
                member: x.member,
            }
        },
        let x: RuntimeTyTuple => TyTuple { items: x.items.map(widen_runtime_ty_to_ty) },
    }
}

// Infallible: every RuntimeTy variant is a LoweringTy variant.
function widen_runtime_ty_to_lowering_ty(t: RuntimeTy) -> LoweringTy throws never {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: RuntimeTyClass => {
            LoweringTyClass { name: x.name, args: x.args.map(widen_runtime_ty_to_lowering_ty) }
        },
        let x: RuntimeTyInterface => {
            LoweringTyInterface {
                name: x.name,
                args: x.args.map(widen_runtime_ty_to_lowering_ty),
                assoc: x.assoc.map(widen_runtime_ty_to_lowering_ty),
            }
        },
        let x: RuntimeTyList => LoweringTyList { elem: widen_runtime_ty_to_lowering_ty(x.elem) },
        let x: RuntimeTyMap => {
            LoweringTyMap {
                key: widen_runtime_ty_to_lowering_ty(x.key),
                value: widen_runtime_ty_to_lowering_ty(x.value),
            }
        },
        let x: RuntimeTyUnion => {
            LoweringTyUnion { members: x.members.map(widen_runtime_ty_to_lowering_ty) }
        },
        let x: RuntimeTyFunction => {
            LoweringTyFunction {
                params: x.params.map(widen_runtime_ty_to_lowering_ty),
                ret: widen_runtime_ty_to_lowering_ty(x.ret),
                throws_: widen_runtime_ty_to_lowering_ty(x.throws_),
            }
        },
        let x: RuntimeTyFuture => {
            LoweringTyFuture {
                value: widen_runtime_ty_to_lowering_ty(x.value),
                error: widen_runtime_ty_to_lowering_ty(x.error),
            }
        },
        let x: RuntimeTyProjection => {
            LoweringTyProjection {
                base: widen_runtime_ty_to_lowering_ty(x.base),
                interface_args: x.interface_args.map(widen_runtime_ty_to_lowering_ty),
                member: x.member,
            }
        },
        let x: RuntimeTyTuple => {
            LoweringTyTuple { items: x.items.map(widen_runtime_ty_to_lowering_ty) }
        },
    }
}

// Fails if any variant, at any depth, is outside CodegenTy.
function narrow_runtime_ty_to_codegen_ty(t: RuntimeTy) -> CodegenTy throws NarrowError {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: RuntimeTyClass => {
            CodegenTyClass { name: x.name, args: x.args.map(narrow_runtime_ty_to_codegen_ty) }
        },
        let x: RuntimeTyInterface => {
            CodegenTyInterface {
                name: x.name,
                args: x.args.map(narrow_runtime_ty_to_codegen_ty),
                assoc: x.assoc.map(narrow_runtime_ty_to_codegen_ty),
            }
        },
        let x: RuntimeTyList => CodegenTyList { elem: narrow_runtime_ty_to_codegen_ty(x.elem) },
        let x: RuntimeTyMap => {
            CodegenTyMap {
                key: narrow_runtime_ty_to_codegen_ty(x.key),
                value: narrow_runtime_ty_to_codegen_ty(x.value),
            }
        },
        let x: RuntimeTyUnion => {
            CodegenTyUnion { members: x.members.map(narrow_runtime_ty_to_codegen_ty) }
        },
        let x: RuntimeTyFunction => {
            CodegenTyFunction {
                params: x.params.map(narrow_runtime_ty_to_codegen_ty),
                ret: narrow_runtime_ty_to_codegen_ty(x.ret),
                throws_: narrow_runtime_ty_to_codegen_ty(x.throws_),
            }
        },
        let x: RuntimeTyFuture => {
            CodegenTyFuture {
                value: narrow_runtime_ty_to_codegen_ty(x.value),
                error: narrow_runtime_ty_to_codegen_ty(x.error),
            }
        },
        let x: RuntimeTyTuple => {
            CodegenTyTuple { items: x.items.map(narrow_runtime_ty_to_codegen_ty) }
        },
        RuntimeTyProjection => throw NarrowError { variant: "Projection", into: "CodegenTy" },
    }
}

// Fails if any variant, at any depth, is outside RealizedTy.
function narrow_runtime_ty_to_realized_ty(t: RuntimeTy) -> RealizedTy throws NarrowError {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: RuntimeTyClass => {
            RealizedTyClass { name: x.name, args: x.args.map(narrow_runtime_ty_to_realized_ty) }
        },
        let x: RuntimeTyInterface => {
            RealizedTyInterface {
                name: x.name,
                args: x.args.map(narrow_runtime_ty_to_realized_ty),
                assoc: x.assoc.map(narrow_runtime_ty_to_realized_ty),
            }
        },
        let x: RuntimeTyList => RealizedTyList { elem: narrow_runtime_ty_to_realized_ty(x.elem) },
        let x: RuntimeTyMap => {
            RealizedTyMap {
                key: narrow_runtime_ty_to_realized_ty(x.key),
                value: narrow_runtime_ty_to_realized_ty(x.value),
            }
        },
        let x: RuntimeTyUnion => {
            RealizedTyUnion { members: x.members.map(narrow_runtime_ty_to_realized_ty) }
        },
        let x: RuntimeTyFunction => {
            RealizedTyFunction {
                params: x.params.map(narrow_runtime_ty_to_realized_ty),
                ret: narrow_runtime_ty_to_realized_ty(x.ret),
                throws_: narrow_runtime_ty_to_realized_ty(x.throws_),
            }
        },
        let x: RuntimeTyFuture => {
            RealizedTyFuture {
                value: narrow_runtime_ty_to_realized_ty(x.value),
                error: narrow_runtime_ty_to_realized_ty(x.error),
            }
        },
        let x: RuntimeTyTuple => {
            RealizedTyTuple { items: x.items.map(narrow_runtime_ty_to_realized_ty) }
        },
        TyTypeVar => throw NarrowError { variant: "TypeVar", into: "RealizedTy" },
        RuntimeTyProjection => throw NarrowError { variant: "Projection", into: "RealizedTy" },
    }
}

// Fails if any variant, at any depth, is outside ConcreteTy.
function narrow_runtime_ty_to_concrete_ty(t: RuntimeTy) -> ConcreteTy throws NarrowError {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyEnum
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyNever =>
        {
            x
        },
        let x: RuntimeTyClass => {
            ConcreteTyClass { name: x.name, args: x.args.map(narrow_runtime_ty_to_concrete_ty) }
        },
        let x: RuntimeTyList => ConcreteTyList { elem: narrow_runtime_ty_to_concrete_ty(x.elem) },
        let x: RuntimeTyMap => {
            ConcreteTyMap {
                key: narrow_runtime_ty_to_concrete_ty(x.key),
                value: narrow_runtime_ty_to_concrete_ty(x.value),
            }
        },
        let x: RuntimeTyFunction => {
            ConcreteTyFunction {
                params: x.params.map(narrow_runtime_ty_to_concrete_ty),
                ret: narrow_runtime_ty_to_concrete_ty(x.ret),
                throws_: narrow_runtime_ty_to_concrete_ty(x.throws_),
            }
        },
        let x: RuntimeTyFuture => {
            ConcreteTyFuture {
                value: narrow_runtime_ty_to_concrete_ty(x.value),
                error: narrow_runtime_ty_to_concrete_ty(x.error),
            }
        },
        let x: RuntimeTyTuple => {
            ConcreteTyTuple { items: x.items.map(narrow_runtime_ty_to_concrete_ty) }
        },
        TyLiteral => throw NarrowError { variant: "Literal", into: "ConcreteTy" },
        RuntimeTyInterface => throw NarrowError { variant: "Interface", into: "ConcreteTy" },
        TyEnumVariant => throw NarrowError { variant: "EnumVariant", into: "ConcreteTy" },
        RuntimeTyUnion => throw NarrowError { variant: "Union", into: "ConcreteTy" },
        TyTypeAlias => throw NarrowError { variant: "TypeAlias", into: "ConcreteTy" },
        TyTypeVar => throw NarrowError { variant: "TypeVar", into: "ConcreteTy" },
        RuntimeTyProjection => throw NarrowError { variant: "Projection", into: "ConcreteTy" },
        TyUnknown => throw NarrowError { variant: "Unknown", into: "ConcreteTy" },
    }
}

// Infallible: every CodegenTy variant is a Ty variant.
function widen_codegen_ty_to_ty(t: CodegenTy) -> Ty throws never {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: CodegenTyClass => TyClass { name: x.name, args: x.args.map(widen_codegen_ty_to_ty) },
        let x: CodegenTyInterface => {
            TyInterface {
                name: x.name,
                args: x.args.map(widen_codegen_ty_to_ty),
                assoc: x.assoc.map(widen_codegen_ty_to_ty),
            }
        },
        let x: CodegenTyList => TyList { elem: widen_codegen_ty_to_ty(x.elem) },
        let x: CodegenTyMap => {
            TyMap { key: widen_codegen_ty_to_ty(x.key), value: widen_codegen_ty_to_ty(x.value) }
        },
        let x: CodegenTyUnion => TyUnion { members: x.members.map(widen_codegen_ty_to_ty) },
        let x: CodegenTyFunction => {
            TyFunction {
                params: x.params.map(widen_codegen_ty_to_ty),
                ret: widen_codegen_ty_to_ty(x.ret),
                throws_: widen_codegen_ty_to_ty(x.throws_),
            }
        },
        let x: CodegenTyFuture => {
            TyFuture {
                value: widen_codegen_ty_to_ty(x.value),
                error: widen_codegen_ty_to_ty(x.error),
            }
        },
        let x: CodegenTyTuple => TyTuple { items: x.items.map(widen_codegen_ty_to_ty) },
    }
}

// Infallible: every CodegenTy variant is a LoweringTy variant.
function widen_codegen_ty_to_lowering_ty(t: CodegenTy) -> LoweringTy throws never {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: CodegenTyClass => {
            LoweringTyClass { name: x.name, args: x.args.map(widen_codegen_ty_to_lowering_ty) }
        },
        let x: CodegenTyInterface => {
            LoweringTyInterface {
                name: x.name,
                args: x.args.map(widen_codegen_ty_to_lowering_ty),
                assoc: x.assoc.map(widen_codegen_ty_to_lowering_ty),
            }
        },
        let x: CodegenTyList => LoweringTyList { elem: widen_codegen_ty_to_lowering_ty(x.elem) },
        let x: CodegenTyMap => {
            LoweringTyMap {
                key: widen_codegen_ty_to_lowering_ty(x.key),
                value: widen_codegen_ty_to_lowering_ty(x.value),
            }
        },
        let x: CodegenTyUnion => {
            LoweringTyUnion { members: x.members.map(widen_codegen_ty_to_lowering_ty) }
        },
        let x: CodegenTyFunction => {
            LoweringTyFunction {
                params: x.params.map(widen_codegen_ty_to_lowering_ty),
                ret: widen_codegen_ty_to_lowering_ty(x.ret),
                throws_: widen_codegen_ty_to_lowering_ty(x.throws_),
            }
        },
        let x: CodegenTyFuture => {
            LoweringTyFuture {
                value: widen_codegen_ty_to_lowering_ty(x.value),
                error: widen_codegen_ty_to_lowering_ty(x.error),
            }
        },
        let x: CodegenTyTuple => {
            LoweringTyTuple { items: x.items.map(widen_codegen_ty_to_lowering_ty) }
        },
    }
}

// Infallible: every CodegenTy variant is a RuntimeTy variant.
function widen_codegen_ty_to_runtime_ty(t: CodegenTy) -> RuntimeTy throws never {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: CodegenTyClass => {
            RuntimeTyClass { name: x.name, args: x.args.map(widen_codegen_ty_to_runtime_ty) }
        },
        let x: CodegenTyInterface => {
            RuntimeTyInterface {
                name: x.name,
                args: x.args.map(widen_codegen_ty_to_runtime_ty),
                assoc: x.assoc.map(widen_codegen_ty_to_runtime_ty),
            }
        },
        let x: CodegenTyList => RuntimeTyList { elem: widen_codegen_ty_to_runtime_ty(x.elem) },
        let x: CodegenTyMap => {
            RuntimeTyMap {
                key: widen_codegen_ty_to_runtime_ty(x.key),
                value: widen_codegen_ty_to_runtime_ty(x.value),
            }
        },
        let x: CodegenTyUnion => {
            RuntimeTyUnion { members: x.members.map(widen_codegen_ty_to_runtime_ty) }
        },
        let x: CodegenTyFunction => {
            RuntimeTyFunction {
                params: x.params.map(widen_codegen_ty_to_runtime_ty),
                ret: widen_codegen_ty_to_runtime_ty(x.ret),
                throws_: widen_codegen_ty_to_runtime_ty(x.throws_),
            }
        },
        let x: CodegenTyFuture => {
            RuntimeTyFuture {
                value: widen_codegen_ty_to_runtime_ty(x.value),
                error: widen_codegen_ty_to_runtime_ty(x.error),
            }
        },
        let x: CodegenTyTuple => {
            RuntimeTyTuple { items: x.items.map(widen_codegen_ty_to_runtime_ty) }
        },
    }
}

// Fails if any variant, at any depth, is outside RealizedTy.
function narrow_codegen_ty_to_realized_ty(t: CodegenTy) -> RealizedTy throws NarrowError {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: CodegenTyClass => {
            RealizedTyClass { name: x.name, args: x.args.map(narrow_codegen_ty_to_realized_ty) }
        },
        let x: CodegenTyInterface => {
            RealizedTyInterface {
                name: x.name,
                args: x.args.map(narrow_codegen_ty_to_realized_ty),
                assoc: x.assoc.map(narrow_codegen_ty_to_realized_ty),
            }
        },
        let x: CodegenTyList => RealizedTyList { elem: narrow_codegen_ty_to_realized_ty(x.elem) },
        let x: CodegenTyMap => {
            RealizedTyMap {
                key: narrow_codegen_ty_to_realized_ty(x.key),
                value: narrow_codegen_ty_to_realized_ty(x.value),
            }
        },
        let x: CodegenTyUnion => {
            RealizedTyUnion { members: x.members.map(narrow_codegen_ty_to_realized_ty) }
        },
        let x: CodegenTyFunction => {
            RealizedTyFunction {
                params: x.params.map(narrow_codegen_ty_to_realized_ty),
                ret: narrow_codegen_ty_to_realized_ty(x.ret),
                throws_: narrow_codegen_ty_to_realized_ty(x.throws_),
            }
        },
        let x: CodegenTyFuture => {
            RealizedTyFuture {
                value: narrow_codegen_ty_to_realized_ty(x.value),
                error: narrow_codegen_ty_to_realized_ty(x.error),
            }
        },
        let x: CodegenTyTuple => {
            RealizedTyTuple { items: x.items.map(narrow_codegen_ty_to_realized_ty) }
        },
        TyTypeVar => throw NarrowError { variant: "TypeVar", into: "RealizedTy" },
    }
}

// Fails if any variant, at any depth, is outside ConcreteTy.
function narrow_codegen_ty_to_concrete_ty(t: CodegenTy) -> ConcreteTy throws NarrowError {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyEnum
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyNever =>
        {
            x
        },
        let x: CodegenTyClass => {
            ConcreteTyClass { name: x.name, args: x.args.map(narrow_codegen_ty_to_concrete_ty) }
        },
        let x: CodegenTyList => ConcreteTyList { elem: narrow_codegen_ty_to_concrete_ty(x.elem) },
        let x: CodegenTyMap => {
            ConcreteTyMap {
                key: narrow_codegen_ty_to_concrete_ty(x.key),
                value: narrow_codegen_ty_to_concrete_ty(x.value),
            }
        },
        let x: CodegenTyFunction => {
            ConcreteTyFunction {
                params: x.params.map(narrow_codegen_ty_to_concrete_ty),
                ret: narrow_codegen_ty_to_concrete_ty(x.ret),
                throws_: narrow_codegen_ty_to_concrete_ty(x.throws_),
            }
        },
        let x: CodegenTyFuture => {
            ConcreteTyFuture {
                value: narrow_codegen_ty_to_concrete_ty(x.value),
                error: narrow_codegen_ty_to_concrete_ty(x.error),
            }
        },
        let x: CodegenTyTuple => {
            ConcreteTyTuple { items: x.items.map(narrow_codegen_ty_to_concrete_ty) }
        },
        TyLiteral => throw NarrowError { variant: "Literal", into: "ConcreteTy" },
        CodegenTyInterface => throw NarrowError { variant: "Interface", into: "ConcreteTy" },
        TyEnumVariant => throw NarrowError { variant: "EnumVariant", into: "ConcreteTy" },
        CodegenTyUnion => throw NarrowError { variant: "Union", into: "ConcreteTy" },
        TyTypeAlias => throw NarrowError { variant: "TypeAlias", into: "ConcreteTy" },
        TyTypeVar => throw NarrowError { variant: "TypeVar", into: "ConcreteTy" },
        TyUnknown => throw NarrowError { variant: "Unknown", into: "ConcreteTy" },
    }
}

// Infallible: every RealizedTy variant is a Ty variant.
function widen_realized_ty_to_ty(t: RealizedTy) -> Ty throws never {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: RealizedTyClass => {
            TyClass { name: x.name, args: x.args.map(widen_realized_ty_to_ty) }
        },
        let x: RealizedTyInterface => {
            TyInterface {
                name: x.name,
                args: x.args.map(widen_realized_ty_to_ty),
                assoc: x.assoc.map(widen_realized_ty_to_ty),
            }
        },
        let x: RealizedTyList => TyList { elem: widen_realized_ty_to_ty(x.elem) },
        let x: RealizedTyMap => {
            TyMap { key: widen_realized_ty_to_ty(x.key), value: widen_realized_ty_to_ty(x.value) }
        },
        let x: RealizedTyUnion => TyUnion { members: x.members.map(widen_realized_ty_to_ty) },
        let x: RealizedTyFunction => {
            TyFunction {
                params: x.params.map(widen_realized_ty_to_ty),
                ret: widen_realized_ty_to_ty(x.ret),
                throws_: widen_realized_ty_to_ty(x.throws_),
            }
        },
        let x: RealizedTyFuture => {
            TyFuture {
                value: widen_realized_ty_to_ty(x.value),
                error: widen_realized_ty_to_ty(x.error),
            }
        },
        let x: RealizedTyTuple => TyTuple { items: x.items.map(widen_realized_ty_to_ty) },
    }
}

// Infallible: every RealizedTy variant is a LoweringTy variant.
function widen_realized_ty_to_lowering_ty(t: RealizedTy) -> LoweringTy throws never {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: RealizedTyClass => {
            LoweringTyClass { name: x.name, args: x.args.map(widen_realized_ty_to_lowering_ty) }
        },
        let x: RealizedTyInterface => {
            LoweringTyInterface {
                name: x.name,
                args: x.args.map(widen_realized_ty_to_lowering_ty),
                assoc: x.assoc.map(widen_realized_ty_to_lowering_ty),
            }
        },
        let x: RealizedTyList => LoweringTyList { elem: widen_realized_ty_to_lowering_ty(x.elem) },
        let x: RealizedTyMap => {
            LoweringTyMap {
                key: widen_realized_ty_to_lowering_ty(x.key),
                value: widen_realized_ty_to_lowering_ty(x.value),
            }
        },
        let x: RealizedTyUnion => {
            LoweringTyUnion { members: x.members.map(widen_realized_ty_to_lowering_ty) }
        },
        let x: RealizedTyFunction => {
            LoweringTyFunction {
                params: x.params.map(widen_realized_ty_to_lowering_ty),
                ret: widen_realized_ty_to_lowering_ty(x.ret),
                throws_: widen_realized_ty_to_lowering_ty(x.throws_),
            }
        },
        let x: RealizedTyFuture => {
            LoweringTyFuture {
                value: widen_realized_ty_to_lowering_ty(x.value),
                error: widen_realized_ty_to_lowering_ty(x.error),
            }
        },
        let x: RealizedTyTuple => {
            LoweringTyTuple { items: x.items.map(widen_realized_ty_to_lowering_ty) }
        },
    }
}

// Infallible: every RealizedTy variant is a RuntimeTy variant.
function widen_realized_ty_to_runtime_ty(t: RealizedTy) -> RuntimeTy throws never {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: RealizedTyClass => {
            RuntimeTyClass { name: x.name, args: x.args.map(widen_realized_ty_to_runtime_ty) }
        },
        let x: RealizedTyInterface => {
            RuntimeTyInterface {
                name: x.name,
                args: x.args.map(widen_realized_ty_to_runtime_ty),
                assoc: x.assoc.map(widen_realized_ty_to_runtime_ty),
            }
        },
        let x: RealizedTyList => RuntimeTyList { elem: widen_realized_ty_to_runtime_ty(x.elem) },
        let x: RealizedTyMap => {
            RuntimeTyMap {
                key: widen_realized_ty_to_runtime_ty(x.key),
                value: widen_realized_ty_to_runtime_ty(x.value),
            }
        },
        let x: RealizedTyUnion => {
            RuntimeTyUnion { members: x.members.map(widen_realized_ty_to_runtime_ty) }
        },
        let x: RealizedTyFunction => {
            RuntimeTyFunction {
                params: x.params.map(widen_realized_ty_to_runtime_ty),
                ret: widen_realized_ty_to_runtime_ty(x.ret),
                throws_: widen_realized_ty_to_runtime_ty(x.throws_),
            }
        },
        let x: RealizedTyFuture => {
            RuntimeTyFuture {
                value: widen_realized_ty_to_runtime_ty(x.value),
                error: widen_realized_ty_to_runtime_ty(x.error),
            }
        },
        let x: RealizedTyTuple => {
            RuntimeTyTuple { items: x.items.map(widen_realized_ty_to_runtime_ty) }
        },
    }
}

// Infallible: every RealizedTy variant is a CodegenTy variant.
function widen_realized_ty_to_codegen_ty(t: RealizedTy) -> CodegenTy throws never {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: RealizedTyClass => {
            CodegenTyClass { name: x.name, args: x.args.map(widen_realized_ty_to_codegen_ty) }
        },
        let x: RealizedTyInterface => {
            CodegenTyInterface {
                name: x.name,
                args: x.args.map(widen_realized_ty_to_codegen_ty),
                assoc: x.assoc.map(widen_realized_ty_to_codegen_ty),
            }
        },
        let x: RealizedTyList => CodegenTyList { elem: widen_realized_ty_to_codegen_ty(x.elem) },
        let x: RealizedTyMap => {
            CodegenTyMap {
                key: widen_realized_ty_to_codegen_ty(x.key),
                value: widen_realized_ty_to_codegen_ty(x.value),
            }
        },
        let x: RealizedTyUnion => {
            CodegenTyUnion { members: x.members.map(widen_realized_ty_to_codegen_ty) }
        },
        let x: RealizedTyFunction => {
            CodegenTyFunction {
                params: x.params.map(widen_realized_ty_to_codegen_ty),
                ret: widen_realized_ty_to_codegen_ty(x.ret),
                throws_: widen_realized_ty_to_codegen_ty(x.throws_),
            }
        },
        let x: RealizedTyFuture => {
            CodegenTyFuture {
                value: widen_realized_ty_to_codegen_ty(x.value),
                error: widen_realized_ty_to_codegen_ty(x.error),
            }
        },
        let x: RealizedTyTuple => {
            CodegenTyTuple { items: x.items.map(widen_realized_ty_to_codegen_ty) }
        },
    }
}

// Fails if any variant, at any depth, is outside ConcreteTy.
function narrow_realized_ty_to_concrete_ty(t: RealizedTy) -> ConcreteTy throws NarrowError {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyEnum
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyNever =>
        {
            x
        },
        let x: RealizedTyClass => {
            ConcreteTyClass { name: x.name, args: x.args.map(narrow_realized_ty_to_concrete_ty) }
        },
        let x: RealizedTyList => ConcreteTyList { elem: narrow_realized_ty_to_concrete_ty(x.elem) },
        let x: RealizedTyMap => {
            ConcreteTyMap {
                key: narrow_realized_ty_to_concrete_ty(x.key),
                value: narrow_realized_ty_to_concrete_ty(x.value),
            }
        },
        let x: RealizedTyFunction => {
            ConcreteTyFunction {
                params: x.params.map(narrow_realized_ty_to_concrete_ty),
                ret: narrow_realized_ty_to_concrete_ty(x.ret),
                throws_: narrow_realized_ty_to_concrete_ty(x.throws_),
            }
        },
        let x: RealizedTyFuture => {
            ConcreteTyFuture {
                value: narrow_realized_ty_to_concrete_ty(x.value),
                error: narrow_realized_ty_to_concrete_ty(x.error),
            }
        },
        let x: RealizedTyTuple => {
            ConcreteTyTuple { items: x.items.map(narrow_realized_ty_to_concrete_ty) }
        },
        TyLiteral => throw NarrowError { variant: "Literal", into: "ConcreteTy" },
        RealizedTyInterface => throw NarrowError { variant: "Interface", into: "ConcreteTy" },
        TyEnumVariant => throw NarrowError { variant: "EnumVariant", into: "ConcreteTy" },
        RealizedTyUnion => throw NarrowError { variant: "Union", into: "ConcreteTy" },
        TyTypeAlias => throw NarrowError { variant: "TypeAlias", into: "ConcreteTy" },
        TyUnknown => throw NarrowError { variant: "Unknown", into: "ConcreteTy" },
    }
}

// Infallible: every RealizedTy variant is a TyTemplate variant.
function widen_realized_ty_to_ty_template(t: RealizedTy) -> TyTemplate throws never {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: RealizedTyClass => {
            TyTemplateClass { name: x.name, args: x.args.map(widen_realized_ty_to_ty_template) }
        },
        let x: RealizedTyInterface => {
            TyTemplateInterface {
                name: x.name,
                args: x.args.map(widen_realized_ty_to_ty_template),
                assoc: x.assoc.map(widen_realized_ty_to_ty_template),
            }
        },
        let x: RealizedTyList => TyTemplateList { elem: widen_realized_ty_to_ty_template(x.elem) },
        let x: RealizedTyMap => {
            TyTemplateMap {
                key: widen_realized_ty_to_ty_template(x.key),
                value: widen_realized_ty_to_ty_template(x.value),
            }
        },
        let x: RealizedTyUnion => {
            TyTemplateUnion { members: x.members.map(widen_realized_ty_to_ty_template) }
        },
        let x: RealizedTyFunction => {
            TyTemplateFunction {
                params: x.params.map(widen_realized_ty_to_ty_template),
                ret: widen_realized_ty_to_ty_template(x.ret),
                throws_: widen_realized_ty_to_ty_template(x.throws_),
            }
        },
        let x: RealizedTyFuture => {
            TyTemplateFuture {
                value: widen_realized_ty_to_ty_template(x.value),
                error: widen_realized_ty_to_ty_template(x.error),
            }
        },
        let x: RealizedTyTuple => {
            TyTemplateTuple { items: x.items.map(widen_realized_ty_to_ty_template) }
        },
    }
}

// Infallible: every ConcreteTy variant is a Ty variant.
function widen_concrete_ty_to_ty(t: ConcreteTy) -> Ty throws never {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyEnum
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyNever =>
        {
            x
        },
        let x: ConcreteTyClass => {
            TyClass { name: x.name, args: x.args.map(widen_concrete_ty_to_ty) }
        },
        let x: ConcreteTyList => TyList { elem: widen_concrete_ty_to_ty(x.elem) },
        let x: ConcreteTyMap => {
            TyMap { key: widen_concrete_ty_to_ty(x.key), value: widen_concrete_ty_to_ty(x.value) }
        },
        let x: ConcreteTyFunction => {
            TyFunction {
                params: x.params.map(widen_concrete_ty_to_ty),
                ret: widen_concrete_ty_to_ty(x.ret),
                throws_: widen_concrete_ty_to_ty(x.throws_),
            }
        },
        let x: ConcreteTyFuture => {
            TyFuture {
                value: widen_concrete_ty_to_ty(x.value),
                error: widen_concrete_ty_to_ty(x.error),
            }
        },
        let x: ConcreteTyTuple => TyTuple { items: x.items.map(widen_concrete_ty_to_ty) },
    }
}

// Infallible: every ConcreteTy variant is a LoweringTy variant.
function widen_concrete_ty_to_lowering_ty(t: ConcreteTy) -> LoweringTy throws never {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyEnum
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyNever =>
        {
            x
        },
        let x: ConcreteTyClass => {
            LoweringTyClass { name: x.name, args: x.args.map(widen_concrete_ty_to_lowering_ty) }
        },
        let x: ConcreteTyList => LoweringTyList { elem: widen_concrete_ty_to_lowering_ty(x.elem) },
        let x: ConcreteTyMap => {
            LoweringTyMap {
                key: widen_concrete_ty_to_lowering_ty(x.key),
                value: widen_concrete_ty_to_lowering_ty(x.value),
            }
        },
        let x: ConcreteTyFunction => {
            LoweringTyFunction {
                params: x.params.map(widen_concrete_ty_to_lowering_ty),
                ret: widen_concrete_ty_to_lowering_ty(x.ret),
                throws_: widen_concrete_ty_to_lowering_ty(x.throws_),
            }
        },
        let x: ConcreteTyFuture => {
            LoweringTyFuture {
                value: widen_concrete_ty_to_lowering_ty(x.value),
                error: widen_concrete_ty_to_lowering_ty(x.error),
            }
        },
        let x: ConcreteTyTuple => {
            LoweringTyTuple { items: x.items.map(widen_concrete_ty_to_lowering_ty) }
        },
    }
}

// Infallible: every ConcreteTy variant is a RuntimeTy variant.
function widen_concrete_ty_to_runtime_ty(t: ConcreteTy) -> RuntimeTy throws never {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyEnum
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyNever =>
        {
            x
        },
        let x: ConcreteTyClass => {
            RuntimeTyClass { name: x.name, args: x.args.map(widen_concrete_ty_to_runtime_ty) }
        },
        let x: ConcreteTyList => RuntimeTyList { elem: widen_concrete_ty_to_runtime_ty(x.elem) },
        let x: ConcreteTyMap => {
            RuntimeTyMap {
                key: widen_concrete_ty_to_runtime_ty(x.key),
                value: widen_concrete_ty_to_runtime_ty(x.value),
            }
        },
        let x: ConcreteTyFunction => {
            RuntimeTyFunction {
                params: x.params.map(widen_concrete_ty_to_runtime_ty),
                ret: widen_concrete_ty_to_runtime_ty(x.ret),
                throws_: widen_concrete_ty_to_runtime_ty(x.throws_),
            }
        },
        let x: ConcreteTyFuture => {
            RuntimeTyFuture {
                value: widen_concrete_ty_to_runtime_ty(x.value),
                error: widen_concrete_ty_to_runtime_ty(x.error),
            }
        },
        let x: ConcreteTyTuple => {
            RuntimeTyTuple { items: x.items.map(widen_concrete_ty_to_runtime_ty) }
        },
    }
}

// Infallible: every ConcreteTy variant is a CodegenTy variant.
function widen_concrete_ty_to_codegen_ty(t: ConcreteTy) -> CodegenTy throws never {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyEnum
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyNever =>
        {
            x
        },
        let x: ConcreteTyClass => {
            CodegenTyClass { name: x.name, args: x.args.map(widen_concrete_ty_to_codegen_ty) }
        },
        let x: ConcreteTyList => CodegenTyList { elem: widen_concrete_ty_to_codegen_ty(x.elem) },
        let x: ConcreteTyMap => {
            CodegenTyMap {
                key: widen_concrete_ty_to_codegen_ty(x.key),
                value: widen_concrete_ty_to_codegen_ty(x.value),
            }
        },
        let x: ConcreteTyFunction => {
            CodegenTyFunction {
                params: x.params.map(widen_concrete_ty_to_codegen_ty),
                ret: widen_concrete_ty_to_codegen_ty(x.ret),
                throws_: widen_concrete_ty_to_codegen_ty(x.throws_),
            }
        },
        let x: ConcreteTyFuture => {
            CodegenTyFuture {
                value: widen_concrete_ty_to_codegen_ty(x.value),
                error: widen_concrete_ty_to_codegen_ty(x.error),
            }
        },
        let x: ConcreteTyTuple => {
            CodegenTyTuple { items: x.items.map(widen_concrete_ty_to_codegen_ty) }
        },
    }
}

// Infallible: every ConcreteTy variant is a RealizedTy variant.
function widen_concrete_ty_to_realized_ty(t: ConcreteTy) -> RealizedTy throws never {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyEnum
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyNever =>
        {
            x
        },
        let x: ConcreteTyClass => {
            RealizedTyClass { name: x.name, args: x.args.map(widen_concrete_ty_to_realized_ty) }
        },
        let x: ConcreteTyList => RealizedTyList { elem: widen_concrete_ty_to_realized_ty(x.elem) },
        let x: ConcreteTyMap => {
            RealizedTyMap {
                key: widen_concrete_ty_to_realized_ty(x.key),
                value: widen_concrete_ty_to_realized_ty(x.value),
            }
        },
        let x: ConcreteTyFunction => {
            RealizedTyFunction {
                params: x.params.map(widen_concrete_ty_to_realized_ty),
                ret: widen_concrete_ty_to_realized_ty(x.ret),
                throws_: widen_concrete_ty_to_realized_ty(x.throws_),
            }
        },
        let x: ConcreteTyFuture => {
            RealizedTyFuture {
                value: widen_concrete_ty_to_realized_ty(x.value),
                error: widen_concrete_ty_to_realized_ty(x.error),
            }
        },
        let x: ConcreteTyTuple => {
            RealizedTyTuple { items: x.items.map(widen_concrete_ty_to_realized_ty) }
        },
    }
}

// Infallible: every ConcreteTy variant is a TyTemplate variant.
function widen_concrete_ty_to_ty_template(t: ConcreteTy) -> TyTemplate throws never {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyEnum
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyNever =>
        {
            x
        },
        let x: ConcreteTyClass => {
            TyTemplateClass { name: x.name, args: x.args.map(widen_concrete_ty_to_ty_template) }
        },
        let x: ConcreteTyList => TyTemplateList { elem: widen_concrete_ty_to_ty_template(x.elem) },
        let x: ConcreteTyMap => {
            TyTemplateMap {
                key: widen_concrete_ty_to_ty_template(x.key),
                value: widen_concrete_ty_to_ty_template(x.value),
            }
        },
        let x: ConcreteTyFunction => {
            TyTemplateFunction {
                params: x.params.map(widen_concrete_ty_to_ty_template),
                ret: widen_concrete_ty_to_ty_template(x.ret),
                throws_: widen_concrete_ty_to_ty_template(x.throws_),
            }
        },
        let x: ConcreteTyFuture => {
            TyTemplateFuture {
                value: widen_concrete_ty_to_ty_template(x.value),
                error: widen_concrete_ty_to_ty_template(x.error),
            }
        },
        let x: ConcreteTyTuple => {
            TyTemplateTuple { items: x.items.map(widen_concrete_ty_to_ty_template) }
        },
    }
}

// Fails if any variant, at any depth, is outside RealizedTy.
function narrow_ty_template_to_realized_ty(t: TyTemplate) -> RealizedTy throws NarrowError {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: TyTemplateClass => {
            RealizedTyClass { name: x.name, args: x.args.map(narrow_ty_template_to_realized_ty) }
        },
        let x: TyTemplateInterface => {
            RealizedTyInterface {
                name: x.name,
                args: x.args.map(narrow_ty_template_to_realized_ty),
                assoc: x.assoc.map(narrow_ty_template_to_realized_ty),
            }
        },
        let x: TyTemplateList => RealizedTyList { elem: narrow_ty_template_to_realized_ty(x.elem) },
        let x: TyTemplateMap => {
            RealizedTyMap {
                key: narrow_ty_template_to_realized_ty(x.key),
                value: narrow_ty_template_to_realized_ty(x.value),
            }
        },
        let x: TyTemplateUnion => {
            RealizedTyUnion { members: x.members.map(narrow_ty_template_to_realized_ty) }
        },
        let x: TyTemplateFunction => {
            RealizedTyFunction {
                params: x.params.map(narrow_ty_template_to_realized_ty),
                ret: narrow_ty_template_to_realized_ty(x.ret),
                throws_: narrow_ty_template_to_realized_ty(x.throws_),
            }
        },
        let x: TyTemplateFuture => {
            RealizedTyFuture {
                value: narrow_ty_template_to_realized_ty(x.value),
                error: narrow_ty_template_to_realized_ty(x.error),
            }
        },
        let x: TyTemplateTuple => {
            RealizedTyTuple { items: x.items.map(narrow_ty_template_to_realized_ty) }
        },
        TyTemplateProjection => throw NarrowError { variant: "Projection", into: "RealizedTy" },
        TyTypeArgRef => throw NarrowError { variant: "TypeArgRef", into: "RealizedTy" },
    }
}

// Fails if any variant, at any depth, is outside ConcreteTy.
function narrow_ty_template_to_concrete_ty(t: TyTemplate) -> ConcreteTy throws NarrowError {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyEnum
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyNever =>
        {
            x
        },
        let x: TyTemplateClass => {
            ConcreteTyClass { name: x.name, args: x.args.map(narrow_ty_template_to_concrete_ty) }
        },
        let x: TyTemplateList => ConcreteTyList { elem: narrow_ty_template_to_concrete_ty(x.elem) },
        let x: TyTemplateMap => {
            ConcreteTyMap {
                key: narrow_ty_template_to_concrete_ty(x.key),
                value: narrow_ty_template_to_concrete_ty(x.value),
            }
        },
        let x: TyTemplateFunction => {
            ConcreteTyFunction {
                params: x.params.map(narrow_ty_template_to_concrete_ty),
                ret: narrow_ty_template_to_concrete_ty(x.ret),
                throws_: narrow_ty_template_to_concrete_ty(x.throws_),
            }
        },
        let x: TyTemplateFuture => {
            ConcreteTyFuture {
                value: narrow_ty_template_to_concrete_ty(x.value),
                error: narrow_ty_template_to_concrete_ty(x.error),
            }
        },
        let x: TyTemplateTuple => {
            ConcreteTyTuple { items: x.items.map(narrow_ty_template_to_concrete_ty) }
        },
        TyLiteral => throw NarrowError { variant: "Literal", into: "ConcreteTy" },
        TyTemplateInterface => throw NarrowError { variant: "Interface", into: "ConcreteTy" },
        TyEnumVariant => throw NarrowError { variant: "EnumVariant", into: "ConcreteTy" },
        TyTemplateUnion => throw NarrowError { variant: "Union", into: "ConcreteTy" },
        TyTypeAlias => throw NarrowError { variant: "TypeAlias", into: "ConcreteTy" },
        TyTemplateProjection => throw NarrowError { variant: "Projection", into: "ConcreteTy" },
        TyUnknown => throw NarrowError { variant: "Unknown", into: "ConcreteTy" },
        TyTypeArgRef => throw NarrowError { variant: "TypeArgRef", into: "ConcreteTy" },
    }
}

// == Generic child walkers =================================================

// Rebuilds `t` with `f` applied to each direct child; leaves are returned as is.
function map_children_ty(t: Ty, f: (Ty) -> Ty) -> Ty {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever
            | TyError =>
        {
            x
        },
        let x: TyClass => TyClass { name: x.name, args: x.args.map(f) },
        let x: TyInterface => {
            TyInterface { name: x.name, args: x.args.map(f), assoc: x.assoc.map(f) }
        },
        let x: TyList => TyList { elem: f(x.elem) },
        let x: TyMap => TyMap { key: f(x.key), value: f(x.value) },
        let x: TyUnion => TyUnion { members: x.members.map(f) },
        let x: TyFunction => {
            TyFunction { params: x.params.map(f), ret: f(x.ret), throws_: f(x.throws_) }
        },
        let x: TyFuture => TyFuture { value: f(x.value), error: f(x.error) },
        let x: TyProjection => {
            TyProjection {
                base: f(x.base),
                interface_args: x.interface_args.map(f),
                member: x.member,
            }
        },
        let x: TyTuple => TyTuple { items: x.items.map(f) },
    }
}

// The direct children of `t`, in field order.
function children_ty(t: Ty) -> Ty[] {
    match (t) {
        TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever
            | TyError =>
        {
            []
        },
        let x: TyClass => x.args,
        let x: TyInterface => x.args.concat(x.assoc),
        let x: TyList => [x.elem],
        let x: TyMap => [x.key].concat([x.value]),
        let x: TyUnion => x.members,
        let x: TyFunction => x.params.concat([x.ret]).concat([x.throws_]),
        let x: TyFuture => [x.value].concat([x.error]),
        let x: TyProjection => [x.base].concat(x.interface_args),
        let x: TyTuple => x.items,
    }
}

// Rebuilds `t` with `f` applied to each direct child; leaves are returned as is.
function map_children_lowering_ty(t: LoweringTy, f: (LoweringTy) -> LoweringTy) -> LoweringTy {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever
            | TyError
            | TyInfer =>
        {
            x
        },
        let x: LoweringTyClass => LoweringTyClass { name: x.name, args: x.args.map(f) },
        let x: LoweringTyInterface => {
            LoweringTyInterface { name: x.name, args: x.args.map(f), assoc: x.assoc.map(f) }
        },
        let x: LoweringTyList => LoweringTyList { elem: f(x.elem) },
        let x: LoweringTyMap => LoweringTyMap { key: f(x.key), value: f(x.value) },
        let x: LoweringTyUnion => LoweringTyUnion { members: x.members.map(f) },
        let x: LoweringTyFunction => {
            LoweringTyFunction { params: x.params.map(f), ret: f(x.ret), throws_: f(x.throws_) }
        },
        let x: LoweringTyFuture => LoweringTyFuture { value: f(x.value), error: f(x.error) },
        let x: LoweringTyProjection => {
            LoweringTyProjection {
                base: f(x.base),
                interface_args: x.interface_args.map(f),
                member: x.member,
            }
        },
        let x: LoweringTyTuple => LoweringTyTuple { items: x.items.map(f) },
    }
}

// The direct children of `t`, in field order.
function children_lowering_ty(t: LoweringTy) -> LoweringTy[] {
    match (t) {
        TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever
            | TyError
            | TyInfer =>
        {
            []
        },
        let x: LoweringTyClass => x.args,
        let x: LoweringTyInterface => x.args.concat(x.assoc),
        let x: LoweringTyList => [x.elem],
        let x: LoweringTyMap => [x.key].concat([x.value]),
        let x: LoweringTyUnion => x.members,
        let x: LoweringTyFunction => x.params.concat([x.ret]).concat([x.throws_]),
        let x: LoweringTyFuture => [x.value].concat([x.error]),
        let x: LoweringTyProjection => [x.base].concat(x.interface_args),
        let x: LoweringTyTuple => x.items,
    }
}

// Rebuilds `t` with `f` applied to each direct child; leaves are returned as is.
function map_children_runtime_ty(t: RuntimeTy, f: (RuntimeTy) -> RuntimeTy) -> RuntimeTy {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: RuntimeTyClass => RuntimeTyClass { name: x.name, args: x.args.map(f) },
        let x: RuntimeTyInterface => {
            RuntimeTyInterface { name: x.name, args: x.args.map(f), assoc: x.assoc.map(f) }
        },
        let x: RuntimeTyList => RuntimeTyList { elem: f(x.elem) },
        let x: RuntimeTyMap => RuntimeTyMap { key: f(x.key), value: f(x.value) },
        let x: RuntimeTyUnion => RuntimeTyUnion { members: x.members.map(f) },
        let x: RuntimeTyFunction => {
            RuntimeTyFunction { params: x.params.map(f), ret: f(x.ret), throws_: f(x.throws_) }
        },
        let x: RuntimeTyFuture => RuntimeTyFuture { value: f(x.value), error: f(x.error) },
        let x: RuntimeTyProjection => {
            RuntimeTyProjection {
                base: f(x.base),
                interface_args: x.interface_args.map(f),
                member: x.member,
            }
        },
        let x: RuntimeTyTuple => RuntimeTyTuple { items: x.items.map(f) },
    }
}

// The direct children of `t`, in field order.
function children_runtime_ty(t: RuntimeTy) -> RuntimeTy[] {
    match (t) {
        TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever =>
        {
            []
        },
        let x: RuntimeTyClass => x.args,
        let x: RuntimeTyInterface => x.args.concat(x.assoc),
        let x: RuntimeTyList => [x.elem],
        let x: RuntimeTyMap => [x.key].concat([x.value]),
        let x: RuntimeTyUnion => x.members,
        let x: RuntimeTyFunction => x.params.concat([x.ret]).concat([x.throws_]),
        let x: RuntimeTyFuture => [x.value].concat([x.error]),
        let x: RuntimeTyProjection => [x.base].concat(x.interface_args),
        let x: RuntimeTyTuple => x.items,
    }
}

// Rebuilds `t` with `f` applied to each direct child; leaves are returned as is.
function map_children_codegen_ty(t: CodegenTy, f: (CodegenTy) -> CodegenTy) -> CodegenTy {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: CodegenTyClass => CodegenTyClass { name: x.name, args: x.args.map(f) },
        let x: CodegenTyInterface => {
            CodegenTyInterface { name: x.name, args: x.args.map(f), assoc: x.assoc.map(f) }
        },
        let x: CodegenTyList => CodegenTyList { elem: f(x.elem) },
        let x: CodegenTyMap => CodegenTyMap { key: f(x.key), value: f(x.value) },
        let x: CodegenTyUnion => CodegenTyUnion { members: x.members.map(f) },
        let x: CodegenTyFunction => {
            CodegenTyFunction { params: x.params.map(f), ret: f(x.ret), throws_: f(x.throws_) }
        },
        let x: CodegenTyFuture => CodegenTyFuture { value: f(x.value), error: f(x.error) },
        let x: CodegenTyTuple => CodegenTyTuple { items: x.items.map(f) },
    }
}

// The direct children of `t`, in field order.
function children_codegen_ty(t: CodegenTy) -> CodegenTy[] {
    match (t) {
        TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever =>
        {
            []
        },
        let x: CodegenTyClass => x.args,
        let x: CodegenTyInterface => x.args.concat(x.assoc),
        let x: CodegenTyList => [x.elem],
        let x: CodegenTyMap => [x.key].concat([x.value]),
        let x: CodegenTyUnion => x.members,
        let x: CodegenTyFunction => x.params.concat([x.ret]).concat([x.throws_]),
        let x: CodegenTyFuture => [x.value].concat([x.error]),
        let x: CodegenTyTuple => x.items,
    }
}

// Rebuilds `t` with `f` applied to each direct child; leaves are returned as is.
function map_children_realized_ty(t: RealizedTy, f: (RealizedTy) -> RealizedTy) -> RealizedTy {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: RealizedTyClass => RealizedTyClass { name: x.name, args: x.args.map(f) },
        let x: RealizedTyInterface => {
            RealizedTyInterface { name: x.name, args: x.args.map(f), assoc: x.assoc.map(f) }
        },
        let x: RealizedTyList => RealizedTyList { elem: f(x.elem) },
        let x: RealizedTyMap => RealizedTyMap { key: f(x.key), value: f(x.value) },
        let x: RealizedTyUnion => RealizedTyUnion { members: x.members.map(f) },
        let x: RealizedTyFunction => {
            RealizedTyFunction { params: x.params.map(f), ret: f(x.ret), throws_: f(x.throws_) }
        },
        let x: RealizedTyFuture => RealizedTyFuture { value: f(x.value), error: f(x.error) },
        let x: RealizedTyTuple => RealizedTyTuple { items: x.items.map(f) },
    }
}

// The direct children of `t`, in field order.
function children_realized_ty(t: RealizedTy) -> RealizedTy[] {
    match (t) {
        TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyUnknown
            | TyNever =>
        {
            []
        },
        let x: RealizedTyClass => x.args,
        let x: RealizedTyInterface => x.args.concat(x.assoc),
        let x: RealizedTyList => [x.elem],
        let x: RealizedTyMap => [x.key].concat([x.value]),
        let x: RealizedTyUnion => x.members,
        let x: RealizedTyFunction => x.params.concat([x.ret]).concat([x.throws_]),
        let x: RealizedTyFuture => [x.value].concat([x.error]),
        let x: RealizedTyTuple => x.items,
    }
}

// Rebuilds `t` with `f` applied to each direct child; leaves are returned as is.
function map_children_concrete_ty(t: ConcreteTy, f: (ConcreteTy) -> ConcreteTy) -> ConcreteTy {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyEnum
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyNever =>
        {
            x
        },
        let x: ConcreteTyClass => ConcreteTyClass { name: x.name, args: x.args.map(f) },
        let x: ConcreteTyList => ConcreteTyList { elem: f(x.elem) },
        let x: ConcreteTyMap => ConcreteTyMap { key: f(x.key), value: f(x.value) },
        let x: ConcreteTyFunction => {
            ConcreteTyFunction { params: x.params.map(f), ret: f(x.ret), throws_: f(x.throws_) }
        },
        let x: ConcreteTyFuture => ConcreteTyFuture { value: f(x.value), error: f(x.error) },
        let x: ConcreteTyTuple => ConcreteTyTuple { items: x.items.map(f) },
    }
}

// The direct children of `t`, in field order.
function children_concrete_ty(t: ConcreteTy) -> ConcreteTy[] {
    match (t) {
        TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyEnum
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyNever =>
        {
            []
        },
        let x: ConcreteTyClass => x.args,
        let x: ConcreteTyList => [x.elem],
        let x: ConcreteTyMap => [x.key].concat([x.value]),
        let x: ConcreteTyFunction => x.params.concat([x.ret]).concat([x.throws_]),
        let x: ConcreteTyFuture => [x.value].concat([x.error]),
        let x: ConcreteTyTuple => x.items,
    }
}

// Rebuilds `t` with `f` applied to each direct child; leaves are returned as is.
function map_children_ty_template(t: TyTemplate, f: (TyTemplate) -> TyTemplate) -> TyTemplate {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyUnknown
            | TyNever
            | TyTypeArgRef =>
        {
            x
        },
        let x: TyTemplateClass => TyTemplateClass { name: x.name, args: x.args.map(f) },
        let x: TyTemplateInterface => {
            TyTemplateInterface { name: x.name, args: x.args.map(f), assoc: x.assoc.map(f) }
        },
        let x: TyTemplateList => TyTemplateList { elem: f(x.elem) },
        let x: TyTemplateMap => TyTemplateMap { key: f(x.key), value: f(x.value) },
        let x: TyTemplateUnion => TyTemplateUnion { members: x.members.map(f) },
        let x: TyTemplateFunction => {
            TyTemplateFunction { params: x.params.map(f), ret: f(x.ret), throws_: f(x.throws_) }
        },
        let x: TyTemplateFuture => TyTemplateFuture { value: f(x.value), error: f(x.error) },
        let x: TyTemplateProjection => {
            TyTemplateProjection {
                base: f(x.base),
                interface_args: x.interface_args.map(f),
                member: x.member,
            }
        },
        let x: TyTemplateTuple => TyTemplateTuple { items: x.items.map(f) },
    }
}

// The direct children of `t`, in field order.
function children_ty_template(t: TyTemplate) -> TyTemplate[] {
    match (t) {
        TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyUnknown
            | TyNever
            | TyTypeArgRef =>
        {
            []
        },
        let x: TyTemplateClass => x.args,
        let x: TyTemplateInterface => x.args.concat(x.assoc),
        let x: TyTemplateList => [x.elem],
        let x: TyTemplateMap => [x.key].concat([x.value]),
        let x: TyTemplateUnion => x.members,
        let x: TyTemplateFunction => x.params.concat([x.ret]).concat([x.throws_]),
        let x: TyTemplateFuture => [x.value].concat([x.error]),
        let x: TyTemplateProjection => [x.base].concat(x.interface_args),
        let x: TyTemplateTuple => x.items,
    }
}

// == InferTy pool conversions ==============================================

const HAS_INFER = 1;
const HAS_ERROR = 2;
const HAS_TYPEVAR = 4;
const HAS_PROJECTION = 8;

function infer_flags(pool: InferPool, k: InferTy) -> int {
    match (k) {
        TyInt => 0,
        TyBigint => 0,
        TyFloat => 0,
        TyString => 0,
        TyBool => 0,
        TyNull => 0,
        TyUint8Array => 0,
        TyMedia => 0,
        TyLiteral => 0,
        let x: InferTyClass => {
            x.args.reduce(
                (acc, c) -> {
                    acc | pool.flags[c]
                },
                0,
            )
        },
        let x: InferTyInterface => {
            x.args.reduce(
                (acc, c) -> {
                    acc | pool.flags[c]
                },
                0,
            )
                | x.assoc.reduce(
                    (acc, c) -> {
                        acc | pool.flags[c]
                    },
                    0,
                )
        },
        TyEnum => 0,
        TyEnumVariant => 0,
        let x: InferTyList => pool.flags[x.elem],
        let x: InferTyMap => pool.flags[x.key] | pool.flags[x.value],
        let x: InferTyUnion => {
            x.members.reduce(
                (acc, c) -> {
                    acc | pool.flags[c]
                },
                0,
            )
        },
        let x: InferTyFunction => {
            x.params.reduce(
                (acc, c) -> {
                    acc | pool.flags[c]
                },
                0,
            )
                | pool.flags[x.ret]
                | pool.flags[x.throws_]
        },
        let x: InferTyFuture => pool.flags[x.value] | pool.flags[x.error],
        TyRustType => 0,
        TyType => 0,
        TyResource => 0,
        TyPromptAst => 0,
        TyTypeAlias => 0,
        TyTypeVar => 4,
        let x: InferTyProjection => {
            8
                | pool.flags[x.base]
                | x.interface_args.reduce(
                    (acc, c) -> {
                        acc | pool.flags[c]
                    },
                    0,
                )
        },
        TyUnknown => 0,
        TyNever => 0,
        TyError => 2,
        TyInferVar => 1,
        let x: InferTyTuple => {
            x.items.reduce(
                (acc, c) -> {
                    acc | pool.flags[c]
                },
                0,
            )
        },
    }
}

function intern_ty(pool: InferPool, t: Ty) -> int {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever
            | TyError =>
        {
            pool.add(x)
        },
        let x: TyClass => {
            pool.add(
                InferTyClass {
                    name: x.name,
                    args: x.args.map((c) -> {
                        intern_ty(pool, c)
                    }),
                },
            )
        },
        let x: TyInterface => {
            pool.add(
                InferTyInterface {
                    name: x.name,
                    args: x.args.map((c) -> {
                        intern_ty(pool, c)
                    }),
                    assoc: x.assoc.map((c) -> {
                        intern_ty(pool, c)
                    }),
                },
            )
        },
        let x: TyList => pool.add(InferTyList { elem: intern_ty(pool, x.elem) }),
        let x: TyMap => {
            pool.add(InferTyMap { key: intern_ty(pool, x.key), value: intern_ty(pool, x.value) })
        },
        let x: TyUnion => {
            pool.add(
                InferTyUnion {
                    members: x.members.map((c) -> {
                        intern_ty(pool, c)
                    }),
                },
            )
        },
        let x: TyFunction => {
            pool.add(
                InferTyFunction {
                    params: x.params.map((c) -> {
                        intern_ty(pool, c)
                    }),
                    ret: intern_ty(pool, x.ret),
                    throws_: intern_ty(pool, x.throws_),
                },
            )
        },
        let x: TyFuture => {
            pool.add(
                InferTyFuture { value: intern_ty(pool, x.value), error: intern_ty(pool, x.error) },
            )
        },
        let x: TyProjection => {
            pool.add(
                InferTyProjection {
                    base: intern_ty(pool, x.base),
                    interface_args: x.interface_args.map((c) -> {
                        intern_ty(pool, c)
                    }),
                    member: x.member,
                },
            )
        },
        let x: TyTuple => {
            pool.add(
                InferTyTuple {
                    items: x.items.map((c) -> {
                        intern_ty(pool, c)
                    }),
                },
            )
        },
    }
}

function intern_runtime_ty(pool: InferPool, t: RuntimeTy) -> int {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever =>
        {
            pool.add(x)
        },
        let x: RuntimeTyClass => {
            pool.add(
                InferTyClass {
                    name: x.name,
                    args: x.args.map((c) -> {
                        intern_runtime_ty(pool, c)
                    }),
                },
            )
        },
        let x: RuntimeTyInterface => {
            pool.add(
                InferTyInterface {
                    name: x.name,
                    args: x.args.map((c) -> {
                        intern_runtime_ty(pool, c)
                    }),
                    assoc: x.assoc.map((c) -> {
                        intern_runtime_ty(pool, c)
                    }),
                },
            )
        },
        let x: RuntimeTyList => pool.add(InferTyList { elem: intern_runtime_ty(pool, x.elem) }),
        let x: RuntimeTyMap => {
            pool.add(
                InferTyMap {
                    key: intern_runtime_ty(pool, x.key),
                    value: intern_runtime_ty(pool, x.value),
                },
            )
        },
        let x: RuntimeTyUnion => {
            pool.add(
                InferTyUnion {
                    members: x.members.map((c) -> {
                        intern_runtime_ty(pool, c)
                    }),
                },
            )
        },
        let x: RuntimeTyFunction => {
            pool.add(
                InferTyFunction {
                    params: x.params.map((c) -> {
                        intern_runtime_ty(pool, c)
                    }),
                    ret: intern_runtime_ty(pool, x.ret),
                    throws_: intern_runtime_ty(pool, x.throws_),
                },
            )
        },
        let x: RuntimeTyFuture => {
            pool.add(
                InferTyFuture {
                    value: intern_runtime_ty(pool, x.value),
                    error: intern_runtime_ty(pool, x.error),
                },
            )
        },
        let x: RuntimeTyProjection => {
            pool.add(
                InferTyProjection {
                    base: intern_runtime_ty(pool, x.base),
                    interface_args: x.interface_args.map((c) -> {
                        intern_runtime_ty(pool, c)
                    }),
                    member: x.member,
                },
            )
        },
        let x: RuntimeTyTuple => {
            pool.add(
                InferTyTuple {
                    items: x.items.map((c) -> {
                        intern_runtime_ty(pool, c)
                    }),
                },
            )
        },
    }
}

function intern_codegen_ty(pool: InferPool, t: CodegenTy) -> int {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever =>
        {
            pool.add(x)
        },
        let x: CodegenTyClass => {
            pool.add(
                InferTyClass {
                    name: x.name,
                    args: x.args.map((c) -> {
                        intern_codegen_ty(pool, c)
                    }),
                },
            )
        },
        let x: CodegenTyInterface => {
            pool.add(
                InferTyInterface {
                    name: x.name,
                    args: x.args.map((c) -> {
                        intern_codegen_ty(pool, c)
                    }),
                    assoc: x.assoc.map((c) -> {
                        intern_codegen_ty(pool, c)
                    }),
                },
            )
        },
        let x: CodegenTyList => pool.add(InferTyList { elem: intern_codegen_ty(pool, x.elem) }),
        let x: CodegenTyMap => {
            pool.add(
                InferTyMap {
                    key: intern_codegen_ty(pool, x.key),
                    value: intern_codegen_ty(pool, x.value),
                },
            )
        },
        let x: CodegenTyUnion => {
            pool.add(
                InferTyUnion {
                    members: x.members.map((c) -> {
                        intern_codegen_ty(pool, c)
                    }),
                },
            )
        },
        let x: CodegenTyFunction => {
            pool.add(
                InferTyFunction {
                    params: x.params.map((c) -> {
                        intern_codegen_ty(pool, c)
                    }),
                    ret: intern_codegen_ty(pool, x.ret),
                    throws_: intern_codegen_ty(pool, x.throws_),
                },
            )
        },
        let x: CodegenTyFuture => {
            pool.add(
                InferTyFuture {
                    value: intern_codegen_ty(pool, x.value),
                    error: intern_codegen_ty(pool, x.error),
                },
            )
        },
        let x: CodegenTyTuple => {
            pool.add(
                InferTyTuple {
                    items: x.items.map((c) -> {
                        intern_codegen_ty(pool, c)
                    }),
                },
            )
        },
    }
}

function intern_realized_ty(pool: InferPool, t: RealizedTy) -> int {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyUnknown
            | TyNever =>
        {
            pool.add(x)
        },
        let x: RealizedTyClass => {
            pool.add(
                InferTyClass {
                    name: x.name,
                    args: x.args.map((c) -> {
                        intern_realized_ty(pool, c)
                    }),
                },
            )
        },
        let x: RealizedTyInterface => {
            pool.add(
                InferTyInterface {
                    name: x.name,
                    args: x.args.map((c) -> {
                        intern_realized_ty(pool, c)
                    }),
                    assoc: x.assoc.map((c) -> {
                        intern_realized_ty(pool, c)
                    }),
                },
            )
        },
        let x: RealizedTyList => pool.add(InferTyList { elem: intern_realized_ty(pool, x.elem) }),
        let x: RealizedTyMap => {
            pool.add(
                InferTyMap {
                    key: intern_realized_ty(pool, x.key),
                    value: intern_realized_ty(pool, x.value),
                },
            )
        },
        let x: RealizedTyUnion => {
            pool.add(
                InferTyUnion {
                    members: x.members.map((c) -> {
                        intern_realized_ty(pool, c)
                    }),
                },
            )
        },
        let x: RealizedTyFunction => {
            pool.add(
                InferTyFunction {
                    params: x.params.map((c) -> {
                        intern_realized_ty(pool, c)
                    }),
                    ret: intern_realized_ty(pool, x.ret),
                    throws_: intern_realized_ty(pool, x.throws_),
                },
            )
        },
        let x: RealizedTyFuture => {
            pool.add(
                InferTyFuture {
                    value: intern_realized_ty(pool, x.value),
                    error: intern_realized_ty(pool, x.error),
                },
            )
        },
        let x: RealizedTyTuple => {
            pool.add(
                InferTyTuple {
                    items: x.items.map((c) -> {
                        intern_realized_ty(pool, c)
                    }),
                },
            )
        },
    }
}

function intern_concrete_ty(pool: InferPool, t: ConcreteTy) -> int {
    match (t) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyEnum
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyNever =>
        {
            pool.add(x)
        },
        let x: ConcreteTyClass => {
            pool.add(
                InferTyClass {
                    name: x.name,
                    args: x.args.map((c) -> {
                        intern_concrete_ty(pool, c)
                    }),
                },
            )
        },
        let x: ConcreteTyList => pool.add(InferTyList { elem: intern_concrete_ty(pool, x.elem) }),
        let x: ConcreteTyMap => {
            pool.add(
                InferTyMap {
                    key: intern_concrete_ty(pool, x.key),
                    value: intern_concrete_ty(pool, x.value),
                },
            )
        },
        let x: ConcreteTyFunction => {
            pool.add(
                InferTyFunction {
                    params: x.params.map((c) -> {
                        intern_concrete_ty(pool, c)
                    }),
                    ret: intern_concrete_ty(pool, x.ret),
                    throws_: intern_concrete_ty(pool, x.throws_),
                },
            )
        },
        let x: ConcreteTyFuture => {
            pool.add(
                InferTyFuture {
                    value: intern_concrete_ty(pool, x.value),
                    error: intern_concrete_ty(pool, x.error),
                },
            )
        },
        let x: ConcreteTyTuple => {
            pool.add(
                InferTyTuple {
                    items: x.items.map((c) -> {
                        intern_concrete_ty(pool, c)
                    }),
                },
            )
        },
    }
}

// Reads handle `h` back as a Ty; fails on a variant outside it.
function resolve_ty(pool: InferPool, h: int) -> Ty throws NarrowError {
    match (pool.kinds[h]) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever
            | TyError =>
        {
            x
        },
        let x: InferTyClass => {
            TyClass {
                name: x.name,
                args: x.args.map((c) -> {
                    resolve_ty(pool, c)
                }),
            }
        },
        let x: InferTyInterface => {
            TyInterface {
                name: x.name,
                args: x.args.map((c) -> {
                    resolve_ty(pool, c)
                }),
                assoc: x.assoc.map((c) -> {
                    resolve_ty(pool, c)
                }),
            }
        },
        let x: InferTyList => TyList { elem: resolve_ty(pool, x.elem) },
        let x: InferTyMap => {
            TyMap { key: resolve_ty(pool, x.key), value: resolve_ty(pool, x.value) }
        },
        let x: InferTyUnion => {
            TyUnion {
                members: x.members.map((c) -> {
                    resolve_ty(pool, c)
                }),
            }
        },
        let x: InferTyFunction => {
            TyFunction {
                params: x.params.map((c) -> {
                    resolve_ty(pool, c)
                }),
                ret: resolve_ty(pool, x.ret),
                throws_: resolve_ty(pool, x.throws_),
            }
        },
        let x: InferTyFuture => {
            TyFuture { value: resolve_ty(pool, x.value), error: resolve_ty(pool, x.error) }
        },
        let x: InferTyProjection => {
            TyProjection {
                base: resolve_ty(pool, x.base),
                interface_args: x.interface_args.map((c) -> {
                    resolve_ty(pool, c)
                }),
                member: x.member,
            }
        },
        let x: InferTyTuple => {
            TyTuple {
                items: x.items.map((c) -> {
                    resolve_ty(pool, c)
                }),
            }
        },
        TyInferVar => throw NarrowError { variant: "InferVar", into: "Ty" },
    }
}

// Reads handle `h` back as a LoweringTy; fails on a variant outside it.
function resolve_lowering_ty(pool: InferPool, h: int) -> LoweringTy throws NarrowError {
    match (pool.kinds[h]) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever
            | TyError =>
        {
            x
        },
        let x: InferTyClass => {
            LoweringTyClass {
                name: x.name,
                args: x.args.map((c) -> {
                    resolve_lowering_ty(pool, c)
                }),
            }
        },
        let x: InferTyInterface => {
            LoweringTyInterface {
                name: x.name,
                args: x.args.map((c) -> {
                    resolve_lowering_ty(pool, c)
                }),
                assoc: x.assoc.map((c) -> {
                    resolve_lowering_ty(pool, c)
                }),
            }
        },
        let x: InferTyList => LoweringTyList { elem: resolve_lowering_ty(pool, x.elem) },
        let x: InferTyMap => {
            LoweringTyMap {
                key: resolve_lowering_ty(pool, x.key),
                value: resolve_lowering_ty(pool, x.value),
            }
        },
        let x: InferTyUnion => {
            LoweringTyUnion {
                members: x.members.map((c) -> {
                    resolve_lowering_ty(pool, c)
                }),
            }
        },
        let x: InferTyFunction => {
            LoweringTyFunction {
                params: x.params.map((c) -> {
                    resolve_lowering_ty(pool, c)
                }),
                ret: resolve_lowering_ty(pool, x.ret),
                throws_: resolve_lowering_ty(pool, x.throws_),
            }
        },
        let x: InferTyFuture => {
            LoweringTyFuture {
                value: resolve_lowering_ty(pool, x.value),
                error: resolve_lowering_ty(pool, x.error),
            }
        },
        let x: InferTyProjection => {
            LoweringTyProjection {
                base: resolve_lowering_ty(pool, x.base),
                interface_args: x.interface_args.map((c) -> {
                    resolve_lowering_ty(pool, c)
                }),
                member: x.member,
            }
        },
        let x: InferTyTuple => {
            LoweringTyTuple {
                items: x.items.map((c) -> {
                    resolve_lowering_ty(pool, c)
                }),
            }
        },
        TyInferVar => throw NarrowError { variant: "InferVar", into: "LoweringTy" },
    }
}

// Reads handle `h` back as a RuntimeTy; fails on a variant outside it.
function resolve_runtime_ty(pool: InferPool, h: int) -> RuntimeTy throws NarrowError {
    match (pool.kinds[h]) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: InferTyClass => {
            RuntimeTyClass {
                name: x.name,
                args: x.args.map((c) -> {
                    resolve_runtime_ty(pool, c)
                }),
            }
        },
        let x: InferTyInterface => {
            RuntimeTyInterface {
                name: x.name,
                args: x.args.map((c) -> {
                    resolve_runtime_ty(pool, c)
                }),
                assoc: x.assoc.map((c) -> {
                    resolve_runtime_ty(pool, c)
                }),
            }
        },
        let x: InferTyList => RuntimeTyList { elem: resolve_runtime_ty(pool, x.elem) },
        let x: InferTyMap => {
            RuntimeTyMap {
                key: resolve_runtime_ty(pool, x.key),
                value: resolve_runtime_ty(pool, x.value),
            }
        },
        let x: InferTyUnion => {
            RuntimeTyUnion {
                members: x.members.map((c) -> {
                    resolve_runtime_ty(pool, c)
                }),
            }
        },
        let x: InferTyFunction => {
            RuntimeTyFunction {
                params: x.params.map((c) -> {
                    resolve_runtime_ty(pool, c)
                }),
                ret: resolve_runtime_ty(pool, x.ret),
                throws_: resolve_runtime_ty(pool, x.throws_),
            }
        },
        let x: InferTyFuture => {
            RuntimeTyFuture {
                value: resolve_runtime_ty(pool, x.value),
                error: resolve_runtime_ty(pool, x.error),
            }
        },
        let x: InferTyProjection => {
            RuntimeTyProjection {
                base: resolve_runtime_ty(pool, x.base),
                interface_args: x.interface_args.map((c) -> {
                    resolve_runtime_ty(pool, c)
                }),
                member: x.member,
            }
        },
        let x: InferTyTuple => {
            RuntimeTyTuple {
                items: x.items.map((c) -> {
                    resolve_runtime_ty(pool, c)
                }),
            }
        },
        TyError => throw NarrowError { variant: "Error", into: "RuntimeTy" },
        TyInferVar => throw NarrowError { variant: "InferVar", into: "RuntimeTy" },
    }
}

// Reads handle `h` back as a CodegenTy; fails on a variant outside it.
function resolve_codegen_ty(pool: InferPool, h: int) -> CodegenTy throws NarrowError {
    match (pool.kinds[h]) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyTypeVar
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: InferTyClass => {
            CodegenTyClass {
                name: x.name,
                args: x.args.map((c) -> {
                    resolve_codegen_ty(pool, c)
                }),
            }
        },
        let x: InferTyInterface => {
            CodegenTyInterface {
                name: x.name,
                args: x.args.map((c) -> {
                    resolve_codegen_ty(pool, c)
                }),
                assoc: x.assoc.map((c) -> {
                    resolve_codegen_ty(pool, c)
                }),
            }
        },
        let x: InferTyList => CodegenTyList { elem: resolve_codegen_ty(pool, x.elem) },
        let x: InferTyMap => {
            CodegenTyMap {
                key: resolve_codegen_ty(pool, x.key),
                value: resolve_codegen_ty(pool, x.value),
            }
        },
        let x: InferTyUnion => {
            CodegenTyUnion {
                members: x.members.map((c) -> {
                    resolve_codegen_ty(pool, c)
                }),
            }
        },
        let x: InferTyFunction => {
            CodegenTyFunction {
                params: x.params.map((c) -> {
                    resolve_codegen_ty(pool, c)
                }),
                ret: resolve_codegen_ty(pool, x.ret),
                throws_: resolve_codegen_ty(pool, x.throws_),
            }
        },
        let x: InferTyFuture => {
            CodegenTyFuture {
                value: resolve_codegen_ty(pool, x.value),
                error: resolve_codegen_ty(pool, x.error),
            }
        },
        let x: InferTyTuple => {
            CodegenTyTuple {
                items: x.items.map((c) -> {
                    resolve_codegen_ty(pool, c)
                }),
            }
        },
        InferTyProjection => throw NarrowError { variant: "Projection", into: "CodegenTy" },
        TyError => throw NarrowError { variant: "Error", into: "CodegenTy" },
        TyInferVar => throw NarrowError { variant: "InferVar", into: "CodegenTy" },
    }
}

// Reads handle `h` back as a RealizedTy; fails on a variant outside it.
function resolve_realized_ty(pool: InferPool, h: int) -> RealizedTy throws NarrowError {
    match (pool.kinds[h]) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: InferTyClass => {
            RealizedTyClass {
                name: x.name,
                args: x.args.map((c) -> {
                    resolve_realized_ty(pool, c)
                }),
            }
        },
        let x: InferTyInterface => {
            RealizedTyInterface {
                name: x.name,
                args: x.args.map((c) -> {
                    resolve_realized_ty(pool, c)
                }),
                assoc: x.assoc.map((c) -> {
                    resolve_realized_ty(pool, c)
                }),
            }
        },
        let x: InferTyList => RealizedTyList { elem: resolve_realized_ty(pool, x.elem) },
        let x: InferTyMap => {
            RealizedTyMap {
                key: resolve_realized_ty(pool, x.key),
                value: resolve_realized_ty(pool, x.value),
            }
        },
        let x: InferTyUnion => {
            RealizedTyUnion {
                members: x.members.map((c) -> {
                    resolve_realized_ty(pool, c)
                }),
            }
        },
        let x: InferTyFunction => {
            RealizedTyFunction {
                params: x.params.map((c) -> {
                    resolve_realized_ty(pool, c)
                }),
                ret: resolve_realized_ty(pool, x.ret),
                throws_: resolve_realized_ty(pool, x.throws_),
            }
        },
        let x: InferTyFuture => {
            RealizedTyFuture {
                value: resolve_realized_ty(pool, x.value),
                error: resolve_realized_ty(pool, x.error),
            }
        },
        let x: InferTyTuple => {
            RealizedTyTuple {
                items: x.items.map((c) -> {
                    resolve_realized_ty(pool, c)
                }),
            }
        },
        TyTypeVar => throw NarrowError { variant: "TypeVar", into: "RealizedTy" },
        InferTyProjection => throw NarrowError { variant: "Projection", into: "RealizedTy" },
        TyError => throw NarrowError { variant: "Error", into: "RealizedTy" },
        TyInferVar => throw NarrowError { variant: "InferVar", into: "RealizedTy" },
    }
}

// Reads handle `h` back as a ConcreteTy; fails on a variant outside it.
function resolve_concrete_ty(pool: InferPool, h: int) -> ConcreteTy throws NarrowError {
    match (pool.kinds[h]) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyEnum
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyNever =>
        {
            x
        },
        let x: InferTyClass => {
            ConcreteTyClass {
                name: x.name,
                args: x.args.map((c) -> {
                    resolve_concrete_ty(pool, c)
                }),
            }
        },
        let x: InferTyList => ConcreteTyList { elem: resolve_concrete_ty(pool, x.elem) },
        let x: InferTyMap => {
            ConcreteTyMap {
                key: resolve_concrete_ty(pool, x.key),
                value: resolve_concrete_ty(pool, x.value),
            }
        },
        let x: InferTyFunction => {
            ConcreteTyFunction {
                params: x.params.map((c) -> {
                    resolve_concrete_ty(pool, c)
                }),
                ret: resolve_concrete_ty(pool, x.ret),
                throws_: resolve_concrete_ty(pool, x.throws_),
            }
        },
        let x: InferTyFuture => {
            ConcreteTyFuture {
                value: resolve_concrete_ty(pool, x.value),
                error: resolve_concrete_ty(pool, x.error),
            }
        },
        let x: InferTyTuple => {
            ConcreteTyTuple {
                items: x.items.map((c) -> {
                    resolve_concrete_ty(pool, c)
                }),
            }
        },
        TyLiteral => throw NarrowError { variant: "Literal", into: "ConcreteTy" },
        InferTyInterface => throw NarrowError { variant: "Interface", into: "ConcreteTy" },
        TyEnumVariant => throw NarrowError { variant: "EnumVariant", into: "ConcreteTy" },
        InferTyUnion => throw NarrowError { variant: "Union", into: "ConcreteTy" },
        TyTypeAlias => throw NarrowError { variant: "TypeAlias", into: "ConcreteTy" },
        TyTypeVar => throw NarrowError { variant: "TypeVar", into: "ConcreteTy" },
        InferTyProjection => throw NarrowError { variant: "Projection", into: "ConcreteTy" },
        TyUnknown => throw NarrowError { variant: "Unknown", into: "ConcreteTy" },
        TyError => throw NarrowError { variant: "Error", into: "ConcreteTy" },
        TyInferVar => throw NarrowError { variant: "InferVar", into: "ConcreteTy" },
    }
}

// Reads handle `h` back as a TyTemplate; fails on a variant outside it.
function resolve_ty_template(pool: InferPool, h: int) -> TyTemplate throws NarrowError {
    match (pool.kinds[h]) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: InferTyClass => {
            TyTemplateClass {
                name: x.name,
                args: x.args.map((c) -> {
                    resolve_ty_template(pool, c)
                }),
            }
        },
        let x: InferTyInterface => {
            TyTemplateInterface {
                name: x.name,
                args: x.args.map((c) -> {
                    resolve_ty_template(pool, c)
                }),
                assoc: x.assoc.map((c) -> {
                    resolve_ty_template(pool, c)
                }),
            }
        },
        let x: InferTyList => TyTemplateList { elem: resolve_ty_template(pool, x.elem) },
        let x: InferTyMap => {
            TyTemplateMap {
                key: resolve_ty_template(pool, x.key),
                value: resolve_ty_template(pool, x.value),
            }
        },
        let x: InferTyUnion => {
            TyTemplateUnion {
                members: x.members.map((c) -> {
                    resolve_ty_template(pool, c)
                }),
            }
        },
        let x: InferTyFunction => {
            TyTemplateFunction {
                params: x.params.map((c) -> {
                    resolve_ty_template(pool, c)
                }),
                ret: resolve_ty_template(pool, x.ret),
                throws_: resolve_ty_template(pool, x.throws_),
            }
        },
        let x: InferTyFuture => {
            TyTemplateFuture {
                value: resolve_ty_template(pool, x.value),
                error: resolve_ty_template(pool, x.error),
            }
        },
        let x: InferTyProjection => {
            TyTemplateProjection {
                base: resolve_ty_template(pool, x.base),
                interface_args: x.interface_args.map((c) -> {
                    resolve_ty_template(pool, c)
                }),
                member: x.member,
            }
        },
        let x: InferTyTuple => {
            TyTemplateTuple {
                items: x.items.map((c) -> {
                    resolve_ty_template(pool, c)
                }),
            }
        },
        TyTypeVar => throw NarrowError { variant: "TypeVar", into: "TyTemplate" },
        TyError => throw NarrowError { variant: "Error", into: "TyTemplate" },
        TyInferVar => throw NarrowError { variant: "InferVar", into: "TyTemplate" },
    }
}
