// port: baml_compiler2_hir_ty/src/diagnostics.rs @ d9be6853b
//
// The body type-diagnostic vocabulary: error kinds, arena-id-anchored
// diagnostics, and their span resolution. Diagnostics hold no `TextRange`;
// locations are arena ids (`int`) resolved through the body's source map at
// render time.
//
// Restructured:
// - Every data enum is a union of classes (`TirTypeError` is
//   `TirTypeError<Variant>`); a tuple variant with more than one field names
//   its fields (`RelatedLocationParam { function_, index }`).
// - `impl` methods on a union are free functions `<type>_<method>`
//   (`tir_type_error_render`, `assoc_container_spell`).
// - `TirTypeError::render` writes into no `fmt::Write`: each arm returns its
//   message.
// - `TirDiagnostic::render` is `render_with_body_type_refs` with its type-ref
//   map defaulted to null (one function, not a forwarding pair).
// - `strsim::jaro_winkler` (an external crate) is ported here for
//   `similar_name_suggestions`.

// port: baml_compiler2_hir_ty/src/diagnostics.rs::ScopedTypeEscapeKind @ d9be6853b
// How a value typed by a block-scoped `let type T = ...` binding would leave
// its block (E0172); the two roads have different remedies.
type ScopedTypeEscapeKind = ScopedTypeEscapeKindValue
    | ScopedTypeEscapeKindThrown
    | ScopedTypeEscapeKindInferred;

// The block's value: it leaves only through a type that does not mention
// `T`, such as `unknown`.
class ScopedTypeEscapeKindValue {
}

// A thrown type an inferred `throws` clause or an enclosing `catch` would
// publish.
class ScopedTypeEscapeKindThrown {
    // The closest type free of the binding that a declared clause may name
    // for the thrown type; null on a report that has not been materialized.
    relaxation: root.types.Ty?,
}

// A type still being inferred would become the escaping type.
class ScopedTypeEscapeKindInferred {
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::ImplicitUnitForm @ d9be6853b
// A form that evaluates to the unit value without the author writing it.
type ImplicitUnitForm = ImplicitUnitFormBlockWithoutTail
    | ImplicitUnitFormIfWithoutElse
    | ImplicitUnitFormBareReturn;

// A block with no final expression.
class ImplicitUnitFormBlockWithoutTail {
    // Its last statement is an expression of the expected type, discarded by
    // its `;`.
    discards_value: bool,
}

// An `if` / `if let` with no `else`.
class ImplicitUnitFormIfWithoutElse {
}

// `return;`.
class ImplicitUnitFormBareReturn {
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::ImplicitUnitForm::around_expected @ d9be6853b
// The message, as the text before and after the expected type. `admits_unit`:
// the expected type admits `null`, which then has to be written.
function implicit_unit_form_around_expected(
    form: ImplicitUnitForm,
    admits_unit: bool,
) -> (string, string) throws never {
    match (form) {
        // The value at hand is the likelier intent than a `null`.
        let f: ImplicitUnitFormBlockWithoutTail if f.discards_value => {
            ("expected ", ", but this value is discarded; remove the `;` to use it")
        },
        ImplicitUnitFormBlockWithoutTail => {
            if (admits_unit) {
                (
                    "expected ",
                    ", but this block ends without a value; write `null` as its final expression to produce it",
                )
            } else {
                ("expected ", ", but this block ends without a value")
            }
        },
        // Whatever the context admits, both branches have to produce it.
        ImplicitUnitFormIfWithoutElse => {
            ("expected ", ", but an `if` without `else` evaluates to `null`; add an `else` branch")
        },
        ImplicitUnitFormBareReturn => {
            if (admits_unit) {
                (
                    "expected a value of type ",
                    ", but a bare `return` returns `null` only where the return type is `null` itself; write `return null`",
                )
            } else {
                ("expected a value of type ", ", but a bare `return` returns `null`")
            }
        },
    }
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::UnitContext @ d9be6853b
// Where a value was produced although only the unit type is admitted.
enum UnitContext {
    // The final expression of a block the unit type is expected of.
    Block,
    // The branch of an `if` / `if let` with no `else`, where the unit type is
    // expected of the `if`.
    IfWithoutElse,
    // The branch of an `if` / `if let` with no `else` whose value is used.
    UsedIfWithoutElse,
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::UnitContext::around_found @ d9be6853b
// The message, as the text before and after the type that was found.
function unit_context_around_found(context: UnitContext) -> (string, string) throws never {
    match (context) {
        UnitContext.Block => ("expected `null`, found ", "; end this with `;` to discard the value"),
        UnitContext.IfWithoutElse => {
            (
                "an `if` without `else` evaluates to `null`, so its branch cannot produce ",
                "; add an `else` branch, or end this with `;` to discard the value",
            )
        },
        UnitContext.UsedIfWithoutElse => {
            (
                "an `if` without `else` evaluates to `null`, so its branch cannot produce ",
                "; add an `else` branch",
            )
        },
    }
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::ReturnContext @ d9be6853b
// An expression context a `return` was written in: not a function body, so
// there is nothing for it to return from.
type ReturnContext = ReturnContextGlobalInitializer
    | ReturnContextParameterDefault
    | ReturnContextTemplateInterpolation;

// The initializer of the named source global.
class ReturnContextGlobalInitializer {
    name: string,
}

// A parameter default, evaluated when the argument is omitted.
class ReturnContextParameterDefault {
}

// A tagged template's interpolation, which runs when the template is
// rendered.
class ReturnContextTemplateInterpolation {
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::LoopHeaderSlot @ d9be6853b
// A slot of a loop's header: evaluated by the loop itself, so a
// `break`/`continue` written there has no place.
enum LoopHeaderSlot {
    WhileCondition,
    WhileLetScrutinee,
    // A C-style `for` loop's update expression.
    ForUpdate,
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::LoopControlBarrier @ d9be6853b
// Why a `break`/`continue` has no loop to take it.
enum LoopControlBarrier {
    // No loop encloses the statement anywhere in the body.
    NoLoop,
    // The statement is in a lambda body.
    Lambda,
    // The statement is in a template interpolation, which runs as a closure
    // when the template is rendered.
    Template,
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::IrrefutableContextKind @ d9be6853b
// The syntactic context an irrefutable-pattern rule fires in.
enum IrrefutableContextKind {
    Let,
    ForLet,
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::IrrefutableContextKind::as_str @ d9be6853b
function irrefutable_context_kind_as_str(kind: IrrefutableContextKind) -> string throws never {
    match (kind) {
        IrrefutableContextKind.Let => "let",
        IrrefutableContextKind.ForLet => "for-let",
    }
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::AssocContainer @ d9be6853b
// The subject an associated-type projection failed to resolve `member` on:
// the container named by `TirTypeErrorUnknownAssociatedType`.
type AssocContainer = AssocContainerInterface
    | AssocContainerClass
    | AssocContainerEnum
    | AssocContainerTypeVar
    | AssocContainerTy;

// An interface subject that does not declare the member.
class AssocContainerInterface {
    value: root.types.DeclName,
}

// A concrete class none of whose impls' interfaces declare the member.
class AssocContainerClass {
    value: root.types.DeclName,
}

// A concrete enum none of whose impls' interfaces declare the member.
class AssocContainerEnum {
    value: root.types.DeclName,
}

// A type variable with no interface bound in scope.
class AssocContainerTypeVar {
    value: string,
}

// Any other subject type, rendered user-facing.
class AssocContainerTy {
    value: root.types.Ty,
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::impl Spell for AssocContainer @ d9be6853b
function assoc_container_spell(container: AssocContainer, vp: Viewpoint) -> string throws never {
    match (container) {
        let c: AssocContainerInterface => ``interface `${vp.path(c.value)}```,
        let c: AssocContainerClass => ``class `${vp.path(c.value)}```,
        let c: AssocContainerEnum => ``enum `${vp.path(c.value)}```,
        let c: AssocContainerTypeVar => ``type variable `${c.value}` (no interface bound)``,
        let c: AssocContainerTy => ``type `${ty_spell(c.value, vp)}```,
    }
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::SelfCallPosition @ d9be6853b
// Where a disallowed `Self` appears in a method called through an
// interface-existential receiver.
enum SelfCallPosition {
    // `Self` in more than one parameter (the `self` receiver counts), or
    // nested inside a parameter's type.
    Parameter,
    // The one `Self`-typed parameter has a default.
    OptionalParameter,
    // `Self` nested inside an invariant constructor in the return or throws
    // type.
    NestedInReturn,
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::ShadowedParamOwner @ d9be6853b
// The kind of enclosing declaration whose type-level parameter a method's
// generic shadows.
enum ShadowedParamOwner {
    Class,
    Interface,
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::impl Display for ShadowedParamOwner @ d9be6853b
function shadowed_param_owner_display(owner: ShadowedParamOwner) -> string throws never {
    match (owner) {
        ShadowedParamOwner.Class => "class",
        ShadowedParamOwner.Interface => "interface",
    }
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::TirTypeError @ d9be6853b
// What went wrong: no location info, just the semantic error. Each variant
// is a class `TirTypeError<Variant>`; field names that are BAML keywords
// take a trailing `_`.
type TirTypeError = TirTypeErrorInvalidTraceHook
    | TirTypeErrorTypeMismatch
    | TirTypeErrorListPatternNeverMatches
    | TirTypeErrorUnresolvedMember
    | TirTypeErrorUnionMemberNoCommonInterface
    | TirTypeErrorUnionMemberAssociatedTypeConflict
    | TirTypeErrorItemShadowsPackage
    | TirTypeErrorUnresolvedName
    | TirTypeErrorComputedGenericArgumentRequiresLetType
    | TirTypeErrorBoundedLetTypeRequiresElse
    | TirTypeErrorLetTypePendingOperand
    | TirTypeErrorMountedPackageCallUnsupported
    | TirTypeErrorInvalidAssignmentTarget
    | TirTypeErrorInvalidRegexPattern
    | TirTypeErrorUnresolvedPropertyShorthand
    | TirTypeErrorUnknownClassPropertyShorthand
    | TirTypeErrorUnknownClassField
    | TirTypeErrorMissingRequiredClassFields
    | TirTypeErrorCannotConstructReflectionKind
    | TirTypeErrorCannotConstructBuiltinCompanion
    | TirTypeErrorCannotConstructOpaqueClass
    | TirTypeErrorCannotConstructAlias
    | TirTypeErrorConstructedTypeParameter
    | TirTypeErrorCallSiteBuiltinValue
    | TirTypeErrorDeadCode
    | TirTypeErrorUnitExpected
    | TirTypeErrorNotCallable
    | TirTypeErrorNotIterable
    | TirTypeErrorNotIndexable
    | TirTypeErrorUnknownClassPatternField
    | TirTypeErrorInvalidMapKeyType
    | TirTypeErrorInvalidBinaryOp
    | TirTypeErrorOrderingDifferentTypes
    | TirTypeErrorOrderingRequiresCompare
    | TirTypeErrorComparisonAlwaysDisjoint
    | TirTypeErrorInvalidUnaryOp
    | TirTypeErrorUnresolvedType
    | TirTypeErrorRemovedReflectSpelling
    | TirTypeErrorNonInterfaceProjectionQualifier
    | TirTypeErrorCannotInferType
    | TirTypeErrorWildcardInProjectionSubject
    | TirTypeErrorTypeMustBeKnown
    | TirTypeErrorReceiverTypeMustBeKnown
    | TirTypeErrorUnknownAssociatedType
    | TirTypeErrorAmbiguousAssociatedTypeProjection
    | TirTypeErrorArgumentCountMismatch
    | TirTypeErrorPositionalArgumentAfterNamed
    | TirTypeErrorTupleElementNotAssignable
    | TirTypeErrorFunctionFieldNeedsParens
    | TirTypeErrorTupleIndexOutOfRange
    | TirTypeErrorTupleTypeTestNeverMatches
    | TirTypeErrorDuplicateNamedArgument
    | TirTypeErrorUnknownNamedArgument
    | TirTypeErrorTraceUnsupportedCall
    | TirTypeErrorTraceOpaqueValue
    | TirTypeErrorDefaultedParamPassedPositionally
    | TirTypeErrorMissingRequiredArgument
    | TirTypeErrorRequiredParamAfterDefault
    | TirTypeErrorSelfParamDefault
    | TirTypeErrorDefaultParamForwardReference
    | TirTypeErrorImplicitUnit
    | TirTypeErrorAliasCycle
    | TirTypeErrorClassCycle
    | TirTypeErrorNonExhaustiveMatch
    | TirTypeErrorNonExhaustiveCatchAll
    | TirTypeErrorUnreachableArm
    | TirTypeErrorOrPatternBindingTypeMismatch
    | TirTypeErrorGenericClassDestructureRequiresTypeArgs
    | TirTypeErrorRestSubPatternNotBinding
    | TirTypeErrorRefutablePatternInLet
    | TirTypeErrorIrrefutablePatternInIfLet
    | TirTypeErrorLetElseMustDiverge
    | TirTypeErrorIrrefutablePatternInLetElse
    | TirTypeErrorIrrefutablePatternInWhileLet
    | TirTypeErrorDeferControlFlowEscape
    | TirTypeErrorLoopControlOutsideLoop
    | TirTypeErrorLoopControlInLoopHeader
    | TirTypeErrorInvalidCatchBindingType
    | TirTypeErrorThrowsContractViolation
    | TirTypeErrorCallbackThrowsContractViolation
    | TirTypeErrorExtraneousThrowsDeclaration
    | TirTypeErrorImpreciseUnknownThrows
    | TirTypeErrorCannotInferTypeParameter
    | TirTypeErrorCannotInferAssociatedType
    | TirTypeErrorConflictingTypeArguments
    | TirTypeErrorTypeParamShadowed
    | TirTypeErrorTypeParamShadowedImplParam
    | TirTypeErrorDuplicateGenericParam
    | TirTypeErrorDuplicateAssociatedType
    | TirTypeErrorAssociatedTypeConflictsWithGenericParam
    | TirTypeErrorWrongNumberOfTypeArgs
    | TirTypeErrorWrongTypeArgArity
    | TirTypeErrorScopedTypeEscapesBlock
    | TirTypeErrorTypeIsNotGeneric
    | TirTypeErrorGenericFunctionValueNotSpecialized
    | TirTypeErrorCannotInferLambdaParamType
    | TirTypeErrorUnnecessaryOptionalChaining
    | TirTypeErrorUnnecessaryNullCoalesce
    | TirTypeErrorSuggestNullCoalesce
    | TirTypeErrorNullCoalesceWithNull
    | TirTypeErrorNullableMemberAccess
    | TirTypeErrorTaggedTagNotAFunction
    | TirTypeErrorTaggedTagNotMarked
    | TirTypeErrorTaggedTagBadBodyParam
    | TirTypeErrorInterpolatedValueMaybeNull
    | TirTypeErrorOutputFormatNotCalled
    | TirTypeErrorRoleMarkerInUntaggedTemplate
    | TirTypeErrorConditionAlwaysConstant
    | TirTypeErrorUncalledFunctionInCondition
    | TirTypeErrorAmbiguousInterfaceMethod
    | TirTypeErrorAmbiguousInterfaceField
    | TirTypeErrorInterfaceFieldRequiresProjection
    | TirTypeErrorInterfaceFieldRequiresQualifiedConstruction
    | TirTypeErrorInvalidInterfaceUpcastTarget
    | TirTypeErrorInterfaceMemberRequiresReceiver
    | TirTypeErrorInvalidSelfCallThroughInterface
    | TirTypeErrorSelflessMethodNeedsConcreteSelf
    | TirTypeErrorSelflessInstanceMember
    | TirTypeErrorErasedSelfMethodValue
    | TirTypeErrorDefaultOnRequiredMethod
    | TirTypeErrorBareDefaultKeyword
    | TirTypeErrorTypeDoesNotImplementInterface
    | TirTypeErrorBlanketBoundNotSatisfied
    | TirTypeErrorAmbiguousImplementation
    | TirTypeErrorIntegerLiteralOutOfRange
    | TirTypeErrorGenericBoundNotInterface
    | TirTypeErrorBuiltinInterfaceNotImplementable
    | TirTypeErrorBuiltinInterfaceNotABound
    | TirTypeErrorBoundedTypeArgNotConcrete
    | TirTypeErrorMissingAssociatedTypeBindings
    | TirTypeErrorInterfaceProjectionBase
    | TirTypeErrorAmbiguousInterfacePatternBindings
    | TirTypeErrorMissingInterfaceMethod
    | TirTypeErrorGenericSysOpMethodInInterfaceImpl
    | TirTypeErrorOutOfBodyImplementsFieldInterface
    | TirTypeErrorUnknownInterfaceMember
    | TirTypeErrorMissingInterfaceField
    | TirTypeErrorInterfaceFieldTypeMismatch
    | TirTypeErrorInterfaceMethodSignatureMismatch
    | TirTypeErrorInterfaceMethodAddsGenericBound
    | TirTypeErrorMissingRequiredInterface
    | TirTypeErrorImplTargetNotInterface
    | TirTypeErrorImplTargetNotConcrete
    | TirTypeErrorUnconstrainedImplTypeParam
    | TirTypeErrorImplViolatesOrphanRule
    | TirTypeErrorUnknownInterfaceFieldLink
    | TirTypeErrorUnknownClassFieldInInterfaceLink
    | TirTypeErrorDuplicateInterfaceFieldLink
    | TirTypeErrorUnknownAssociatedTypeBinding
    | TirTypeErrorDuplicateAssociatedTypeBinding
    | TirTypeErrorMissingImplAssociatedTypeBinding
    | TirTypeErrorAssociatedTypeBindingsOnImplementsTarget
    | TirTypeErrorAssociatedTypeBindingViolatesBound
    | TirTypeErrorSelfInInterfaceField
    | TirTypeErrorSelfInAssociatedTypeDefault
    | TirTypeErrorInterfaceRequiresNonInterface
    | TirTypeErrorInterfaceRequiresCycle
    | TirTypeErrorAssociatedTypeDefaultViolatesBound
    | TirTypeErrorCyclicImplHeader
    | TirTypeErrorInterfaceMethodMissingThrows
    | TirTypeErrorFunctionTypeMissingThrows
    | TirTypeErrorInitIoNotAllowed
    | TirTypeErrorInitSuspendNotAllowed
    | TirTypeErrorInitThrowNotHandled
    | TirTypeErrorLlmOutputMemberDropped
    | TirTypeErrorLlmOutputFieldAlwaysNull
    | TirTypeErrorJsonAttributesWithOverride
    | TirTypeErrorJsonRestFieldType
    | TirTypeErrorJsonRestRenamed
    | TirTypeErrorJsonAttributeSkipped
    | TirTypeErrorJsonRestRepeated
    | TirTypeErrorJsonFallbackFieldNotLiteral
    | TirTypeErrorJsonFallbackNoTag
    | TirTypeErrorJsonFallbackUntaggedMember
    | TirTypeErrorJsonFallbackOverlap
    | TirTypeErrorAssignmentToGlobal
    | TirTypeErrorReturnOutsideFunctionBody
    | TirTypeErrorGlobalInitializationCycle;

// A declaration trace hook is invalid.
class TirTypeErrorInvalidTraceHook {
    message: string,
}

// Type mismatch: expected vs actual.
class TirTypeErrorTypeMismatch {
    expected: root.types.Ty,
    got: root.types.Ty,
}

// A list pattern against a scrutinee none of whose values is a list: the
// pattern can never match.
class TirTypeErrorListPatternNeverMatches {
    scrutinee: root.types.Ty,
}

// Member not found on a known type. Reported when the base type IS resolved
// (known class/enum) but the member doesn't exist. Error messages are tailored
// by base type: - Class: "Class `X` has no member `y`" - Enum: "Enum `X` has
// no variant `y`"
class TirTypeErrorUnresolvedMember {
    base_type: root.types.Ty,
    member: string,
}

// A member (method or field) accessed on a union type is not reachable because
// the union's arms implement no *common* interface that declares it. Each arm
// may declare it independently (via distinct interfaces), but those are
// different members - the union has no single agreed-upon one.
class TirTypeErrorUnionMemberNoCommonInterface {
    union: root.types.Ty,
    member: string,
}

// A member reached through a union needs ONE type at a position where its arms
// bind an associated type differently. A method parameter takes one argument
// whichever arm the receiver holds, and a field is both read and written, so
// neither can be typed per arm the way a return type is. `types` are the arms'
// types for the offending position.
class TirTypeErrorUnionMemberAssociatedTypeConflict {
    union: root.types.Ty,
    member: string,
    is_method: bool,
    types: root.types.Ty[],
}

// A path that resolved to nothing started at an item of this namespace spelled
// like a package: the package is out of reach by that name.
class TirTypeErrorItemShadowsPackage {
    name: string,
}

// Name could not be resolved at all.
class TirTypeErrorUnresolvedName {
    name: string,
    // "Did you mean" candidates, each a fully qualified `root.…` path.
    suggestions: string[],
}

// A value name was written bare in a generic slot. A runtime type is lifted
// into a type position only by a `let type T = value;` binding; the slot then
// names `T`.
class TirTypeErrorComputedGenericArgumentRequiresLetType {
    name: string,
}

// A `let type T extends … = …` statement has no `else` block. Its bounds are
// checked when it runs, so it must say what a miss does.
class TirTypeErrorBoundedLetTypeRequiresElse {
    name: string,
}

// A `let type` operand is a class builder's pending type, which is not a type
// until the builder is built.
class TirTypeErrorLetTypePendingOperand {
}

// A mounted callable whose implementation is compiler-owned and has no
// location-free link ABI was invoked from a source-less consumer.
class TirTypeErrorMountedPackageCallUnsupported {
    path: string,
}

// An assignment target spelled as a path whose root is not a local binding - a
// function, an enum variant, a class - so there is no storage to write through
// (`mk = mk`, `Shape.Circle = Shape.Circle`).
class TirTypeErrorInvalidAssignmentTarget {
    path: string,
}

// A constant pattern argument to `baml.regex.new` does not compile. Checked
// here so a typo in a literal pattern is a source error rather than a throw
// the program has to reach to discover.
class TirTypeErrorInvalidRegexPattern {
    // The same classification `baml.regex.Error.kind` carries at runtime.
    kind: baml.regex.ErrorKind,
    // The engine's own one-line diagnostic.
    message: string,
    // Codepoint offset into the pattern where the problem starts, when the
    // engine reports one. The pattern is a decoded string literal, so this
    // indexes the pattern, not the source line.
    offset: int?,
}

// A shorthand property (`{ name }`) could not resolve its implicit value.
// Suggestions are in-scope values with similar names; the diagnostic renders
// them as explicit `name: suggestion` mappings.
class TirTypeErrorUnresolvedPropertyShorthand {
    name: string,
    suggestions: string[],
}

// A class constructor shorthand property resolves as a value but its name is
// not an exact class-field match.
class TirTypeErrorUnknownClassPropertyShorthand {
    class_name: root.types.DeclName,
    name: string,
    suggestions: string[],
}

// A class constructor explicitly names a field the class does not declare.
class TirTypeErrorUnknownClassField {
    class_name: root.types.DeclName,
    field_name: string,
    suggestions: string[],
}

// A class constructor omitted fields whose resolved types do not admit `null`.
// A field whose type admits `null` (`T?`, `unknown`, `baml.json.json`) may be
// omitted because the object representation initializes absent slots to
// `null`.
class TirTypeErrorMissingRequiredClassFields {
    class_name: root.types.DeclName,
    field_names: string[],
}

// Sealed reflection-kind values are VM views and cannot be constructed with an
// object literal.
class TirTypeErrorCannotConstructReflectionKind {
    class_name: root.types.DeclName,
}

// Builtin companion carriers (`baml.Int`, `baml.Map`, …) hold no fields and
// cannot be constructed with an object literal.
class TirTypeErrorCannotConstructBuiltinCompanion {
    class_name: root.types.DeclName,
    companion: root.types.BuiltinCompanion,
}

// A class literal for a class with a `$rust_type` field. Only the class's own
// native functions create that state, so the literal could only relabel a
// handle taken from another value.
class TirTypeErrorCannotConstructOpaqueClass {
    class_name: root.types.DeclName,
    // The first field that holds native state.
    field: string,
}

// A constructor head that is an alias of a type no object literal can
// construct (anything but a class).
class TirTypeErrorCannotConstructAlias {
    name: string,
    denotes: root.types.Ty,
}

// A constructor head that is a type parameter or a scoped `type` binding: it
// shadows every item and names no class.
class TirTypeErrorConstructedTypeParameter {
    name: string,
}

// A builtin that is lowered where it is called (`log.info`,
// `baml.spawn.__spawn`, ...) was referenced as a value.
class TirTypeErrorCallSiteBuiltinValue {
    reference: string,
}

// Unreachable code after a diverging statement (return/break/continue).
class TirTypeErrorDeadCode {
    unreachable_count: int,
}

// A value was produced where only the unit type is admitted: the final
// expression of a block expected to be unit, the branch of an `if` with no
// `else`. The value would be dropped silently, so the author discards it with
// `;`.
class TirTypeErrorUnitExpected {
    context: UnitContext,
    found: root.types.Ty,
}

// Expression is not callable (e.g. `42(1)` or `Foo(1)` where Foo is a class).
class TirTypeErrorNotCallable {
    ty: root.types.Ty,
}

// Expression is not iterable (e.g. `for let i in 42 { ... }` where 42 is an
// int).
class TirTypeErrorNotIterable {
    ty: root.types.Ty,
}

// Expression is not indexable (e.g. `true[0]`).
class TirTypeErrorNotIndexable {
    ty: root.types.Ty,
}

// A class destructuring pattern names a field the class does not declare.
class TirTypeErrorUnknownClassPatternField {
    class_name: root.types.DeclName,
    field_name: string,
    suggestions: string[],
}

// A `map` type expression whose key type is not `string` (e.g. `map<int, V>`).
// Map keys are strings at runtime, so the key type must denote `string` or a
// subset of it.
class TirTypeErrorInvalidMapKeyType {
    key: root.types.Ty,
}

// Invalid operand types for a binary operator (e.g. `true + false`).
class TirTypeErrorInvalidBinaryOp {
    op: root.ast.BinaryOp,
    lhs: root.types.Ty,
    rhs: root.types.Ty,
}

// Ordering (`<` `<=` `>` `>=`) between two different types. Ordering is exact-
// type: both operands must have the same type (subtyping is not enough - only
// `==` spans types), so this fires even when one operand is a subtype of the
// other.
class TirTypeErrorOrderingDifferentTypes {
    op: root.ast.BinaryOp,
    lhs: root.types.Ty,
    rhs: root.types.Ty,
}

// Ordering (`<` `<=` `>` `>=`) on a common type that does not implement
// `baml.ops.Compare`, so no ordering is defined for it.
class TirTypeErrorOrderingRequiresCompare {
    op: root.ast.BinaryOp,
    ty: root.types.Ty,
}

// An equality (`==` / `!=`) whose operand types are provably disjoint - no
// value of one can ever equal a value of the other - so the result is a
// constant (`==` always `false`, `!=` always `true`). A warning, not an error:
// the comparison is valid, just pointless.
class TirTypeErrorComparisonAlwaysDisjoint {
    op: root.ast.BinaryOp,
    lhs: root.types.Ty,
    rhs: root.types.Ty,
}

// Invalid operand type for a unary operator (e.g. `-"hello"`).
class TirTypeErrorInvalidUnaryOp {
    op: root.ast.UnaryOp,
    operand: root.types.Ty,
}

// A type name in a type annotation could not be resolved.
class TirTypeErrorUnresolvedType {
    name: string,
    // "Did you mean" candidates, each a fully qualified `root.…` path.
    suggestions: string[],
}

// A spelling that reflection used before it became its own package:
// `baml.reflect.X`, `type.of<T>()`, or a bare `type` annotation. These resolve
// nowhere now, so say what replaces them instead of reporting an ordinary
// unknown name.
class TirTypeErrorRemovedReflectSpelling {
    // What the source wrote.
    written: string,
    // What it should say now.
    replacement: string,
    // Set when the message should add that the `type` keyword itself is still
    // around - only the `type.` value prefix and the bare `type` annotation
    // went away.
    mentions_type_keyword: bool,
}

// An associated-type projection's explicit `as X` qualifier resolved to a non-
// interface type (a class, alias, etc.). The qualifier must name an interface;
// without one the projection cannot be resolved, so it must not silently fall
// back to an unqualified projection.
class TirTypeErrorNonInterfaceProjectionQualifier {
}

// A type-inference placeholder `_` (a `TypeExprKind::Infer` wildcard) could
// not have its type inferred - inference for `_` is unavailable, so the type
// must be written explicitly. Lowered to `Ty::Error` so it never reaches the
// canonical normalizer, which treats the inference hole as `unreachable!`.
class TirTypeErrorCannotInferType {
}

// A `_` in the subject of an associated-type projection (`(Box<_> as
// I).Item`): the subject decides which interface declares the member, so it
// cannot be left for inference.
class TirTypeErrorWildcardInProjectionSubject {
}

// An ordinary inference variable remained unresolved at writeback.
class TirTypeErrorTypeMustBeKnown {
    full_type: root.types.Ty,
}

// A member was accessed on a value whose type was still being inferred. Member
// lookup needs the receiver's structure at that point; resolving the variable
// later cannot retroactively choose the member.
class TirTypeErrorReceiverTypeMustBeKnown {
    member: string,
}

// An associated-type projection references `member`, but the subject it
// projects through does not declare (or cannot declare) it as an associated
// type. Interfaces do not inherit associated types through `requires` (it is a
// bound, not inheritance), so a member declared on a *required* interface must
// be projected through that interface directly: `(Foo as Iterator).Item`, not
// `(Foo as RequiresIterator).Item`.
class TirTypeErrorUnknownAssociatedType {
    member: string,
    container: AssocContainer,
}

// An unqualified associated-type projection `Base.member` matches more than
// one interface that declares `member`; it must be disambiguated with an
// explicit `(Base as Interface).member` qualifier.
class TirTypeErrorAmbiguousAssociatedTypeProjection {
    member: string,
    candidates: root.types.DeclName[],
}

// Wrong number of arguments in a function call.
class TirTypeErrorArgumentCountMismatch {
    expected: int,
    got: int,
}

// A positional argument appeared after a named argument in the same call.
class TirTypeErrorPositionalArgumentAfterNamed {
}

class TirTypeErrorTupleElementNotAssignable {
}

class TirTypeErrorFunctionFieldNeedsParens {
}

class TirTypeErrorTupleIndexOutOfRange {
    index: int,
    tuple: root.types.Ty,
    variant: root.types.Ty?,
}

class TirTypeErrorTupleTypeTestNeverMatches {
    scrutinee: root.types.Ty,
    tested: root.types.Ty,
}

// A named argument was supplied more than once.
class TirTypeErrorDuplicateNamedArgument {
    name: string,
}

// A call supplied a named argument that is not present in the callable type.
class TirTypeErrorUnknownNamedArgument {
    name: string,
}

// Native and compiler-only calls do not expose a traceable invocation.
class TirTypeErrorTraceUnsupportedCall {
}

// Trace handles have no public constructor or fields.
class TirTypeErrorTraceOpaqueValue {
}

// A defaulted parameter was supplied positionally instead of by name.
class TirTypeErrorDefaultedParamPassedPositionally {
    name: string,
}

// A required parameter was omitted.
class TirTypeErrorMissingRequiredArgument {
    name: string,
}

// A required parameter appeared after a defaulted parameter in a declaration.
class TirTypeErrorRequiredParamAfterDefault {
    name: string,
}

// The special `self` receiver cannot declare a default.
class TirTypeErrorSelfParamDefault {
}

// A default expression referenced a later parameter from the same signature.
class TirTypeErrorDefaultParamForwardReference {
    param: string,
    referenced: string,
}

// An implicit unit - a block with no final expression, an `if` with no `else`,
// a bare `return;` - stands where a type other than the unit type is expected.
// `null <: int?` does not admit it: the value the author left out must be
// written.
class TirTypeErrorImplicitUnit {
    form: ImplicitUnitForm,
    expected: root.types.Ty,
    // `expected` admits `null`.
    admits_unit: bool,
}

// Type alias participates in an invalid (unguarded) cycle. Examples: `type A =
// A`, `type A = B; type B = A`. Valid recursion through containers (`type JSON
// = string | JSON[]`) does NOT trigger this - only cycles with no base case.
class TirTypeErrorAliasCycle {
    name: string,
}

// Class participates in an unconstructable required-field cycle. Examples:
// `class A { b B }; class B { a A }`. Cycles through optional, list, or map
// fields are valid since those can be null/empty, breaking the construction
// dependency.
class TirTypeErrorClassCycle {
    name: string,
    cycle_path: string,
}

// `match` is missing arms for one or more values.
class TirTypeErrorNonExhaustiveMatch {
    scrutinee_type: root.types.Ty,
    missing_cases: string[],
}

// A `catch_all` / `catch_all_panics` clause is missing arms for one or more
// caught throw types (or, for `catch_all_panics`, panics).
class TirTypeErrorNonExhaustiveCatchAll {
    // The clause keyword: `catch_all` or `catch_all_panics`.
    keyword: string,
    caught_type: root.types.Ty,
    missing_cases: string[],
}

// A `match`/`catch` arm can never execute because previous arms are
// exhaustive.
class TirTypeErrorUnreachableArm {
}

// Or-pattern alternatives bind the same name with conflicting narrow types.
// HIR already ensures the *names* line up across branches; this is the type-
// level counterpart.
class TirTypeErrorOrPatternBindingTypeMismatch {
    name: string,
    first_type: root.types.Ty,
    other_type: root.types.Ty,
}

// A generic class destructure with fields must write its type arguments
// directly on the class pattern, e.g. `Box<int> { value }`.
class TirTypeErrorGenericClassDestructureRequiresTypeArgs {
    class_name: string,
}

// A rest pattern (`..`) carries a sub-pattern that is not binding-shaped.
// Allowed: `..let r`, `.._`, bind chains, and a terminal `: T` ascription
// link. Rejected: bare type patterns, structural destructures, and or-patterns
// - see `lower_array_pat` for why each is blocked and what expanding the set
// would take.
class TirTypeErrorRestSubPatternNotBinding {
}

// A `let` statement or `for-let` binding uses a pattern that can fail for
// values of the type flowing into it.
class TirTypeErrorRefutablePatternInLet {
    context: IrrefutableContextKind,
}

// An `if let` pattern that covers every value of the scrutinee - the `else`
// branch is unreachable. Suggests using a plain `let` instead.
class TirTypeErrorIrrefutablePatternInIfLet {
}

// `let … else { … }` whose else block does not have type `Ty::Never`. The else
// branch must diverge - return, throw, break, continue, or loop forever - so
// that fall-through past the binding cannot occur.
class TirTypeErrorLetElseMustDiverge {
    got: root.types.Ty,
}

// A `let … else` pattern that covers every value of the initializer type - the
// else branch is unreachable. Suggest using a plain `let`.
class TirTypeErrorIrrefutablePatternInLetElse {
}

// A `while let` pattern that covers every value of the scrutinee - the loop
// never exits via pattern failure (an unconditional infinite loop). Suggest a
// plain `while`/`loop` instead.
class TirTypeErrorIrrefutablePatternInWhileLet {
}

// `return`/`break`/`continue` inside a `defer` body that would escape the
// defer (BEP-042). Only `throw` may leave a defer. `keyword` is the offending
// control-flow keyword.
class TirTypeErrorDeferControlFlowEscape {
    keyword: string,
}

// `break`/`continue` that no loop can take: `barrier` is what stands between
// the statement and any loop.
class TirTypeErrorLoopControlOutsideLoop {
    keyword: string,
    barrier: LoopControlBarrier,
}

// A `break`/`continue` written in a loop's header rather than its body.
class TirTypeErrorLoopControlInLoopHeader {
    keyword: string,
    slot: LoopHeaderSlot,
}

// Catch binding cannot be typed as `any` or `unknown`.
class TirTypeErrorInvalidCatchBindingType {
    type_name: string,
}

// Inferred escaping throws are not covered by the declared throws contract.
class TirTypeErrorThrowsContractViolation {
    declared: root.types.Ty,
    // What the body may throw beyond the clause, as ONE type so the renderer
    // parenthesizes what needs it.
    extra: root.types.Ty,
}

// Inferred escaping throws are explainable through a single callback path.
class TirTypeErrorCallbackThrowsContractViolation {
    callback_name: string,
    declared: root.types.Ty,
    concrete_throws: root.types.Ty?,
}

// Declared throws contains extra types that never escape.
class TirTypeErrorExtraneousThrowsDeclaration {
    extra_types: string[],
}

// An `unknown`-containing throws contract without an escaping value typed
// `unknown`.
class TirTypeErrorImpreciseUnknownThrows {
    // What the function actually throws, as ONE type so the renderer
    // parenthesizes what needs it - this message asks the author to write what
    // it prints. `None` when it throws nothing.
    inferred: root.types.Ty?,
    // The clause must stay (a member is a scoped thrown type's relaxation);
    // only its spelling is wrong.
    needs_declaration: bool,
}

// A type parameter could not be inferred at a call site.
class TirTypeErrorCannotInferTypeParameter {
    name: string,
}

// An interface pattern's instantiation leaves the associated type `name`
// unpinned, and nothing else determines it.
class TirTypeErrorCannotInferAssociatedType {
    name: string,
}

// A type parameter's arguments give it types with no common candidate
// (`pick(1, "s")` for `pick<T>(a: T, b: T)`), and nothing else - an expected
// type - decides between them. Two of the conflicting types are named.
class TirTypeErrorConflictingTypeArguments {
    name: string,
    first: root.types.Ty,
    second: root.types.Ty,
}

// A method's generic type parameter shadows a generic parameter of the
// enclosing class or interface.
class TirTypeErrorTypeParamShadowed {
    param_name: string,
    type_name: string,
    owner: ShadowedParamOwner,
}

// A method's generic type parameter shadows a generic parameter declared on
// the enclosing `implements` block.
class TirTypeErrorTypeParamShadowedImplParam {
    param_name: string,
}

// A generic type parameter declared more than once in the same parameter list.
class TirTypeErrorDuplicateGenericParam {
    name: string,
}

// An associated type declared more than once on the same interface.
class TirTypeErrorDuplicateAssociatedType {
    name: string,
}

// An associated type sharing its name with one of the interface's own generic
// parameters.
class TirTypeErrorAssociatedTypeConflictsWithGenericParam {
    name: string,
}

// Wrong number of type arguments for a generic class or interface.
class TirTypeErrorWrongNumberOfTypeArgs {
    type_name: string,
    expected: int,
    got: int,
}

// Wrong number of explicit type arguments at a function call site. E.g.
// `f<int>(x)` when `f` declares zero type params, or `f<int, string>(x)` when
// `f<T>` declares only one.
class TirTypeErrorWrongTypeArgArity {
    callee_name: string,
    expected: int,
    got: int,
}

// A value typed by a body-scoped `let type T = …` binding would be observable
// outside the block that binds `T` (E0172): the block's value, or a thrown
// type an inferred `throws` clause would publish. `value` is the escaping type
// as it mentions `T`.
class TirTypeErrorScopedTypeEscapesBlock {
    name: string,
    value: root.types.Ty,
    kind: ScopedTypeEscapeKind,
}

// Type arguments were supplied for a type that is not generic (enums and type
// aliases cannot take type parameters).
class TirTypeErrorTypeIsNotGeneric {
    type_name: string,
    kind: string,
}

// A generic function was referenced as a value without specialization (`let f
// = identity` where `identity<T>`). A generic function is a type constructor -
// it must be specialized (`identity<int>`) or have its type arguments
// inferable from context before it becomes a usable value.
class TirTypeErrorGenericFunctionValueNotSpecialized {
    name: string,
    reference: string,
    had_expected_type: bool,
    generic_params: string[],
    binding_name: string?,
    function_shape: string?,
    annotation_example: string?,
    specialization_example: string?,
    specialization_syntax_available: bool,
}

// A lambda parameter has no type annotation and no expected type context to
// infer the type from.
class TirTypeErrorCannotInferLambdaParamType {
    param_name: string,
}

// `?.` used on a non-nullable type (e.g. `a?.b` where `a` is not nullable).
class TirTypeErrorUnnecessaryOptionalChaining {
    // The full expression text (e.g. `a?.b`)
    expr: string,
    // The base expression text (e.g. `a`)
    base: string,
}

// `??` used where the left operand is non-nullable.
class TirTypeErrorUnnecessaryNullCoalesce {
    // LHS expression text
    lhs: string,
    // Full expression text (e.g. `a ?? b`)
    expr: string,
}

// `||` used where `??` was likely intended (nullable LHS).
class TirTypeErrorSuggestNullCoalesce {
    // LHS expression text
    lhs: string,
    // RHS expression text
    rhs: string,
}

// `?? null` is a no-op.
class TirTypeErrorNullCoalesceWithNull {
    // LHS expression text
    lhs: string,
}

// Member access (`.field` or `[index]`) on a nullable type without `?.`.
// Occurs when parentheses break an optional chain: `(a?.b).c`.
class TirTypeErrorNullableMemberAccess {
    // The base expression text (e.g. `a`)
    base: string,
    // The member being accessed (e.g. `.name`)
    member: string,
    // The full expression text (e.g. `a.name`)
    expr: string,
}

// BEP-049 §10: a backtick template was attached to a tag that resolves to
// something that isn't a function (so it can't be a tagged-string tag).
class TirTypeErrorTaggedTagNotAFunction {
    name: string,
}

// BEP-049 §10: the tag resolves to a function, but it lacks the
// `//baml:tagged_string` marker that makes it usable as a tagged-template tag.
class TirTypeErrorTaggedTagNotMarked {
    name: string,
}

// BEP-049 §10: a `//baml:tagged_string` tag's first parameter is not a well-
// formed `body: (...) -> baml.TaggedString` (missing / wrong name / not a
// lambda / lambda return type isn't `baml.TaggedString`).
class TirTypeErrorTaggedTagBadBodyParam {
    name: string,
}

// BEP-049 §11: an untagged `${expr}` interpolates a nullable value. The
// implicit `.to_string()` can't run on a possibly-null value; the user must
// coalesce (`${x ?? "…"}`) or unwrap first.
class TirTypeErrorInterpolatedValueMaybeNull {
    ty: root.types.Ty,
}

// The output-format method was referenced without being called.
class TirTypeErrorOutputFormatNotCalled {
}

// An untagged `${expr}` interpolates a value whose type holds an `ai.Role`.
// Only a `prompt` template turns a role marker into a message boundary; an
// untagged string would render it as text.
class TirTypeErrorRoleMarkerInUntaggedTemplate {
    ty: root.types.Ty,
}

// A condition whose truthiness is statically known. The type is included when
// it alone proves the result (rather than boolean composition).
class TirTypeErrorConditionAlwaysConstant {
    ty: root.types.Ty?,
    always_true: bool,
}

// A function value tested without being called.
class TirTypeErrorUncalledFunctionInCondition {
    name: string,
    suggestion: string?,
}

// BEP-044 §"Method Disambiguation": an unqualified call resolves to a method
// declared by two or more interfaces - the receiver carries no information to
// pick one. `sources` lists every contributing interface as a namespace-
// qualified display string (e.g. `zoo.Animal`) so colliding same-simple-name
// interfaces from different namespaces are distinguishable and the suggested
// `as<…>` fix actually compiles.
class TirTypeErrorAmbiguousInterfaceMethod {
    class_name: string,
    method_name: string,
    sources: string[],
}

// BEP-044 interface fields live in per-interface namespaces. A bare field
// access is ambiguous when multiple implemented interfaces provide the same
// field name and the class does not shadow it with an own field.
class TirTypeErrorAmbiguousInterfaceField {
    class_name: string,
    field_name: string,
    sources: string[],
}

// A concrete-typed receiver tried to access an interface field name that is
// only available after projecting to the interface view.
class TirTypeErrorInterfaceFieldRequiresProjection {
    class_name: string,
    field_name: string,
    interface_name: string,
}

// Interface-qualified field keys such as `Animal.name` are not class
// constructor fields. Interface fields are satisfied by class-owned fields or
// explicit `field as class_field` links.
class TirTypeErrorInterfaceFieldRequiresQualifiedConstruction {
    field_name: string,
    qualified_name: string,
}

// `.as<T>` is an interface projection/upcast; the target must be an interface
// type.
class TirTypeErrorInvalidInterfaceUpcastTarget {
    target: root.types.Ty,
}

// Interface members are instance/view members, not static members on the
// interface type. Call through an interface-typed value or `.as<I>`.
class TirTypeErrorInterfaceMemberRequiresReceiver {
    interface_name: string,
    member_name: string,
}

// An erased `Self` (an interface-existential or union) cannot call a method
// that breaks the one-`Self` rule: `Self` in more than one parameter or nested
// in a parameter (the concrete implementor is unknown for those arguments), or
// `Self` nested inside an invariant constructor in the return/throws type (`->
// Self[]`, `-> Box<Self>` - the impl returns a concretely-tagged container
// that is NOT a subtype of the existential-tagged one; containers are
// invariant). A bare top-level `-> Self` is fine (it collapses covariantly).
// The `self` receiver is one `Self`-typed parameter like any other. Rust `dyn
// Trait` parity.
class TirTypeErrorInvalidSelfCallThroughInterface {
    interface_name: string,
    method_name: string,
    position: SelfCallPosition,
}

// An interface method with NO `Self`-typed parameter referenced with an erased
// `Self` (an interface-existential or union). There is no value to derive a
// concrete implementor from - dispatch is keyed on the `Self` TYPE - and an
// erased type names no single impl.
class TirTypeErrorSelflessMethodNeedsConcreteSelf {
    interface_name: string,
    method_name: string,
    self_ty: root.types.Ty,
}

// A `self`-less interface method reached through a VALUE receiver
// (`f.make(5)`, `f.as<I>.make()`): an associated function, not an instance
// member - the receiver spellings pass the receiver as `self`, which the
// callee has no slot for. Rust's E0599 split.
class TirTypeErrorSelflessInstanceMember {
    // The declaring interface, when statically known.
    interface_name: string?,
    method_name: string,
}

// A receiver method reified as a VALUE with an erased `Self` (an interface-
// existential or union). A direct call dispatches off the receiver argument,
// but an uncalled value has no resolution moment.
class TirTypeErrorErasedSelfMethodValue {
    interface_name: string,
    method_name: string,
    self_ty: root.types.Ty,
}

// BEP-044 §"default keyword scoping rules": `default.method()` on a required
// method (no default body) is a compile error.
class TirTypeErrorDefaultOnRequiredMethod {
    interface_name: string,
    method_name: string,
}

// BEP-044: bare `default` (not `default.method(...)`) used as a value.
// `default` is only meaningful in call position.
class TirTypeErrorBareDefaultKeyword {
}

// BEP-044: `value.as<I>` where the concrete `value`'s type does not implement
// interface `I`. A clearer form of the generic type-mismatch.
class TirTypeErrorTypeDoesNotImplementInterface {
    value_type: root.types.Ty,
    // The full interface type (with any generic args), so the diagnostic names
    // `Cargo<int>` rather than the bare `Cargo`.
    interface_: root.types.Ty,
}

// BEP-044: a value almost satisfies an interface via a blanket impl, but a
// generic bound (`T extends Bound`) is not met. Names the failed bound.
class TirTypeErrorBlanketBoundNotSatisfied {
    value_type: root.types.Ty,
    bound: root.types.Ty,
}

// More than one implementation could prove that `value_type` implements
// `interface`, and nothing in the program picks one (rustc's E0283).
class TirTypeErrorAmbiguousImplementation {
    value_type: root.types.Ty,
    // The interface as far as inference determined it.
    interface_: root.types.Ty,
}

// An integer literal (or a constant-folded integer expression) is outside the
// representable `int` range `[-2^62, 2^62-1]`. `int` is 63-bit; larger
// magnitudes need a `bigint` literal (`n` suffix).
class TirTypeErrorIntegerLiteralOutOfRange {
    value: int,
}

// BEP-044: a generic parameter's bound (`<T extends X>`) resolved to a
// concrete non-interface type. Generic bounds must be interfaces.
class TirTypeErrorGenericBoundNotInterface {
    bound: root.types.Ty,
}

// BEP-062: an `implements` block targets a compiler-builtin interface
// (`reflect.AnyFunction`), whose conformance is derived by the compiler and
// cannot be written by hand.
class TirTypeErrorBuiltinInterfaceNotImplementable {
    interface_: root.types.DeclName,
}

// BEP-062: a generic parameter's bound names a compiler-builtin interface
// (`reflect.AnyFunction`) that is only legal as a value type (an existential),
// never as a bound.
class TirTypeErrorBuiltinInterfaceNotABound {
    interface_: root.types.DeclName,
}

// `TYPE_SYSTEM.md` § Generics on Functions: an interface-bounded type
// parameter (`<T extends I>`) was given a non-concrete type argument (a union,
// interface-existential, literal, `unknown`, …). Only a concrete type has a
// single run-time representation, so virtual dispatch on the parameter is
// well-defined; a `T = A | B` would let `a.method(b)` dispatch on two
// different concrete types at once. Names the argument and the interface bound
// (a conjunction of interfaces - a non-interface bound is a separate
// `GenericBoundNotInterface` error, never this one).
class TirTypeErrorBoundedTypeArgNotConcrete {
    arg: root.types.Ty,
    bound: root.types.InterfaceConstraint[],
}

// `TYPE_SYSTEM.md` § Generics on Functions: an interface used as an
// **existential type** (a value's type - a parameter, return, field, or
// annotation) must specify every associated type, like Rust's `dyn
// Iterator<Item = …>` (E0191). Only associated types with a declared default
// may be omitted. An unpinned existential (`Iterator` instead of
// `Iterator<Item = int>`) is otherwise ill-formed: `Iterator` and
// `Iterator<Item = int>` would be mutually-incomparable types and membership
// would be vacuous. (Interface *bounds* - `<T extends Iterator>` - do NOT
// require this; they are not existentials.) Names the interface and the
// unpinned associated types.
class TirTypeErrorMissingAssociatedTypeBindings {
    interface_: root.types.DeclName,
    missing: string[],
}

// The dotted projection shorthand (`Base.Member`) was written with the
// interface itself as the base (`Iterator.Element`). The base of a projection
// is an *implementor* - a concrete type (`ArrayIterator.Element`), a bounded
// type variable (`T.Element`), or `Self` inside a body - never the interface:
// an associated type is defined per `(interface, implementor, member)` triple,
// so the interface alone does not determine it (Rust's E0223). Naming the
// interface explicitly takes a qualified projection (`(Base as
// Iterator).Element`).
class TirTypeErrorInterfaceProjectionBase {
    interface_: root.types.DeclName,
    member: string,
}

// A *bare* interface destructure pattern (`Source { value }`, no written
// generic args or associated bindings) adopts its associated-type bindings
// from the scrutinee - so the scrutinee must determine them uniquely. A
// scrutinee admitting two distinct realizations of the pattern's interface
// (`Source<Item = int> | Source<Item = string>`) is ambiguous: the pattern
// must write the bindings explicitly. (A *type* pattern never infers - it is
// an ordinary type and pins everything, per
// `TirTypeErrorMissingAssociatedTypeBindings`.)
class TirTypeErrorAmbiguousInterfacePatternBindings {
    interface_: root.types.DeclName,
    candidates: root.types.Ty[],
}

// An `implements` block does not provide a body for a method the interface
// declares as required (no default). Impl conformance (E0113).
class TirTypeErrorMissingInterfaceMethod {
    interface_: root.types.DeclName,
    method: string,
}

// A `$rust_io_function` (sys-op) method inside an `implements` block has
// method-level generic parameters. An impl-block method is reached only
// through interface (virtual) dispatch, which does not reconstruct the
// synthetic type-argument slots a generic sys-op's glue reads off the stack -
// so such a call would fail at runtime. (A generic sys-op declared directly on
// a class is fine: it lowers to a direct `SysOp` instruction, which does
// supply those slots.) Impl conformance.
class TirTypeErrorGenericSysOpMethodInInterfaceImpl {
    interface_: root.types.DeclName,
    method: string,
}

// An interface that declares fields is implemented out-of-body (`implement I
// for T`). A field-bearing interface can only be implemented in the class
// body, where its fields are satisfied by the class's own fields (E0126).
class TirTypeErrorOutOfBodyImplementsFieldInterface {
    interface_: root.types.DeclName,
}

// An `implements` block provides a method the interface neither requires nor
// declares as a default - so it overrides nothing. Impl conformance (E0115).
class TirTypeErrorUnknownInterfaceMember {
    interface_: root.types.DeclName,
    member: string,
}

// An interface field is not satisfied by any class field - neither a same-
// named field nor an explicit `field as class_field` link. Impl conformance
// (E0124).
class TirTypeErrorMissingInterfaceField {
    interface_: root.types.DeclName,
    field: string,
}

// The class field satisfying an interface field has an incompatible type -
// field types are invariant, so they must be equivalent. Impl conformance
// (E0116).
class TirTypeErrorInterfaceFieldTypeMismatch {
    interface_: root.types.DeclName,
    field: string,
    // The interface's declared field type (realized at the impl's interface
    // args).
    expected: root.types.Ty,
    // The satisfying class field's type.
    got: root.types.Ty,
}

// An override's signature is not a subtype of the interface's declared
// signature - args/kwargs are contravariant, return/throws covariant. Impl
// conformance (E0120).
class TirTypeErrorInterfaceMethodSignatureMismatch {
    interface_: root.types.DeclName,
    method: string,
    // The interface's declared signature (realized at the impl's interface
    // args).
    expected: root.types.Ty,
    // The override's signature.
    got: root.types.Ty,
}

// An override declares a generic bound on one of its type parameters that the
// interface method does not require - the implementation has stricter
// requirements than the interface (Rust's E0276), so a caller satisfying the
// interface could be rejected.
class TirTypeErrorInterfaceMethodAddsGenericBound {
    interface_: root.types.DeclName,
    method: string,
    param: string,
    bound: root.types.InterfaceConstraint,
}

// The impl's target type does not implement an interface the implemented
// interface `requires` - implementing `I` requires also implementing each of
// `I`'s parents. `required` is the *realized* obligation (generic args and
// associated pins included), so a type that implements the parent at a
// different binding reads as what's missing (`Parent<Item = int>`, not a bare
// `Parent` it does implement). Impl conformance (E0125).
class TirTypeErrorMissingRequiredInterface {
    interface_: root.types.DeclName,
    required: root.types.InterfaceConstraint,
}

// An `implements` head names a type that is not an interface (a class, enum,
// or alias). Impl header (E0119).
class TirTypeErrorImplTargetNotInterface {
    name: string,
}

// An out-of-body impl's `for` target is not a single concrete impl subject - a
// union, optional, interface (`dyn`), literal, `unknown`, function, `Future`,
// … Impl header (E0138).
class TirTypeErrorImplTargetNotConcrete {
    target: root.types.Ty,
}

// An impl declares a generic parameter that its `for` type and interface
// arguments do not determine, so it can never be inferred at a use site. Impl
// header (E0135).
class TirTypeErrorUnconstrainedImplTypeParam {
    name: string,
}

// An out-of-body impl of a *foreign* interface is not anchored on a local type
// - the RFC-2451 covered rule (BEP-044). Impl header (E0139).
class TirTypeErrorImplViolatesOrphanRule {
    interface_: root.types.DeclName,
    // The uncovered type parameter appearing before any local type, if that is
    // the failure; `None` when no local type appears anywhere in the impl's
    // inputs.
    uncovered_param: string?,
}

// The left side of a `field as class_field` link does not name a field of the
// implemented interface. Field-link well-formedness (E0128).
class TirTypeErrorUnknownInterfaceFieldLink {
    interface_: root.types.DeclName,
    field: string,
}

// The right side of a `field as class_field` link does not name a field of the
// class. Field-link well-formedness (E0129).
class TirTypeErrorUnknownClassFieldInInterfaceLink {
    class_: string,
    interface_: root.types.DeclName,
    field: string,
}

// The same interface field is linked by more than one `field as class_field`
// link in one `implements` block. Field-link well-formedness (E0130).
class TirTypeErrorDuplicateInterfaceFieldLink {
    interface_: root.types.DeclName,
    field: string,
}

// A `type Name = …` binding in an `implements` block names an associated type
// the interface does not declare. Assoc-binding hygiene.
class TirTypeErrorUnknownAssociatedTypeBinding {
    interface_: root.types.DeclName,
    name: string,
}

// An `implements` block binds the same associated type more than once. Assoc-
// binding hygiene.
class TirTypeErrorDuplicateAssociatedTypeBinding {
    interface_: root.types.DeclName,
    name: string,
}

// An `implements` block does not bind an associated type the interface
// declares with no default, so it is left undetermined. Assoc-binding hygiene.
// (Distinct from `TirTypeErrorMissingAssociatedTypeBindings`, which is the
// existential *value*-position rule.)
class TirTypeErrorMissingImplAssociatedTypeBinding {
    interface_: root.types.DeclName,
    name: string,
}

// Associated type bindings were written on an `implements` *target*
// (`implements I<Item = …>`) instead of inside the block (`type Item = …`).
// Assoc-binding hygiene.
class TirTypeErrorAssociatedTypeBindingsOnImplementsTarget {
    interface_: root.types.DeclName,
}

// An `implements` block binds an associated type to a type that does not
// implement the interface's declared bound for it (`type Item extends J`) - a
// bound is an *implements* relation, like a generic bound. Assoc-binding
// hygiene.
class TirTypeErrorAssociatedTypeBindingViolatesBound {
    interface_: root.types.DeclName,
    name: string,
    // The bound type the binding fails to implement.
    binding: root.types.Ty,
    bound: root.types.InterfaceConstraint,
}

// `Self` appears in an interface *field* type. `Self` is only meaningful in
// method signatures; a recursive field must name the interface itself.
// Interface-declaration well-formedness (E0136).
class TirTypeErrorSelfInInterfaceField {
    interface_: root.types.DeclName,
    field: string,
}

// Bare `Self` appears in an associated type's *default*. `Self` is universal -
// it denotes each implementor, not the existential - so at an interface-
// existential type (`I<…>`, where the implementor is hidden) such a default
// has nothing to resolve against. Defaulting it to the existential itself
// would pin the member to a type no impl ever binds, making the existential
// uninhabited. A `Self.Assoc` projection is fine: the existential's own pins
// already fix it. Interface-declaration well-formedness (E0157).
class TirTypeErrorSelfInAssociatedTypeDefault {
    interface_: root.types.DeclName,
    associated_type: string,
}

// An interface's `requires` clause names a type that is not an interface (a
// class, enum, alias, or any structural type - the clause parses a full type
// expression). Only interfaces can be required, exactly as only interfaces can
// be generic bounds (see `TirTypeErrorGenericBoundNotInterface`). Interface-
// declaration well-formedness (E0133).
class TirTypeErrorInterfaceRequiresNonInterface {
    interface_: root.types.DeclName,
    target: root.types.Ty,
}

// An interface's transitive `requires` graph cycles back to itself. Interface-
// declaration well-formedness (E0118). `chain` is the witnessing name path
// `[root, …, root]`.
class TirTypeErrorInterfaceRequiresCycle {
    chain: string[],
}

// An interface associated type's default does not implement its declared bound
// (`type Item extends J = V` where `V` does not implement `J`). Interface-
// declaration well-formedness.
class TirTypeErrorAssociatedTypeDefaultViolatesBound {
    interface_: root.types.DeclName,
    name: string,
    // The default type that fails to implement the bound.
    default_: root.types.Ty,
    bound: root.types.InterfaceConstraint,
}

// An impl header contains a concrete associated-type projection (`implement I
// for C.Item`, or an interface argument `I<X = C.Item>`) whose resolution
// enumerates this very impl set, so it cycles. The `impl_data` cycle fallback
// can't carry a diagnostic, so it is re-detected and reported here. Impl
// header.
class TirTypeErrorCyclicImplHeader {
}

// An interface method (required or default) omits its `throws` clause.
// Interface signatures must declare it explicitly - it is never inferred
// (`TYPE_SYSTEM.md` rule 1). Interface-declaration well-formedness.
class TirTypeErrorInterfaceMethodMissingThrows {
    interface_: root.types.DeclName,
    method: string,
}

// A function type omits its `throws` clause in a position where the error type
// cannot be inferred - a type alias, class field, `let` annotation, nested or
// return position (`TYPE_SYSTEM.md` rule 5). Only an immediate callback
// parameter of a function declaration may omit it; there the compiler opens it
// to a synthetic effect parameter (rule 4). Lambda parameters have no generic
// binder to open an effect parameter on, so they must declare it explicitly.
class TirTypeErrorFunctionTypeMissingThrows {
}

// A top-level declaration's initializer reaches an io sysop. Top-level
// declarations (`client Foo = …`, `let x = …`) are evaluated by the
// synthesized `$init` chainer when the engine is created, on a path that
// cannot suspend - so the io does not fail with a catchable BAML error, it
// kills engine construction with an opaque `InitFailed`. Detected by
// `crate::init_io` (E0158).
class TirTypeErrorInitIoNotAllowed {
    // The declaration's name.
    declaration: string,
    // `client Foo = …` (true) versus a global variable, `const NAME = …`
    // (false). Only affects wording.
    is_client: bool,
    // Fully-qualified name of the io sysop reached (`baml.env.get`).
    sysop: string,
    // The first call hop from the initializer toward `sysop`. `None` when the
    // initializer calls the sysop directly.
    via: string?,
}

// A top-level declaration's initializer reaches `spawn` or `await`. `$init`
// runs on a path with no scheduler to launch a task onto or suspend into, so
// either kills engine construction the way io does. Detected by
// `crate::init_io`.
class TirTypeErrorInitSuspendNotAllowed {
    // The declaration's name.
    declaration: string,
    // `client Foo = …` (true) versus a global variable, `const NAME = …`
    // (false).
    is_client: bool,
    // The suspending operation: `"spawn"` or `"await"`.
    operation: string,
    // The first call hop from the initializer toward the operation. `None`
    // when the initializer performs it directly.
    via: string?,
}

// A top-level declaration's initializer can throw `thrown`, and nothing in it
// catches the throw. An uncaught throw in `$init` stops the engine from being
// created, so it must be handled where the value is made.
class TirTypeErrorInitThrowNotHandled {
    declaration: string,
    is_client: bool,
    thrown: root.types.Ty,
}

// A member of an LLM function's return type that a model's JSON answer can
// never be (a warning): one with no JSON form, such as `uint8array`, or with
// no values. The runtime drops it from the output schema.
class TirTypeErrorLlmOutputMemberDropped {
    function_: string,
    member: root.types.Ty,
    // The member has no values at all, rather than no JSON form.
    no_values: bool,
    // What the function can return instead, or `None` when it can return
    // nothing.
    kept: root.types.Ty?,
}

// An optional field, in a class an LLM function returns, that a model's JSON
// answer can never fill (a warning): its type has no JSON form besides `null`,
// so the field is always `null`.
class TirTypeErrorLlmOutputFieldAlwaysNull {
    field: string,
}

// `@json` attributes on a class that provides `baml.ToJson` or
// `baml.FromJson`, which they would not reach.
class TirTypeErrorJsonAttributesWithOverride {
    name: string,
    interface_: string,
}

// `@json.flatten` or `@json.fallback` on a field that is not `map<string,
// json>`.
class TirTypeErrorJsonRestFieldType {
    attribute: string,
    field: string,
}

// `@json.rename` on a `@json.flatten` or `@json.fallback` field, which has no
// key of its own.
class TirTypeErrorJsonRestRenamed {
    attribute: string,
    field: string,
}

// `@skip` on a field JSON has to read: a `@json.flatten` or `@json.fallback`
// field, or a fallback class's tag.
class TirTypeErrorJsonAttributeSkipped {
    field: string,
}

// A class with a second `@json.flatten` or `@json.fallback` field.
class TirTypeErrorJsonRestRepeated {
    class_: string,
}

// A `@json.fallback` class with a field that is not a literal.
class TirTypeErrorJsonFallbackFieldNotLiteral {
    class_: string,
    field: string,
}

// A `@json.fallback` class with no literal field to name its tag.
class TirTypeErrorJsonFallbackNoTag {
    class_: string,
}

// A union with a `@json.fallback` member and a member the tag can't reach, so
// the fallback would take its objects or it would take every object.
class TirTypeErrorJsonFallbackUntaggedMember {
    fallback: string,
    member: root.types.Ty,
}

// A union with a `@json.fallback` member and two members no literal field
// tells apart.
class TirTypeErrorJsonFallbackOverlap {
    first: root.types.Ty,
    second: root.types.Ty,
}

// An assignment targets a top-level binding. `$init` sets every global once
// and requests then share it, so the binding is immutable; only what it holds
// may change.
class TirTypeErrorAssignmentToGlobal {
    name: string,
    // `client Foo = …` (true) versus a global variable (false).
    is_client: bool,
}

// A `return` written in an expression that is not a function body.
class TirTypeErrorReturnOutsideFunctionBody {
    context: ReturnContext,
}

// Global variables whose initializers need each other's values: no order
// exists in which `$init` could evaluate them. `chain` is the cycle as
// written, starting and ending at the reported global, with every function it
// passes through (`a → helper → b → a`).
class TirTypeErrorGlobalInitializationCycle {
    chain: string[],
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::write_generic_function_value_diagnostic @ d9be6853b
// The E0001 message for a generic function referenced as a value without
// specialization.
// Restructured: returns the text instead of writing it into a buffer.
function write_generic_function_value_diagnostic(
    name: string,
    reference: string,
    had_expected_type: bool,
    generic_params: string[],
    binding_name: string?,
    function_shape: string?,
    annotation_example: string?,
    specialization_example: string?,
    specialization_syntax_available: bool,
) -> string throws never {
    let out: string[] = [];
    if (had_expected_type) {
        out.push(
            ``cannot determine every type argument for generic function `${name}` from the expected function type. ``,
        );
    } else if (binding_name != null) {
        out.push(
            ``generic function `${name}` needs concrete type arguments before it can be stored in `${binding_name}`. ``,
        );
    } else {
        out.push(
            ``generic function `${name}` needs concrete type arguments before it can be used as a value. ``,
        );
    }

    let param_names = generic_params.join(", ");
    if (specialization_example != null) {
        out.push(
            ``Specialize it explicitly, for example `${reference}<${specialization_example}>`. ``,
        );
    } else if (!specialization_syntax_available) {
        out.push(
            `This reference form cannot take type arguments as a stored value; choose concrete types for ${param_names} with a function type annotation instead. `,
        );
    } else {
        out.push(
            `Specialize it explicitly by choosing concrete types for ${param_names}; each type must satisfy its declared bounds. `,
        );
    }

    if (binding_name != null && annotation_example != null) {
        out.push(
            ``Or write the concrete function type after the binding name: `let ${binding_name}: ${annotation_example} = ${reference}`. ``,
        );
    } else if (binding_name != null && function_shape != null) {
        out.push(
            ``Or write the concrete function type after the binding name, using `${function_shape}` as the shape and replacing ${param_names} with the types you want: `let ${binding_name}: ... = ${reference}`. ``,
        );
    } else if (binding_name == null && annotation_example != null) {
        out.push(
            ``Bind it first with a concrete function type: `let function_value: ${annotation_example} = ${reference}`. ``,
        );
    } else if (function_shape != null) {
        out.push(
            ``A concrete annotation can use `${function_shape}` as its shape; replace ${param_names} with the types you want. ``,
        );
    }

    out.push(
        ``Calling `${reference}(...)` directly works only when that call's arguments or expected result determine every type argument``,
    );
    out.join("")
}

// port: core::str::parse::<usize> @ d9be6853b
// Whether `text` parses as a `usize`: an optional `+`, then ASCII digits
// whose value fits in 64 bits.
function parses_as_usize(text: string) -> bool throws never {
    let digits = root.base.strip_prefix(text, "+") ?? text;
    if (
        digits.length() == 0
            || !digits.chars().every((c) -> {
                c.is_ascii_numeric()
            })
    ) {
        return false;
    }
    let significant = root.base.trim_start_matches(digits, "0");
    let max = "18446744073709551615";
    significant.length() < max.length()
        || (significant.length() == max.length() && significant <= max)
}

// port: the "Did you mean" tail TirTypeError::render writes after
// `UnresolvedName` and `UnresolvedType`: nothing, `. Did you mean `x`?`, or
// `. Did you mean one of these: `x`, `y`?`.
function did_you_mean(suggestions: string[]) -> string throws never {
    match (suggestions.length()) {
        0 => "",
        1 => ``. Did you mean `${suggestions[0]}`?``,
        _ => ``. Did you mean one of these: `${suggestions.join("`, `")}`?``,
    }
}

// port: the shared `UnknownClassField | UnknownClassPatternField` arm of
// TirTypeError::render.
function unknown_class_field_message(
    class_name: root.types.DeclName,
    field_name: string,
    suggestions: string[],
    vp: Viewpoint,
) -> string throws never {
    let class_path = vp.path(class_name);
    match (suggestions.length()) {
        0 => ``class `${class_path}` has no field `${field_name}```,
        1 => {
            ``class `${class_path}` has no field `${field_name}`. Did you mean `${suggestions[0]}`?``
        },
        _ => {
            ``class `${class_path}` has no field `${field_name}`. Did you mean one of these: `${suggestions.join("`, `")}`?``
        },
    }
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::TirTypeError::render @ d9be6853b
// The message, with every type spelled from `vp`.
function tir_type_error_render(error: TirTypeError, vp: Viewpoint) -> string throws never {
    let spell = (ty: root.types.Ty) -> string {
        ty_spell(ty, vp)
    };
    match (error) {
        let e: TirTypeErrorInvalidTraceHook => e.message,
        let e: TirTypeErrorTypeMismatch => {
            `type mismatch: expected ${spell(e.expected)}, got ${spell(e.got)}`
        },
        let e: TirTypeErrorListPatternNeverMatches => {
            ``a list pattern never matches a value of type `${spell(e.scrutinee)}```
        },
        let e: TirTypeErrorUnresolvedMember => {
            match (e.base_type) {
                root.types.TyUnknown => ``cannot access field `${e.member}` on `unknown```,
                root.types.TyTuple => {
                    ``tuple `${spell(e.base_type)}` has no named member `${e.member}`; tuple slots are numbered, such as `.0```
                },
                _ => ``type `${spell(e.base_type)}` has no member `${e.member}```,
            }
        },
        let e: TirTypeErrorUnionMemberNoCommonInterface => {
            let member = e.member;
            let union_ = e.union;
            if (parses_as_usize(member)) {
                if let members: root.types.TyUnion = union_ {
                    if (
                        members.members.some((m) -> {
                            m is root.types.TyTuple
                        })
                    ) {
                        if (
                            members.members.length() == 2
                                && members.members.some((m) -> {
                                    m is root.types.TyNull
                                })
                        ) {
                            return ``cannot read slot `${member}` on optional tuple `${spell(union_)}`; use `?.${member}` or narrow away `null` first``;
                        }
                        return ``cannot read slot `${member}` through tuple union `${spell(union_)}`; narrow to one tuple type first``;
                    }
                }
            }
            ``type `${spell(union_)}` has no member `${member}`: its members implement no common interface that declares `${member}```
        },
        let e: TirTypeErrorUnionMemberAssociatedTypeConflict => {
            let position = if (e.is_method) {
                "a parameter's type"
            } else {
                "its type"
            };
            let types = e.types
                .map((ty) -> {
                    ``\`${spell(ty)}```
                })
                .join(", ");
            ``member `${e.member}` cannot be used on `${spell(e.union)}`: ${position} depends on an associated type its members bind differently (${types}); narrow the union first``
        },
        let e: TirTypeErrorItemShadowsPackage => {
            ``\`${e.name}` is an item of this namespace, which shadows the package `${e.name}`: the package cannot be reached by that name from here``
        },
        let e: TirTypeErrorUnresolvedName => {
            `unresolved name: ${e.name}${did_you_mean(e.suggestions)}`
        },
        let e: TirTypeErrorComputedGenericArgumentRequiresLetType => {
            root.diagnostics.computed_generic_argument_requires_let_type(e.name).message
        },
        let e: TirTypeErrorBoundedLetTypeRequiresElse => {
            root.diagnostics.bounded_let_type_requires_else(e.name).message
        },
        TirTypeErrorLetTypePendingOperand => root.diagnostics.let_type_pending_operand().message,
        let e: TirTypeErrorUnresolvedPropertyShorthand => {
            let name = e.name;
            let head = ``property shorthand `${name}` requires an in-scope value named `${name}```;
            match (e.suggestions.length()) {
                0 => head,
                1 => ``${head}. Did you mean `${name}: ${e.suggestions[0]}`?``,
                _ => {
                    let joined = e.suggestions
                        .map((suggestion) -> {
                            `${name}: ${suggestion}`
                        })
                        .join("`, `");
                    ``${head}. Did you mean one of these: `${joined}`?``
                },
            }
        },
        let e: TirTypeErrorUnknownClassPropertyShorthand => {
            let name = e.name;
            let class_path = vp.path(e.class_name);
            match (e.suggestions.length()) {
                0 => {
                    ``property shorthand `${name}` requires class `${class_path}` to have a field named `${name}```
                },
                1 => {
                    ``class `${class_path}` has no field `${name}` for property shorthand. Did you mean `${e.suggestions[0]}: ${name}`?``
                },
                _ => {
                    let joined = e.suggestions
                        .map((field) -> {
                            `${field}: ${name}`
                        })
                        .join("`, `");
                    ``class `${class_path}` has no field `${name}` for property shorthand. Did you mean one of these: `${joined}`?``
                },
            }
        },
        let e: TirTypeErrorCannotConstructReflectionKind => {
            root.diagnostics.cannot_construct_reflection_kind(vp.path(e.class_name)).message
        },
        let e: TirTypeErrorCannotConstructBuiltinCompanion => {
            root.diagnostics
                .cannot_construct_builtin_companion(
                    vp.path(e.class_name),
                    e.companion.builtin,
                    e.companion.origin,
                    e.companion.carries_methods,
                )
                .message
        },
        let e: TirTypeErrorCannotConstructOpaqueClass => {
            ``class `${vp.path(e.class_name)}` cannot be built with a class literal: its field `${e.field}` holds state that only the class's own functions create``
        },
        let e: TirTypeErrorCallSiteBuiltinValue => {
            ``\`${e.reference}` can only be called directly, not used as a value; to pass it along, wrap the call in a lambda``
        },
        let e: TirTypeErrorCannotConstructAlias => {
            ``cannot construct `${e.name}`: it is an alias of `${spell(e.denotes)}`, not a class``
        },
        let e: TirTypeErrorConstructedTypeParameter => {
            ``cannot construct `${e.name}`: it is a type parameter here, not a class``
        },
        let e: TirTypeErrorInvalidAssignmentTarget => {
            ``invalid assignment target; `${e.path}` is not a variable, so it cannot be assigned to``
        },
        let e: TirTypeErrorMountedPackageCallUnsupported => {
            root.diagnostics.mounted_package_call_unsupported(e.path).message
        },
        let e: TirTypeErrorInvalidRegexPattern => {
            let headline = match (e.kind) {
                baml.regex.ErrorKind.Syntax => "invalid regex pattern",
                baml.regex.ErrorKind.Unsupported => "unsupported regex construct",
                baml.regex.ErrorKind.TooLarge => "regex pattern is too large",
            };
            let offset = e.offset;
            if (offset != null) {
                `${headline} at character ${offset}: ${e.message}`
            } else {
                `${headline}: ${e.message}`
            }
        },
        let e: TirTypeErrorDeadCode => {
            `unreachable code: ${e.unreachable_count} statement(s) after diverging statement`
        },
        let e: TirTypeErrorUnitExpected => {
            let (let before, let after) = unit_context_around_found(e.context);
            ``${before}`${spell(e.found)}`${after}``
        },
        let e: TirTypeErrorNotCallable => {
            ``\`${spell(e.ty)}` is not a function — it cannot be called``
        },
        let e: TirTypeErrorNotIterable => ``cannot iterate over type `${spell(e.ty)}```,
        let e: TirTypeErrorNotIndexable => {
            let head = ``type `${spell(e.ty)}` is not indexable``;
            if (e.ty is root.types.TyTuple) {
                ``${head}; tuples use fixed dot slots such as `.0`; use `reflect.Tuple.get_element` for a runtime-selected slot``
            } else {
                head
            }
        },
        let e: TirTypeErrorUnknownClassField => {
            unknown_class_field_message(e.class_name, e.field_name, e.suggestions, vp)
        },
        let e: TirTypeErrorUnknownClassPatternField => {
            unknown_class_field_message(e.class_name, e.field_name, e.suggestions, vp)
        },
        let e: TirTypeErrorMissingRequiredClassFields => {
            let fields = e.field_names
                .map((field) -> {
                    ``\`${field}```
                })
                .join(", ");
            let noun = if (e.field_names.length() == 1) {
                "field"
            } else {
                "fields"
            };
            ``class `${vp.path(e.class_name)}` is missing required ${noun}: ${fields}``
        },
        let e: TirTypeErrorInvalidMapKeyType => {
            ``map keys must implement `baml.Hash`; got `${spell(e.key)}```
        },
        let e: TirTypeErrorInvalidBinaryOp => {
            ``operator `${root.ast.binary_op_display(e.op)}` cannot be applied to `${spell(e.lhs)}` and `${spell(e.rhs)}```
        },
        let e: TirTypeErrorOrderingDifferentTypes => {
            ``cannot order `${spell(e.lhs)}` and `${spell(e.rhs)}` with `${root.ast.binary_op_display(e.op)}`: ordering requires both operands to have the same type``
        },
        let e: TirTypeErrorOrderingRequiresCompare => {
            ``\`${spell(e.ty)}` does not implement `Compare`, so it cannot be ordered with `${root.ast.binary_op_display(e.op)}```
        },
        let e: TirTypeErrorComparisonAlwaysDisjoint => {
            let always = if (e.op == root.ast.BinaryOp.Ne) {
                "true"
            } else {
                "false"
            };
            ``\`${spell(e.lhs)}` and `${spell(e.rhs)}` share no value, so this comparison is always ${always}``
        },
        let e: TirTypeErrorInvalidUnaryOp => {
            ``operator `${root.ast.unary_op_display(e.op)}` cannot be applied to `${spell(e.operand)}```
        },
        TirTypeErrorNonInterfaceProjectionQualifier => {
            "qualified associated type projection must use an interface"
        },
        TirTypeErrorWildcardInProjectionSubject => {
            "`_` is not allowed in the subject of an associated-type projection: the subject decides which interface declares the member, so write it out"
        },
        TirTypeErrorCannotInferType => "type inference failed; write the type explicitly",
        let e: TirTypeErrorReceiverTypeMustBeKnown => {
            ``type annotations needed: the type of this value must be known before accessing `${e.member}```
        },
        let e: TirTypeErrorTypeMustBeKnown => {
            ``type annotations needed\nfull type: `${spell(e.full_type)}```
        },
        let e: TirTypeErrorUnknownAssociatedType => {
            ``unknown associated type `${e.member}` for ${assoc_container_spell(e.container, vp)}``
        },
        let e: TirTypeErrorAmbiguousAssociatedTypeProjection => {
            let names = e.candidates
                .map((c) -> {
                    ``\`${vp.path(c)}```
                })
                .join(", ");
            ``ambiguous associated type `${e.member}`: declared by multiple interfaces (${names}); qualify the projection with `(... as Interface).${e.member}```
        },
        let e: TirTypeErrorRemovedReflectSpelling => {
            if (e.mentions_type_keyword) {
                let head = if (e.written == "type") {
                    "`type` no longer names a runtime type value — "
                } else {
                    ``\`${e.written}` no longer exists — ``
                };
                ``${head}write `${e.replacement}` instead. The `type` keyword itself is unchanged: it still names aliases (`type UserId = string`) and scoped type bindings (`let type T = t;`)``
            } else {
                ``\`${e.written}` no longer exists — reflection is its own package now, so write `${e.replacement}` instead``
            }
        },
        let e: TirTypeErrorUnresolvedType => {
            `unresolved type: ${e.name}${did_you_mean(e.suggestions)}`
        },
        let e: TirTypeErrorArgumentCountMismatch => {
            `expected ${e.expected} argument(s), got ${e.got}`
        },
        TirTypeErrorFunctionFieldNeedsParens => {
            "calling a function-valued member requires parentheses: use `(obj.f)(...)` or `(t.0)(...)`"
        },
        TirTypeErrorTupleElementNotAssignable => {
            "cannot replace a tuple slot: tuple slots are immutable; build a new tuple instead (mutable children can still be changed)"
        },
        let e: TirTypeErrorTupleIndexOutOfRange => {
            let variant = e.variant;
            let target = if (variant != null) {
                ``\`${spell(variant)}`, a variant of `${spell(e.tuple)}`: every tuple variant must have the slot``
            } else {
                ``\`${spell(e.tuple)}```
            };
            let arity = match (e.tuple) {
                let t: root.types.TyTuple => ` (arity ${t.items.length()})`,
                _ => "",
            };
            let start = if (e.index < 0) {
                "; tuple indices start at 0"
            } else {
                ""
            };
            `tuple slot ${e.index} is out of range for ${target}${arity}${start}`
        },
        let e: TirTypeErrorTupleTypeTestNeverMatches => {
            ``this pattern tests whether the tuple's type is `${spell(e.tested)}`, which can never match a `${spell(e.scrutinee)}`; to compare values use `==`, or add a binding or `_` to destructure the tuple``
        },
        TirTypeErrorPositionalArgumentAfterNamed => {
            "positional arguments cannot appear after named arguments"
        },
        let e: TirTypeErrorDuplicateNamedArgument => ``duplicate named argument `${e.name}```,
        let e: TirTypeErrorUnknownNamedArgument => ``unknown named argument `${e.name}```,
        TirTypeErrorTraceUnsupportedCall => {
            "`$trace` is not supported on native, host, or compiler-intrinsic calls"
        },
        TirTypeErrorTraceOpaqueValue => {
            "trace options, reservations, and span IDs are opaque; use their public methods"
        },
        let e: TirTypeErrorDefaultedParamPassedPositionally => {
            ``defaulted parameter `${e.name}` must be passed by name``
        },
        let e: TirTypeErrorMissingRequiredArgument => ``missing required argument `${e.name}```,
        let e: TirTypeErrorRequiredParamAfterDefault => {
            ``required parameter `${e.name}` cannot appear after a defaulted parameter``
        },
        TirTypeErrorSelfParamDefault => "`self` cannot have a default value",
        let e: TirTypeErrorDefaultParamForwardReference => {
            ``default for parameter `${e.param}` cannot reference later parameter `${e.referenced}```
        },
        let e: TirTypeErrorImplicitUnit => {
            let (let before, let after) = implicit_unit_form_around_expected(e.form, e.admits_unit);
            ``${before}`${spell(e.expected)}`${after}``
        },
        let e: TirTypeErrorAliasCycle => `recursive type alias cycle: ${e.name}`,
        let e: TirTypeErrorClassCycle => `class cycle: ${e.cycle_path}`,
        let e: TirTypeErrorNonExhaustiveMatch => {
            ``non-exhaustive match on `${spell(e.scrutinee_type)}`; missing: ${e.missing_cases.join(", ")}``
        },
        let e: TirTypeErrorNonExhaustiveCatchAll => {
            ``non-exhaustive ${e.keyword} on `${spell(e.caught_type)}`; missing: ${e.missing_cases.join(", ")}``
        },
        TirTypeErrorUnreachableArm => "unreachable arm",
        let e: TirTypeErrorOrPatternBindingTypeMismatch => {
            ``Or-pattern alternatives bind `${e.name}` with conflicting types: `${spell(e.first_type)}` vs `${spell(e.other_type)}```
        },
        let e: TirTypeErrorGenericClassDestructureRequiresTypeArgs => {
            ``generic class destructure `${e.class_name} { ... }` must specify type arguments``
        },
        TirTypeErrorRestSubPatternNotBinding => {
            "rest pattern `..` can only carry a binding; write `..let name` or `..let name: T[]`"
        },
        let e: TirTypeErrorRefutablePatternInLet => {
            ``refutable pattern in ${irrefutable_context_kind_as_str(e.context)} binding; refutable patterns belong in `match```
        },
        TirTypeErrorIrrefutablePatternInIfLet => {
            "irrefutable `if let` pattern; the `else` branch is unreachable — use a plain `let` binding instead"
        },
        let e: TirTypeErrorLetElseMustDiverge => {
            ``\`let … else` requires a diverging else block (`return`, `throw`, `break`, or `continue`); got `${spell(e.got)}```
        },
        TirTypeErrorIrrefutablePatternInLetElse => {
            "irrefutable `let … else` pattern; the `else` branch is unreachable — use a plain `let` binding instead"
        },
        TirTypeErrorIrrefutablePatternInWhileLet => {
            "irrefutable `while let` pattern; the loop never exits by pattern failure — use a plain `while`/`loop` instead"
        },
        let e: TirTypeErrorDeferControlFlowEscape => {
            ``\`${e.keyword}` cannot leave a `defer` body; only `throw` may propagate out of a defer``
        },
        let e: TirTypeErrorLoopControlOutsideLoop => {
            match (e.barrier) {
                LoopControlBarrier.NoLoop => ``\`${e.keyword}` outside of a loop``,
                LoopControlBarrier.Lambda => {
                    ``\`${e.keyword}` cannot leave a loop from inside a lambda body``
                },
                LoopControlBarrier.Template => {
                    ``\`${e.keyword}` cannot leave a loop from inside a template interpolation``
                },
            }
        },
        let e: TirTypeErrorLoopControlInLoopHeader => {
            let slot = match (e.slot) {
                LoopHeaderSlot.WhileCondition => "a `while` condition",
                LoopHeaderSlot.WhileLetScrutinee => "a `while let` scrutinee",
                LoopHeaderSlot.ForUpdate => "a `for` loop's update expression",
            };
            ``\`${e.keyword}` cannot appear in ${slot}; a loop is left from its body - move the `${e.keyword}` there``
        },
        let e: TirTypeErrorInvalidCatchBindingType => {
            ``invalid catch binding type `${e.type_name}`; use a concrete type instead``
        },
        let e: TirTypeErrorThrowsContractViolation => {
            ``declared throws is `${spell(e.declared)}`, but this function may also throw `${spell(e.extra)}```
        },
        let e: TirTypeErrorCallbackThrowsContractViolation => {
            let callback_name = e.callback_name;
            let head = ``this body may throw through callback `${callback_name}`, but declared throws is `${spell(e.declared)}`. ``;
            let concrete_throws = e.concrete_throws;
            if (concrete_throws != null) {
                ``${head}Add `throws ${spell(concrete_throws)}` to the callback, catch the call, or make the callback non-throwing.``
            } else {
                ``${head}The callback type does not say what it can throw. If `${callback_name}` is an infallible host callback, annotate it with `throws never`; otherwise catch the call or let the enclosing function declare/propagate the callback's throws.``
            }
        },
        let e: TirTypeErrorExtraneousThrowsDeclaration => {
            `extraneous throws declaration: ${e.extra_types.join(", ")}`
        },
        let e: TirTypeErrorImpreciseUnknownThrows => {
            let inferred_ty = e.inferred;
            if (inferred_ty == null) {
                "`throws unknown` is unnecessary: BAML infers thrown types automatically, and this function does not throw. Remove the declaration; write an explicit `throws` type only to bound what may escape"
            } else {
                let inferred = spell(inferred_ty);
                if (e.needs_declaration) {
                    ``\`throws unknown` is imprecise: this function throws `${inferred}`; write `throws ${inferred}```
                } else {
                    ``\`throws unknown` is imprecise: this function only throws `${inferred}`. BAML infers thrown types automatically, so remove the declaration; write `throws ${inferred}` only to explicitly bound what may escape``
                }
            }
        },
        let e: TirTypeErrorCannotInferTypeParameter => ``cannot infer type parameter `${e.name}```,
        let e: TirTypeErrorCannotInferAssociatedType => {
            ``cannot infer associated type `${e.name}`; write it on the pattern's interface``
        },
        let e: TirTypeErrorConflictingTypeArguments => {
            ``cannot infer type parameter `${e.name}`: its arguments give it the conflicting types `${spell(e.first)}` and `${spell(e.second)}`; write the type argument or annotate the expected type``
        },
        let e: TirTypeErrorWrongNumberOfTypeArgs => {
            ``type `${e.type_name}` expects ${e.expected} type argument(s), got ${e.got}``
        },
        let e: TirTypeErrorWrongTypeArgArity => {
            ``function `${e.callee_name}` expects ${e.expected} type argument(s), got ${e.got}``
        },
        let e: TirTypeErrorScopedTypeEscapesBlock => {
            root.diagnostics.scoped_type_escapes_block(e.name).message
        },
        let e: TirTypeErrorTypeIsNotGeneric => {
            ``${e.kind} `${e.type_name}` is not generic and cannot take type arguments``
        },
        let e: TirTypeErrorGenericFunctionValueNotSpecialized => {
            write_generic_function_value_diagnostic(
                e.name,
                e.reference,
                e.had_expected_type,
                e.generic_params,
                e.binding_name,
                e.function_shape,
                e.annotation_example,
                e.specialization_example,
                e.specialization_syntax_available,
            )
        },
        let e: TirTypeErrorTypeParamShadowed => {
            ``type parameter `${e.param_name}` on method shadows the same parameter on ${shadowed_param_owner_display(e.owner)} `${e.type_name}`. Please use a different name for the type parameter.``
        },
        let e: TirTypeErrorTypeParamShadowedImplParam => {
            ``type parameter `${e.param_name}` on method shadows the same parameter on the enclosing `implements` block. Please use a different name for the type parameter.``
        },
        let e: TirTypeErrorDuplicateGenericParam => {
            ``generic type parameter `${e.name}` is declared more than once``
        },
        let e: TirTypeErrorDuplicateAssociatedType => {
            ``associated type `${e.name}` is declared more than once on this interface``
        },
        let e: TirTypeErrorAssociatedTypeConflictsWithGenericParam => {
            ``associated type `${e.name}` conflicts with the interface's generic parameter of the same name. Please use a different name for one of them.``
        },
        let e: TirTypeErrorCannotInferLambdaParamType => {
            ``cannot infer type of lambda parameter `${e.param_name}` — add a type annotation or provide context``
        },
        let e: TirTypeErrorUnnecessaryOptionalChaining => {
            // Build the rewrite from the base/suffix boundary so the diagnosed
            // `?.` is stripped, not the first one in the string.
            let base = e.base;
            let suffix = e.expr.slice(base.length(), e.expr.length());
            let call = root.base.strip_prefix(suffix, "?.(");
            let index = root.base.strip_prefix(suffix, "?.[");
            let member = root.base.strip_prefix(suffix, "?.");
            let dotted = if (call != null) {
                `${base}(${call}`
            } else if (index != null) {
                `${base}[${index}`
            } else if (member != null) {
                `${base}.${member}`
            } else {
                e.expr.replace("?.", ".")
            };
            ``did you mean `${dotted}`? `${e.expr}` is unnecessary, because `${base}` cannot be null``
        },
        let e: TirTypeErrorUnnecessaryNullCoalesce => {
            ``did you mean `${e.lhs}`? `${e.expr}` is unnecessary, because `${e.lhs}` cannot be null``
        },
        let e: TirTypeErrorSuggestNullCoalesce => {
            ``did you mean `${e.lhs} ?? ${e.rhs}`? BAML uses `??` instead of `||` for null coalescing``
        },
        let e: TirTypeErrorNullCoalesceWithNull => {
            ``did you mean `${e.lhs}`? `... ?? null` is unnecessary because `${e.lhs}` is already nullable``
        },
        let e: TirTypeErrorNullableMemberAccess => {
            // `member` is `.name` or `[...]`: the suggestion inserts `?`.
            let suggested = if (e.member.starts_with(".")) {
                `${e.base}?${e.member}`
            } else {
                `${e.base}?.${e.member}`
            };
            ``did you mean `${suggested}`? `${e.expr}` does not handle the case when `${e.base}` is null``
        },
        let e: TirTypeErrorTaggedTagNotAFunction => {
            ``\`${e.name}` is not a function — a tagged-template tag must be a function marked `//baml:tagged_string```
        },
        let e: TirTypeErrorTaggedTagNotMarked => {
            ``\`${e.name}` is not a tagged-string function — only functions marked `//baml:tagged_string` can be used as a tagged-template tag``
        },
        let e: TirTypeErrorTaggedTagBadBodyParam => {
            ``the first parameter of tagged-string function `${e.name}` must be `body: (...) -> baml.TaggedString```
        },
        let e: TirTypeErrorInterpolatedValueMaybeNull => {
            match (e.ty) {
                // A value that is only ever `null` has nothing to coalesce:
                // it is a unit expression, written for its effect.
                root.types.TyNull => {
                    "cannot interpolate a value of type `null`; to run the expression without rendering it, end it with `;`"
                },
                _ => {
                    ``cannot interpolate a value of type `${spell(e.ty)}` — it may be null; coalesce with `?? "…"` or unwrap it first``
                },
            }
        },
        TirTypeErrorOutputFormatNotCalled => "`output_format` must be called; use `output_format()`",
        let e: TirTypeErrorUncalledFunctionInCondition => ``function `${e.name}` is always truthy``,
        let e: TirTypeErrorConditionAlwaysConstant => {
            let (let always, let never_) = if (e.always_true) {
                ("truthy", "falsy")
            } else {
                ("falsy", "truthy")
            };
            let ty = e.ty;
            if (ty != null) {
                ``this condition is always ${always}: a value of type `${spell(ty)}` can never be ${never_}``
            } else {
                `this condition is always ${always}`
            }
        },
        let e: TirTypeErrorRoleMarkerInUntaggedTemplate => {
            ``cannot interpolate `${spell(e.ty)}` into an untagged string; a role marker only starts a message when interpolated directly into a `prompt` template\nhelp: interpolate it in the `prompt` template itself (use `\${for}` there to repeat turns), or use `.name` for the role's text``
        },
        let e: TirTypeErrorAmbiguousInterfaceMethod => {
            let method_name = e.method_name;
            let iface_list = e.sources
                .map((n) -> {
                    ``\`${n}```
                })
                .join(", ");
            let hint = e.sources
                .map((n) -> {
                    `obj.as<${n}>.${method_name}()`
                })
                .join(" or ");
            ``method `${method_name}` on class `${e.class_name}` is declared by multiple interfaces: ${iface_list}; unqualified calls will be ambiguous — use ${hint}``
        },
        let e: TirTypeErrorAmbiguousInterfaceField => {
            let field_name = e.field_name;
            let iface_list = e.sources
                .map((n) -> {
                    ``\`${n}```
                })
                .join(", ");
            let hint = e.sources
                .map((n) -> {
                    `obj.as<${n}>.${field_name}`
                })
                .join(" or ");
            ``field `${field_name}` on class `${e.class_name}` is ambiguous because it is declared by multiple interfaces: ${iface_list}; use ${hint}``
        },
        let e: TirTypeErrorInterfaceFieldRequiresProjection => {
            ``field `${e.field_name}` is an interface field on `${e.interface_name}`, not a concrete field on class `${e.class_name}`; use obj.as<${e.interface_name}>.${e.field_name}``
        },
        let e: TirTypeErrorInterfaceFieldRequiresQualifiedConstruction => {
            ``interface-qualified field `${e.field_name}` cannot be used in a class constructor; use class field `${e.qualified_name}```
        },
        let e: TirTypeErrorInvalidInterfaceUpcastTarget => {
            ``\`.as<T>` target must be an interface, got `${spell(e.target)}```
        },
        let e: TirTypeErrorInterfaceMemberRequiresReceiver => {
            ``interface member `${e.member_name}` on `${e.interface_name}` must be accessed through a value; use value.as<${e.interface_name}>.${e.member_name}``
        },
        let e: TirTypeErrorSelflessInstanceMember => {
            let interface_name = e.interface_name;
            let method_name = e.method_name;
            if (interface_name != null) {
                ``method `${method_name}` on interface `${interface_name}` has no `self` receiver, so it cannot be called on a value — qualify the type instead: `(SomeImplementor as ${interface_name}).${method_name}(...)```
            } else {
                // No interface: a class-inherent static, whose spelling is
                // the owning type, not a qualifier.
                ``method `${method_name}` has no `self` receiver, so it cannot be called on a value — qualify the type instead: `TypeName.${method_name}(...)```
            }
        },
        let e: TirTypeErrorErasedSelfMethodValue => {
            ``cannot take `${e.interface_name}.${e.method_name}` as a function value with `Self` = `${spell(e.self_ty)}`: the implementation is only known from a receiver at each call — call the method directly, or name a concrete implementor (`(SomeImplementor as ${e.interface_name}).${e.method_name}`)``
        },
        let e: TirTypeErrorSelflessMethodNeedsConcreteSelf => {
            ``method `${e.method_name}` on interface `${e.interface_name}` has no `Self`-typed parameter to dispatch on, so `Self` must be a concrete implementor type — `${spell(e.self_ty)}` does not name one; write `(SomeImplementor as ${e.interface_name}).${e.method_name}```
        },
        let e: TirTypeErrorInvalidSelfCallThroughInterface => {
            let position = match (e.position) {
                SelfCallPosition.Parameter => "more than one parameter, or nested in a parameter",
                SelfCallPosition.OptionalParameter => {
                    "a parameter with a default, which a call may omit"
                },
                SelfCallPosition.NestedInReturn => {
                    "its return/throws type, nested in a container (e.g. `Self[]`)"
                },
            };
            ``method `${e.method_name}` on interface `${e.interface_name}` uses `Self` in ${position}, so it requires a concrete `Self`, not an erased one (an interface-existential or union)``
        },
        let e: TirTypeErrorDefaultOnRequiredMethod => {
            ``\`default.${e.method_name}()` is invalid: method `${e.method_name}` on interface `${e.interface_name}` has no default body``
        },
        TirTypeErrorBareDefaultKeyword => {
            "`default` may only be used to call an interface default method, as `default.method(...)`"
        },
        let e: TirTypeErrorTypeDoesNotImplementInterface => {
            ``type `${spell(e.value_type)}` does not implement interface `${spell(e.interface_)}```
        },
        let e: TirTypeErrorBlanketBoundNotSatisfied => {
            ``type `${spell(e.value_type)}` does not satisfy the bound `${spell(e.bound)}` required by the blanket `implements` rule``
        },
        let e: TirTypeErrorAmbiguousImplementation => {
            ``type annotations needed: more than one implementation could make type `${spell(e.value_type)}` implement `${spell(e.interface_)}```
        },
        let e: TirTypeErrorIntegerLiteralOutOfRange => {
            ``integer literal `${e.value}` is out of range for `int` (which holds -4611686018427387904 to 4611686018427387903); append `n` to write it as a `bigint```
        },
        let e: TirTypeErrorGenericBoundNotInterface => {
            ``generic bound `${spell(e.bound)}` is not an interface; bounds must be interfaces``
        },
        let e: TirTypeErrorBuiltinInterfaceNotImplementable => {
            ``\`${vp.path(e.interface_)}` is a compiler builtin and cannot be implemented by hand; every function type implements it automatically``
        },
        let e: TirTypeErrorBuiltinInterfaceNotABound => {
            let interface_ = vp.path(e.interface_);
            ``\`${interface_}` cannot be used as a generic bound; use it as a value type instead (e.g. `f: ${interface_}`)``
        },
        let e: TirTypeErrorBoundedTypeArgNotConcrete => {
            let bound = e.bound
                .map((iface) -> {
                    interface_spell(iface, vp)
                })
                .join(" & ");
            ``type argument `${spell(e.arg)}` is not concrete; a type parameter bounded by `${bound}` requires a concrete type that implements it (a union, an interface, `unknown` or `never` has no single runtime type to dispatch on, and a literal type is a subset of its concrete type, not one)``
        },
        let e: TirTypeErrorMissingAssociatedTypeBindings => {
            let interface_ = vp.path(e.interface_);
            let missing = e.missing
                .map((name) -> {
                    ``\`${name}```
                })
                .join(", ");
            ``interface-existential type `${interface_}` must specify its associated type(s) ${missing} (only associated types with a default may be omitted; an interface *bound* `<T extends ${interface_}>` does not require them)``
        },
        let e: TirTypeErrorInterfaceProjectionBase => {
            let interface_ = vp.path(e.interface_);
            ``cannot project `${e.member}` directly off interface `${interface_}`: a projection's base is an implementor type, a bounded type variable, or `Self` — to name the interface explicitly, write a qualified projection (`(Base as ${interface_}).${e.member}`)``
        },
        let e: TirTypeErrorAmbiguousInterfacePatternBindings => {
            let interface_ = vp.path(e.interface_);
            let candidates = e.candidates
                .map((ty) -> {
                    ``\`${spell(ty)}```
                })
                .join(" and ");
            ``cannot infer the associated type bindings for the bare interface pattern `${interface_} { … }`: the scrutinee admits ${candidates}; write the bindings explicitly (`${interface_}<…> { … }`)``
        },
        let e: TirTypeErrorMissingInterfaceMethod => {
            ``missing implementation of method `${e.method}` required by interface `${vp.path(e.interface_)}```
        },
        let e: TirTypeErrorGenericSysOpMethodInInterfaceImpl => {
            ``\`$rust_io_function` method `${e.method}` implementing interface `${vp.path(e.interface_)}` may not declare its own generic parameters: a sys-op reached through interface dispatch cannot carry method-level type arguments``
        },
        let e: TirTypeErrorOutOfBodyImplementsFieldInterface => {
            ``interface `${vp.path(e.interface_)}` declares fields and can only be implemented in the class body, not out-of-body``
        },
        let e: TirTypeErrorUnknownInterfaceMember => {
            ``\`${e.member}` is not a method of interface `${vp.path(e.interface_)}```
        },
        let e: TirTypeErrorMissingInterfaceField => {
            ``missing field `${e.field}` required by interface `${vp.path(e.interface_)}` (add a class field named `${e.field}` or link one with `${e.field} as <class_field>`)``
        },
        let e: TirTypeErrorInterfaceFieldTypeMismatch => {
            ``field `${e.field}` has type ${spell(e.got)}, but interface `${vp.path(e.interface_)}` declares it as ${spell(e.expected)}``
        },
        let e: TirTypeErrorInterfaceMethodSignatureMismatch => {
            ``method `${e.method}` has signature ${spell(e.got)}, which does not conform to interface `${vp.path(e.interface_)}`'s declared ${spell(e.expected)}``
        },
        let e: TirTypeErrorInterfaceMethodAddsGenericBound => {
            ``method `${e.method}` requires `${e.param}: ${interface_spell(e.bound, vp)}`, but interface `${vp.path(e.interface_)}`'s `${e.method}` declares no such bound — an implementation may not add requirements the interface does not``
        },
        let e: TirTypeErrorMissingRequiredInterface => {
            ``implementing `${vp.path(e.interface_)}` also requires implementing `${interface_spell(e.required, vp)}```
        },
        let e: TirTypeErrorImplTargetNotInterface => {
            ``\`${e.name}` is not an interface and cannot be implemented``
        },
        let e: TirTypeErrorImplTargetNotConcrete => {
            ``cannot implement an interface for ${spell(e.target)} — the target must be a single concrete type``
        },
        let e: TirTypeErrorUnconstrainedImplTypeParam => {
            ``generic parameter `${e.name}` is not constrained by the `for` type or interface arguments, so it can never be inferred``
        },
        let e: TirTypeErrorImplViolatesOrphanRule => {
            let param = e.uncovered_param;
            if (param != null) {
                ``orphan rule: implementing the foreign interface `${vp.path(e.interface_)}` requires a local type before the uncovered parameter `${param}```
            } else {
                ``orphan rule: a foreign interface `${vp.path(e.interface_)}` can only be implemented for a local type``
            }
        },
        let e: TirTypeErrorUnknownInterfaceFieldLink => {
            ``interface `${vp.path(e.interface_)}` has no field `${e.field}` to link``
        },
        let e: TirTypeErrorUnknownClassFieldInInterfaceLink => {
            ``class `${e.class_}` has no field `${e.field}` to link for interface `${vp.path(e.interface_)}```
        },
        let e: TirTypeErrorDuplicateInterfaceFieldLink => {
            ``field `${e.field}` of interface `${vp.path(e.interface_)}` is linked more than once``
        },
        let e: TirTypeErrorUnknownAssociatedTypeBinding => {
            ``unknown associated type `${e.name}` for interface `${vp.path(e.interface_)}```
        },
        let e: TirTypeErrorDuplicateAssociatedTypeBinding => {
            ``associated type `${e.name}` of interface `${vp.path(e.interface_)}` is bound more than once``
        },
        let e: TirTypeErrorMissingImplAssociatedTypeBinding => {
            ``missing associated type binding `${e.name}` for interface `${vp.path(e.interface_)}` (add `type ${e.name} = …` to the implements block)``
        },
        let e: TirTypeErrorAssociatedTypeBindingsOnImplementsTarget => {
            ``associated type bindings are not allowed on an `implements` target for `${vp.path(e.interface_)}`; bind them inside the block with `type Name = …```
        },
        let e: TirTypeErrorAssociatedTypeBindingViolatesBound => {
            ``associated type binding `${e.name}` = `${spell(e.binding)}` does not implement bound `${interface_spell(e.bound, vp)}` declared by interface `${vp.path(e.interface_)}```
        },
        let e: TirTypeErrorSelfInInterfaceField => {
            ``\`Self` is not allowed in the type of interface field `${e.field}` on `${vp.path(e.interface_)}`; name the interface itself for recursion``
        },
        let e: TirTypeErrorSelfInAssociatedTypeDefault => {
            let interface_ = vp.path(e.interface_);
            let associated_type = e.associated_type;
            ``\`Self` is not allowed in the default for associated type `${associated_type}` on `${interface_}`: `Self` names each implementor, so it has no meaning where `${interface_}` is used as an interface-existential type and the implementor is hidden. Drop the default and let each `implements` block bind `${associated_type}` (uses as a bound are unaffected; uses as an interface-existential type then write `${interface_}<…, ${associated_type} = …>`). A `Self.Assoc` projection is allowed``
        },
        let e: TirTypeErrorInterfaceRequiresNonInterface => {
            ``interface `${vp.path(e.interface_)}` cannot require `${spell(e.target)}`, which is not an interface``
        },
        let e: TirTypeErrorInterfaceRequiresCycle => {
            ``interface `requires` cycle: ${e.chain.join(" → ")}``
        },
        let e: TirTypeErrorAssociatedTypeDefaultViolatesBound => {
            ``associated type default `${e.name}` = `${spell(e.default_)}` does not implement bound `${interface_spell(e.bound, vp)}` declared by interface `${vp.path(e.interface_)}```
        },
        TirTypeErrorCyclicImplHeader => {
            "a concrete associated-type projection in an impl header is illegal here (it resolves through this impl); name the resolved type directly"
        },
        let e: TirTypeErrorInterfaceMethodMissingThrows => {
            ``interface method `${e.method}` on `${vp.path(e.interface_)}` must declare an explicit `throws` clause``
        },
        TirTypeErrorFunctionTypeMissingThrows => {
            "function type must declare an explicit `throws` clause; add `throws never` if calling it cannot throw"
        },
        let e: TirTypeErrorInitIoNotAllowed => {
            let kind = if (e.is_client) {
                "client"
            } else {
                "global"
            };
            let via = e.via;
            let reach = if (via != null) {
                ``reaches `${e.sysop}`, which performs io, through `${via}```
            } else {
                ``calls `${e.sysop}`, which performs io``
            };
            ``${kind} `${e.declaration}` ${reach} — top-level declarations are evaluated at startup (`$init`), where io is unavailable; resolve at request time instead — e.g. `env.X`, a late-bound reference read only when the request is made``
        },
        let e: TirTypeErrorInitSuspendNotAllowed => {
            let kind = if (e.is_client) {
                "client"
            } else {
                "global"
            };
            let via = e.via;
            let reach = if (via != null) {
                ``reaches `${e.operation}` through `${via}```
            } else {
                ``uses `${e.operation}```
            };
            ``${kind} `${e.declaration}` ${reach} — top-level declarations are evaluated once at startup (`$init`), before anything can be scheduled or waited on; compute the value synchronously, or move the concurrent work into the function that needs it``
        },
        let e: TirTypeErrorLlmOutputMemberDropped => {
            let why = if (e.no_values) {
                "has no values"
            } else {
                "has no JSON form"
            };
            let head = ``\`${spell(e.member)}` ${why}, so the model can never return it``;
            let kept = e.kept;
            if (kept != null) {
                ``${head}. `${e.function_}` can only return `${spell(kept)}```
            } else {
                ``${head}, and every call to `${e.function_}` fails``
            }
        },
        let e: TirTypeErrorLlmOutputFieldAlwaysNull => {
            ``the model can never fill `${e.field}`, so it is always null. Mark it @skip if that is intended``
        },
        let e: TirTypeErrorJsonAttributesWithOverride => {
            ``\`${e.name}` implements `${e.interface_}`, so its `@json` attributes would be ignored. Remove the attributes or the override``
        },
        let e: TirTypeErrorJsonAttributeSkipped => {
            ``\`@skip` leaves `${e.field}` out of JSON, which its `@json` role needs``
        },
        let e: TirTypeErrorJsonFallbackNoTag => {
            ``\`${e.class_}` has a `@json.fallback` field, so it needs a literal field to name the union's tag, such as `type: "UNKNOWN"```
        },
        let e: TirTypeErrorJsonFallbackOverlap => {
            ``no literal field tells `${spell(e.first)}` from `${spell(e.second)}`, so this union can't pick between them. Give one of them a literal the other doesn't have``
        },
        let e: TirTypeErrorJsonRestFieldType => {
            ``\`${e.attribute}` needs a `map<string, json>` field, and `${e.field}` is not one``
        },
        let e: TirTypeErrorJsonRestRenamed => {
            ``\`${e.field}` holds keys of the object through `${e.attribute}`, so it has no key for `@json.rename` to set``
        },
        let e: TirTypeErrorJsonRestRepeated => {
            ``\`${e.class_}` can have only one `@json.flatten` or `@json.fallback` field``
        },
        let e: TirTypeErrorJsonFallbackFieldNotLiteral => {
            ``\`${e.class_}` has a `@json.fallback` field, so its other fields must be literals, and `${e.field}` is not one``
        },
        let e: TirTypeErrorJsonFallbackUntaggedMember => {
            ``\`${e.fallback}` is this union's `@json.fallback` member, but `${spell(e.member)}` has no literal field for its tag, so the union can't tell when an object is one. Add a literal field such as `type: "name"`, or remove `@json.fallback```
        },
        let e: TirTypeErrorInitThrowNotHandled => {
            let kind = if (e.is_client) {
                "client"
            } else {
                "global"
            };
            ``${kind} `${e.declaration}` can throw `${spell(e.thrown)}` while it is initialized — globals are evaluated once, at startup, and an uncaught throw there stops the program from starting; if that is not intended, handle it in the initializer with `catch```
        },
        let e: TirTypeErrorAssignmentToGlobal => {
            let kind = if (e.is_client) {
                "client"
            } else {
                "global variable"
            };
            ``cannot assign to ${kind} `${e.name}` — top-level bindings are set once, at startup, and shared by every call, so they cannot be reassigned; declare a local (`let x = ${e.name};`) to work with a copy of the binding, or change what it holds through its fields or elements``
        },
        let e: TirTypeErrorReturnOutsideFunctionBody => {
            match (e.context) {
                let c: ReturnContextGlobalInitializer => {
                    ``\`return` is not allowed in the initializer of global `${c.name}` — an initializer is an expression, not a function body; its value is its last expression (move early exits into a helper function)``
                },
                ReturnContextParameterDefault => {
                    "`return` is not allowed in a parameter default — a default is an expression evaluated when the argument is omitted, not part of the function body; its value is its last expression"
                },
                ReturnContextTemplateInterpolation => {
                    "`return` is not allowed in a template interpolation — the interpolation runs when the template is rendered, not as part of the enclosing function; its value is its last expression"
                },
            }
        },
        let e: TirTypeErrorGlobalInitializationCycle => {
            let first = e.chain.at(0) ?? "";
            let path = e.chain
                .map((name) -> {
                    ``\`${name}```
                })
                .join(" → ");
            ``initialization cycle: global `${first}` needs its own value to be initialized (${path}) — globals are initialized once, at startup, in dependency order, and no order can satisfy a cycle``
        },
    }
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::DiagnosticSeverity @ d9be6853b
// Diagnostic severity used by the type checker's diagnostics.
enum DiagnosticSeverity {
    Error,
    Warning,
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::RelatedLocation @ d9be6853b
// A location that may be in the current scope, another scope, or another
// file, by stable id; resolved to a range by `resolve_related_location`.
type RelatedLocation = RelatedLocationExpr
    | RelatedLocationExprSegment
    | RelatedLocationStmt
    | RelatedLocationParam
    | RelatedLocationClassField
    | RelatedLocationItem;

// Expression in the same scope's body.
class RelatedLocationExpr {
    value: int,
}

// A specific segment of a multi-segment `Path` expression.
class RelatedLocationExprSegment {
    expr: int,
    segment: int,
}

// Statement in the same scope's body.
class RelatedLocationStmt {
    value: int,
}

// A function parameter (possibly in another file), by function and index.
class RelatedLocationParam {
    function_: int,
    index: int,
}

// A class field definition.
class RelatedLocationClassField {
    class_: int,
    name: string,
}

// Any top-level item definition (class, enum, function, etc.).
class RelatedLocationItem {
    value: root.hir.Definition,
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::RelatedNote @ d9be6853b
// Also `RelatedNote::new` (a class literal).
class RelatedNote {
    location: RelatedLocation,
    message: string,
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::removed_reflect_spelling @ d9be6853b
// Recognize a path that reflection used to answer to and no longer does
// (`baml.reflect.X`, `type.of<T>()`, a bare `type`); returns the error that
// names the replacement, or null for a genuinely unknown name.
function removed_reflect_spelling(name: string) -> TirTypeError? throws never {
    let type_rest = root.base.strip_prefix(name, "type.");
    let (let replacement, let mentions_type_keyword) = if (name == "type") {
        ("reflect.Type", true)
    } else if (type_rest != null) {
        (`reflect.Type.${type_rest}`, true)
    } else if (name == "baml.reflect") {
        ("reflect", false)
    } else {
        let rest = root.base.strip_prefix(name, "baml.reflect.")
            ?? return null;
        (`reflect.${rest}`, false)
    };
    TirTypeErrorRemovedReflectSpelling {
        written: name,
        replacement: replacement,
        mentions_type_keyword: mentions_type_keyword,
    }
}

// port: strsim/src/lib.rs::generic_jaro @ 0.11.1
// The Jaro similarity of two character sequences.
function jaro(a: string[], b: string[]) -> float throws never {
    let a_len = a.length();
    let b_len = b.length();
    if (a_len == 0 && b_len == 0) {
        return 1.0;
    }
    if (a_len == 0 || b_len == 0) {
        return 0.0;
    }
    let longer = if (a_len > b_len) {
        a_len
    } else {
        b_len
    };
    let search_range = if (longer / 2 > 0) {
        longer / 2 - 1
    } else {
        0
    };
    let a_flags = a.map((_) -> {
        false
    });
    let b_flags = b.map((_) -> {
        false
    });
    let matches = 0;
    for (let i = 0; i < a_len; i += 1) {
        let min_bound = if (i > search_range) {
            i - search_range
        } else {
            0
        };
        let max_bound = if (b_len < i + search_range + 1) {
            b_len
        } else {
            i + search_range + 1
        };
        for (let j = min_bound; j < max_bound; j += 1) {
            if (a[i] == b[j] && !b_flags[j]) {
                a_flags[i] = true;
                b_flags[j] = true;
                matches += 1;
                break;
            }
        }
    }
    if (matches == 0) {
        return 0.0;
    }
    let transpositions = 0;
    let j = 0;
    for (let i = 0; i < a_len; i += 1) {
        if (!a_flags[i]) {
            continue;
        }
        while (!b_flags[j]) {
            j += 1;
        }
        if (a[i] != b[j]) {
            transpositions += 1;
        }
        j += 1;
    }
    transpositions = transpositions / 2;
    let m = matches * 1.0;
    (m / a_len + m / b_len + (matches - transpositions) / m) / 3.0
}

// port: strsim/src/lib.rs::jaro_winkler @ 0.11.1
// Jaro similarity with a boost for a common prefix of up to four characters.
function jaro_winkler(a: string, b: string) -> float throws never {
    let a_chars = a.chars();
    let b_chars = b.chars();
    let sim = jaro(a_chars, b_chars);
    if (sim <= 0.7) {
        return sim;
    }
    let prefix_length = 0;
    while (
        prefix_length < 4
            && prefix_length < a_chars.length()
            && prefix_length < b_chars.length()
            && a_chars[prefix_length] == b_chars[prefix_length]
    ) {
        prefix_length += 1;
    }
    sim + 0.1 * prefix_length * (1.0 - sim)
}

// port: core::str::to_ascii_lowercase @ d9be6853b
// ASCII letters lowercased, everything else kept.
function to_ascii_lowercase(text: string) -> string throws never {
    text.chars()
        .map((c) -> {
            if (c.is_ascii_uppercase()) {
                c.to_lower_case()
            } else {
                c
            }
        })
        .join("")
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::similar_name_suggestions @ d9be6853b
// "Did you mean" candidates for an unknown member/field name: fuzzy-scored
// against the declared names, best first, at most three.
function similar_name_suggestions(
    unknown_name: string,
    candidates: string[],
) -> string[] throws never {
    let needle = to_ascii_lowercase(unknown_name);
    if (needle.length() == 0) {
        return [];
    }
    let scored: (float, string)[] = candidates
        .map((candidate) -> {
            let candidate_lower = to_ascii_lowercase(candidate);
            let score = jaro_winkler(needle, candidate_lower);
            if (candidate_lower.starts_with(needle) || needle.starts_with(candidate_lower)) {
                score += 0.15;
            }
            if (candidate_lower.includes(needle) || needle.includes(candidate_lower)) {
                score += 0.10;
            }
            let capped = if (score < 1.0) {
                score
            } else {
                1.0
            };
            (capped, candidate)
        })
        .filter((entry) -> {
            entry.0 >= 0.80
        });
    scored
        .sort_by((a, b) -> {
            if (a.0 > b.0) {
                baml.ops.Ordering.Less
            } else if (a.0 < b.0) {
                baml.ops.Ordering.Greater
            } else {
                a.1.cmp(b.1)
            }
        })
        .slice(0, 3)
        .map((entry) -> {
            entry.1
        })
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::DiagnosticLocation @ d9be6853b
// Primary location for a diagnostic: an expression, a statement, or a raw
// source span (for type annotations that lack an expression id).
type DiagnosticLocation = DiagnosticLocationExpr
    | DiagnosticLocationExprMember
    | DiagnosticLocationExprSegment
    | DiagnosticLocationLambdaParameter
    | DiagnosticLocationStmt
    | DiagnosticLocationTypeAnnot
    | DiagnosticLocationPat
    | DiagnosticLocationBodyTypeRef
    | DiagnosticLocationObjectFieldName
    | DiagnosticLocationSpan;

class DiagnosticLocationExpr {
    value: int,
}

// The member-name portion of a `MemberAccess` expression (after the dot).
class DiagnosticLocationExprMember {
    value: int,
}

// A specific segment of a multi-segment `Path` expression.
class DiagnosticLocationExprSegment {
    expr: int,
    segment: int,
}

// A lambda parameter name, by its lambda expression and declaration index.
class DiagnosticLocationLambdaParameter {
    expr: int,
    parameter: int,
}

class DiagnosticLocationStmt {
    value: int,
}

class DiagnosticLocationTypeAnnot {
    value: int,
}

// A pattern's span.
class DiagnosticLocationPat {
    value: int,
}

// A written body type reference, resolved through the owning body's source
// map at render time.
class DiagnosticLocationBodyTypeRef {
    value: root.hir.BodyTypeRefId,
}

// The field-name portion of an object-literal entry: the object expression
// and the field's value expression.
class DiagnosticLocationObjectFieldName {
    object: int,
    value: int,
}

class DiagnosticLocationSpan {
    value: root.syntax.TextRange,
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::TirDiagnostic @ d9be6853b
// A single type-check diagnostic with primary location and optional related
// spans.
class TirDiagnostic {
    error: TirTypeError,
    severity: DiagnosticSeverity,
    // Where the error was detected.
    primary: DiagnosticLocation,
    // Secondary spans with explanatory messages.
    related: RelatedNote[],

    // port: baml_compiler2_hir_ty/src/diagnostics.rs::TirDiagnostic::render_with_body_type_refs @ d9be6853b
    // Also `TirDiagnostic::render`, which is this without the body's type-ref
    // span map. Resolves this diagnostic's arena ids to source ranges and
    // renders its message. `source_map` is the body's `AstSourceMap` that owns
    // the expressions and statements `primary` names.
    function render(
        self,
        db: root.hir.Db,
        scope_file: int,
        source_map: root.ast.AstSourceMap?,
        type_ref_spans: root.hir.BodyTypeRefSourceMap? = null,
    ) -> RenderedTirDiagnostic throws never {
        let primary_range = match (self.primary) {
            let l: DiagnosticLocationExpr => source_map?.expr_span(l.value),
            let l: DiagnosticLocationObjectFieldName => {
                source_map?.object_field_name_span(l.object, l.value)
            },
            let l: DiagnosticLocationExprMember => source_map?.member_access_member_span(l.value),
            let l: DiagnosticLocationExprSegment => source_map?.path_segment_span(l.expr, l.segment),
            let l: DiagnosticLocationLambdaParameter => {
                source_map?.lambda_parameter_span(l.expr, l.parameter)
            },
            let l: DiagnosticLocationStmt => source_map?.stmt_span(l.value),
            let l: DiagnosticLocationTypeAnnot => source_map?.type_annotation_span(l.value),
            let l: DiagnosticLocationPat => source_map?.pattern_span(l.value),
            let l: DiagnosticLocationBodyTypeRef => type_ref_spans?.span(l.value),
            let l: DiagnosticLocationSpan => l.value,
        };
        let related: RenderedRelatedInformation[] = self.related.filter_map((note) -> {
            let resolved = resolve_related_location(db, scope_file, source_map, note.location)
                ?? return null;
            RenderedRelatedInformation {
                file_id: resolved.0,
                range: resolved.1,
                message: note.message,
            }
        });
        RenderedTirDiagnostic {
            error: self.error,
            message: tir_type_error_render(self.error, Viewpoint.for_file(db, scope_file)),
            range: primary_range ?? root.syntax.TextRange.empty(0),
            severity: self.severity,
            related: related,
        }
    }
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::resolve_related_location @ d9be6853b
// The file and range a related location names, if it resolves.
function resolve_related_location(
    db: root.hir.Db,
    scope_file: int,
    source_map: root.ast.AstSourceMap?,
    location: RelatedLocation,
) -> (int, root.syntax.TextRange)? throws never {
    match (location) {
        let l: RelatedLocationExpr => {
            if (source_map != null) {
                (scope_file, source_map.expr_span(l.value))
            } else {
                null
            }
        },
        let l: RelatedLocationExprSegment => {
            if (source_map != null) {
                (scope_file, source_map.path_segment_span(l.expr, l.segment))
            } else {
                null
            }
        },
        let l: RelatedLocationStmt => {
            if (source_map != null) {
                (scope_file, source_map.stmt_span(l.value))
            } else {
                null
            }
        },
        let l: RelatedLocationParam => {
            let range = root.hir.function_signature_source_map(db, l.function_).param_spans.at(l.index)
                ?? return null;
            (db.function_locs.get(l.function_).file, range)
        },
        let l: RelatedLocationClassField => {
            let field_index = root.hir.class_data(db, l.class_).fields.find_index((field) -> {
                field.name == l.name
            })
                ?? return null;
            let range = root.hir.class_source_map(db, l.class_).field_name_spans.at(field_index)
                ?? return null;
            (db.class_locs.get(l.class_).file, range)
        },
        let l: RelatedLocationItem => {
            match (l.value) {
                let function_: root.hir.DefinitionFunction => {
                    (
                        db.function_locs.get(function_.value).file,
                        root.hir.function_source_map(db, function_.value).name_span,
                    )
                },
                _ => {
                    let def = l.value;
                    let file = root.hir.definition_file(def, db);
                    let contributions = root.hir.file_symbol_contributions(db, file);
                    let found = contributions.types.concat(contributions.values).find((entry) -> {
                        entry.1.definition == def
                    })
                        ?? return null;
                    (file, found.1.name_span)
                },
            }
        },
    }
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::RenderedTirDiagnostic @ d9be6853b
// A fully rendered diagnostic: the message and the resolved source range.
class RenderedTirDiagnostic {
    // The typed error, for downstream id mapping.
    error: TirTypeError,
    message: string,
    range: root.syntax.TextRange,
    severity: DiagnosticSeverity,
    // Resolved related spans and messages.
    related: RenderedRelatedInformation[],

    // port: baml_compiler2_hir_ty/src/diagnostics.rs::impl Display for RenderedTirDiagnostic @ d9be6853b
    implements baml.ToString {
        function to_string(self) -> string throws never {
            `${self.range.start}..${self.range.end}: ${self.message}`
        }
    }
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::RenderedRelatedInformation @ d9be6853b
class RenderedRelatedInformation {
    file_id: int,
    range: root.syntax.TextRange,
    message: string,
}

// port: baml_compiler2_hir_ty/src/diagnostics.rs::TypeCheckDiagnostics @ d9be6853b
// Accumulated diagnostics for a single inference run.
class TypeCheckDiagnostics {
    diagnostics: TirDiagnostic[],

    // port: baml_compiler2_hir_ty/src/diagnostics.rs::TypeCheckDiagnostics::is_empty @ d9be6853b
    function is_empty(self) -> bool throws never {
        self.diagnostics.length() == 0
    }

    // port: baml_compiler2_hir_ty/src/diagnostics.rs::TypeCheckDiagnostics::extend @ d9be6853b
    function extend(self, other: TypeCheckDiagnostics) -> void throws never {
        root.base.extend(self.diagnostics, other.diagnostics);
    }
}
