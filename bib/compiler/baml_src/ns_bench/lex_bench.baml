// Lexer speed spike: lex every .baml file under `dir` and report throughput.

class LexBench {
    files: int,
    bytes: int,
    tokens: int,
    millis: bigint,
}

function lex_dir(dir: string) -> LexBench throws baml.errors.Io | baml.errors.ParseError {
    let paths = baml.glob.new("**/*.baml").scan(dir);
    let sources = paths.map((path) -> {
        baml.fs.read(`${dir}/${path}`)
    });
    let started = baml.time.Instant.now();
    let tokens = sources
        .map((text) -> {
            root.syntax.lex(text).kinds.length()
        })
        .reduce(
            (a, b) -> {
                a + b
            },
            0,
        );
    let millis = started.elapsed().to_milliseconds();
    LexBench {
        files: sources.length(),
        bytes: sources
            .map((text) -> {
                text.byte_length()
            })
            .reduce(
                (a, b) -> {
                    a + b
                },
                0,
            ),
        tokens: tokens,
        millis: millis,
    }
}
