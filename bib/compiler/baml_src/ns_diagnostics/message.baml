// port: baml_compiler_diagnostics/src/message.rs @ d9be6853b
//
// Highlight offsets are UTF-8 byte offsets into the text, as in Rust.

// port: baml_compiler_diagnostics/src/message.rs::DiagnosticIdentifierKind @ d9be6853b
enum DiagnosticIdentifierKind {
    Type,
    Function,
    Field,
    Variable,
    EnumVariant,
    Attribute,
}

// port: baml_compiler_diagnostics/src/message.rs::DiagnosticMessageKind @ d9be6853b
type DiagnosticMessageKind = DiagnosticMessageKindIdentifier
    | DiagnosticMessageKindTypeExpression
    | DiagnosticMessageKindCode;

class DiagnosticMessageKindIdentifier {
    value: DiagnosticIdentifierKind,
}

class DiagnosticMessageKindTypeExpression {
}

class DiagnosticMessageKindCode {
}

// port: baml_compiler_diagnostics/src/message.rs::DiagnosticMessageHighlight @ d9be6853b
class DiagnosticMessageHighlight {
    start: int,
    end: int,
    kind: DiagnosticMessageKind,
}

// The byte value of a backtick.
const BACKTICK_BYTE: int = 96;

// port: baml_compiler_diagnostics/src/message.rs::DiagnosticText @ d9be6853b
// Message text plus the styled ranges inside it. The builder methods append
// in place and return `self`, so chains read as in Rust.
class DiagnosticText {
    // Rust's private `text`; suffixed because `text` is also a method. Read
    // it directly (Rust's `as_str`, `into_parts`).
    text_value: string,
    highlights: DiagnosticMessageHighlight[],

    // port: baml_compiler_diagnostics/src/message.rs::DiagnosticText::new @ d9be6853b
    // Also `Default`.
    function new() -> DiagnosticText throws never {
        DiagnosticText { text_value: "", highlights: [] }
    }

    // port: baml_compiler_diagnostics/src/message.rs::DiagnosticText::from_inline_code @ d9be6853b
    // Plain text whose backticked spans become `Code` highlights; an empty
    // pair of backticks highlights nothing, and an unclosed one ends the scan.
    function from_inline_code(text: string) -> DiagnosticText throws never {
        let bytes = text.to_utf8();
        let highlights: DiagnosticMessageHighlight[] = [];
        let open: int? = null;
        for (let i = 0; i < bytes.length(); i += 1) {
            if (bytes[i] != BACKTICK_BYTE) {
                continue;
            }
            if (open == null) {
                open = i;
                continue;
            }
            let content_start = open + 1;
            if (content_start < i) {
                highlights.push(DiagnosticMessageHighlight { start: content_start, end: i, kind: DiagnosticMessageKindCode {} });
            }
            open = null;
        }
        DiagnosticText { text_value: text, highlights: highlights }
    }

    // port: baml_compiler_diagnostics/src/message.rs::DiagnosticText::text @ d9be6853b
    function text(self, value: string) -> DiagnosticText throws never {
        self.text_value = `${self.text_value}${value}`;
        self
    }

    // port: baml_compiler_diagnostics/src/message.rs::DiagnosticText::identifier @ d9be6853b
    function identifier(self, value: string, kind: DiagnosticIdentifierKind) -> DiagnosticText throws never {
        self.fragment(value, DiagnosticMessageKindIdentifier { value: kind })
    }

    // port: baml_compiler_diagnostics/src/message.rs::DiagnosticText::type_expr @ d9be6853b
    function type_expr(self, value: string) -> DiagnosticText throws never {
        self.fragment(value, DiagnosticMessageKindTypeExpression {})
    }

    // port: baml_compiler_diagnostics/src/message.rs::DiagnosticText::code @ d9be6853b
    function code(self, value: string) -> DiagnosticText throws never {
        self.fragment(value, DiagnosticMessageKindCode {})
    }

    // port: baml_compiler_diagnostics/src/message.rs::DiagnosticText::fragment @ d9be6853b
    // `value` in backticks, the inside highlighted as `kind`.
    function fragment(self, value: string, kind: DiagnosticMessageKind) -> DiagnosticText throws never {
        self.text_value = `${self.text_value}\``;
        let start = self.text_value.byte_length();
        self.text_value = `${self.text_value}${value}`;
        let end = self.text_value.byte_length();
        self.text_value = `${self.text_value}\``;
        self.highlights.push(DiagnosticMessageHighlight { start: start, end: end, kind: kind });
        self
    }

    // port: baml_compiler_diagnostics/src/message.rs::impl Display for DiagnosticText @ d9be6853b
    implements baml.ToString {
        function to_string(self) -> string throws never {
            self.text_value
        }
    }
}

// port: baml_compiler_diagnostics/src/message.rs::impl From<String> for DiagnosticText @ d9be6853b
// Also `From<&str>` and `From<&String>`: Rust's `impl Into<DiagnosticText>`
// parameters take `string | DiagnosticText` here and convert through this.
function diagnostic_text_from(message: string | DiagnosticText) -> DiagnosticText throws never {
    match (message) {
        let text: string => DiagnosticText.from_inline_code(text),
        let text: DiagnosticText => text,
    }
}
