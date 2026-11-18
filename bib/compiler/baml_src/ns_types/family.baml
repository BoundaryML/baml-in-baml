// GENERATED from ns_family_gen/spec.baml by `baml run types.family_gen.main`.
// Do not edit by hand: change the spec and regenerate.

// == Shared variants =======================================================

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
    kind: root.base.MediaKind,
}

class TyLiteral {
    value: root.base.Literal,
    freshness: Freshness,
}

class TyEnum {
    name: DeclName,
}

class TyEnumVariant {
    name: DeclName,
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
    name: DeclName,
}

class TyTypeVar {
    param: ParamTy,
}

class TyUnknown {
}

class TyNever {
}

class TyError {
}

class TyInfer {
}

class TyTypeArgRef {
    index: int,
}

class TyInferVar {
    var: int,
}

// -- Ty (deep) -------------------------------------------------------------

class TyClass {
    name: DeclName,
    args: Ty[],
}

class TyInterface {
    name: DeclName,
    args: Ty[],
    associated_types: AssociatedType[],
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
    params: FunctionParamTy[],
    ret: Ty,
    throws_: Ty,
}

class TyFuture {
    value: Ty,
    error: Ty,
}

class TyAssociatedTypeProjection {
    base: Ty,
    interface_: InterfaceConstraint,
    member: string,
}

class TyTuple {
    items: Ty[],
}

class FunctionParamTy {
    name: string?,
    ty: Ty,
    mode: FunctionParamMode,
}

class InterfaceConstraint {
    name: DeclName,
    generics: Ty[],
    associated_types: AssociatedType[],
}

class AssociatedType {
    name: string,
    ty: Ty,
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
    | TyAssociatedTypeProjection
    | TyUnknown
    | TyNever
    | TyError
    | TyTuple;

// -- LoweringTy (deep) -----------------------------------------------------

class LoweringTyClass {
    name: DeclName,
    args: LoweringTy[],
}

class LoweringTyInterface {
    name: DeclName,
    args: LoweringTy[],
    associated_types: LoweringAssociatedType[],
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
    params: LoweringFunctionParamTy[],
    ret: LoweringTy,
    throws_: LoweringTy,
}

class LoweringTyFuture {
    value: LoweringTy,
    error: LoweringTy,
}

class LoweringTyAssociatedTypeProjection {
    base: LoweringTy,
    interface_: LoweringInterfaceConstraint,
    member: string,
}

class LoweringTyTuple {
    items: LoweringTy[],
}

class LoweringFunctionParamTy {
    name: string?,
    ty: LoweringTy,
    mode: FunctionParamMode,
}

class LoweringInterfaceConstraint {
    name: DeclName,
    generics: LoweringTy[],
    associated_types: LoweringAssociatedType[],
}

class LoweringAssociatedType {
    name: string,
    ty: LoweringTy,
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
    | LoweringTyAssociatedTypeProjection
    | TyUnknown
    | TyNever
    | TyError
    | TyInfer
    | LoweringTyTuple;

// -- RuntimeTy (deep) ------------------------------------------------------

class RuntimeTyClass {
    name: DeclName,
    args: RuntimeTy[],
}

class RuntimeTyInterface {
    name: DeclName,
    args: RuntimeTy[],
    associated_types: RuntimeAssociatedType[],
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
    params: RuntimeFunctionParamTy[],
    ret: RuntimeTy,
    throws_: RuntimeTy,
}

class RuntimeTyFuture {
    value: RuntimeTy,
    error: RuntimeTy,
}

class RuntimeTyAssociatedTypeProjection {
    base: RuntimeTy,
    interface_: RuntimeInterfaceConstraint,
    member: string,
}

class RuntimeTyTuple {
    items: RuntimeTy[],
}

class RuntimeFunctionParamTy {
    name: string?,
    ty: RuntimeTy,
    mode: FunctionParamMode,
}

class RuntimeInterfaceConstraint {
    name: DeclName,
    generics: RuntimeTy[],
    associated_types: RuntimeAssociatedType[],
}

class RuntimeAssociatedType {
    name: string,
    ty: RuntimeTy,
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
    | RuntimeTyAssociatedTypeProjection
    | TyUnknown
    | TyNever
    | RuntimeTyTuple;

// -- CodegenTy (deep) ------------------------------------------------------

class CodegenTyClass {
    name: DeclName,
    args: CodegenTy[],
}

class CodegenTyInterface {
    name: DeclName,
    args: CodegenTy[],
    associated_types: CodegenAssociatedType[],
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
    params: CodegenFunctionParamTy[],
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

class CodegenFunctionParamTy {
    name: string?,
    ty: CodegenTy,
    mode: FunctionParamMode,
}

class CodegenInterfaceConstraint {
    name: DeclName,
    generics: CodegenTy[],
    associated_types: CodegenAssociatedType[],
}

class CodegenAssociatedType {
    name: string,
    ty: CodegenTy,
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

// -- RealizedTy (deep) -----------------------------------------------------

class RealizedTyClass {
    name: DeclName,
    args: RealizedTy[],
}

class RealizedTyInterface {
    name: DeclName,
    args: RealizedTy[],
    associated_types: RealizedAssociatedType[],
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
    params: RealizedFunctionParamTy[],
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

class RealizedFunctionParamTy {
    name: string?,
    ty: RealizedTy,
    mode: FunctionParamMode,
}

class RealizedInterfaceConstraint {
    name: DeclName,
    generics: RealizedTy[],
    associated_types: RealizedAssociatedType[],
}

class RealizedAssociatedType {
    name: string,
    ty: RealizedTy,
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

// -- ConcreteTy (shallow over RuntimeTy) -----------------------------------

class ConcreteTyClass {
    name: DeclName,
    args: RuntimeTy[],
}

class ConcreteTyList {
    elem: RuntimeTy,
}

class ConcreteTyMap {
    key: RuntimeTy,
    value: RuntimeTy,
}

class ConcreteTyFunction {
    params: RuntimeFunctionParamTy[],
    ret: RuntimeTy,
    throws_: RuntimeTy,
}

class ConcreteTyFuture {
    value: RuntimeTy,
    error: RuntimeTy,
}

class ConcreteTyTuple {
    items: RuntimeTy[],
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

// -- ConcreteRealizedTy (shallow over RealizedTy) --------------------------

class ConcreteRealizedTyClass {
    name: DeclName,
    args: RealizedTy[],
}

class ConcreteRealizedTyList {
    elem: RealizedTy,
}

class ConcreteRealizedTyMap {
    key: RealizedTy,
    value: RealizedTy,
}

class ConcreteRealizedTyFunction {
    params: RealizedFunctionParamTy[],
    ret: RealizedTy,
    throws_: RealizedTy,
}

class ConcreteRealizedTyFuture {
    value: RealizedTy,
    error: RealizedTy,
}

class ConcreteRealizedTyTuple {
    items: RealizedTy[],
}

type ConcreteRealizedTy = TyInt
    | TyBigint
    | TyFloat
    | TyString
    | TyBool
    | TyNull
    | TyUint8Array
    | TyMedia
    | ConcreteRealizedTyClass
    | TyEnum
    | ConcreteRealizedTyList
    | ConcreteRealizedTyMap
    | ConcreteRealizedTyFunction
    | ConcreteRealizedTyFuture
    | TyRustType
    | TyType
    | TyResource
    | TyPromptAst
    | TyNever
    | ConcreteRealizedTyTuple;

// -- TyTemplate (deep) -----------------------------------------------------

class TyTemplateClass {
    name: DeclName,
    args: TyTemplate[],
}

class TyTemplateInterface {
    name: DeclName,
    args: TyTemplate[],
    associated_types: TyTemplateAssociatedType[],
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
    params: TyTemplateFunctionParamTy[],
    ret: TyTemplate,
    throws_: TyTemplate,
}

class TyTemplateFuture {
    value: TyTemplate,
    error: TyTemplate,
}

class TyTemplateAssociatedTypeProjection {
    base: TyTemplate,
    interface_: TyTemplateInterfaceConstraint,
    member: string,
}

class TyTemplateTuple {
    items: TyTemplate[],
}

class TyTemplateFunctionParamTy {
    name: string?,
    ty: TyTemplate,
    mode: FunctionParamMode,
}

class TyTemplateInterfaceConstraint {
    name: DeclName,
    generics: TyTemplate[],
    associated_types: TyTemplateAssociatedType[],
}

class TyTemplateAssociatedType {
    name: string,
    ty: TyTemplate,
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
    | TyTemplateAssociatedTypeProjection
    | TyUnknown
    | TyNever
    | TyTypeArgRef
    | TyTemplateTuple;

// -- InferTy (interned: children are pool handles) -------------------------

class InferTyClass {
    name: DeclName,
    args: int[],
}

class InferTyInterface {
    name: DeclName,
    args: int[],
    associated_types: InferAssociatedType[],
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
    params: InferFunctionParamTy[],
    ret: int,
    throws_: int,
}

class InferTyFuture {
    value: int,
    error: int,
}

class InferTyAssociatedTypeProjection {
    base: int,
    interface_: InferInterfaceConstraint,
    member: string,
}

class InferTyTuple {
    items: int[],
}

class InferFunctionParamTy {
    name: string?,
    ty: int,
    mode: FunctionParamMode,
}

class InferInterfaceConstraint {
    name: DeclName,
    generics: int[],
    associated_types: InferAssociatedType[],
}

class InferAssociatedType {
    name: string,
    ty: int,
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
    | InferTyAssociatedTypeProjection
    | TyUnknown
    | TyNever
    | TyError
    | TyInferVar
    | InferTyTuple;

// == Widening and narrowing ================================================

// Infallible: every Ty is a LoweringTy.
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
                associated_types: x.associated_types.map((s0) -> {
                    LoweringAssociatedType { name: s0.name, ty: widen_ty_to_lowering_ty(s0.ty) }
                }),
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
                params: x.params.map((s0) -> {
                    LoweringFunctionParamTy {
                        name: s0.name,
                        ty: widen_ty_to_lowering_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
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
        let x: TyAssociatedTypeProjection => {
            LoweringTyAssociatedTypeProjection {
                base: widen_ty_to_lowering_ty(x.base),
                interface_: LoweringInterfaceConstraint {
                    name: x.interface_.name,
                    generics: x.interface_.generics.map(widen_ty_to_lowering_ty),
                    associated_types: x.interface_.associated_types.map((s0) -> {
                        LoweringAssociatedType { name: s0.name, ty: widen_ty_to_lowering_ty(s0.ty) }
                    }),
                },
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
                associated_types: x.associated_types.map((s0) -> {
                    RuntimeAssociatedType { name: s0.name, ty: narrow_ty_to_runtime_ty(s0.ty) }
                }),
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
                params: x.params.map((s0) -> {
                    RuntimeFunctionParamTy {
                        name: s0.name,
                        ty: narrow_ty_to_runtime_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
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
        let x: TyAssociatedTypeProjection => {
            RuntimeTyAssociatedTypeProjection {
                base: narrow_ty_to_runtime_ty(x.base),
                interface_: RuntimeInterfaceConstraint {
                    name: x.interface_.name,
                    generics: x.interface_.generics.map(narrow_ty_to_runtime_ty),
                    associated_types: x.interface_.associated_types.map((s0) -> {
                        RuntimeAssociatedType { name: s0.name, ty: narrow_ty_to_runtime_ty(s0.ty) }
                    }),
                },
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
                associated_types: x.associated_types.map((s0) -> {
                    CodegenAssociatedType { name: s0.name, ty: narrow_ty_to_codegen_ty(s0.ty) }
                }),
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
                params: x.params.map((s0) -> {
                    CodegenFunctionParamTy {
                        name: s0.name,
                        ty: narrow_ty_to_codegen_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
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
        TyAssociatedTypeProjection => {
            throw NarrowError { variant: "AssociatedTypeProjection", into: "CodegenTy" }
        },
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
                associated_types: x.associated_types.map((s0) -> {
                    RealizedAssociatedType { name: s0.name, ty: narrow_ty_to_realized_ty(s0.ty) }
                }),
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
                params: x.params.map((s0) -> {
                    RealizedFunctionParamTy {
                        name: s0.name,
                        ty: narrow_ty_to_realized_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
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
        TyAssociatedTypeProjection => {
            throw NarrowError { variant: "AssociatedTypeProjection", into: "RealizedTy" }
        },
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
            ConcreteTyClass { name: x.name, args: x.args.map(narrow_ty_to_runtime_ty) }
        },
        let x: TyList => ConcreteTyList { elem: narrow_ty_to_runtime_ty(x.elem) },
        let x: TyMap => {
            ConcreteTyMap {
                key: narrow_ty_to_runtime_ty(x.key),
                value: narrow_ty_to_runtime_ty(x.value),
            }
        },
        let x: TyFunction => {
            ConcreteTyFunction {
                params: x.params.map((s0) -> {
                    RuntimeFunctionParamTy {
                        name: s0.name,
                        ty: narrow_ty_to_runtime_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
                ret: narrow_ty_to_runtime_ty(x.ret),
                throws_: narrow_ty_to_runtime_ty(x.throws_),
            }
        },
        let x: TyFuture => {
            ConcreteTyFuture {
                value: narrow_ty_to_runtime_ty(x.value),
                error: narrow_ty_to_runtime_ty(x.error),
            }
        },
        let x: TyTuple => ConcreteTyTuple { items: x.items.map(narrow_ty_to_runtime_ty) },
        TyLiteral => throw NarrowError { variant: "Literal", into: "ConcreteTy" },
        TyInterface => throw NarrowError { variant: "Interface", into: "ConcreteTy" },
        TyEnumVariant => throw NarrowError { variant: "EnumVariant", into: "ConcreteTy" },
        TyUnion => throw NarrowError { variant: "Union", into: "ConcreteTy" },
        TyTypeAlias => throw NarrowError { variant: "TypeAlias", into: "ConcreteTy" },
        TyTypeVar => throw NarrowError { variant: "TypeVar", into: "ConcreteTy" },
        TyAssociatedTypeProjection => {
            throw NarrowError { variant: "AssociatedTypeProjection", into: "ConcreteTy" }
        },
        TyUnknown => throw NarrowError { variant: "Unknown", into: "ConcreteTy" },
        TyError => throw NarrowError { variant: "Error", into: "ConcreteTy" },
    }
}

// Fails if any variant, at any depth, is outside ConcreteRealizedTy.
function narrow_ty_to_concrete_realized_ty(t: Ty) -> ConcreteRealizedTy throws NarrowError {
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
            ConcreteRealizedTyClass { name: x.name, args: x.args.map(narrow_ty_to_realized_ty) }
        },
        let x: TyList => ConcreteRealizedTyList { elem: narrow_ty_to_realized_ty(x.elem) },
        let x: TyMap => {
            ConcreteRealizedTyMap {
                key: narrow_ty_to_realized_ty(x.key),
                value: narrow_ty_to_realized_ty(x.value),
            }
        },
        let x: TyFunction => {
            ConcreteRealizedTyFunction {
                params: x.params.map((s0) -> {
                    RealizedFunctionParamTy {
                        name: s0.name,
                        ty: narrow_ty_to_realized_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
                ret: narrow_ty_to_realized_ty(x.ret),
                throws_: narrow_ty_to_realized_ty(x.throws_),
            }
        },
        let x: TyFuture => {
            ConcreteRealizedTyFuture {
                value: narrow_ty_to_realized_ty(x.value),
                error: narrow_ty_to_realized_ty(x.error),
            }
        },
        let x: TyTuple => ConcreteRealizedTyTuple { items: x.items.map(narrow_ty_to_realized_ty) },
        TyLiteral => throw NarrowError { variant: "Literal", into: "ConcreteRealizedTy" },
        TyInterface => throw NarrowError { variant: "Interface", into: "ConcreteRealizedTy" },
        TyEnumVariant => throw NarrowError { variant: "EnumVariant", into: "ConcreteRealizedTy" },
        TyUnion => throw NarrowError { variant: "Union", into: "ConcreteRealizedTy" },
        TyTypeAlias => throw NarrowError { variant: "TypeAlias", into: "ConcreteRealizedTy" },
        TyTypeVar => throw NarrowError { variant: "TypeVar", into: "ConcreteRealizedTy" },
        TyAssociatedTypeProjection => {
            throw NarrowError { variant: "AssociatedTypeProjection", into: "ConcreteRealizedTy" }
        },
        TyUnknown => throw NarrowError { variant: "Unknown", into: "ConcreteRealizedTy" },
        TyError => throw NarrowError { variant: "Error", into: "ConcreteRealizedTy" },
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
                associated_types: x.associated_types.map((s0) -> {
                    AssociatedType { name: s0.name, ty: narrow_lowering_ty_to_ty(s0.ty) }
                }),
            }
        },
        let x: LoweringTyList => TyList { elem: narrow_lowering_ty_to_ty(x.elem) },
        let x: LoweringTyMap => {
            TyMap { key: narrow_lowering_ty_to_ty(x.key), value: narrow_lowering_ty_to_ty(x.value) }
        },
        let x: LoweringTyUnion => TyUnion { members: x.members.map(narrow_lowering_ty_to_ty) },
        let x: LoweringTyFunction => {
            TyFunction {
                params: x.params.map((s0) -> {
                    FunctionParamTy {
                        name: s0.name,
                        ty: narrow_lowering_ty_to_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
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
        let x: LoweringTyAssociatedTypeProjection => {
            TyAssociatedTypeProjection {
                base: narrow_lowering_ty_to_ty(x.base),
                interface_: InterfaceConstraint {
                    name: x.interface_.name,
                    generics: x.interface_.generics.map(narrow_lowering_ty_to_ty),
                    associated_types: x.interface_.associated_types.map((s0) -> {
                        AssociatedType { name: s0.name, ty: narrow_lowering_ty_to_ty(s0.ty) }
                    }),
                },
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
                associated_types: x.associated_types.map((s0) -> {
                    RuntimeAssociatedType {
                        name: s0.name,
                        ty: narrow_lowering_ty_to_runtime_ty(s0.ty),
                    }
                }),
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
                params: x.params.map((s0) -> {
                    RuntimeFunctionParamTy {
                        name: s0.name,
                        ty: narrow_lowering_ty_to_runtime_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
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
        let x: LoweringTyAssociatedTypeProjection => {
            RuntimeTyAssociatedTypeProjection {
                base: narrow_lowering_ty_to_runtime_ty(x.base),
                interface_: RuntimeInterfaceConstraint {
                    name: x.interface_.name,
                    generics: x.interface_.generics.map(narrow_lowering_ty_to_runtime_ty),
                    associated_types: x.interface_.associated_types.map((s0) -> {
                        RuntimeAssociatedType {
                            name: s0.name,
                            ty: narrow_lowering_ty_to_runtime_ty(s0.ty),
                        }
                    }),
                },
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
                associated_types: x.associated_types.map((s0) -> {
                    CodegenAssociatedType {
                        name: s0.name,
                        ty: narrow_lowering_ty_to_codegen_ty(s0.ty),
                    }
                }),
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
                params: x.params.map((s0) -> {
                    CodegenFunctionParamTy {
                        name: s0.name,
                        ty: narrow_lowering_ty_to_codegen_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
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
        LoweringTyAssociatedTypeProjection => {
            throw NarrowError { variant: "AssociatedTypeProjection", into: "CodegenTy" }
        },
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
                associated_types: x.associated_types.map((s0) -> {
                    RealizedAssociatedType {
                        name: s0.name,
                        ty: narrow_lowering_ty_to_realized_ty(s0.ty),
                    }
                }),
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
                params: x.params.map((s0) -> {
                    RealizedFunctionParamTy {
                        name: s0.name,
                        ty: narrow_lowering_ty_to_realized_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
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
        LoweringTyAssociatedTypeProjection => {
            throw NarrowError { variant: "AssociatedTypeProjection", into: "RealizedTy" }
        },
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
            ConcreteTyClass { name: x.name, args: x.args.map(narrow_lowering_ty_to_runtime_ty) }
        },
        let x: LoweringTyList => ConcreteTyList { elem: narrow_lowering_ty_to_runtime_ty(x.elem) },
        let x: LoweringTyMap => {
            ConcreteTyMap {
                key: narrow_lowering_ty_to_runtime_ty(x.key),
                value: narrow_lowering_ty_to_runtime_ty(x.value),
            }
        },
        let x: LoweringTyFunction => {
            ConcreteTyFunction {
                params: x.params.map((s0) -> {
                    RuntimeFunctionParamTy {
                        name: s0.name,
                        ty: narrow_lowering_ty_to_runtime_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
                ret: narrow_lowering_ty_to_runtime_ty(x.ret),
                throws_: narrow_lowering_ty_to_runtime_ty(x.throws_),
            }
        },
        let x: LoweringTyFuture => {
            ConcreteTyFuture {
                value: narrow_lowering_ty_to_runtime_ty(x.value),
                error: narrow_lowering_ty_to_runtime_ty(x.error),
            }
        },
        let x: LoweringTyTuple => {
            ConcreteTyTuple { items: x.items.map(narrow_lowering_ty_to_runtime_ty) }
        },
        TyLiteral => throw NarrowError { variant: "Literal", into: "ConcreteTy" },
        LoweringTyInterface => throw NarrowError { variant: "Interface", into: "ConcreteTy" },
        TyEnumVariant => throw NarrowError { variant: "EnumVariant", into: "ConcreteTy" },
        LoweringTyUnion => throw NarrowError { variant: "Union", into: "ConcreteTy" },
        TyTypeAlias => throw NarrowError { variant: "TypeAlias", into: "ConcreteTy" },
        TyTypeVar => throw NarrowError { variant: "TypeVar", into: "ConcreteTy" },
        LoweringTyAssociatedTypeProjection => {
            throw NarrowError { variant: "AssociatedTypeProjection", into: "ConcreteTy" }
        },
        TyUnknown => throw NarrowError { variant: "Unknown", into: "ConcreteTy" },
        TyError => throw NarrowError { variant: "Error", into: "ConcreteTy" },
        TyInfer => throw NarrowError { variant: "Infer", into: "ConcreteTy" },
    }
}

// Fails if any variant, at any depth, is outside ConcreteRealizedTy.
function narrow_lowering_ty_to_concrete_realized_ty(
    t: LoweringTy,
) -> ConcreteRealizedTy throws NarrowError {
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
            ConcreteRealizedTyClass {
                name: x.name,
                args: x.args.map(narrow_lowering_ty_to_realized_ty),
            }
        },
        let x: LoweringTyList => {
            ConcreteRealizedTyList { elem: narrow_lowering_ty_to_realized_ty(x.elem) }
        },
        let x: LoweringTyMap => {
            ConcreteRealizedTyMap {
                key: narrow_lowering_ty_to_realized_ty(x.key),
                value: narrow_lowering_ty_to_realized_ty(x.value),
            }
        },
        let x: LoweringTyFunction => {
            ConcreteRealizedTyFunction {
                params: x.params.map((s0) -> {
                    RealizedFunctionParamTy {
                        name: s0.name,
                        ty: narrow_lowering_ty_to_realized_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
                ret: narrow_lowering_ty_to_realized_ty(x.ret),
                throws_: narrow_lowering_ty_to_realized_ty(x.throws_),
            }
        },
        let x: LoweringTyFuture => {
            ConcreteRealizedTyFuture {
                value: narrow_lowering_ty_to_realized_ty(x.value),
                error: narrow_lowering_ty_to_realized_ty(x.error),
            }
        },
        let x: LoweringTyTuple => {
            ConcreteRealizedTyTuple { items: x.items.map(narrow_lowering_ty_to_realized_ty) }
        },
        TyLiteral => throw NarrowError { variant: "Literal", into: "ConcreteRealizedTy" },
        LoweringTyInterface => {
            throw NarrowError { variant: "Interface", into: "ConcreteRealizedTy" }
        },
        TyEnumVariant => throw NarrowError { variant: "EnumVariant", into: "ConcreteRealizedTy" },
        LoweringTyUnion => throw NarrowError { variant: "Union", into: "ConcreteRealizedTy" },
        TyTypeAlias => throw NarrowError { variant: "TypeAlias", into: "ConcreteRealizedTy" },
        TyTypeVar => throw NarrowError { variant: "TypeVar", into: "ConcreteRealizedTy" },
        LoweringTyAssociatedTypeProjection => {
            throw NarrowError { variant: "AssociatedTypeProjection", into: "ConcreteRealizedTy" }
        },
        TyUnknown => throw NarrowError { variant: "Unknown", into: "ConcreteRealizedTy" },
        TyError => throw NarrowError { variant: "Error", into: "ConcreteRealizedTy" },
        TyInfer => throw NarrowError { variant: "Infer", into: "ConcreteRealizedTy" },
    }
}

// Infallible: every RuntimeTy is a Ty.
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
                associated_types: x.associated_types.map((s0) -> {
                    AssociatedType { name: s0.name, ty: widen_runtime_ty_to_ty(s0.ty) }
                }),
            }
        },
        let x: RuntimeTyList => TyList { elem: widen_runtime_ty_to_ty(x.elem) },
        let x: RuntimeTyMap => {
            TyMap { key: widen_runtime_ty_to_ty(x.key), value: widen_runtime_ty_to_ty(x.value) }
        },
        let x: RuntimeTyUnion => TyUnion { members: x.members.map(widen_runtime_ty_to_ty) },
        let x: RuntimeTyFunction => {
            TyFunction {
                params: x.params.map((s0) -> {
                    FunctionParamTy {
                        name: s0.name,
                        ty: widen_runtime_ty_to_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
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
        let x: RuntimeTyAssociatedTypeProjection => {
            TyAssociatedTypeProjection {
                base: widen_runtime_ty_to_ty(x.base),
                interface_: InterfaceConstraint {
                    name: x.interface_.name,
                    generics: x.interface_.generics.map(widen_runtime_ty_to_ty),
                    associated_types: x.interface_.associated_types.map((s0) -> {
                        AssociatedType { name: s0.name, ty: widen_runtime_ty_to_ty(s0.ty) }
                    }),
                },
                member: x.member,
            }
        },
        let x: RuntimeTyTuple => TyTuple { items: x.items.map(widen_runtime_ty_to_ty) },
    }
}

// Infallible: every RuntimeTy is a LoweringTy.
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
                associated_types: x.associated_types.map((s0) -> {
                    LoweringAssociatedType {
                        name: s0.name,
                        ty: widen_runtime_ty_to_lowering_ty(s0.ty),
                    }
                }),
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
                params: x.params.map((s0) -> {
                    LoweringFunctionParamTy {
                        name: s0.name,
                        ty: widen_runtime_ty_to_lowering_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
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
        let x: RuntimeTyAssociatedTypeProjection => {
            LoweringTyAssociatedTypeProjection {
                base: widen_runtime_ty_to_lowering_ty(x.base),
                interface_: LoweringInterfaceConstraint {
                    name: x.interface_.name,
                    generics: x.interface_.generics.map(widen_runtime_ty_to_lowering_ty),
                    associated_types: x.interface_.associated_types.map((s0) -> {
                        LoweringAssociatedType {
                            name: s0.name,
                            ty: widen_runtime_ty_to_lowering_ty(s0.ty),
                        }
                    }),
                },
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
                associated_types: x.associated_types.map((s0) -> {
                    CodegenAssociatedType {
                        name: s0.name,
                        ty: narrow_runtime_ty_to_codegen_ty(s0.ty),
                    }
                }),
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
                params: x.params.map((s0) -> {
                    CodegenFunctionParamTy {
                        name: s0.name,
                        ty: narrow_runtime_ty_to_codegen_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
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
        RuntimeTyAssociatedTypeProjection => {
            throw NarrowError { variant: "AssociatedTypeProjection", into: "CodegenTy" }
        },
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
                associated_types: x.associated_types.map((s0) -> {
                    RealizedAssociatedType {
                        name: s0.name,
                        ty: narrow_runtime_ty_to_realized_ty(s0.ty),
                    }
                }),
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
                params: x.params.map((s0) -> {
                    RealizedFunctionParamTy {
                        name: s0.name,
                        ty: narrow_runtime_ty_to_realized_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
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
        RuntimeTyAssociatedTypeProjection => {
            throw NarrowError { variant: "AssociatedTypeProjection", into: "RealizedTy" }
        },
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
        let x: RuntimeTyClass => ConcreteTyClass { name: x.name, args: x.args },
        let x: RuntimeTyList => ConcreteTyList { elem: x.elem },
        let x: RuntimeTyMap => ConcreteTyMap { key: x.key, value: x.value },
        let x: RuntimeTyFunction => {
            ConcreteTyFunction { params: x.params, ret: x.ret, throws_: x.throws_ }
        },
        let x: RuntimeTyFuture => ConcreteTyFuture { value: x.value, error: x.error },
        let x: RuntimeTyTuple => ConcreteTyTuple { items: x.items },
        TyLiteral => throw NarrowError { variant: "Literal", into: "ConcreteTy" },
        RuntimeTyInterface => throw NarrowError { variant: "Interface", into: "ConcreteTy" },
        TyEnumVariant => throw NarrowError { variant: "EnumVariant", into: "ConcreteTy" },
        RuntimeTyUnion => throw NarrowError { variant: "Union", into: "ConcreteTy" },
        TyTypeAlias => throw NarrowError { variant: "TypeAlias", into: "ConcreteTy" },
        TyTypeVar => throw NarrowError { variant: "TypeVar", into: "ConcreteTy" },
        RuntimeTyAssociatedTypeProjection => {
            throw NarrowError { variant: "AssociatedTypeProjection", into: "ConcreteTy" }
        },
        TyUnknown => throw NarrowError { variant: "Unknown", into: "ConcreteTy" },
    }
}

// Fails if any variant, at any depth, is outside ConcreteRealizedTy.
function narrow_runtime_ty_to_concrete_realized_ty(
    t: RuntimeTy,
) -> ConcreteRealizedTy throws NarrowError {
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
            ConcreteRealizedTyClass {
                name: x.name,
                args: x.args.map(narrow_runtime_ty_to_realized_ty),
            }
        },
        let x: RuntimeTyList => {
            ConcreteRealizedTyList { elem: narrow_runtime_ty_to_realized_ty(x.elem) }
        },
        let x: RuntimeTyMap => {
            ConcreteRealizedTyMap {
                key: narrow_runtime_ty_to_realized_ty(x.key),
                value: narrow_runtime_ty_to_realized_ty(x.value),
            }
        },
        let x: RuntimeTyFunction => {
            ConcreteRealizedTyFunction {
                params: x.params.map((s0) -> {
                    RealizedFunctionParamTy {
                        name: s0.name,
                        ty: narrow_runtime_ty_to_realized_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
                ret: narrow_runtime_ty_to_realized_ty(x.ret),
                throws_: narrow_runtime_ty_to_realized_ty(x.throws_),
            }
        },
        let x: RuntimeTyFuture => {
            ConcreteRealizedTyFuture {
                value: narrow_runtime_ty_to_realized_ty(x.value),
                error: narrow_runtime_ty_to_realized_ty(x.error),
            }
        },
        let x: RuntimeTyTuple => {
            ConcreteRealizedTyTuple { items: x.items.map(narrow_runtime_ty_to_realized_ty) }
        },
        TyLiteral => throw NarrowError { variant: "Literal", into: "ConcreteRealizedTy" },
        RuntimeTyInterface => throw NarrowError { variant: "Interface", into: "ConcreteRealizedTy" },
        TyEnumVariant => throw NarrowError { variant: "EnumVariant", into: "ConcreteRealizedTy" },
        RuntimeTyUnion => throw NarrowError { variant: "Union", into: "ConcreteRealizedTy" },
        TyTypeAlias => throw NarrowError { variant: "TypeAlias", into: "ConcreteRealizedTy" },
        TyTypeVar => throw NarrowError { variant: "TypeVar", into: "ConcreteRealizedTy" },
        RuntimeTyAssociatedTypeProjection => {
            throw NarrowError { variant: "AssociatedTypeProjection", into: "ConcreteRealizedTy" }
        },
        TyUnknown => throw NarrowError { variant: "Unknown", into: "ConcreteRealizedTy" },
    }
}

// Infallible: every CodegenTy is a Ty.
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
                associated_types: x.associated_types.map((s0) -> {
                    AssociatedType { name: s0.name, ty: widen_codegen_ty_to_ty(s0.ty) }
                }),
            }
        },
        let x: CodegenTyList => TyList { elem: widen_codegen_ty_to_ty(x.elem) },
        let x: CodegenTyMap => {
            TyMap { key: widen_codegen_ty_to_ty(x.key), value: widen_codegen_ty_to_ty(x.value) }
        },
        let x: CodegenTyUnion => TyUnion { members: x.members.map(widen_codegen_ty_to_ty) },
        let x: CodegenTyFunction => {
            TyFunction {
                params: x.params.map((s0) -> {
                    FunctionParamTy {
                        name: s0.name,
                        ty: widen_codegen_ty_to_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
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

// Infallible: every CodegenTy is a LoweringTy.
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
                associated_types: x.associated_types.map((s0) -> {
                    LoweringAssociatedType {
                        name: s0.name,
                        ty: widen_codegen_ty_to_lowering_ty(s0.ty),
                    }
                }),
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
                params: x.params.map((s0) -> {
                    LoweringFunctionParamTy {
                        name: s0.name,
                        ty: widen_codegen_ty_to_lowering_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
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

// Infallible: every CodegenTy is a RuntimeTy.
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
                associated_types: x.associated_types.map((s0) -> {
                    RuntimeAssociatedType {
                        name: s0.name,
                        ty: widen_codegen_ty_to_runtime_ty(s0.ty),
                    }
                }),
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
                params: x.params.map((s0) -> {
                    RuntimeFunctionParamTy {
                        name: s0.name,
                        ty: widen_codegen_ty_to_runtime_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
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
                associated_types: x.associated_types.map((s0) -> {
                    RealizedAssociatedType {
                        name: s0.name,
                        ty: narrow_codegen_ty_to_realized_ty(s0.ty),
                    }
                }),
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
                params: x.params.map((s0) -> {
                    RealizedFunctionParamTy {
                        name: s0.name,
                        ty: narrow_codegen_ty_to_realized_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
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

// Fails if any variant, at any depth, is outside ConcreteRealizedTy.
function narrow_codegen_ty_to_concrete_realized_ty(
    t: CodegenTy,
) -> ConcreteRealizedTy throws NarrowError {
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
            ConcreteRealizedTyClass {
                name: x.name,
                args: x.args.map(narrow_codegen_ty_to_realized_ty),
            }
        },
        let x: CodegenTyList => {
            ConcreteRealizedTyList { elem: narrow_codegen_ty_to_realized_ty(x.elem) }
        },
        let x: CodegenTyMap => {
            ConcreteRealizedTyMap {
                key: narrow_codegen_ty_to_realized_ty(x.key),
                value: narrow_codegen_ty_to_realized_ty(x.value),
            }
        },
        let x: CodegenTyFunction => {
            ConcreteRealizedTyFunction {
                params: x.params.map((s0) -> {
                    RealizedFunctionParamTy {
                        name: s0.name,
                        ty: narrow_codegen_ty_to_realized_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
                ret: narrow_codegen_ty_to_realized_ty(x.ret),
                throws_: narrow_codegen_ty_to_realized_ty(x.throws_),
            }
        },
        let x: CodegenTyFuture => {
            ConcreteRealizedTyFuture {
                value: narrow_codegen_ty_to_realized_ty(x.value),
                error: narrow_codegen_ty_to_realized_ty(x.error),
            }
        },
        let x: CodegenTyTuple => {
            ConcreteRealizedTyTuple { items: x.items.map(narrow_codegen_ty_to_realized_ty) }
        },
        TyLiteral => throw NarrowError { variant: "Literal", into: "ConcreteRealizedTy" },
        CodegenTyInterface => throw NarrowError { variant: "Interface", into: "ConcreteRealizedTy" },
        TyEnumVariant => throw NarrowError { variant: "EnumVariant", into: "ConcreteRealizedTy" },
        CodegenTyUnion => throw NarrowError { variant: "Union", into: "ConcreteRealizedTy" },
        TyTypeAlias => throw NarrowError { variant: "TypeAlias", into: "ConcreteRealizedTy" },
        TyTypeVar => throw NarrowError { variant: "TypeVar", into: "ConcreteRealizedTy" },
        TyUnknown => throw NarrowError { variant: "Unknown", into: "ConcreteRealizedTy" },
    }
}

// Infallible: every RealizedTy is a Ty.
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
                associated_types: x.associated_types.map((s0) -> {
                    AssociatedType { name: s0.name, ty: widen_realized_ty_to_ty(s0.ty) }
                }),
            }
        },
        let x: RealizedTyList => TyList { elem: widen_realized_ty_to_ty(x.elem) },
        let x: RealizedTyMap => {
            TyMap { key: widen_realized_ty_to_ty(x.key), value: widen_realized_ty_to_ty(x.value) }
        },
        let x: RealizedTyUnion => TyUnion { members: x.members.map(widen_realized_ty_to_ty) },
        let x: RealizedTyFunction => {
            TyFunction {
                params: x.params.map((s0) -> {
                    FunctionParamTy {
                        name: s0.name,
                        ty: widen_realized_ty_to_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
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

// Infallible: every RealizedTy is a LoweringTy.
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
                associated_types: x.associated_types.map((s0) -> {
                    LoweringAssociatedType {
                        name: s0.name,
                        ty: widen_realized_ty_to_lowering_ty(s0.ty),
                    }
                }),
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
                params: x.params.map((s0) -> {
                    LoweringFunctionParamTy {
                        name: s0.name,
                        ty: widen_realized_ty_to_lowering_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
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

// Infallible: every RealizedTy is a RuntimeTy.
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
                associated_types: x.associated_types.map((s0) -> {
                    RuntimeAssociatedType {
                        name: s0.name,
                        ty: widen_realized_ty_to_runtime_ty(s0.ty),
                    }
                }),
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
                params: x.params.map((s0) -> {
                    RuntimeFunctionParamTy {
                        name: s0.name,
                        ty: widen_realized_ty_to_runtime_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
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

// Infallible: every RealizedTy is a CodegenTy.
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
                associated_types: x.associated_types.map((s0) -> {
                    CodegenAssociatedType {
                        name: s0.name,
                        ty: widen_realized_ty_to_codegen_ty(s0.ty),
                    }
                }),
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
                params: x.params.map((s0) -> {
                    CodegenFunctionParamTy {
                        name: s0.name,
                        ty: widen_realized_ty_to_codegen_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
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

// Fails if any variant, at any depth, is outside ConcreteRealizedTy.
function narrow_realized_ty_to_concrete_realized_ty(
    t: RealizedTy,
) -> ConcreteRealizedTy throws NarrowError {
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
        let x: RealizedTyClass => ConcreteRealizedTyClass { name: x.name, args: x.args },
        let x: RealizedTyList => ConcreteRealizedTyList { elem: x.elem },
        let x: RealizedTyMap => ConcreteRealizedTyMap { key: x.key, value: x.value },
        let x: RealizedTyFunction => {
            ConcreteRealizedTyFunction { params: x.params, ret: x.ret, throws_: x.throws_ }
        },
        let x: RealizedTyFuture => ConcreteRealizedTyFuture { value: x.value, error: x.error },
        let x: RealizedTyTuple => ConcreteRealizedTyTuple { items: x.items },
        TyLiteral => throw NarrowError { variant: "Literal", into: "ConcreteRealizedTy" },
        RealizedTyInterface => {
            throw NarrowError { variant: "Interface", into: "ConcreteRealizedTy" }
        },
        TyEnumVariant => throw NarrowError { variant: "EnumVariant", into: "ConcreteRealizedTy" },
        RealizedTyUnion => throw NarrowError { variant: "Union", into: "ConcreteRealizedTy" },
        TyTypeAlias => throw NarrowError { variant: "TypeAlias", into: "ConcreteRealizedTy" },
        TyUnknown => throw NarrowError { variant: "Unknown", into: "ConcreteRealizedTy" },
    }
}

// Infallible: every RealizedTy is a TyTemplate.
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
                associated_types: x.associated_types.map((s0) -> {
                    TyTemplateAssociatedType {
                        name: s0.name,
                        ty: widen_realized_ty_to_ty_template(s0.ty),
                    }
                }),
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
                params: x.params.map((s0) -> {
                    TyTemplateFunctionParamTy {
                        name: s0.name,
                        ty: widen_realized_ty_to_ty_template(s0.ty),
                        mode: s0.mode,
                    }
                }),
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

// Infallible: every ConcreteTy is a Ty.
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
        let x: ConcreteTyClass => TyClass { name: x.name, args: x.args.map(widen_runtime_ty_to_ty) },
        let x: ConcreteTyList => TyList { elem: widen_runtime_ty_to_ty(x.elem) },
        let x: ConcreteTyMap => {
            TyMap { key: widen_runtime_ty_to_ty(x.key), value: widen_runtime_ty_to_ty(x.value) }
        },
        let x: ConcreteTyFunction => {
            TyFunction {
                params: x.params.map((s0) -> {
                    FunctionParamTy {
                        name: s0.name,
                        ty: widen_runtime_ty_to_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
                ret: widen_runtime_ty_to_ty(x.ret),
                throws_: widen_runtime_ty_to_ty(x.throws_),
            }
        },
        let x: ConcreteTyFuture => {
            TyFuture {
                value: widen_runtime_ty_to_ty(x.value),
                error: widen_runtime_ty_to_ty(x.error),
            }
        },
        let x: ConcreteTyTuple => TyTuple { items: x.items.map(widen_runtime_ty_to_ty) },
    }
}

// Infallible: every ConcreteTy is a LoweringTy.
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
            LoweringTyClass { name: x.name, args: x.args.map(widen_runtime_ty_to_lowering_ty) }
        },
        let x: ConcreteTyList => LoweringTyList { elem: widen_runtime_ty_to_lowering_ty(x.elem) },
        let x: ConcreteTyMap => {
            LoweringTyMap {
                key: widen_runtime_ty_to_lowering_ty(x.key),
                value: widen_runtime_ty_to_lowering_ty(x.value),
            }
        },
        let x: ConcreteTyFunction => {
            LoweringTyFunction {
                params: x.params.map((s0) -> {
                    LoweringFunctionParamTy {
                        name: s0.name,
                        ty: widen_runtime_ty_to_lowering_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
                ret: widen_runtime_ty_to_lowering_ty(x.ret),
                throws_: widen_runtime_ty_to_lowering_ty(x.throws_),
            }
        },
        let x: ConcreteTyFuture => {
            LoweringTyFuture {
                value: widen_runtime_ty_to_lowering_ty(x.value),
                error: widen_runtime_ty_to_lowering_ty(x.error),
            }
        },
        let x: ConcreteTyTuple => {
            LoweringTyTuple { items: x.items.map(widen_runtime_ty_to_lowering_ty) }
        },
    }
}

// Infallible: every ConcreteTy is a RuntimeTy.
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
        let x: ConcreteTyClass => RuntimeTyClass { name: x.name, args: x.args },
        let x: ConcreteTyList => RuntimeTyList { elem: x.elem },
        let x: ConcreteTyMap => RuntimeTyMap { key: x.key, value: x.value },
        let x: ConcreteTyFunction => {
            RuntimeTyFunction { params: x.params, ret: x.ret, throws_: x.throws_ }
        },
        let x: ConcreteTyFuture => RuntimeTyFuture { value: x.value, error: x.error },
        let x: ConcreteTyTuple => RuntimeTyTuple { items: x.items },
    }
}

// Fails if any variant, at any depth, is outside ConcreteRealizedTy.
function narrow_concrete_ty_to_concrete_realized_ty(
    t: ConcreteTy,
) -> ConcreteRealizedTy throws NarrowError {
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
            ConcreteRealizedTyClass {
                name: x.name,
                args: x.args.map(narrow_runtime_ty_to_realized_ty),
            }
        },
        let x: ConcreteTyList => {
            ConcreteRealizedTyList { elem: narrow_runtime_ty_to_realized_ty(x.elem) }
        },
        let x: ConcreteTyMap => {
            ConcreteRealizedTyMap {
                key: narrow_runtime_ty_to_realized_ty(x.key),
                value: narrow_runtime_ty_to_realized_ty(x.value),
            }
        },
        let x: ConcreteTyFunction => {
            ConcreteRealizedTyFunction {
                params: x.params.map((s0) -> {
                    RealizedFunctionParamTy {
                        name: s0.name,
                        ty: narrow_runtime_ty_to_realized_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
                ret: narrow_runtime_ty_to_realized_ty(x.ret),
                throws_: narrow_runtime_ty_to_realized_ty(x.throws_),
            }
        },
        let x: ConcreteTyFuture => {
            ConcreteRealizedTyFuture {
                value: narrow_runtime_ty_to_realized_ty(x.value),
                error: narrow_runtime_ty_to_realized_ty(x.error),
            }
        },
        let x: ConcreteTyTuple => {
            ConcreteRealizedTyTuple { items: x.items.map(narrow_runtime_ty_to_realized_ty) }
        },
    }
}

// Infallible: every ConcreteRealizedTy is a Ty.
function widen_concrete_realized_ty_to_ty(t: ConcreteRealizedTy) -> Ty throws never {
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
        let x: ConcreteRealizedTyClass => {
            TyClass { name: x.name, args: x.args.map(widen_realized_ty_to_ty) }
        },
        let x: ConcreteRealizedTyList => TyList { elem: widen_realized_ty_to_ty(x.elem) },
        let x: ConcreteRealizedTyMap => {
            TyMap { key: widen_realized_ty_to_ty(x.key), value: widen_realized_ty_to_ty(x.value) }
        },
        let x: ConcreteRealizedTyFunction => {
            TyFunction {
                params: x.params.map((s0) -> {
                    FunctionParamTy {
                        name: s0.name,
                        ty: widen_realized_ty_to_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
                ret: widen_realized_ty_to_ty(x.ret),
                throws_: widen_realized_ty_to_ty(x.throws_),
            }
        },
        let x: ConcreteRealizedTyFuture => {
            TyFuture {
                value: widen_realized_ty_to_ty(x.value),
                error: widen_realized_ty_to_ty(x.error),
            }
        },
        let x: ConcreteRealizedTyTuple => TyTuple { items: x.items.map(widen_realized_ty_to_ty) },
    }
}

// Infallible: every ConcreteRealizedTy is a LoweringTy.
function widen_concrete_realized_ty_to_lowering_ty(
    t: ConcreteRealizedTy,
) -> LoweringTy throws never {
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
        let x: ConcreteRealizedTyClass => {
            LoweringTyClass { name: x.name, args: x.args.map(widen_realized_ty_to_lowering_ty) }
        },
        let x: ConcreteRealizedTyList => {
            LoweringTyList { elem: widen_realized_ty_to_lowering_ty(x.elem) }
        },
        let x: ConcreteRealizedTyMap => {
            LoweringTyMap {
                key: widen_realized_ty_to_lowering_ty(x.key),
                value: widen_realized_ty_to_lowering_ty(x.value),
            }
        },
        let x: ConcreteRealizedTyFunction => {
            LoweringTyFunction {
                params: x.params.map((s0) -> {
                    LoweringFunctionParamTy {
                        name: s0.name,
                        ty: widen_realized_ty_to_lowering_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
                ret: widen_realized_ty_to_lowering_ty(x.ret),
                throws_: widen_realized_ty_to_lowering_ty(x.throws_),
            }
        },
        let x: ConcreteRealizedTyFuture => {
            LoweringTyFuture {
                value: widen_realized_ty_to_lowering_ty(x.value),
                error: widen_realized_ty_to_lowering_ty(x.error),
            }
        },
        let x: ConcreteRealizedTyTuple => {
            LoweringTyTuple { items: x.items.map(widen_realized_ty_to_lowering_ty) }
        },
    }
}

// Infallible: every ConcreteRealizedTy is a RuntimeTy.
function widen_concrete_realized_ty_to_runtime_ty(t: ConcreteRealizedTy) -> RuntimeTy throws never {
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
        let x: ConcreteRealizedTyClass => {
            RuntimeTyClass { name: x.name, args: x.args.map(widen_realized_ty_to_runtime_ty) }
        },
        let x: ConcreteRealizedTyList => {
            RuntimeTyList { elem: widen_realized_ty_to_runtime_ty(x.elem) }
        },
        let x: ConcreteRealizedTyMap => {
            RuntimeTyMap {
                key: widen_realized_ty_to_runtime_ty(x.key),
                value: widen_realized_ty_to_runtime_ty(x.value),
            }
        },
        let x: ConcreteRealizedTyFunction => {
            RuntimeTyFunction {
                params: x.params.map((s0) -> {
                    RuntimeFunctionParamTy {
                        name: s0.name,
                        ty: widen_realized_ty_to_runtime_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
                ret: widen_realized_ty_to_runtime_ty(x.ret),
                throws_: widen_realized_ty_to_runtime_ty(x.throws_),
            }
        },
        let x: ConcreteRealizedTyFuture => {
            RuntimeTyFuture {
                value: widen_realized_ty_to_runtime_ty(x.value),
                error: widen_realized_ty_to_runtime_ty(x.error),
            }
        },
        let x: ConcreteRealizedTyTuple => {
            RuntimeTyTuple { items: x.items.map(widen_realized_ty_to_runtime_ty) }
        },
    }
}

// Infallible: every ConcreteRealizedTy is a CodegenTy.
function widen_concrete_realized_ty_to_codegen_ty(t: ConcreteRealizedTy) -> CodegenTy throws never {
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
        let x: ConcreteRealizedTyClass => {
            CodegenTyClass { name: x.name, args: x.args.map(widen_realized_ty_to_codegen_ty) }
        },
        let x: ConcreteRealizedTyList => {
            CodegenTyList { elem: widen_realized_ty_to_codegen_ty(x.elem) }
        },
        let x: ConcreteRealizedTyMap => {
            CodegenTyMap {
                key: widen_realized_ty_to_codegen_ty(x.key),
                value: widen_realized_ty_to_codegen_ty(x.value),
            }
        },
        let x: ConcreteRealizedTyFunction => {
            CodegenTyFunction {
                params: x.params.map((s0) -> {
                    CodegenFunctionParamTy {
                        name: s0.name,
                        ty: widen_realized_ty_to_codegen_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
                ret: widen_realized_ty_to_codegen_ty(x.ret),
                throws_: widen_realized_ty_to_codegen_ty(x.throws_),
            }
        },
        let x: ConcreteRealizedTyFuture => {
            CodegenTyFuture {
                value: widen_realized_ty_to_codegen_ty(x.value),
                error: widen_realized_ty_to_codegen_ty(x.error),
            }
        },
        let x: ConcreteRealizedTyTuple => {
            CodegenTyTuple { items: x.items.map(widen_realized_ty_to_codegen_ty) }
        },
    }
}

// Infallible: every ConcreteRealizedTy is a RealizedTy.
function widen_concrete_realized_ty_to_realized_ty(
    t: ConcreteRealizedTy,
) -> RealizedTy throws never {
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
        let x: ConcreteRealizedTyClass => RealizedTyClass { name: x.name, args: x.args },
        let x: ConcreteRealizedTyList => RealizedTyList { elem: x.elem },
        let x: ConcreteRealizedTyMap => RealizedTyMap { key: x.key, value: x.value },
        let x: ConcreteRealizedTyFunction => {
            RealizedTyFunction { params: x.params, ret: x.ret, throws_: x.throws_ }
        },
        let x: ConcreteRealizedTyFuture => RealizedTyFuture { value: x.value, error: x.error },
        let x: ConcreteRealizedTyTuple => RealizedTyTuple { items: x.items },
    }
}

// Infallible: every ConcreteRealizedTy is a ConcreteTy.
function widen_concrete_realized_ty_to_concrete_ty(
    t: ConcreteRealizedTy,
) -> ConcreteTy throws never {
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
        let x: ConcreteRealizedTyClass => {
            ConcreteTyClass { name: x.name, args: x.args.map(widen_realized_ty_to_runtime_ty) }
        },
        let x: ConcreteRealizedTyList => {
            ConcreteTyList { elem: widen_realized_ty_to_runtime_ty(x.elem) }
        },
        let x: ConcreteRealizedTyMap => {
            ConcreteTyMap {
                key: widen_realized_ty_to_runtime_ty(x.key),
                value: widen_realized_ty_to_runtime_ty(x.value),
            }
        },
        let x: ConcreteRealizedTyFunction => {
            ConcreteTyFunction {
                params: x.params.map((s0) -> {
                    RuntimeFunctionParamTy {
                        name: s0.name,
                        ty: widen_realized_ty_to_runtime_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
                ret: widen_realized_ty_to_runtime_ty(x.ret),
                throws_: widen_realized_ty_to_runtime_ty(x.throws_),
            }
        },
        let x: ConcreteRealizedTyFuture => {
            ConcreteTyFuture {
                value: widen_realized_ty_to_runtime_ty(x.value),
                error: widen_realized_ty_to_runtime_ty(x.error),
            }
        },
        let x: ConcreteRealizedTyTuple => {
            ConcreteTyTuple { items: x.items.map(widen_realized_ty_to_runtime_ty) }
        },
    }
}

// Infallible: every ConcreteRealizedTy is a TyTemplate.
function widen_concrete_realized_ty_to_ty_template(
    t: ConcreteRealizedTy,
) -> TyTemplate throws never {
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
        let x: ConcreteRealizedTyClass => {
            TyTemplateClass { name: x.name, args: x.args.map(widen_realized_ty_to_ty_template) }
        },
        let x: ConcreteRealizedTyList => {
            TyTemplateList { elem: widen_realized_ty_to_ty_template(x.elem) }
        },
        let x: ConcreteRealizedTyMap => {
            TyTemplateMap {
                key: widen_realized_ty_to_ty_template(x.key),
                value: widen_realized_ty_to_ty_template(x.value),
            }
        },
        let x: ConcreteRealizedTyFunction => {
            TyTemplateFunction {
                params: x.params.map((s0) -> {
                    TyTemplateFunctionParamTy {
                        name: s0.name,
                        ty: widen_realized_ty_to_ty_template(s0.ty),
                        mode: s0.mode,
                    }
                }),
                ret: widen_realized_ty_to_ty_template(x.ret),
                throws_: widen_realized_ty_to_ty_template(x.throws_),
            }
        },
        let x: ConcreteRealizedTyFuture => {
            TyTemplateFuture {
                value: widen_realized_ty_to_ty_template(x.value),
                error: widen_realized_ty_to_ty_template(x.error),
            }
        },
        let x: ConcreteRealizedTyTuple => {
            TyTemplateTuple { items: x.items.map(widen_realized_ty_to_ty_template) }
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
                associated_types: x.associated_types.map((s0) -> {
                    RealizedAssociatedType {
                        name: s0.name,
                        ty: narrow_ty_template_to_realized_ty(s0.ty),
                    }
                }),
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
                params: x.params.map((s0) -> {
                    RealizedFunctionParamTy {
                        name: s0.name,
                        ty: narrow_ty_template_to_realized_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
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
        TyTemplateAssociatedTypeProjection => {
            throw NarrowError { variant: "AssociatedTypeProjection", into: "RealizedTy" }
        },
        TyTypeArgRef => throw NarrowError { variant: "TypeArgRef", into: "RealizedTy" },
    }
}

// Fails if any variant, at any depth, is outside ConcreteRealizedTy.
function narrow_ty_template_to_concrete_realized_ty(
    t: TyTemplate,
) -> ConcreteRealizedTy throws NarrowError {
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
            ConcreteRealizedTyClass {
                name: x.name,
                args: x.args.map(narrow_ty_template_to_realized_ty),
            }
        },
        let x: TyTemplateList => {
            ConcreteRealizedTyList { elem: narrow_ty_template_to_realized_ty(x.elem) }
        },
        let x: TyTemplateMap => {
            ConcreteRealizedTyMap {
                key: narrow_ty_template_to_realized_ty(x.key),
                value: narrow_ty_template_to_realized_ty(x.value),
            }
        },
        let x: TyTemplateFunction => {
            ConcreteRealizedTyFunction {
                params: x.params.map((s0) -> {
                    RealizedFunctionParamTy {
                        name: s0.name,
                        ty: narrow_ty_template_to_realized_ty(s0.ty),
                        mode: s0.mode,
                    }
                }),
                ret: narrow_ty_template_to_realized_ty(x.ret),
                throws_: narrow_ty_template_to_realized_ty(x.throws_),
            }
        },
        let x: TyTemplateFuture => {
            ConcreteRealizedTyFuture {
                value: narrow_ty_template_to_realized_ty(x.value),
                error: narrow_ty_template_to_realized_ty(x.error),
            }
        },
        let x: TyTemplateTuple => {
            ConcreteRealizedTyTuple { items: x.items.map(narrow_ty_template_to_realized_ty) }
        },
        TyLiteral => throw NarrowError { variant: "Literal", into: "ConcreteRealizedTy" },
        TyTemplateInterface => {
            throw NarrowError { variant: "Interface", into: "ConcreteRealizedTy" }
        },
        TyEnumVariant => throw NarrowError { variant: "EnumVariant", into: "ConcreteRealizedTy" },
        TyTemplateUnion => throw NarrowError { variant: "Union", into: "ConcreteRealizedTy" },
        TyTypeAlias => throw NarrowError { variant: "TypeAlias", into: "ConcreteRealizedTy" },
        TyTemplateAssociatedTypeProjection => {
            throw NarrowError { variant: "AssociatedTypeProjection", into: "ConcreteRealizedTy" }
        },
        TyUnknown => throw NarrowError { variant: "Unknown", into: "ConcreteRealizedTy" },
        TyTypeArgRef => throw NarrowError { variant: "TypeArgRef", into: "ConcreteRealizedTy" },
    }
}

// == Child walkers =========================================================

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
            TyInterface {
                name: x.name,
                args: x.args.map(f),
                associated_types: x.associated_types.map((s0) -> {
                    AssociatedType { name: s0.name, ty: f(s0.ty) }
                }),
            }
        },
        let x: TyList => TyList { elem: f(x.elem) },
        let x: TyMap => TyMap { key: f(x.key), value: f(x.value) },
        let x: TyUnion => TyUnion { members: x.members.map(f) },
        let x: TyFunction => {
            TyFunction {
                params: x.params.map((s0) -> {
                    FunctionParamTy { name: s0.name, ty: f(s0.ty), mode: s0.mode }
                }),
                ret: f(x.ret),
                throws_: f(x.throws_),
            }
        },
        let x: TyFuture => TyFuture { value: f(x.value), error: f(x.error) },
        let x: TyAssociatedTypeProjection => {
            TyAssociatedTypeProjection {
                base: f(x.base),
                interface_: InterfaceConstraint {
                    name: x.interface_.name,
                    generics: x.interface_.generics.map(f),
                    associated_types: x.interface_.associated_types.map((s0) -> {
                        AssociatedType { name: s0.name, ty: f(s0.ty) }
                    }),
                },
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
        let x: TyInterface => {
            x.args.concat(
                x.associated_types.flat_map((s0) -> {
                    [s0.ty]
                }),
            )
        },
        let x: TyList => [x.elem],
        let x: TyMap => [x.key].concat([x.value]),
        let x: TyUnion => x.members,
        let x: TyFunction => {
            x.params
                .flat_map((s0) -> {
                    [s0.ty]
                })
                .concat([x.ret])
                .concat([x.throws_])
        },
        let x: TyFuture => [x.value].concat([x.error]),
        let x: TyAssociatedTypeProjection => {
            [x.base].concat(x.interface_.generics).concat(
                x.interface_.associated_types.flat_map((s0) -> {
                    [s0.ty]
                }),
            )
        },
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
            LoweringTyInterface {
                name: x.name,
                args: x.args.map(f),
                associated_types: x.associated_types.map((s0) -> {
                    LoweringAssociatedType { name: s0.name, ty: f(s0.ty) }
                }),
            }
        },
        let x: LoweringTyList => LoweringTyList { elem: f(x.elem) },
        let x: LoweringTyMap => LoweringTyMap { key: f(x.key), value: f(x.value) },
        let x: LoweringTyUnion => LoweringTyUnion { members: x.members.map(f) },
        let x: LoweringTyFunction => {
            LoweringTyFunction {
                params: x.params.map((s0) -> {
                    LoweringFunctionParamTy { name: s0.name, ty: f(s0.ty), mode: s0.mode }
                }),
                ret: f(x.ret),
                throws_: f(x.throws_),
            }
        },
        let x: LoweringTyFuture => LoweringTyFuture { value: f(x.value), error: f(x.error) },
        let x: LoweringTyAssociatedTypeProjection => {
            LoweringTyAssociatedTypeProjection {
                base: f(x.base),
                interface_: LoweringInterfaceConstraint {
                    name: x.interface_.name,
                    generics: x.interface_.generics.map(f),
                    associated_types: x.interface_.associated_types.map((s0) -> {
                        LoweringAssociatedType { name: s0.name, ty: f(s0.ty) }
                    }),
                },
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
        let x: LoweringTyInterface => {
            x.args.concat(
                x.associated_types.flat_map((s0) -> {
                    [s0.ty]
                }),
            )
        },
        let x: LoweringTyList => [x.elem],
        let x: LoweringTyMap => [x.key].concat([x.value]),
        let x: LoweringTyUnion => x.members,
        let x: LoweringTyFunction => {
            x.params
                .flat_map((s0) -> {
                    [s0.ty]
                })
                .concat([x.ret])
                .concat([x.throws_])
        },
        let x: LoweringTyFuture => [x.value].concat([x.error]),
        let x: LoweringTyAssociatedTypeProjection => {
            [x.base].concat(x.interface_.generics).concat(
                x.interface_.associated_types.flat_map((s0) -> {
                    [s0.ty]
                }),
            )
        },
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
            RuntimeTyInterface {
                name: x.name,
                args: x.args.map(f),
                associated_types: x.associated_types.map((s0) -> {
                    RuntimeAssociatedType { name: s0.name, ty: f(s0.ty) }
                }),
            }
        },
        let x: RuntimeTyList => RuntimeTyList { elem: f(x.elem) },
        let x: RuntimeTyMap => RuntimeTyMap { key: f(x.key), value: f(x.value) },
        let x: RuntimeTyUnion => RuntimeTyUnion { members: x.members.map(f) },
        let x: RuntimeTyFunction => {
            RuntimeTyFunction {
                params: x.params.map((s0) -> {
                    RuntimeFunctionParamTy { name: s0.name, ty: f(s0.ty), mode: s0.mode }
                }),
                ret: f(x.ret),
                throws_: f(x.throws_),
            }
        },
        let x: RuntimeTyFuture => RuntimeTyFuture { value: f(x.value), error: f(x.error) },
        let x: RuntimeTyAssociatedTypeProjection => {
            RuntimeTyAssociatedTypeProjection {
                base: f(x.base),
                interface_: RuntimeInterfaceConstraint {
                    name: x.interface_.name,
                    generics: x.interface_.generics.map(f),
                    associated_types: x.interface_.associated_types.map((s0) -> {
                        RuntimeAssociatedType { name: s0.name, ty: f(s0.ty) }
                    }),
                },
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
        let x: RuntimeTyInterface => {
            x.args.concat(
                x.associated_types.flat_map((s0) -> {
                    [s0.ty]
                }),
            )
        },
        let x: RuntimeTyList => [x.elem],
        let x: RuntimeTyMap => [x.key].concat([x.value]),
        let x: RuntimeTyUnion => x.members,
        let x: RuntimeTyFunction => {
            x.params
                .flat_map((s0) -> {
                    [s0.ty]
                })
                .concat([x.ret])
                .concat([x.throws_])
        },
        let x: RuntimeTyFuture => [x.value].concat([x.error]),
        let x: RuntimeTyAssociatedTypeProjection => {
            [x.base].concat(x.interface_.generics).concat(
                x.interface_.associated_types.flat_map((s0) -> {
                    [s0.ty]
                }),
            )
        },
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
            CodegenTyInterface {
                name: x.name,
                args: x.args.map(f),
                associated_types: x.associated_types.map((s0) -> {
                    CodegenAssociatedType { name: s0.name, ty: f(s0.ty) }
                }),
            }
        },
        let x: CodegenTyList => CodegenTyList { elem: f(x.elem) },
        let x: CodegenTyMap => CodegenTyMap { key: f(x.key), value: f(x.value) },
        let x: CodegenTyUnion => CodegenTyUnion { members: x.members.map(f) },
        let x: CodegenTyFunction => {
            CodegenTyFunction {
                params: x.params.map((s0) -> {
                    CodegenFunctionParamTy { name: s0.name, ty: f(s0.ty), mode: s0.mode }
                }),
                ret: f(x.ret),
                throws_: f(x.throws_),
            }
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
        let x: CodegenTyInterface => {
            x.args.concat(
                x.associated_types.flat_map((s0) -> {
                    [s0.ty]
                }),
            )
        },
        let x: CodegenTyList => [x.elem],
        let x: CodegenTyMap => [x.key].concat([x.value]),
        let x: CodegenTyUnion => x.members,
        let x: CodegenTyFunction => {
            x.params
                .flat_map((s0) -> {
                    [s0.ty]
                })
                .concat([x.ret])
                .concat([x.throws_])
        },
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
            RealizedTyInterface {
                name: x.name,
                args: x.args.map(f),
                associated_types: x.associated_types.map((s0) -> {
                    RealizedAssociatedType { name: s0.name, ty: f(s0.ty) }
                }),
            }
        },
        let x: RealizedTyList => RealizedTyList { elem: f(x.elem) },
        let x: RealizedTyMap => RealizedTyMap { key: f(x.key), value: f(x.value) },
        let x: RealizedTyUnion => RealizedTyUnion { members: x.members.map(f) },
        let x: RealizedTyFunction => {
            RealizedTyFunction {
                params: x.params.map((s0) -> {
                    RealizedFunctionParamTy { name: s0.name, ty: f(s0.ty), mode: s0.mode }
                }),
                ret: f(x.ret),
                throws_: f(x.throws_),
            }
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
        let x: RealizedTyInterface => {
            x.args.concat(
                x.associated_types.flat_map((s0) -> {
                    [s0.ty]
                }),
            )
        },
        let x: RealizedTyList => [x.elem],
        let x: RealizedTyMap => [x.key].concat([x.value]),
        let x: RealizedTyUnion => x.members,
        let x: RealizedTyFunction => {
            x.params
                .flat_map((s0) -> {
                    [s0.ty]
                })
                .concat([x.ret])
                .concat([x.throws_])
        },
        let x: RealizedTyFuture => [x.value].concat([x.error]),
        let x: RealizedTyTuple => x.items,
    }
}

// Rebuilds `t` with `f` applied to each direct child; leaves are returned as is.
function map_children_concrete_ty(t: ConcreteTy, f: (RuntimeTy) -> RuntimeTy) -> ConcreteTy {
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
            ConcreteTyFunction {
                params: x.params.map((s0) -> {
                    RuntimeFunctionParamTy { name: s0.name, ty: f(s0.ty), mode: s0.mode }
                }),
                ret: f(x.ret),
                throws_: f(x.throws_),
            }
        },
        let x: ConcreteTyFuture => ConcreteTyFuture { value: f(x.value), error: f(x.error) },
        let x: ConcreteTyTuple => ConcreteTyTuple { items: x.items.map(f) },
    }
}

// The direct children of `t`, in field order.
function children_concrete_ty(t: ConcreteTy) -> RuntimeTy[] {
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
        let x: ConcreteTyFunction => {
            x.params
                .flat_map((s0) -> {
                    [s0.ty]
                })
                .concat([x.ret])
                .concat([x.throws_])
        },
        let x: ConcreteTyFuture => [x.value].concat([x.error]),
        let x: ConcreteTyTuple => x.items,
    }
}

// Rebuilds `t` with `f` applied to each direct child; leaves are returned as is.
function map_children_concrete_realized_ty(
    t: ConcreteRealizedTy,
    f: (RealizedTy) -> RealizedTy,
) -> ConcreteRealizedTy {
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
        let x: ConcreteRealizedTyClass => {
            ConcreteRealizedTyClass { name: x.name, args: x.args.map(f) }
        },
        let x: ConcreteRealizedTyList => ConcreteRealizedTyList { elem: f(x.elem) },
        let x: ConcreteRealizedTyMap => ConcreteRealizedTyMap { key: f(x.key), value: f(x.value) },
        let x: ConcreteRealizedTyFunction => {
            ConcreteRealizedTyFunction {
                params: x.params.map((s0) -> {
                    RealizedFunctionParamTy { name: s0.name, ty: f(s0.ty), mode: s0.mode }
                }),
                ret: f(x.ret),
                throws_: f(x.throws_),
            }
        },
        let x: ConcreteRealizedTyFuture => {
            ConcreteRealizedTyFuture { value: f(x.value), error: f(x.error) }
        },
        let x: ConcreteRealizedTyTuple => ConcreteRealizedTyTuple { items: x.items.map(f) },
    }
}

// The direct children of `t`, in field order.
function children_concrete_realized_ty(t: ConcreteRealizedTy) -> RealizedTy[] {
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
        let x: ConcreteRealizedTyClass => x.args,
        let x: ConcreteRealizedTyList => [x.elem],
        let x: ConcreteRealizedTyMap => [x.key].concat([x.value]),
        let x: ConcreteRealizedTyFunction => {
            x.params
                .flat_map((s0) -> {
                    [s0.ty]
                })
                .concat([x.ret])
                .concat([x.throws_])
        },
        let x: ConcreteRealizedTyFuture => [x.value].concat([x.error]),
        let x: ConcreteRealizedTyTuple => x.items,
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
            TyTemplateInterface {
                name: x.name,
                args: x.args.map(f),
                associated_types: x.associated_types.map((s0) -> {
                    TyTemplateAssociatedType { name: s0.name, ty: f(s0.ty) }
                }),
            }
        },
        let x: TyTemplateList => TyTemplateList { elem: f(x.elem) },
        let x: TyTemplateMap => TyTemplateMap { key: f(x.key), value: f(x.value) },
        let x: TyTemplateUnion => TyTemplateUnion { members: x.members.map(f) },
        let x: TyTemplateFunction => {
            TyTemplateFunction {
                params: x.params.map((s0) -> {
                    TyTemplateFunctionParamTy { name: s0.name, ty: f(s0.ty), mode: s0.mode }
                }),
                ret: f(x.ret),
                throws_: f(x.throws_),
            }
        },
        let x: TyTemplateFuture => TyTemplateFuture { value: f(x.value), error: f(x.error) },
        let x: TyTemplateAssociatedTypeProjection => {
            TyTemplateAssociatedTypeProjection {
                base: f(x.base),
                interface_: TyTemplateInterfaceConstraint {
                    name: x.interface_.name,
                    generics: x.interface_.generics.map(f),
                    associated_types: x.interface_.associated_types.map((s0) -> {
                        TyTemplateAssociatedType { name: s0.name, ty: f(s0.ty) }
                    }),
                },
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
        let x: TyTemplateInterface => {
            x.args.concat(
                x.associated_types.flat_map((s0) -> {
                    [s0.ty]
                }),
            )
        },
        let x: TyTemplateList => [x.elem],
        let x: TyTemplateMap => [x.key].concat([x.value]),
        let x: TyTemplateUnion => x.members,
        let x: TyTemplateFunction => {
            x.params
                .flat_map((s0) -> {
                    [s0.ty]
                })
                .concat([x.ret])
                .concat([x.throws_])
        },
        let x: TyTemplateFuture => [x.value].concat([x.error]),
        let x: TyTemplateAssociatedTypeProjection => {
            [x.base].concat(x.interface_.generics).concat(
                x.interface_.associated_types.flat_map((s0) -> {
                    [s0.ty]
                }),
            )
        },
        let x: TyTemplateTuple => x.items,
    }
}

// == InferTy pool ==========================================================

// The direct children of `t`, in field order.
function children_infer_ty(t: InferTy) -> int[] {
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
            | TyInferVar =>
        {
            []
        },
        let x: InferTyClass => x.args,
        let x: InferTyInterface => {
            x.args.concat(
                x.associated_types.flat_map((s0) -> {
                    [s0.ty]
                }),
            )
        },
        let x: InferTyList => [x.elem],
        let x: InferTyMap => [x.key].concat([x.value]),
        let x: InferTyUnion => x.members,
        let x: InferTyFunction => {
            x.params
                .flat_map((s0) -> {
                    [s0.ty]
                })
                .concat([x.ret])
                .concat([x.throws_])
        },
        let x: InferTyFuture => [x.value].concat([x.error]),
        let x: InferTyAssociatedTypeProjection => {
            [x.base].concat(x.interface_.generics).concat(
                x.interface_.associated_types.flat_map((s0) -> {
                    [s0.ty]
                }),
            )
        },
        let x: InferTyTuple => x.items,
    }
}

// Interns `t` bottom-up; returns its handle.
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
                    args: x.args.map((c0) -> {
                        intern_ty(pool, c0)
                    }),
                },
            )
        },
        let x: TyInterface => {
            pool.add(
                InferTyInterface {
                    name: x.name,
                    args: x.args.map((c0) -> {
                        intern_ty(pool, c0)
                    }),
                    associated_types: x.associated_types.map((s0) -> {
                        InferAssociatedType { name: s0.name, ty: intern_ty(pool, s0.ty) }
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
                    members: x.members.map((c0) -> {
                        intern_ty(pool, c0)
                    }),
                },
            )
        },
        let x: TyFunction => {
            pool.add(
                InferTyFunction {
                    params: x.params.map((s0) -> {
                        InferFunctionParamTy {
                            name: s0.name,
                            ty: intern_ty(pool, s0.ty),
                            mode: s0.mode,
                        }
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
        let x: TyAssociatedTypeProjection => {
            pool.add(
                InferTyAssociatedTypeProjection {
                    base: intern_ty(pool, x.base),
                    interface_: InferInterfaceConstraint {
                        name: x.interface_.name,
                        generics: x.interface_.generics.map((c0) -> {
                            intern_ty(pool, c0)
                        }),
                        associated_types: x.interface_.associated_types.map((s0) -> {
                            InferAssociatedType { name: s0.name, ty: intern_ty(pool, s0.ty) }
                        }),
                    },
                    member: x.member,
                },
            )
        },
        let x: TyTuple => {
            pool.add(
                InferTyTuple {
                    items: x.items.map((c0) -> {
                        intern_ty(pool, c0)
                    }),
                },
            )
        },
    }
}

// Interns `t` bottom-up; returns its handle.
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
                    args: x.args.map((c0) -> {
                        intern_runtime_ty(pool, c0)
                    }),
                },
            )
        },
        let x: RuntimeTyInterface => {
            pool.add(
                InferTyInterface {
                    name: x.name,
                    args: x.args.map((c0) -> {
                        intern_runtime_ty(pool, c0)
                    }),
                    associated_types: x.associated_types.map((s0) -> {
                        InferAssociatedType { name: s0.name, ty: intern_runtime_ty(pool, s0.ty) }
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
                    members: x.members.map((c0) -> {
                        intern_runtime_ty(pool, c0)
                    }),
                },
            )
        },
        let x: RuntimeTyFunction => {
            pool.add(
                InferTyFunction {
                    params: x.params.map((s0) -> {
                        InferFunctionParamTy {
                            name: s0.name,
                            ty: intern_runtime_ty(pool, s0.ty),
                            mode: s0.mode,
                        }
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
        let x: RuntimeTyAssociatedTypeProjection => {
            pool.add(
                InferTyAssociatedTypeProjection {
                    base: intern_runtime_ty(pool, x.base),
                    interface_: InferInterfaceConstraint {
                        name: x.interface_.name,
                        generics: x.interface_.generics.map((c0) -> {
                            intern_runtime_ty(pool, c0)
                        }),
                        associated_types: x.interface_.associated_types.map((s0) -> {
                            InferAssociatedType {
                                name: s0.name,
                                ty: intern_runtime_ty(pool, s0.ty),
                            }
                        }),
                    },
                    member: x.member,
                },
            )
        },
        let x: RuntimeTyTuple => {
            pool.add(
                InferTyTuple {
                    items: x.items.map((c0) -> {
                        intern_runtime_ty(pool, c0)
                    }),
                },
            )
        },
    }
}

// Interns `t` bottom-up; returns its handle.
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
                    args: x.args.map((c0) -> {
                        intern_codegen_ty(pool, c0)
                    }),
                },
            )
        },
        let x: CodegenTyInterface => {
            pool.add(
                InferTyInterface {
                    name: x.name,
                    args: x.args.map((c0) -> {
                        intern_codegen_ty(pool, c0)
                    }),
                    associated_types: x.associated_types.map((s0) -> {
                        InferAssociatedType { name: s0.name, ty: intern_codegen_ty(pool, s0.ty) }
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
                    members: x.members.map((c0) -> {
                        intern_codegen_ty(pool, c0)
                    }),
                },
            )
        },
        let x: CodegenTyFunction => {
            pool.add(
                InferTyFunction {
                    params: x.params.map((s0) -> {
                        InferFunctionParamTy {
                            name: s0.name,
                            ty: intern_codegen_ty(pool, s0.ty),
                            mode: s0.mode,
                        }
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
                    items: x.items.map((c0) -> {
                        intern_codegen_ty(pool, c0)
                    }),
                },
            )
        },
    }
}

// Interns `t` bottom-up; returns its handle.
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
                    args: x.args.map((c0) -> {
                        intern_realized_ty(pool, c0)
                    }),
                },
            )
        },
        let x: RealizedTyInterface => {
            pool.add(
                InferTyInterface {
                    name: x.name,
                    args: x.args.map((c0) -> {
                        intern_realized_ty(pool, c0)
                    }),
                    associated_types: x.associated_types.map((s0) -> {
                        InferAssociatedType { name: s0.name, ty: intern_realized_ty(pool, s0.ty) }
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
                    members: x.members.map((c0) -> {
                        intern_realized_ty(pool, c0)
                    }),
                },
            )
        },
        let x: RealizedTyFunction => {
            pool.add(
                InferTyFunction {
                    params: x.params.map((s0) -> {
                        InferFunctionParamTy {
                            name: s0.name,
                            ty: intern_realized_ty(pool, s0.ty),
                            mode: s0.mode,
                        }
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
                    items: x.items.map((c0) -> {
                        intern_realized_ty(pool, c0)
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
                args: x.args.map((c0) -> {
                    resolve_ty(pool, c0)
                }),
            }
        },
        let x: InferTyInterface => {
            TyInterface {
                name: x.name,
                args: x.args.map((c0) -> {
                    resolve_ty(pool, c0)
                }),
                associated_types: x.associated_types.map((s0) -> {
                    AssociatedType { name: s0.name, ty: resolve_ty(pool, s0.ty) }
                }),
            }
        },
        let x: InferTyList => TyList { elem: resolve_ty(pool, x.elem) },
        let x: InferTyMap => {
            TyMap { key: resolve_ty(pool, x.key), value: resolve_ty(pool, x.value) }
        },
        let x: InferTyUnion => {
            TyUnion {
                members: x.members.map((c0) -> {
                    resolve_ty(pool, c0)
                }),
            }
        },
        let x: InferTyFunction => {
            TyFunction {
                params: x.params.map((s0) -> {
                    FunctionParamTy { name: s0.name, ty: resolve_ty(pool, s0.ty), mode: s0.mode }
                }),
                ret: resolve_ty(pool, x.ret),
                throws_: resolve_ty(pool, x.throws_),
            }
        },
        let x: InferTyFuture => {
            TyFuture { value: resolve_ty(pool, x.value), error: resolve_ty(pool, x.error) }
        },
        let x: InferTyAssociatedTypeProjection => {
            TyAssociatedTypeProjection {
                base: resolve_ty(pool, x.base),
                interface_: InterfaceConstraint {
                    name: x.interface_.name,
                    generics: x.interface_.generics.map((c0) -> {
                        resolve_ty(pool, c0)
                    }),
                    associated_types: x.interface_.associated_types.map((s0) -> {
                        AssociatedType { name: s0.name, ty: resolve_ty(pool, s0.ty) }
                    }),
                },
                member: x.member,
            }
        },
        let x: InferTyTuple => {
            TyTuple {
                items: x.items.map((c0) -> {
                    resolve_ty(pool, c0)
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
                args: x.args.map((c0) -> {
                    resolve_lowering_ty(pool, c0)
                }),
            }
        },
        let x: InferTyInterface => {
            LoweringTyInterface {
                name: x.name,
                args: x.args.map((c0) -> {
                    resolve_lowering_ty(pool, c0)
                }),
                associated_types: x.associated_types.map((s0) -> {
                    LoweringAssociatedType { name: s0.name, ty: resolve_lowering_ty(pool, s0.ty) }
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
                members: x.members.map((c0) -> {
                    resolve_lowering_ty(pool, c0)
                }),
            }
        },
        let x: InferTyFunction => {
            LoweringTyFunction {
                params: x.params.map((s0) -> {
                    LoweringFunctionParamTy {
                        name: s0.name,
                        ty: resolve_lowering_ty(pool, s0.ty),
                        mode: s0.mode,
                    }
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
        let x: InferTyAssociatedTypeProjection => {
            LoweringTyAssociatedTypeProjection {
                base: resolve_lowering_ty(pool, x.base),
                interface_: LoweringInterfaceConstraint {
                    name: x.interface_.name,
                    generics: x.interface_.generics.map((c0) -> {
                        resolve_lowering_ty(pool, c0)
                    }),
                    associated_types: x.interface_.associated_types.map((s0) -> {
                        LoweringAssociatedType {
                            name: s0.name,
                            ty: resolve_lowering_ty(pool, s0.ty),
                        }
                    }),
                },
                member: x.member,
            }
        },
        let x: InferTyTuple => {
            LoweringTyTuple {
                items: x.items.map((c0) -> {
                    resolve_lowering_ty(pool, c0)
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
                args: x.args.map((c0) -> {
                    resolve_runtime_ty(pool, c0)
                }),
            }
        },
        let x: InferTyInterface => {
            RuntimeTyInterface {
                name: x.name,
                args: x.args.map((c0) -> {
                    resolve_runtime_ty(pool, c0)
                }),
                associated_types: x.associated_types.map((s0) -> {
                    RuntimeAssociatedType { name: s0.name, ty: resolve_runtime_ty(pool, s0.ty) }
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
                members: x.members.map((c0) -> {
                    resolve_runtime_ty(pool, c0)
                }),
            }
        },
        let x: InferTyFunction => {
            RuntimeTyFunction {
                params: x.params.map((s0) -> {
                    RuntimeFunctionParamTy {
                        name: s0.name,
                        ty: resolve_runtime_ty(pool, s0.ty),
                        mode: s0.mode,
                    }
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
        let x: InferTyAssociatedTypeProjection => {
            RuntimeTyAssociatedTypeProjection {
                base: resolve_runtime_ty(pool, x.base),
                interface_: RuntimeInterfaceConstraint {
                    name: x.interface_.name,
                    generics: x.interface_.generics.map((c0) -> {
                        resolve_runtime_ty(pool, c0)
                    }),
                    associated_types: x.interface_.associated_types.map((s0) -> {
                        RuntimeAssociatedType { name: s0.name, ty: resolve_runtime_ty(pool, s0.ty) }
                    }),
                },
                member: x.member,
            }
        },
        let x: InferTyTuple => {
            RuntimeTyTuple {
                items: x.items.map((c0) -> {
                    resolve_runtime_ty(pool, c0)
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
                args: x.args.map((c0) -> {
                    resolve_codegen_ty(pool, c0)
                }),
            }
        },
        let x: InferTyInterface => {
            CodegenTyInterface {
                name: x.name,
                args: x.args.map((c0) -> {
                    resolve_codegen_ty(pool, c0)
                }),
                associated_types: x.associated_types.map((s0) -> {
                    CodegenAssociatedType { name: s0.name, ty: resolve_codegen_ty(pool, s0.ty) }
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
                members: x.members.map((c0) -> {
                    resolve_codegen_ty(pool, c0)
                }),
            }
        },
        let x: InferTyFunction => {
            CodegenTyFunction {
                params: x.params.map((s0) -> {
                    CodegenFunctionParamTy {
                        name: s0.name,
                        ty: resolve_codegen_ty(pool, s0.ty),
                        mode: s0.mode,
                    }
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
                items: x.items.map((c0) -> {
                    resolve_codegen_ty(pool, c0)
                }),
            }
        },
        InferTyAssociatedTypeProjection => {
            throw NarrowError { variant: "AssociatedTypeProjection", into: "CodegenTy" }
        },
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
                args: x.args.map((c0) -> {
                    resolve_realized_ty(pool, c0)
                }),
            }
        },
        let x: InferTyInterface => {
            RealizedTyInterface {
                name: x.name,
                args: x.args.map((c0) -> {
                    resolve_realized_ty(pool, c0)
                }),
                associated_types: x.associated_types.map((s0) -> {
                    RealizedAssociatedType { name: s0.name, ty: resolve_realized_ty(pool, s0.ty) }
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
                members: x.members.map((c0) -> {
                    resolve_realized_ty(pool, c0)
                }),
            }
        },
        let x: InferTyFunction => {
            RealizedTyFunction {
                params: x.params.map((s0) -> {
                    RealizedFunctionParamTy {
                        name: s0.name,
                        ty: resolve_realized_ty(pool, s0.ty),
                        mode: s0.mode,
                    }
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
                items: x.items.map((c0) -> {
                    resolve_realized_ty(pool, c0)
                }),
            }
        },
        TyTypeVar => throw NarrowError { variant: "TypeVar", into: "RealizedTy" },
        InferTyAssociatedTypeProjection => {
            throw NarrowError { variant: "AssociatedTypeProjection", into: "RealizedTy" }
        },
        TyError => throw NarrowError { variant: "Error", into: "RealizedTy" },
        TyInferVar => throw NarrowError { variant: "InferVar", into: "RealizedTy" },
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
                args: x.args.map((c0) -> {
                    resolve_ty_template(pool, c0)
                }),
            }
        },
        let x: InferTyInterface => {
            TyTemplateInterface {
                name: x.name,
                args: x.args.map((c0) -> {
                    resolve_ty_template(pool, c0)
                }),
                associated_types: x.associated_types.map((s0) -> {
                    TyTemplateAssociatedType { name: s0.name, ty: resolve_ty_template(pool, s0.ty) }
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
                members: x.members.map((c0) -> {
                    resolve_ty_template(pool, c0)
                }),
            }
        },
        let x: InferTyFunction => {
            TyTemplateFunction {
                params: x.params.map((s0) -> {
                    TyTemplateFunctionParamTy {
                        name: s0.name,
                        ty: resolve_ty_template(pool, s0.ty),
                        mode: s0.mode,
                    }
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
        let x: InferTyAssociatedTypeProjection => {
            TyTemplateAssociatedTypeProjection {
                base: resolve_ty_template(pool, x.base),
                interface_: TyTemplateInterfaceConstraint {
                    name: x.interface_.name,
                    generics: x.interface_.generics.map((c0) -> {
                        resolve_ty_template(pool, c0)
                    }),
                    associated_types: x.interface_.associated_types.map((s0) -> {
                        TyTemplateAssociatedType {
                            name: s0.name,
                            ty: resolve_ty_template(pool, s0.ty),
                        }
                    }),
                },
                member: x.member,
            }
        },
        let x: InferTyTuple => {
            TyTemplateTuple {
                items: x.items.map((c0) -> {
                    resolve_ty_template(pool, c0)
                }),
            }
        },
        TyTypeVar => throw NarrowError { variant: "TypeVar", into: "TyTemplate" },
        TyError => throw NarrowError { variant: "Error", into: "TyTemplate" },
        TyInferVar => throw NarrowError { variant: "InferVar", into: "TyTemplate" },
    }
}
