// port: baml_parser/src/sink.rs (with the tree builder it wraps) @ d9be6853b
//
// Where the parse goes: the diagnostics, and the few node kinds a pass reads
// back from the whole tree so far (every `Bogus`, every `//#` header). Nodes
// themselves are built as class literals by the grammar, so there is no
// arena; a discarded speculation simply drops its nodes, and the registries
// here are truncated back to the speculation's start.
//
// The two recovery values have exactly one way in each, and both take the
// diagnostic they belong to: `Missing` from `missing`, `Bogus` from `bogus`.

// The lengths of the sink's lists at a point, to roll a speculation back to.
class SinkMark {
    errors: int,
    bogus: int,
    header_stmts: int,
    header_lines: int,
}

class Sink {
    errors: ParseError[],
    bogus_nodes: Bogus[],
    header_stmts: HeaderStmt[],
    header_lines: HeaderLine[],

    function new() -> Sink throws never {
        Sink { errors: [], bogus_nodes: [], header_stmts: [], header_lines: [] }
    }

    function checkpoint(self) -> SinkMark throws never {
        SinkMark {
            errors: self.errors.length(),
            bogus: self.bogus_nodes.length(),
            header_stmts: self.header_stmts.length(),
            header_lines: self.header_lines.length(),
        }
    }

    // Drop the nodes registered since `mark`, and the diagnostics too when
    // `errors` is set (a probe).
    function rollback(self, mark: SinkMark, errors: bool) -> void throws never {
        truncate(self.bogus_nodes, mark.bogus);
        truncate(self.header_stmts, mark.header_stmts);
        truncate(self.header_lines, mark.header_lines);
        if (errors) {
            truncate(self.errors, mark.errors);
        }
    }

    // ----- nodes read back --------------------------------------------------------

    // The spans of every `Bogus` so far.
    function bogus_spans(self) -> TokenRange[] throws never {
        self.bogus_nodes.map((node) -> {
            node.span
        })
    }

    // port: owned_tokens::<HeaderStmt> + owned_tokens::<HeaderLine>. The
    // `//#` tokens the header nodes own so far.
    function owned_header_tokens(self) -> int[] throws never {
        self.header_stmts
            .map((node) -> {
                node.token
            })
            .concat(
                self.header_lines.map((node) -> {
                    node.token
                }),
            )
    }

    // A `//#` statement, registered so the header pass can find it.
    function header_stmt(self, node: HeaderStmt) -> HeaderStmt throws never {
        self.header_stmts.push(node);
        node
    }

    // A `//#` title line, registered so the header pass can find it.
    function header_line(self, node: HeaderLine) -> HeaderLine throws never {
        self.header_lines.push(node);
        node
    }

    // ----- diagnostics --------------------------------------------------------------

    function report(self, error: ParseError) -> void throws never {
        self.errors.push(error);
    }

    // A required position the text did not fill, with its report.
    function missing(self, error: ParseError) -> Missing throws never {
        self.report(error);
        Missing { at: parse_error_range(error).start }
    }

    // Tokens that fit no node, with their report.
    function bogus(self, tokens: TokenRange, error: ParseError) -> Bogus throws never {
        self.report(error);
        let node = Bogus { span: tokens };
        self.bogus_nodes.push(node);
        node
    }
}

// Shorten `items` to its first `len` elements.
function truncate<T>(items: T[], len: int) -> void throws never {
    while (items.length() > len) {
        items.pop();
    }
}
