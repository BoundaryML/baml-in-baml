// port: baml_compiler_diagnostics/src/diagnostic.rs::DiagnosticId::code @ d9be6853b
// The code each diagnostic id renders as, for the ids ported so far. Several
// ids share a code (UnexpectedToken and InvalidSyntax are both E0010).

const TYPE_MISMATCH: string = "E0001";
const UNEXPECTED_EOF: string = "E0009";
const UNEXPECTED_TOKEN: string = "E0010";
const INVALID_SYNTAX: string = "E0010";
const GENERATOR_BLOCK_UNSUPPORTED: string = "E0017";
const REMOVED_FEATURE: string = "E0098";
const MALFORMED_ATTRIBUTE: string = "E0105";
const UNPARSEABLE_TYPE: string = "E0108";
const INVALID_STRING_ESCAPE: string = "E0109";
const INTERFACE_FIELD_DECLARED_IN_IMPLEMENTS_BLOCK: string = "E0127";
const WILDCARD_TYPE_NOT_ALLOWED: string = "E0147";
const INVALID_NUMERIC_LITERAL: string = "E0152";
const INVALID_BUILTIN_TYPE_ARGUMENTS: string = "E0171";
const AMBIGUOUS_UNION: string = "E0175";
// The ids `baml_compiler2_hir` reports.
const DUPLICATE_NAME: string = "E0011";
const DUPLICATE_FIELD: string = "E0012";
const DUPLICATE_ATTRIBUTE: string = "E0014";
const UNKNOWN_ATTRIBUTE: string = "E0015";
const INVALID_ATTRIBUTE_CONTEXT: string = "E0016";
const INVALID_ATTRIBUTE_ARG: string = "E0037";
const UNEXPECTED_ATTRIBUTE_ARG: string = "E0038";
const DUPLICATE_BINDING: string = "E0094";
const THROWS_CONTRACT_VIOLATION: string = "E0096";
const NAMESPACE_NAME_COLLISION: string = "E0099";
const UNKNOWN_INTERFACE: string = "E0112";
const MISSING_INTERFACE_METHOD: string = "E0113";
const DUPLICATE_IMPLEMENTS_BLOCK: string = "E0114";
const UNKNOWN_INTERFACE_MEMBER: string = "E0115";
const INTERFACE_FIELD_TYPE_MISMATCH: string = "E0116";
const CONFLICTING_INTERFACE_FIELD_TYPES: string = "E0117";
const INTERFACE_EXTENDS_CYCLE: string = "E0118";
const NOT_AN_INTERFACE: string = "E0119";
const INTERFACE_METHOD_SIGNATURE_MISMATCH: string = "E0120";
const AMBIGUOUS_INTERFACE_METHOD: string = "E0121";
const INTERFACE_EXTENDS_FIELD_CONFLICT: string = "E0122";
const MISSING_INTERFACE_FIELD: string = "E0124";
const MISSING_REQUIRED_INTERFACE: string = "E0125";
const OUT_OF_BODY_IMPLEMENTS_FIELD_INTERFACE: string = "E0126";
const UNKNOWN_INTERFACE_FIELD_LINK: string = "E0128";
const UNKNOWN_CLASS_FIELD_IN_INTERFACE_LINK: string = "E0129";
const DUPLICATE_INTERFACE_FIELD_LINK: string = "E0130";
const INTERFACE_REQUIRES_NON_INTERFACE: string = "E0133";
const TO_STRING_MUST_IMPLEMENT_INTERFACE: string = "E0140";
const TO_JSON_MUST_IMPLEMENT_INTERFACE: string = "E0142";
const FROM_JSON_MUST_IMPLEMENT_INTERFACE: string = "E0143";
const DUPLICATE_FIELD_ALIAS: string = "E0149";
const ROOT_IS_RESERVED: string = "E0176";
// The ids the type checker reports (`baml_compiler2_hir_ty` through
// `baml_db/src/check.rs`).
const UNKNOWN_TYPE: string = "E0002";
const UNKNOWN_VARIABLE: string = "E0003";
const INVALID_OPERATOR: string = "E0004";
const ARGUMENT_COUNT_MISMATCH: string = "E0005";
const NOT_CALLABLE: string = "E0006";
const NO_SUCH_FIELD: string = "E0007";
const NOT_INDEXABLE: string = "E0008";
const MISSING_RETURN_EXPRESSION: string = "E0029";
const NON_EXHAUSTIVE_MATCH: string = "E0062";
const UNREACHABLE_ARM: string = "E0063";
const INVALID_MAP_KEY_TYPE: string = "E0067";
const ALIAS_CYCLE: string = "E0068";
const CLASS_CYCLE: string = "E0069";
const INVALID_CATCH_BINDING_TYPE: string = "E0093";
const THROWS_CONTRACT_EXTRANEOUS: string = "E0097";
const REFUTABLE_PATTERN_IN_LET: string = "E0111";
const IRREFUTABLE_PATTERN_IN_IF_LET: string = "E0112";
const LET_ELSE_MUST_DIVERGE: string = "E0113";
const IRREFUTABLE_PATTERN_IN_LET_ELSE: string = "E0114";
const DEFAULT_ON_REQUIRED_METHOD: string = "E0123";
const AMBIGUOUS_INTERFACE_FIELD: string = "E0131";
const OVERLAPPING_IMPLEMENTS: string = "E0132";
const BARE_DEFAULT_KEYWORD: string = "E0134";
const UNCONSTRAINED_IMPL_TYPE_PARAM: string = "E0135";
const SELF_IN_INTERFACE_FIELD: string = "E0136";
const IRREFUTABLE_PATTERN_IN_WHILE_LET: string = "E0137";
const IMPL_TARGET_NOT_CONCRETE: string = "E0138";
const IMPL_VIOLATES_ORPHAN_RULE: string = "E0139";
const DEFER_CONTROL_FLOW_ESCAPE: string = "E0141";
const CLEANUP_MAGIC_METHOD_SIGNATURE: string = "E0144";
const GENERIC_BOUND_NOT_INTERFACE: string = "E0145";
const UNREACHABLE_CODE: string = "E0146";
const INTEGER_LITERAL_OUT_OF_RANGE: string = "E0150";
const FUNCTION_TYPE_MISSING_THROWS: string = "E0151";
const GENERIC_SYS_OP_METHOD_IN_INTERFACE_IMPL: string = "E0153";
const BUILTIN_INTERFACE_NOT_IMPLEMENTABLE: string = "E0153";
const BUILTIN_INTERFACE_NOT_A_BOUND: string = "E0154";
const TYPE_MUST_BE_KNOWN: string = "E0155";
const INTERFACE_PROJECTION_BASE: string = "E0156";
const SELF_IN_ASSOCIATED_TYPE_DEFAULT: string = "E0157";
const MOUNTED_PACKAGE_CALL_UNSUPPORTED: string = "E0158";
const INIT_IO_NOT_ALLOWED: string = "E0163";
const CANNOT_CONSTRUCT_BUILTIN_COMPANION: string = "E0166";
const CONDITION_ALWAYS_CONSTANT: string = "E0167";
const INTERFACE_METHOD_MISSING_THROWS: string = "E0170";
const SCOPED_TYPE_ESCAPES_BLOCK: string = "E0172";
const CANNOT_CONSTRUCT_OPAQUE_CLASS: string = "E0173";
const INVALID_REGEX_PATTERN: string = "E0174";
const CALL_SITE_BUILTIN_VALUE: string = "E0177";
const ASSIGNMENT_TO_GLOBAL: string = "E0179";
const RETURN_OUTSIDE_FUNCTION_BODY: string = "E0180";
const GLOBAL_INITIALIZATION_CYCLE: string = "E0181";
const INIT_SUSPEND_NOT_ALLOWED: string = "E0182";
const INIT_THROW_NOT_HANDLED: string = "E0183";
const LLM_OUTPUT_MEMBER_DROPPED: string = "E0184";
const LLM_OUTPUT_FIELD_ALWAYS_NULL: string = "E0185";
const INVALID_JSON_ATTRIBUTE: string = "E0186";
const LOOP_CONTROL_OUTSIDE_LOOP: string = "E0187";
const LOOP_CONTROL_IN_LOOP_HEADER: string = "E0188";

// port: baml_compiler_diagnostics/src/diagnostic.rs::Annotation @ d9be6853b
// An annotation pointing to a span in the source code.
class Annotation {
    span: root.base.Span,
    // Null for a span-only annotation.
    message: string?,
    message_highlights: DiagnosticMessageHighlight[],
    is_primary: bool,

    // port: baml_compiler_diagnostics/src/diagnostic.rs::Annotation::primary @ d9be6853b
    function primary(
        span: root.base.Span,
        message: string | DiagnosticText,
    ) -> Annotation throws never {
        let text = diagnostic_text_from(message);
        Annotation {
            span: span,
            message: text.text_value,
            message_highlights: text.highlights,
            is_primary: true,
        }
    }

    // port: baml_compiler_diagnostics/src/diagnostic.rs::Annotation::primary_span @ d9be6853b
    function primary_span(span: root.base.Span) -> Annotation throws never {
        Annotation { span: span, message: null, message_highlights: [], is_primary: true }
    }

    // port: baml_compiler_diagnostics/src/diagnostic.rs::Annotation::secondary @ d9be6853b
    function secondary(
        span: root.base.Span,
        message: string | DiagnosticText,
    ) -> Annotation throws never {
        let text = diagnostic_text_from(message);
        Annotation {
            span: span,
            message: text.text_value,
            message_highlights: text.highlights,
            is_primary: false,
        }
    }
}

// port: baml_compiler_diagnostics/src/diagnostic.rs::RelatedInfo @ d9be6853b
// Related diagnostic information (for cross-file references).
class RelatedInfo {
    span: root.base.Span,
    message: string,
    message_highlights: DiagnosticMessageHighlight[],
    // Optional file path for display purposes.
    file_path: string?,

    // port: baml_compiler_diagnostics/src/diagnostic.rs::RelatedInfo::new @ d9be6853b
    function new(
        span: root.base.Span,
        message: string | DiagnosticText,
    ) -> RelatedInfo throws never {
        let text = diagnostic_text_from(message);
        RelatedInfo {
            span: span,
            message: text.text_value,
            message_highlights: text.highlights,
            file_path: null,
        }
    }
}

// port: baml_compiler_diagnostics/src/diagnostic.rs::Diagnostic @ d9be6853b
// A unified diagnostic for any compiler error. Rust's `id: DiagnosticId` is
// its code here (`id`), as the constants above name ids. The builder methods
// append in place and return `self`. `DiagnosticPhase` is
// `root.hir.DiagnosticPhase` and `Severity` is `root.base.Severity`.
class Diagnostic {
    id: string,
    severity: root.base.Severity,
    message: string,
    message_highlights: DiagnosticMessageHighlight[],
    annotations: Annotation[],
    related_info: RelatedInfo[],
    phase: root.hir.DiagnosticPhase,

    // port: baml_compiler_diagnostics/src/diagnostic.rs::Diagnostic::new @ d9be6853b
    function new(
        id: string,
        severity: root.base.Severity,
        message: string | DiagnosticText,
    ) -> Diagnostic throws never {
        let text = diagnostic_text_from(message);
        Diagnostic {
            id: id,
            severity: severity,
            message: text.text_value,
            message_highlights: text.highlights,
            annotations: [],
            related_info: [],
            phase: root.hir.DiagnosticPhase.Parse,
        }
    }

    // port: baml_compiler_diagnostics/src/diagnostic.rs::Diagnostic::error @ d9be6853b
    function error(id: string, message: string | DiagnosticText) -> Diagnostic throws never {
        Diagnostic.new(id, root.base.Severity.Error, message)
    }

    // port: baml_compiler_diagnostics/src/diagnostic.rs::Diagnostic::warning @ d9be6853b
    function warning(id: string, message: string | DiagnosticText) -> Diagnostic throws never {
        Diagnostic.new(id, root.base.Severity.Warning, message)
    }

    // port: baml_compiler_diagnostics/src/diagnostic.rs::Diagnostic::with_phase @ d9be6853b
    function with_phase(self, phase: root.hir.DiagnosticPhase) -> Diagnostic throws never {
        self.phase = phase;
        self
    }

    // port: baml_compiler_diagnostics/src/diagnostic.rs::Diagnostic::with_primary @ d9be6853b
    function with_primary(
        self,
        span: root.base.Span,
        message: string | DiagnosticText,
    ) -> Diagnostic throws never {
        self.annotations.push(Annotation.primary(span, message));
        self
    }

    // port: baml_compiler_diagnostics/src/diagnostic.rs::Diagnostic::with_primary_span @ d9be6853b
    function with_primary_span(self, span: root.base.Span) -> Diagnostic throws never {
        self.annotations.push(Annotation.primary_span(span));
        self
    }

    // port: baml_compiler_diagnostics/src/diagnostic.rs::Diagnostic::with_secondary @ d9be6853b
    function with_secondary(
        self,
        span: root.base.Span,
        message: string | DiagnosticText,
    ) -> Diagnostic throws never {
        self.annotations.push(Annotation.secondary(span, message));
        self
    }

    // port: baml_compiler_diagnostics/src/diagnostic.rs::Diagnostic::with_related @ d9be6853b
    function with_related(
        self,
        span: root.base.Span,
        message: string | DiagnosticText,
    ) -> Diagnostic throws never {
        self.related_info.push(RelatedInfo.new(span, message));
        self
    }

    // port: baml_compiler_diagnostics/src/diagnostic.rs::Diagnostic::primary_span @ d9be6853b
    // The span of the first primary annotation.
    function primary_span(self) -> root.base.Span? throws never {
        self.annotations
            .find((a) -> {
                a.is_primary
            })
            ?.span
    }

    // port: baml_compiler_diagnostics/src/diagnostic.rs::Diagnostic::message_with_primary_label @ d9be6853b
    // The headline plus a distinct primary annotation label.
    function message_with_primary_label(self) -> string throws never {
        let label = self.annotations
            .find((a) -> {
                a.is_primary
            })
            ?.message;
        if (label != null && label != self.message) {
            `${self.message}: ${label}`
        } else {
            self.message
        }
    }
}
