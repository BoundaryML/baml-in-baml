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
