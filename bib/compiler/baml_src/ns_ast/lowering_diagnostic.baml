// port: baml_compiler2_ast/src/lowering_diagnostic.rs @ d9be6853b
//
// Diagnostics emitted during CST → AST lowering: structural problems
// ("missing name token", "unparseable type") rather than semantic ones.
// Ranges are file-relative; the file is added when converting.

// port: lowering_diagnostic.rs::DESTRUCTURING_DOCS_URL. The book chapter on
// patterns and destructuring, linked from `InvalidAssignmentTarget`.
const DESTRUCTURING_DOCS_URL: string = "https://developer.boundaryml.com/baml/book/patterns";

// port: lowering_diagnostic.rs::TestBlockKind. Which keyword a test block was
// written with.
enum TestBlockKind {
    Test,
    Testset,
}

// port: lowering_diagnostic.rs::LoweringDiagnostic
type LoweringDiagnostic = LoweringDiagnosticInvalidBuiltinTypeArguments
    | LoweringDiagnosticSpecTargetNotFunctionName
    | LoweringDiagnosticUnparseableType
    | LoweringDiagnosticUnsupportedParameterDefault
    | LoweringDiagnosticReservedLlmParam
    | LoweringDiagnosticGeneratorBlockInBaml
    | LoweringDiagnosticInstanceofRemoved
    | LoweringDiagnosticEmptyInterpolation
    | LoweringDiagnosticWildcardTypeNotAllowed
    | LoweringDiagnosticInvalidPatternAscription
    | LoweringDiagnosticInvalidTopLevelLet
    | LoweringDiagnosticTopLevelLetType
    | LoweringDiagnosticTestOutsideTestset
    | LoweringDiagnosticConstBindingIntroducer
    | LoweringDiagnosticLetInConstDestructure
    | LoweringDiagnosticTopLevelLetIntroducer
    | LoweringDiagnosticReservedConstBindingName
    | LoweringDiagnosticInvalidAssignmentTarget
    | LoweringDiagnosticMissingObjectConstructor
    | LoweringDiagnosticInterfaceFieldDeclaredInImplementsBlock
    | LoweringDiagnosticTypeArgsOnNonPathBase
    | LoweringDiagnosticClientBlockRemoved
    | LoweringDiagnosticRetryPolicyRemoved
    | LoweringDiagnosticLlmJinjaPromptRemoved
    | LoweringDiagnosticQuotedPromptInterpolation
    | LoweringDiagnosticTemplateStringRemoved
    | LoweringDiagnosticInvalidLlmClient
    | LoweringDiagnosticInvalidNumericLiteral;

// Builtin aliases have a fixed arity and no associated bindings; reported
// before lowering erases their written type arguments.
class LoweringDiagnosticInvalidBuiltinTypeArguments {
    name: string,
    expected: int,
    got: int,
    associated_bindings: int,
    span: root.syntax.TextRange,
}

// `expr@spec(…)` whose `expr` is not a bare function name.
class LoweringDiagnosticSpecTargetNotFunctionName {
    span: root.syntax.TextRange,
}

// A type expression could not be parsed.
class LoweringDiagnosticUnparseableType {
    // "field `Foo.bar`", "return type", "parameter `x`"
    context: string,
    span: root.syntax.TextRange,
}

// A parameter default in a context that does not support defaults.
class LoweringDiagnosticUnsupportedParameterDefault {
    context: string,
    span: root.syntax.TextRange,
}

// A user LLM function parameter that collides with a binding the LLM
// lowering owns.
class LoweringDiagnosticReservedLlmParam {
    function_name: string,
    param_name: string,
    reserved_for: string,
    span: root.syntax.TextRange,
}

// A `generator { … }` block in `.baml`; generators live in `baml.toml` now.
class LoweringDiagnosticGeneratorBlockInBaml {
    name: string?,
    span: root.syntax.TextRange,
}

// The removed `instanceof` operator.
class LoweringDiagnosticInstanceofRemoved {
    span: root.syntax.TextRange,
}

// A `${}` interpolation with no expression inside.
class LoweringDiagnosticEmptyInterpolation {
    span: root.syntax.TextRange,
}

// The `_` wildcard type where it cannot be inferred.
class LoweringDiagnosticWildcardTypeNotAllowed {
    context: string,
    span: root.syntax.TextRange,
}

// A `:` ascription on a pattern that takes none (only `let x: T` and
// `[…]: T` do).
class LoweringDiagnosticInvalidPatternAscription {
    reason: string,
    span: root.syntax.TextRange,
}

// A file-scope binding that does not bind exactly one name.
class LoweringDiagnosticInvalidTopLevelLet {
    reason: string,
    span: root.syntax.TextRange,
}

// A `let type` binding at file scope, where there is no block to bind in.
class LoweringDiagnosticTopLevelLetType {
    span: root.syntax.TextRange,
}

// A `test`/`testset` block in a body that is no testset's.
class LoweringDiagnosticTestOutsideTestset {
    kind: TestBlockKind,
    span: root.syntax.TextRange,
}

// `const` currently parses as a non-immutable alias for `let`.
class LoweringDiagnosticConstBindingIntroducer {
    span: root.syntax.TextRange,
}

class LoweringDiagnosticLetInConstDestructure {
    span: root.syntax.TextRange,
    const_span: root.syntax.TextRange,
}

// `let` introducing a global variable; globals are declared with `const`.
class LoweringDiagnosticTopLevelLetIntroducer {
    span: root.syntax.TextRange,
}

// `const` used as a binding name.
class LoweringDiagnosticReservedConstBindingName {
    span: root.syntax.TextRange,
}

// The left side of an assignment is not a place. `destructure` is set for a
// plain `=` into a class or array literal, which reads as a destructure.
class LoweringDiagnosticInvalidAssignmentTarget {
    span: root.syntax.TextRange,
    destructure: bool,
}

// Parser recovery produced an object literal without a constructor name.
class LoweringDiagnosticMissingObjectConstructor {
    span: root.syntax.TextRange,
}

// A field declared inside an `implements` block (the obsolete model).
class LoweringDiagnosticInterfaceFieldDeclaredInImplementsBlock {
    interface_name: string,
    field_name: string,
    span: root.syntax.TextRange,
}

// `<...>` applied to an expression that is not a plain function reference.
class LoweringDiagnosticTypeArgsOnNonPathBase {
    span: root.syntax.TextRange,
}

// A removed `client<llm> Name { ... }` block; `provider` is its own
// `provider` value, which picks the suggested replacement.
class LoweringDiagnosticClientBlockRemoved {
    name: string,
    provider: string?,
    span: root.syntax.TextRange,
}

// A removed `retry_policy` block.
class LoweringDiagnosticRetryPolicyRemoved {
    name: string,
    span: root.syntax.TextRange,
}

// A removed Jinja `#"..."#` prompt on an LLM function.
class LoweringDiagnosticLlmJinjaPromptRemoved {
    span: root.syntax.TextRange,
}

// A `${` in a quoted LLM prompt, which reaches the model as literal text.
class LoweringDiagnosticQuotedPromptInterpolation {
    span: root.syntax.TextRange,
}

// A removed `template_string` declaration.
class LoweringDiagnosticTemplateStringRemoved {
    span: root.syntax.TextRange,
}

// The LLM function's `client` value cannot be used.
class LoweringDiagnosticInvalidLlmClient {
    function_name: string,
    reason: string,
    span: root.syntax.TextRange,
}

// A numeric literal token failed validation. `InvalidDigits` gets one
// diagnostic per offending digit, spanning that digit.
class LoweringDiagnosticInvalidNumericLiteral {
    error: root.base.IntLitError,
    span: root.syntax.TextRange,
}

// port: baml_compiler2_ast/src/lowering_diagnostic.rs::client_replacement_expr @ d9be6853b
// The client expression a removed `client<llm>` block should become, by its
// own `provider` value: the class that speaks that provider's protocol (the
// same set the "provider/model" shorthand resolves). An unknown or absent
// provider keeps the generic OpenAI suggestion. Known gap: composite
// providers get a shape, not their configured strategy list.
function client_replacement_expr(provider: string?) -> string throws never {
    let normalized = if (provider != null) {
        trim_matches_quote(provider.trim())
    } else {
        null
    };
    match (normalized) {
        "anthropic" => "anthropic.Client.new(model = \"...\")",
        "google-ai" | "google" | "gemini" => "google.GeminiClient.new(model = \"...\")",
        "vertex-ai" | "vertex" => "google.VertexClient.new(model = \"...\")",
        "aws-bedrock" | "bedrock" => "aws.BedrockClient.new(model = \"...\")",
        "azure-openai" | "azure" => "openai.AzureClient.new(model = \"...\", base_url = \"...\")",
        "ollama" => "openai.OllamaClient.new(model = \"...\")",
        "openrouter" => "openai.OpenRouterClient.new(model = \"...\")",
        "openai-generic" => "openai.GenericClient.new(model = \"...\", base_url = \"...\")",
        "openai-chat" => "openai.ChatClient.new(model = \"...\")",
        "fallback" => "ai.Fallback.new(members = [FirstClient, SecondClient])",
        "round-robin" => "ai.RoundRobin.new(members = [FirstClient, SecondClient])",
        _ => "openai.ResponsesClient.new(model = \"...\")",
    }
}

// Rust's `str::trim_matches('"')`: every leading and trailing `"` removed.
function trim_matches_quote(s: string) -> string throws never {
    let chars = s.chars();
    let start = chars.find_index((c) -> {
        c != "\""
    })
        ?? chars.length();
    let end = (
        chars.find_last_index((c) -> {
            c != "\""
        })
            ?? -1
    )
        + 1;
    chars.slice(start, end).join("")
}

// What `to_diagnostic` reads off a lowering diagnostic: the Rust match's
// `(id, severity, message, range, label)` tuple.
class LoweringReport {
    code: string,
    severity: root.base.Severity,
    message: string,
    range: root.syntax.TextRange,
    label: string,
}

// port: baml_compiler2_ast/src/lowering_diagnostic.rs::LoweringDiagnostic::to_diagnostic @ d9be6853b
// The diagnostic for a lowering problem in `file`, in the shape
// `reflect.Package.compile` reports (phase "hir"), with the conventions of
// `root.syntax.parse_error_diagnostic`. `message` is the headline plus the
// primary label when the label differs (`message_with_primary_label`).
function to_diagnostic(
    diagnostic: LoweringDiagnostic,
    file: string,
) -> reflect.Diagnostic throws never {
    let report = lowering_report(diagnostic);
    let message = if (report.label != report.message) {
        `${report.message}: ${report.label}`
    } else {
        report.message
    };
    // The secondary annotation is the one `with_secondary` adds. The primary
    // is left out of `annotations`, as `parse_error_diagnostic` does.
    let annotations: reflect.DiagnosticAnnotation[] = match (diagnostic) {
        let d: LoweringDiagnosticLetInConstDestructure => {
            [
                reflect.DiagnosticAnnotation {
                    span: reflect.Span { file: file, start: d.const_span.start, end: d.const_span.end },
                    message: "the destructure starts with `const` here",
                    message_highlights: [],
                    is_primary: false,
                },
            ]
        },
        _ => [],
    };
    reflect.Diagnostic {
        code: report.code,
        span: reflect.Span { file: file, start: report.range.start, end: report.range.end },
        message: message,
        severity: match (report.severity) {
            root.base.Severity.Error => "error",
            root.base.Severity.Warning => "warning",
            root.base.Severity.Info => "info",
        },
        phase: "hir",
        headline: report.message,
        primary_label: report.label,
        message_highlights: [],
        annotations: annotations,
        related_info: [],
    }
}

// The match at the top of `to_diagnostic`. (`GeneratorBlockInBaml` returns
// early in Rust only to use a different severity; it fits the same shape.)
function lowering_report(diagnostic: LoweringDiagnostic) -> LoweringReport throws never {
    let error = root.base.Severity.Error;
    let warning = root.base.Severity.Warning;
    let r = (
        code: string,
        severity: root.base.Severity,
        message: string,
        range: root.syntax.TextRange,
        label: string,
    ) -> LoweringReport {
        LoweringReport {
            code: code,
            severity: severity,
            message: message,
            range: range,
            label: label,
        }
    };
    match (diagnostic) {
        let d: LoweringDiagnosticInvalidBuiltinTypeArguments => {
            r(
                root.diagnostics.INVALID_BUILTIN_TYPE_ARGUMENTS,
                error,
                if (d.associated_bindings == 0) {
                    `type \`${d.name}\` expects ${d.expected} type argument(s), got ${d.got}`
                } else {
                    `builtin type \`${d.name}\` does not accept associated-type bindings`
                },
                d.span,
                "invalid builtin type arguments",
            )
        },
        let d: LoweringDiagnosticSpecTargetNotFunctionName => {
            r(
                root.diagnostics.INVALID_SYNTAX,
                error,
                "`@spec` applies to a function name: write `Function@spec(...)` without type arguments or parentheses around the name",
                d.span,
                "not a function name",
            )
        },
        let d: LoweringDiagnosticUnparseableType => {
            r(
                root.diagnostics.UNPARSEABLE_TYPE,
                error,
                `could not parse type expression for ${d.context}`,
                d.span,
                "unparseable type",
            )
        },
        let d: LoweringDiagnosticUnsupportedParameterDefault => {
            r(
                root.diagnostics.INVALID_SYNTAX,
                error,
                `parameter defaults are not supported in ${d.context}`,
                d.span,
                "default value is not allowed here",
            )
        },
        let d: LoweringDiagnosticReservedLlmParam => {
            r(
                root.diagnostics.INVALID_SYNTAX,
                error,
                `LLM function \`${d.function_name}\` cannot declare a parameter named \`${d.param_name}\`; \`${d.param_name}\` is reserved for ${d.reserved_for}`,
                d.span,
                "reserved LLM parameter name",
            )
        },
        let d: LoweringDiagnosticGeneratorBlockInBaml => {
            let what = if let n: string = d.name {
                `\`generator ${n}\``
            } else {
                "this `generator` block"
            };
            r(
                root.diagnostics.GENERATOR_BLOCK_UNSUPPORTED,
                warning,
                `${what} is ignored: code generators are configured in \`baml.toml\` now. Move it to a \`[generator.<name>]\` section in \`baml.toml\`.`,
                d.span,
                "move this to baml.toml",
            )
        },
        let d: LoweringDiagnosticInstanceofRemoved => {
            r(
                root.diagnostics.REMOVED_FEATURE,
                error,
                "`instanceof` is no longer supported. Use a `match` expression for type checking instead.",
                d.span,
                "use `match` instead",
            )
        },
        // A warning: an empty `${}` renders to the empty string.
        let d: LoweringDiagnosticEmptyInterpolation => {
            r(
                root.diagnostics.INVALID_SYNTAX,
                warning,
                "empty interpolation ${} has no expression",
                d.span,
                "expected an expression inside ${…}",
            )
        },
        let d: LoweringDiagnosticWildcardTypeNotAllowed => {
            r(
                root.diagnostics.WILDCARD_TYPE_NOT_ALLOWED,
                error,
                `the \`_\` wildcard type can only be inferred in a \`let\` binding or a \`throws\` clause, not in ${d.context}`,
                d.span,
                "`_` cannot be inferred here",
            )
        },
        let d: LoweringDiagnosticInvalidPatternAscription => {
            r(
                root.diagnostics.TYPE_MISMATCH,
                error,
                `invalid pattern type ascription: ${d.reason}`,
                d.span,
                "type ascription not allowed here",
            )
        },
        let d: LoweringDiagnosticInvalidTopLevelLet => {
            r(
                root.diagnostics.INVALID_SYNTAX,
                error,
                `invalid top-level \`const\`: ${d.reason}`,
                d.span,
                "a global variable binds one name: `const NAME = value;` or `const NAME: Type = value;`",
            )
        },
        let d: LoweringDiagnosticTestOutsideTestset => {
            r(
                root.diagnostics.INVALID_SYNTAX,
                error,
                "invalid syntax",
                d.span,
                match (d.kind) {
                    TestBlockKind.Test => {
                        "test blocks are only allowed at the top level or inside a testset"
                    },
                    TestBlockKind.Testset => {
                        "testset blocks are only allowed at the top level or inside a testset"
                    },
                },
            )
        },
        let d: LoweringDiagnosticTopLevelLetType => {
            r(
                root.diagnostics.INVALID_SYNTAX,
                error,
                "`let type` binds a type for the rest of a block, so it is only allowed inside a body",
                d.span,
                "move this binding into a function body",
            )
        },
        let d: LoweringDiagnosticConstBindingIntroducer => {
            r(
                root.diagnostics.INVALID_SYNTAX,
                warning,
                "`const` is currently treated like `let`; BAML does not enforce immutability yet. Use `let` for current BAML semantics.",
                d.span,
                "`const` behaves like `let` for now",
            )
        },
        let d: LoweringDiagnosticLetInConstDestructure => {
            r(
                root.diagnostics.INVALID_SYNTAX,
                error,
                "a destructure started with `const` binds only with `const`",
                d.span,
                "write `const` here, or start the destructure with `let` to mix introducers",
            )
        },
        let d: LoweringDiagnosticTopLevelLetIntroducer => {
            r(
                root.diagnostics.INVALID_SYNTAX,
                error,
                "global variables are declared with `const`: `const NAME = value;`",
                d.span,
                "write `const` here; `let` is only allowed inside a body",
            )
        },
        let d: LoweringDiagnosticReservedConstBindingName => {
            r(
                root.diagnostics.INVALID_SYNTAX,
                error,
                "`const` is reserved and cannot be used as a binding name",
                d.span,
                "`const` is reserved here",
            )
        },
        let d: LoweringDiagnosticInvalidAssignmentTarget => {
            r(
                root.diagnostics.INVALID_SYNTAX,
                error,
                if (d.destructure) {
                    `invalid assignment target; the left side of \`=\` is an expression, not a pattern. To destructure, use a \`let\` pattern: see ${DESTRUCTURING_DOCS_URL}`
                } else {
                    "invalid assignment target; only a variable, a field, or an index can be assigned to"
                },
                d.span,
                "cannot assign to this expression",
            )
        },
        let d: LoweringDiagnosticMissingObjectConstructor => {
            r(
                root.diagnostics.INVALID_SYNTAX,
                error,
                "object construction requires a class or type name",
                d.span,
                "expected a constructor name before `{`",
            )
        },
        let d: LoweringDiagnosticInterfaceFieldDeclaredInImplementsBlock => {
            r(
                root.diagnostics.INTERFACE_FIELD_DECLARED_IN_IMPLEMENTS_BLOCK,
                error,
                `field \`${d.field_name}\` cannot be declared inside \`implements ${d.interface_name}\``,
                d.span,
                "add a class field, or link it with `field as class_field`",
            )
        },
        let d: LoweringDiagnosticTypeArgsOnNonPathBase => {
            r(
                root.diagnostics.INVALID_SYNTAX,
                error,
                "type arguments can only be applied to a function reference",
                d.span,
                "specialize a generic function directly, e.g. `foo<int>`",
            )
        },
        let d: LoweringDiagnosticClientBlockRemoved => {
            r(
                root.diagnostics.INVALID_SYNTAX,
                error,
                `\`client<llm>\` config blocks are removed; declare a client value instead: \`client ${d.name} = ${client_replacement_expr(d.provider)};\` (compose reliability with ai.Retry / ai.Fallback / ai.RoundRobin)`,
                d.span,
                "replace with `client Name = <expr>;`",
            )
        },
        let d: LoweringDiagnosticRetryPolicyRemoved => {
            r(
                root.diagnostics.INVALID_SYNTAX,
                error,
                `\`retry_policy\` blocks are removed; wrap the client instead: \`client Reliable = ai.Retry.new(<inner>, max_attempts = ...);\` (\`${d.name}\` has no effect)`,
                d.span,
                "retry composes at the client boundary now",
            )
        },
        let d: LoweringDiagnosticLlmJinjaPromptRemoved => {
            r(
                root.diagnostics.INVALID_SYNTAX,
                error,
                "Jinja `#\"...\"#` prompts are no longer supported. Use a backtick prompt with `${...}` interpolation instead.",
                d.span,
                "use a backtick prompt instead",
            )
        },
        // A warning: the prompt renders, with the marker verbatim.
        let d: LoweringDiagnosticQuotedPromptInterpolation => {
            r(
                root.diagnostics.INVALID_SYNTAX,
                warning,
                "`${...}` in a quoted prompt is sent to the model as literal text — `\"...\"` strings do not interpolate. Use a backtick prompt to interpolate, or write `\\${...}` in a backtick prompt to keep the literal `${`.",
                d.span,
                "literal text here, not an interpolation",
            )
        },
        let d: LoweringDiagnosticTemplateStringRemoved => {
            r(
                root.diagnostics.INVALID_SYNTAX,
                error,
                "`template_string` declarations are no longer supported. Use a function returning a backtick string instead.",
                d.span,
                "use a function returning a backtick string instead",
            )
        },
        let d: LoweringDiagnosticInvalidLlmClient => {
            r(
                root.diagnostics.INVALID_SYNTAX,
                error,
                `LLM function \`${d.function_name}\` has an unusable \`client\`: ${d.reason}`,
                d.span,
                "use a \"provider/model\" string or an expression evaluating to ai.Client",
            )
        },
        let d: LoweringDiagnosticInvalidNumericLiteral => {
            r(
                root.diagnostics.INVALID_NUMERIC_LITERAL,
                error,
                root.base.int_lit_error_message(d.error),
                d.span,
                match (d.error) {
                    root.base.IntLitErrorUppercaseBasePrefix => {
                        "base prefixes (`0x`, `0o`, `0b`) are lowercase"
                    },
                    root.base.IntLitErrorNoDigits => "expected at least one digit",
                    root.base.IntLitErrorInvalidDigits => "invalid digit",
                    root.base.IntLitErrorTooLarge => {
                        "does not fit in `int`; use a `bigint` literal (`n` suffix) for arbitrary precision"
                    },
                },
            )
        },
    }
}
