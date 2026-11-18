// port: baml_compiler2_ast/src/lower_tree/mod.rs @ d9be6853b
//
// Lowering from the typed syntax tree (namespace `syntax`) to the AST arenas.
// Spans are the node's own: never trivia, and a postfix modifier spans the
// type it modifies plus itself.

// port: lower_tree/mod.rs::View. A read-only view of the tree being lowered:
// the lookups every lowering function needs, named for what they return.
// Rust takes node ids; here a node's `span` (or `root.syntax.node_span(any)`
// for a union) stands for the node.
class View {
    tree: root.syntax.FileTree,

    // The text range of a node's tokens, trivia inside included, none outside.
    function range(self, span: root.syntax.TokenRange) -> root.syntax.TextRange throws never {
        self.tree.text_range(span)
    }

    function token_range(self, token: int) -> root.syntax.TextRange throws never {
        self.tree.token_range(token)
    }

    function text(self, token: int) -> string throws never {
        self.tree.token_text(token)
    }

    // The source text a node covers.
    function text_of(self, span: root.syntax.TokenRange) -> string throws never {
        self.tree.slice(self.range(span))
    }

    function name(self, name: root.syntax.Name) -> string throws never {
        self.text(name.token)
    }

    function name_range(self, name: root.syntax.Name) -> root.syntax.TextRange throws never {
        self.token_range(name.token)
    }

    // Where something that is not there would have been.
    function missing_range(missing: root.syntax.Missing) -> root.syntax.TextRange throws never {
        root.syntax.TextRange.empty(missing.at)
    }
}
