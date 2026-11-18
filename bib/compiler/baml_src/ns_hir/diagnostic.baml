// port: baml_compiler2_hir/src/diagnostic.rs @ d9be6853b
//
// HIR per-file diagnostics, produced while building a file's semantic index.
// They hold `TextRange`s, not spans, because the file is known from context;
// `to_diagnostic` adds it when converting.
//
// deviation: `DiagnosticMessage.diagnostic_id` holds the id's code
// (`root.diagnostics.*`), the way the ported diagnostics name ids.

// port: diagnostic.rs::MemberSite. A definition site within a scope, with its
// kind tag and source range.
class MemberSite {
    range: root.syntax.TextRange,
    kind: DefinitionKind,
}

// port: diagnostic.rs::Hir2Diagnostic
type Hir2Diagnostic = Hir2DiagnosticDuplicateDefinition
    | Hir2DiagnosticUnknownAttribute
    | Hir2DiagnosticAttributeNotAllowedHere
    | Hir2DiagnosticBuiltinOnlySyntax
    | Hir2DiagnosticRootIsReserved
    | Hir2DiagnosticRootNamespace
    | Hir2DiagnosticDiagnosticMessage
    | Hir2DiagnosticDuplicatePatternBinding
    | Hir2DiagnosticDuplicatePatternField
    | Hir2DiagnosticDuplicateFieldAlias
    | Hir2DiagnosticDuplicateAttribute
    | Hir2DiagnosticOrPatternBindingMismatch
    | Hir2InterfaceDiagnostic;

// The interface diagnostics (BEP-044), a group of `Hir2Diagnostic`.
type Hir2InterfaceDiagnostic = Hir2DiagnosticUnknownInterface
    | Hir2DiagnosticNotAnInterface
    | Hir2DiagnosticInterfaceRequiresNonInterface
    | Hir2DiagnosticUnknownRequiredInterface
    | Hir2DiagnosticMissingInterfaceMethod
    | Hir2DiagnosticDuplicateImplementsBlock
    | Hir2DiagnosticUnknownInterfaceMember
    | Hir2DiagnosticToStringMustImplementInterface
    | Hir2DiagnosticToJsonMustImplementInterface
    | Hir2DiagnosticFromJsonMustImplementInterface
    | Hir2DiagnosticInterfaceFieldTypeMismatch
    | Hir2DiagnosticConflictingInterfaceFieldTypes
    | Hir2DiagnosticInterfaceExtendsCycle
    | Hir2DiagnosticInterfaceExtendsFieldConflict
    | Hir2DiagnosticInterfaceMethodSignatureMismatch
    | Hir2DiagnosticAmbiguousInterfaceMethod
    | Hir2DiagnosticMissingInterfaceField
    | Hir2DiagnosticUnknownInterfaceFieldLink
    | Hir2DiagnosticUnknownClassFieldInInterfaceLink
    | Hir2DiagnosticDuplicateInterfaceFieldLink
    | Hir2DiagnosticMissingRequiredInterface
    | Hir2DiagnosticOutOfBodyImplementsFieldInterface;

// A name defined more than once within one scope. `sites` are all definition
// sites in source order; the first is the "winner". `scope` is the parent
// scope's name (`Foo` for members of `class Foo`), null at file level.
class Hir2DiagnosticDuplicateDefinition {
    name: string,
    scope: string?,
    sites: MemberSite[],
}

// An attribute the language does not define: a misspelling or a removed
// attribute, never a pass-through annotation.
class Hir2DiagnosticUnknownAttribute {
    attr_name: string,
    position: root.base.AttributePosition,
    span: root.syntax.TextRange,
}

// A schema attribute at a declaration position it has no meaning at.
class Hir2DiagnosticAttributeNotAllowedHere {
    attr_name: string,
    position: root.base.AttributePosition,
    allowed: root.base.AttributePosition[],
    span: root.syntax.TextRange,
}

// Builtin-only syntax used outside builtin stdlib files.
class Hir2DiagnosticBuiltinOnlySyntax {
    feature: string,
    span: root.syntax.TextRange,
}

// A binding, item, or type parameter named `root`, the path to the package.
class Hir2DiagnosticRootIsReserved {
    span: root.syntax.TextRange,
}

// A file under a directory `ns_root/`: a namespace named `root`.
class Hir2DiagnosticRootNamespace {
    span: root.syntax.TextRange,
}

// Generic single-span diagnostic for builtin contract validation.
class Hir2DiagnosticDiagnosticMessage {
    diagnostic_id: string,
    message: string,
    span: root.syntax.TextRange,
}

// A pattern introduces the same name more than once. `sites` lists every
// binding site in source order; the first is the original.
class Hir2DiagnosticDuplicatePatternBinding {
    name: string,
    sites: root.syntax.TextRange[],
}

// A class destructure names the same field more than once.
class Hir2DiagnosticDuplicatePatternField {
    name: string,
    sites: root.syntax.TextRange[],
}

// Two or more members of a class or enum serialize to the same JSON key.
// `sites` lists the name span of every contributing member in source order.
class Hir2DiagnosticDuplicateFieldAlias {
    key: string,
    sites: root.syntax.TextRange[],
    container: SerializedKeyContainer,
}

// One declaration carries the same single-valued schema attribute more than
// once. `attr_name` has no leading `@`.
class Hir2DiagnosticDuplicateAttribute {
    attr_name: string,
    sites: root.syntax.TextRange[],
}

// An `Or` pattern's alternatives don't all bind the same names.
class Hir2DiagnosticOrPatternBindingMismatch {
    // The `Or` pattern itself.
    or_span: root.syntax.TextRange,
    // Names some alternatives bind and others don't.
    mismatched_names: string[],
}

// `implements I {}` names no known interface.
class Hir2DiagnosticUnknownInterface {
    class_name: string,
    target_name: string,
    span: root.syntax.TextRange,
}

// `implements X {}` names a type that is not an interface.
class Hir2DiagnosticNotAnInterface {
    class_name: string,
    target_name: string,
    span: root.syntax.TextRange,
}

// `interface I requires X` where `X` exists but is not an interface.
class Hir2DiagnosticInterfaceRequiresNonInterface {
    interface_name: string,
    target_name: string,
    span: root.syntax.TextRange,
}

// `interface I requires X` where `X` names no type at all.
class Hir2DiagnosticUnknownRequiredInterface {
    interface_name: string,
    target_name: string,
    span: root.syntax.TextRange,
}

// A class lacks a body for a required (no-default) interface method. `span`
// is the `implements I { ... }` block's.
class Hir2DiagnosticMissingInterfaceMethod {
    class_name: string,
    interface_name: string,
    method_name: string,
    span: root.syntax.TextRange,
}

// The same `implements I` block twice on a class. The first site wins.
class Hir2DiagnosticDuplicateImplementsBlock {
    class_name: string,
    interface_name: string,
    sites: root.syntax.TextRange[],
}

// A method in `implements I { ... }` that I does not declare.
class Hir2DiagnosticUnknownInterfaceMember {
    interface_name: string,
    method_name: string,
    span: root.syntax.TextRange,
}

// A `to_string` method in a class body instead of `implements baml.ToString`.
class Hir2DiagnosticToStringMustImplementInterface {
    class_name: string,
    span: root.syntax.TextRange,
}

// A `to_json` method in a class body instead of `implements baml.ToJson`.
class Hir2DiagnosticToJsonMustImplementInterface {
    class_name: string,
    span: root.syntax.TextRange,
}

// A `from_json` method in a class body instead of `implements baml.FromJson`.
class Hir2DiagnosticFromJsonMustImplementInterface {
    class_name: string,
    span: root.syntax.TextRange,
}

// A class field whose type differs from the interface's. `interface_field_name`
// differs from `field_name` when the block links it (`name as name_count`).
class Hir2DiagnosticInterfaceFieldTypeMismatch {
    class_name: string,
    field_name: string,
    interface_field_name: string,
    interface_name: string,
    class_type: string,
    interface_type: string,
    span: root.syntax.TextRange,
}

// Two implemented interfaces require one field name with different types.
class Hir2DiagnosticConflictingInterfaceFieldTypes {
    class_name: string,
    field_name: string,
    first_interface: string,
    first_type: string,
    second_interface: string,
    second_type: string,
    span: root.syntax.TextRange,
}

// An interface's `requires` chain forms a cycle.
class Hir2DiagnosticInterfaceExtendsCycle {
    chain: string[],
    span: root.syntax.TextRange,
}

// An interface inherits conflicting types for one field from two parents.
class Hir2DiagnosticInterfaceExtendsFieldConflict {
    interface_name: string,
    field_name: string,
    first_interface: string,
    first_type: string,
    second_interface: string,
    second_type: string,
    span: root.syntax.TextRange,
}

// A method in an `implements` block whose signature differs from the
// interface's.
class Hir2DiagnosticInterfaceMethodSignatureMismatch {
    class_name: string,
    interface_name: string,
    method_name: string,
    actual: string,
    expected: string,
    span: root.syntax.TextRange,
}

// One method name declared in two or more `implements` blocks of a class.
// `sources` is `(interface_name, declaration_span)` per block, in source order.
class Hir2DiagnosticAmbiguousInterfaceMethod {
    class_name: string,
    method_name: string,
    sources: (string, root.syntax.TextRange)[],
}

// An `implements` block (at `span`) missing a field the interface requires.
class Hir2DiagnosticMissingInterfaceField {
    class_name: string,
    interface_name: string,
    field_name: string,
    span: root.syntax.TextRange,
}

// The left side of `field as class_field` is no field of the interface.
class Hir2DiagnosticUnknownInterfaceFieldLink {
    interface_name: string,
    field_name: string,
    span: root.syntax.TextRange,
}

// The right side of `field as class_field` is no class field.
class Hir2DiagnosticUnknownClassFieldInInterfaceLink {
    class_name: string,
    interface_name: string,
    field_name: string,
    span: root.syntax.TextRange,
}

// One interface field linked more than once in an implements block.
class Hir2DiagnosticDuplicateInterfaceFieldLink {
    interface_name: string,
    field_name: string,
    sites: root.syntax.TextRange[],
}

// A class implements an interface without all of its `requires` parents.
class Hir2DiagnosticMissingRequiredInterface {
    class_name: string,
    interface_name: string,
    missing_parents: string[],
    span: root.syntax.TextRange,
}

// Top-level `implements I for T` of an interface that declares fields.
class Hir2DiagnosticOutOfBodyImplementsFieldInterface {
    target_name: string,
    interface_name: string,
    span: root.syntax.TextRange,
}

// port: baml_compiler2_hir/src/diagnostic.rs::Hir2Diagnostic::to_diagnostic @ d9be6853b
// The diagnostic for a HIR problem in `file`, in the shape
// `reflect.Package.compile` reports (phase "hir"), with the conventions of
// `root.ast.to_diagnostic`.
function to_diagnostic(
    diagnostic: Hir2Diagnostic,
    file: string,
) -> reflect.Diagnostic throws never {
    let report = match (diagnostic) {
        let d: Hir2InterfaceDiagnostic => interface_report(d),
        let d: Hir2DiagnosticDuplicateDefinition => duplicate_definition_report(d),
        let d: Hir2DiagnosticUnknownAttribute => unknown_attribute_report(d),
        let d: Hir2DiagnosticAttributeNotAllowedHere => attribute_not_allowed_report(d),
        let d: Hir2DiagnosticRootIsReserved => {
            Diagnostic
                .error(
                    root.diagnostics.ROOT_IS_RESERVED,
                    "`root` is the path to this package and cannot name a binding, an item, or a type parameter",
                )
                .with_primary(d.span, "`root` is this package")
        },
        let d: Hir2DiagnosticRootNamespace => {
            Diagnostic
                .error(
                    root.diagnostics.ROOT_IS_RESERVED,
                    "`root` is the path to this package and cannot name a namespace: rename the directory `ns_root/`",
                )
                .with_primary(d.span, "this file is in `ns_root/`")
        },
        let d: Hir2DiagnosticBuiltinOnlySyntax => {
            Diagnostic
                .error(
                    root.diagnostics.INVALID_ATTRIBUTE_CONTEXT,
                    `builtin-only syntax \`${d.feature}\` is only allowed in builtin stdlib files`,
                )
                .with_primary(d.span, "builtin-only syntax")
        },
        let d: Hir2DiagnosticDiagnosticMessage => {
            Diagnostic.error(d.diagnostic_id, d.message).with_primary(
                d.span,
                "invalid builtin declaration",
            )
        },
        let d: Hir2DiagnosticDuplicatePatternBinding => {
            Diagnostic
                .error(
                    root.diagnostics.DUPLICATE_BINDING,
                    `duplicate binding \`${d.name}\` in pattern`,
                )
                .with_repeats(
                    d.sites,
                    `\`${d.name}\` first bound here`,
                    `\`${d.name}\` bound again here`,
                )
        },
        let d: Hir2DiagnosticDuplicatePatternField => {
            Diagnostic
                .error(
                    root.diagnostics.DUPLICATE_FIELD,
                    `duplicate field \`${d.name}\` in class destructure pattern`,
                )
                .with_repeats(
                    d.sites,
                    `field \`${d.name}\` first destructured here`,
                    `field \`${d.name}\` destructured again here`,
                )
        },
        let d: Hir2DiagnosticDuplicateFieldAlias => {
            duplicate_serialized_key(d.key, d.container).with_repeats(
                d.sites,
                `key \`${d.key}\` first serialized here`,
                `also serialized as \`${d.key}\` here`,
            )
        },
        let d: Hir2DiagnosticDuplicateAttribute => {
            Diagnostic
                .error(
                    root.diagnostics.DUPLICATE_ATTRIBUTE,
                    `duplicate attribute \`@${d.attr_name}\``,
                )
                .with_repeats(
                    d.sites,
                    `\`@${d.attr_name}\` first applied here`,
                    `duplicate \`@${d.attr_name}\` — only the last takes effect`,
                )
        },
        let d: Hir2DiagnosticOrPatternBindingMismatch => {
            Diagnostic
                .error(
                    root.diagnostics.DUPLICATE_BINDING,
                    `or-pattern alternatives must bind the same names. Inconsistent across branches: ${d.mismatched_names.join(", ")}`,
                )
                .with_primary(d.or_span, "alternatives bind different names")
        },
    };
    report.finish(file)
}

// port: the `DuplicateDefinition` arm of diagnostic.rs::to_diagnostic.
function duplicate_definition_report(
    d: Hir2DiagnosticDuplicateDefinition,
) -> Diagnostic throws never {
    let first = d.sites[0];
    let rest = d.sites.slice(1, d.sites.length());
    let first_kind = definition_kind_as_str(first.kind);
    let diag = duplicate_definition_headline(d);
    diag.with_secondary(first.range, `first defined as ${first_kind} here`);
    for (let site in rest) {
        diag.with_primary(site.range, `duplicate ${definition_kind_as_str(site.kind)} definition`);
    }
    diag
}

// port: the headline half of the `DuplicateDefinition` arm. A field or
// variant of a named scope whose sites all agree is the shared E0012
// duplicate member; anything else names the kinds itself.
function duplicate_definition_headline(
    d: Hir2DiagnosticDuplicateDefinition,
) -> Diagnostic throws never {
    let first = d.sites[0];
    let rest = d.sites.slice(1, d.sites.length());
    let use_dot = definition_kind_is_member(first.kind);
    let scope = d.scope;
    let qualified = if (scope != null && use_dot) {
        `${scope}.${d.name}`
    } else {
        d.name
    };
    let in_scope = if (scope != null && !use_dot) {
        ` in \`${scope}\``
    } else {
        ""
    };
    let kinds_match = rest.every((s) -> {
        s.kind == first.kind
    });
    if (kinds_match && first.kind == DefinitionKind.Field && scope != null) {
        return duplicate_member(DuplicateMemberKind.Field, scope, d.name);
    }
    if (kinds_match && first.kind == DefinitionKind.Variant && scope != null) {
        return duplicate_member(DuplicateMemberKind.Variant, scope, d.name);
    }
    let message = if (kinds_match) {
        `duplicate ${definition_kind_as_str(first.kind)} \`${qualified}\`${in_scope}`
    } else {
        let kind_list = d.sites.map((s) -> {
            definition_kind_as_str(s.kind)
        });
        `name \`${qualified}\`${in_scope} defined ${d.sites.length()} times as: ${kind_list.join(", ")}`
    };
    Diagnostic.error(root.diagnostics.DUPLICATE_FIELD, message)
}

// port: the `UnknownAttribute` arm of diagnostic.rs::to_diagnostic.
function unknown_attribute_report(d: Hir2DiagnosticUnknownAttribute) -> Diagnostic throws never {
    let sigil = root.base.attribute_position_sigil(d.position);
    let where_ = root.base.attribute_position_describe(d.position);
    let valid = root.base.schema_attribute_specs_at(d.position).map((spec) -> {
        `\`${sigil}${spec.name}\``
    });
    let valid_text = if (valid.length() == 0) {
        `no attribute is valid on ${where_}`
    } else {
        `valid on ${where_}: ${valid.join(", ")}`
    };
    Diagnostic
        .error(
            root.diagnostics.UNKNOWN_ATTRIBUTE,
            `unknown attribute \`${sigil}${d.attr_name}\`; ${valid_text}`,
        )
        .with_primary(d.span, "unknown attribute")
}

// port: the `AttributeNotAllowedHere` arm of diagnostic.rs::to_diagnostic.
function attribute_not_allowed_report(
    d: Hir2DiagnosticAttributeNotAllowedHere,
) -> Diagnostic throws never {
    let allowed = d.allowed
        .map((position) -> {
            `\`${root.base.attribute_position_sigil(position)}${d.attr_name}\` on ${root.base.attribute_position_describe(position)}`
        })
        .join(", ");
    Diagnostic
        .error(
            root.diagnostics.INVALID_ATTRIBUTE_CONTEXT,
            `attribute \`${root.base.attribute_position_sigil(d.position)}${d.attr_name}\` is not valid on ${root.base.attribute_position_describe(d.position)}; allowed: ${allowed}`,
        )
        .with_primary(d.span, "not valid here")
}

// port: the interface arms (BEP-044) of diagnostic.rs::to_diagnostic.
function interface_report(diagnostic: Hir2InterfaceDiagnostic) -> Diagnostic throws never {
    match (diagnostic) {
        let d: Hir2DiagnosticUnknownInterface => {
            Diagnostic
                .error(
                    root.diagnostics.UNKNOWN_INTERFACE,
                    `class \`${d.class_name}\` cannot implement \`${d.target_name}\`: no interface with that name is in scope`,
                )
                .with_primary(d.span, "interface not found")
        },
        let d: Hir2DiagnosticNotAnInterface => {
            Diagnostic
                .error(
                    root.diagnostics.NOT_AN_INTERFACE,
                    `\`${d.target_name}\` is not an interface; class \`${d.class_name}\` can only implement interfaces`,
                )
                .with_primary(d.span, "not an interface")
        },
        let d: Hir2DiagnosticInterfaceRequiresNonInterface => {
            Diagnostic
                .error(
                    root.diagnostics.INTERFACE_REQUIRES_NON_INTERFACE,
                    `\`${d.target_name}\` is not an interface; interface \`${d.interface_name}\` can only require interfaces`,
                )
                .with_primary(d.span, "not an interface")
        },
        let d: Hir2DiagnosticUnknownRequiredInterface => {
            Diagnostic
                .error(
                    root.diagnostics.UNKNOWN_INTERFACE,
                    `interface \`${d.interface_name}\` cannot require \`${d.target_name}\`: no interface with that name is in scope`,
                )
                .with_primary(d.span, "interface not found")
        },
        let d: Hir2DiagnosticMissingInterfaceMethod => {
            Diagnostic
                .error(
                    root.diagnostics.MISSING_INTERFACE_METHOD,
                    `class \`${d.class_name}\` does not implement required method \`${d.method_name}\` of interface \`${d.interface_name}\``,
                )
                .with_primary(d.span, `missing \`${d.method_name}\` here`)
        },
        let d: Hir2DiagnosticDuplicateImplementsBlock => {
            Diagnostic
                .error(
                    root.diagnostics.DUPLICATE_IMPLEMENTS_BLOCK,
                    `class \`${d.class_name}\` has multiple \`implements ${d.interface_name}\` blocks; a class may implement each interface at most once`,
                )
                .with_repeats(
                    d.sites,
                    "first `implements` block here",
                    "duplicate `implements` block",
                )
        },
        let d: Hir2DiagnosticUnknownInterfaceMember => {
            Diagnostic
                .error(
                    root.diagnostics.UNKNOWN_INTERFACE_MEMBER,
                    `method \`${d.method_name}\` is not declared on interface \`${d.interface_name}\`; remove it or add it to the interface`,
                )
                .with_primary(d.span, "not a member of the interface")
        },
        let d: Hir2DiagnosticToStringMustImplementInterface => {
            Diagnostic
                .error(
                    root.diagnostics.TO_STRING_MUST_IMPLEMENT_INTERFACE,
                    `\`to_string\` cannot be defined as a method on class \`${d.class_name}\`; implement the \`baml.ToString\` interface instead`,
                )
                .with_primary(d.span, "move this into `implements baml.ToString { ... }`")
        },
        let d: Hir2DiagnosticToJsonMustImplementInterface => {
            Diagnostic
                .error(
                    root.diagnostics.TO_JSON_MUST_IMPLEMENT_INTERFACE,
                    `\`to_json\` cannot be defined as a method on class \`${d.class_name}\`; implement the \`baml.ToJson\` interface instead`,
                )
                .with_primary(d.span, "move this into `implements baml.ToJson { ... }`")
        },
        let d: Hir2DiagnosticFromJsonMustImplementInterface => {
            Diagnostic
                .error(
                    root.diagnostics.FROM_JSON_MUST_IMPLEMENT_INTERFACE,
                    `\`from_json\` cannot be defined as a method on class \`${d.class_name}\`; implement the \`baml.FromJson\` interface instead`,
                )
                .with_primary(d.span, "move this into `implements baml.FromJson { ... }`")
        },
        let d: Hir2DiagnosticAmbiguousInterfaceMethod => ambiguous_interface_method_report(d),
        let d: Hir2DiagnosticDuplicateInterfaceFieldLink => {
            let diag = Diagnostic.error(
                root.diagnostics.DUPLICATE_INTERFACE_FIELD_LINK,
                `field \`${d.field_name}\` of interface \`${d.interface_name}\` is linked more than once`,
            );
            if (d.sites.length() > 0) {
                diag.with_repeats(d.sites, "first link here", "duplicate link here");
            }
            diag
        },
        let d: Hir2DiagnosticMissingRequiredInterface => {
            let list = d.missing_parents
                .map((n) -> {
                    `\`${n}\``
                })
                .join(", ");
            Diagnostic
                .error(
                    root.diagnostics.MISSING_REQUIRED_INTERFACE,
                    `class \`${d.class_name}\` implements \`${d.interface_name}\`, which requires ${list}, but \`${d.class_name}\` does not implement them`,
                )
                .with_primary(d.span, `requires ${list}`)
        },
        let d: Hir2DiagnosticInterfaceExtendsCycle => {
            Diagnostic
                .error(
                    root.diagnostics.INTERFACE_EXTENDS_CYCLE,
                    `interface \`requires\` chain forms a cycle: ${d.chain.join(" -> ")}`,
                )
                .with_primary(d.span, "cyclic `requires`")
        },
        let d: Hir2DiagnosticInterfaceFieldTypeMismatch
            | Hir2DiagnosticConflictingInterfaceFieldTypes
            | Hir2DiagnosticInterfaceExtendsFieldConflict
            | Hir2DiagnosticInterfaceMethodSignatureMismatch
            | Hir2DiagnosticMissingInterfaceField
            | Hir2DiagnosticUnknownInterfaceFieldLink
            | Hir2DiagnosticUnknownClassFieldInInterfaceLink
            | Hir2DiagnosticOutOfBodyImplementsFieldInterface =>
        {
            interface_member_report(d)
        },
    }
}

// port: the interface member arms (fields, links, signatures) of
// diagnostic.rs::to_diagnostic.
function interface_member_report(
    diagnostic: Hir2DiagnosticInterfaceFieldTypeMismatch
        | Hir2DiagnosticConflictingInterfaceFieldTypes
        | Hir2DiagnosticInterfaceExtendsFieldConflict
        | Hir2DiagnosticInterfaceMethodSignatureMismatch
        | Hir2DiagnosticMissingInterfaceField
        | Hir2DiagnosticUnknownInterfaceFieldLink
        | Hir2DiagnosticUnknownClassFieldInInterfaceLink
        | Hir2DiagnosticOutOfBodyImplementsFieldInterface,
) -> Diagnostic throws never {
    match (diagnostic) {
        let d: Hir2DiagnosticInterfaceFieldTypeMismatch => {
            Diagnostic
                .error(
                    root.diagnostics.INTERFACE_FIELD_TYPE_MISMATCH,
                    `class \`${d.class_name}\` declares field \`${d.field_name}: ${d.class_type}\` but interface \`${d.interface_name}\` requires \`${d.interface_field_name}\` to have type \`${d.interface_type}\``,
                )
                .with_primary(d.span, `expected \`${d.interface_type}\`, found \`${d.class_type}\``)
        },
        let d: Hir2DiagnosticConflictingInterfaceFieldTypes => {
            Diagnostic
                .error(
                    root.diagnostics.CONFLICTING_INTERFACE_FIELD_TYPES,
                    `class \`${d.class_name}\` cannot implement both \`${d.first_interface}\` and \`${d.second_interface}\`: field \`${d.field_name}\` is declared as \`${d.first_type}\` in \`${d.first_interface}\` but \`${d.second_type}\` in \`${d.second_interface}\``,
                )
                .with_primary(d.span, "conflicting field types from two interfaces")
        },
        let d: Hir2DiagnosticInterfaceExtendsFieldConflict => {
            Diagnostic
                .error(
                    root.diagnostics.INTERFACE_EXTENDS_FIELD_CONFLICT,
                    `interface \`${d.interface_name}\` inherits conflicting types for field \`${d.field_name}\`: \`${d.first_type}\` from \`${d.first_interface}\`, \`${d.second_type}\` from \`${d.second_interface}\``,
                )
                .with_primary(d.span, "conflicting field types inherited via `requires`")
        },
        let d: Hir2DiagnosticInterfaceMethodSignatureMismatch => {
            Diagnostic
                .error(
                    root.diagnostics.INTERFACE_METHOD_SIGNATURE_MISMATCH,
                    `method \`${d.method_name}\` in class \`${d.class_name}\` does not match interface \`${d.interface_name}\`: expected \`${d.expected}\`, found \`${d.actual}\``,
                )
                .with_primary(d.span, "signature mismatch")
        },
        let d: Hir2DiagnosticMissingInterfaceField => {
            Diagnostic
                .error(
                    root.diagnostics.MISSING_INTERFACE_FIELD,
                    `class \`${d.class_name}\` does not provide field \`${d.field_name}\` required by interface \`${d.interface_name}\``,
                )
                .with_primary(
                    d.span,
                    `add class field \`${d.field_name}\`, or link it with \`${d.field_name} as class_field\``,
                )
        },
        let d: Hir2DiagnosticUnknownInterfaceFieldLink => {
            Diagnostic
                .error(
                    root.diagnostics.UNKNOWN_INTERFACE_FIELD_LINK,
                    `interface \`${d.interface_name}\` has no field \`${d.field_name}\``,
                )
                .with_primary(d.span, "not a field of the interface")
        },
        let d: Hir2DiagnosticUnknownClassFieldInInterfaceLink => {
            Diagnostic
                .error(
                    root.diagnostics.UNKNOWN_CLASS_FIELD_IN_INTERFACE_LINK,
                    `class \`${d.class_name}\` has no field \`${d.field_name}\` to link for interface \`${d.interface_name}\``,
                )
                .with_primary(d.span, "not a field of the class")
        },
        let d: Hir2DiagnosticOutOfBodyImplementsFieldInterface => {
            Diagnostic
                .error(
                    root.diagnostics.OUT_OF_BODY_IMPLEMENTS_FIELD_INTERFACE,
                    `\`implements ${d.interface_name} for ${d.target_name}\` cannot implement field-bearing interface \`${d.interface_name}\` outside the class body`,
                )
                .with_primary(
                    d.span,
                    "field-bearing interfaces must be implemented inside the class body",
                )
        },
    }
}

// port: the `AmbiguousInterfaceMethod` arm of diagnostic.rs::to_diagnostic.
function ambiguous_interface_method_report(
    d: Hir2DiagnosticAmbiguousInterfaceMethod,
) -> Diagnostic throws never {
    let iface_list = d.sources
        .map((source) -> {
            `\`${source.0}\``
        })
        .join(", ");
    let hint = d.sources
        .map((source) -> {
            `obj.${source.0}.${d.method_name}()`
        })
        .join(" or ");
    let diag = Diagnostic.error(
        root.diagnostics.AMBIGUOUS_INTERFACE_METHOD,
        `method \`${d.method_name}\` on class \`${d.class_name}\` is declared by multiple interfaces: ${iface_list}; unqualified calls will be ambiguous — use ${hint}`,
    );
    let first = d.sources.at(0);
    if (first != null) {
        diag.with_secondary(first.1, `first declared in \`implements ${first.0}\` here`);
        for (let source in d.sources.slice(1, d.sources.length())) {
            diag.with_primary(source.1, `also declared in \`implements ${source.0}\``);
        }
    }
    diag
}

// needs foundation: baml_compiler_diagnostics/src/runtime_type.rs::SerializedKeyContainer.
// The declaration kind whose members collide after serialization.
enum SerializedKeyContainer {
    Class,
    Enum,
}

// needs foundation: runtime_type.rs::DuplicateMemberKind. The kind of
// repeated runtime-type member reported by E0012.
enum DuplicateMemberKind {
    Field,
    Variant,
}

// needs foundation: runtime_type.rs::duplicate_member. E0012: a repeated
// field or variant.
function duplicate_member(
    kind: DuplicateMemberKind,
    container: string,
    member: string,
) -> Diagnostic throws never {
    let kind_text = match (kind) {
        DuplicateMemberKind.Field => "field",
        DuplicateMemberKind.Variant => "variant",
    };
    Diagnostic.error(
        root.diagnostics.DUPLICATE_FIELD,
        `duplicate ${kind_text} \`${container}.${member}\``,
    )
}

// needs foundation: runtime_type.rs::duplicate_serialized_key. E0149: two
// members serialize to the same key.
function duplicate_serialized_key(
    key: string,
    container: SerializedKeyContainer,
) -> Diagnostic throws never {
    let container_text = match (container) {
        SerializedKeyContainer.Class => "class",
        SerializedKeyContainer.Enum => "enum",
    };
    Diagnostic.error(
        root.diagnostics.DUPLICATE_FIELD_ALIAS,
        `duplicate serialized key \`${key}\` in ${container_text}`,
    )
}

// needs foundation: baml_compiler_diagnostics/src/diagnostic.rs::Annotation.
// A primary or secondary label on a range of the diagnostic's file.
class Annotation {
    range: root.syntax.TextRange,
    message: string,
    is_primary: bool,
}

// needs foundation: baml_compiler_diagnostics/src/diagnostic.rs::Diagnostic,
// the error builder the HIR arms chain (`error`, `with_primary`,
// `with_secondary`), finished into a `reflect.Diagnostic` with phase "hir".
// Every HIR diagnostic is an error.
class Diagnostic {
    code: string,
    message: string,
    annotations: Annotation[],

    // port: Diagnostic::error
    function error(code: string, message: string) -> Diagnostic throws never {
        Diagnostic { code: code, message: message, annotations: [] }
    }

    // port: Diagnostic::with_primary
    function with_primary(
        self,
        range: root.syntax.TextRange,
        message: string,
    ) -> Diagnostic throws never {
        self.annotations.push(Annotation { range: range, message: message, is_primary: true });
        self
    }

    // port: Diagnostic::with_secondary
    function with_secondary(
        self,
        range: root.syntax.TextRange,
        message: string,
    ) -> Diagnostic throws never {
        self.annotations.push(Annotation { range: range, message: message, is_primary: false });
        self
    }

    // The repeated-sites shape several arms share: a secondary at the first
    // site (an empty range at 0 when there is none, Rust's
    // `unwrap_or_default`), then a primary at each later one.
    function with_repeats(
        self,
        sites: root.syntax.TextRange[],
        first: string,
        again: string,
    ) -> Diagnostic throws never {
        self.with_secondary(sites.at(0) ?? root.syntax.TextRange.empty(0), first);
        for (let range in sites.slice(1, sites.length())) {
            self.with_primary(range, again);
        }
        self
    }

    // The `reflect.Diagnostic` in `file`. `message` is the headline plus the
    // first primary label when it differs (`message_with_primary_label`); that
    // primary is the span and is left out of `annotations`, as
    // `root.ast.to_diagnostic` does.
    function finish(self, file: string) -> reflect.Diagnostic throws never {
        let count = self.annotations.length();
        let primary_index = self.annotations.find_index((a) -> {
            a.is_primary
        })
            ?? count;
        let primary = self.annotations.at(primary_index);
        let label = primary?.message;
        let message = if (label != null && label != self.message) {
            `${self.message}: ${label}`
        } else {
            self.message
        };
        let others = self.annotations.slice(0, primary_index).concat(
            self.annotations.slice(primary_index + 1, count),
        );
        reflect.Diagnostic {
            code: self.code,
            span: if (primary != null) {
                reflect.Span { file: file, start: primary.range.start, end: primary.range.end }
            } else {
                null
            },
            message: message,
            severity: "error",
            phase: "hir",
            headline: self.message,
            primary_label: label,
            message_highlights: [],
            annotations: others.map((a) -> {
                reflect.DiagnosticAnnotation {
                    span: reflect.Span { file: file, start: a.range.start, end: a.range.end },
                    message: a.message,
                    message_highlights: [],
                    is_primary: a.is_primary,
                }
            }),
            related_info: [],
        }
    }
}
