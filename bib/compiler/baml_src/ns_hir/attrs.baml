// port: baml_compiler2_hir/src/attrs.rs @ d9be6853b
//
// Attribute lowering: the one pass that reads a declaration's attributes.
// Attributes are a fixed vocabulary (`root.base.SCHEMA_ATTRIBUTE_SPECS`), each
// entry with an argument shape and the declaration positions it has meaning
// at. Lowering reads a declaration's raw `@`/`@@` list once and produces the
// position's typed carrier and every attribute diagnostic together, so what
// was checked and what was stored cannot disagree.
//
// deviation: Rust's carrier trait has an associated `POSITION` const and a
// `Default` bound; here the position is the method `position(self)`, and
// `lower_attributes` takes the caller's fresh (default) carrier.

// port: attrs.rs::AttributeValue. One attribute's argument, in the shape its
// spec declares.
type AttributeValue = AttributeValueFlag | AttributeValueText;

// A flag attribute (`@skip`): present or not.
class AttributeValueFlag {
}

// A string attribute (`@alias("k")`): the decoded literal.
class AttributeValueText {
    value: string,
}

// port: attrs.rs::AttributeCarrier. A declaration position's typed attribute
// carrier.
interface AttributeCarrier {
    // port: AttributeCarrier::POSITION
    function position(self) -> root.base.AttributePosition throws never;

    // Store one attribute. Called only for a spec the table allows at
    // `position()`, with a value of the spec's declared shape, so a name this
    // cannot store is a drift between the table and the carrier.
    function record(
        self,
        spec: root.base.SchemaAttributeSpec,
        value: AttributeValue,
    ) -> void throws never;
}

// port: baml_compiler2_hir/src/attrs.rs::lower_attributes @ d9be6853b
// Lower a declaration's attributes into `carrier` (a fresh one of its
// position), reporting unknown names, names without meaning at the position,
// malformed arguments, and repeats of a single-valued attribute.
function lower_attributes<C extends AttributeCarrier>(
    raw: root.ast.RawAttribute[],
    carrier: C,
    diagnostics: Hir2Diagnostic[],
) -> C throws never {
    lower_into(raw, carrier.position(), diagnostics, (spec, value) -> {
        carrier.record(spec, value);
    });
    carrier
}

// port: baml_compiler2_hir/src/attrs.rs::reject_attributes @ d9be6853b
// Lower the attributes of a declaration whose position admits none: every
// attribute written there is diagnosed and nothing is stored.
function reject_attributes(
    raw: root.ast.RawAttribute[],
    position: root.base.AttributePosition,
    diagnostics: Hir2Diagnostic[],
) -> void throws never {
    lower_into(raw, position, diagnostics, (spec, _value) -> {
        baml.sys.panic(
            `the attribute table allows \`${spec.name}\` on ${root.base.attribute_position_describe(position)} but the position has no carrier`,
        );
    });
}

// port: baml_compiler2_hir/src/attrs.rs::lower_into @ d9be6853b
function lower_into(
    raw: root.ast.RawAttribute[],
    position: root.base.AttributePosition,
    diagnostics: Hir2Diagnostic[],
    record: (root.base.SchemaAttributeSpec, AttributeValue) -> void throws never,
) -> void throws never {
    // Sites of each single-valued attribute, in first-seen order, so the E0014
    // diagnostics are deterministic.
    let sites: (string, root.syntax.TextRange[])[] = [];
    for (let attr in raw) {
        let found = root.base.schema_attribute_spec(attr.name);
        if (found == null) {
            diagnostics.push(
                Hir2DiagnosticUnknownAttribute {
                    attr_name: attr.name,
                    position: position,
                    span: attr.span,
                },
            );
            continue;
        }
        let spec: root.base.SchemaAttributeSpec = found;
        if (!spec.allows(position)) {
            diagnostics.push(
                Hir2DiagnosticAttributeNotAllowedHere {
                    attr_name: attr.name,
                    position: position,
                    allowed: spec.positions,
                    span: attr.span,
                },
            );
            continue;
        }
        if (!spec.repeatable) {
            note_site(sites, spec.name, attr.span);
        }
        // A repeat still records: the last write wins, as E0014 says.
        let value = parse_argument(spec, attr, position, diagnostics);
        if (value != null) {
            record(spec, value);
        }
    }
    for (let site in sites) {
        if (site.1.length() >= 2) {
            diagnostics.push(Hir2DiagnosticDuplicateAttribute { attr_name: site.0, sites: site.1 });
        }
    }
}

// port: the `sites` bookkeeping in attrs.rs::lower_into. Add `span` to
// `name`'s sites, starting its entry on first sight.
function note_site(
    sites: (string, root.syntax.TextRange[])[],
    name: string,
    span: root.syntax.TextRange,
) -> void throws never {
    let seen = sites.find((site) -> {
        site.0 == name
    });
    if (seen != null) {
        seen.1.push(span);
    } else {
        sites.push((name, [span]));
    }
}

// port: baml_compiler2_hir/src/attrs.rs::parse_argument @ d9be6853b
// The attribute's argument in its spec's shape, or null after reporting a
// malformed one: a malformed attribute stores nothing rather than a guess.
function parse_argument(
    spec: root.base.SchemaAttributeSpec,
    attr: root.ast.RawAttribute,
    position: root.base.AttributePosition,
    diagnostics: Hir2Diagnostic[],
) -> AttributeValue? throws never {
    let spelled = `${root.base.attribute_position_sigil(position)}${spec.name}`;
    match (spec.arguments) {
        root.base.SchemaAttributeArgumentsNone => {
            if (attr.args.length() == 0) {
                return AttributeValueFlag {};
            }
            diagnostics.push(
                Hir2DiagnosticDiagnosticMessage {
                    diagnostic_id: root.diagnostics.UNEXPECTED_ATTRIBUTE_ARG,
                    message: `\`${spelled}\` does not take any arguments`,
                    span: attr.span,
                },
            );
            null
        },
        root.base.SchemaAttributeArgumentsString => {
            if (attr.args.length() != 1) {
                diagnostics.push(
                    Hir2DiagnosticDiagnosticMessage {
                        diagnostic_id: root.diagnostics.INVALID_ATTRIBUTE_ARG,
                        message: `\`${spelled}\` expects exactly one string argument`,
                        span: attr.span,
                    },
                );
                return null;
            }
            let arg = attr.args[0];
            let text = root.ast.parse_string_attr_value(arg.value);
            if (text != null) {
                return AttributeValueText { value: text };
            }
            diagnostics.push(
                Hir2DiagnosticDiagnosticMessage {
                    diagnostic_id: root.diagnostics.INVALID_ATTRIBUTE_ARG,
                    message: `\`${spelled}\` argument must be a string literal, got \`${arg.value}\``,
                    span: arg.span,
                },
            );
            null
        },
    }
}

// port: baml_compiler2_hir/src/attrs.rs::record_schema @ d9be6853b
// Store a schema-wide attribute on `schema`, handing back a value that is not
// one so the carrier can store it itself.
function record_schema(
    schema: SchemaAttrs,
    spec: root.base.SchemaAttributeSpec,
    value: AttributeValue,
) -> AttributeValue? throws never {
    match (value) {
        let text: AttributeValueText if spec.name == "description" => {
            schema.description = text.value;
            null
        },
        let text: AttributeValueText if spec.name == "alias" => {
            schema.alias = text.value;
            null
        },
        _ => value,
    }
}

// port: baml_compiler2_hir/src/attrs.rs::drift @ d9be6853b
function drift(
    spec: root.base.SchemaAttributeSpec,
    position: root.base.AttributePosition,
) -> void throws never {
    baml.sys.panic(
        `the attribute table allows \`${spec.name}\` on ${root.base.attribute_position_describe(position)} but its carrier has no field for it`,
    );
}

// port: attrs.rs::impl AttributeCarrier for ClassFieldAttrs
implements AttributeCarrier for ClassFieldAttrs {
  function position(self) -> root.base.AttributePosition throws never {
    root.base.AttributePosition.ClassField
  }

  function record(self, spec: root.base.SchemaAttributeSpec, value: AttributeValue) -> void throws never {
    let rest = record_schema(self.schema, spec, value) ?? return;
    match (rest) {
      AttributeValueFlag if spec.name == "skip" => { self.skip = true; },
      AttributeValueFlag if spec.name == "stream.done" => { self.stream_done = true; },
      AttributeValueFlag if spec.name == "stream.must_exist" => { self.must_exist = true; },
      let key: AttributeValueText if spec.name == "json.rename" => { self.json_rename = key.value; },
      AttributeValueFlag if spec.name == "json.flatten" => { self.json_flatten = true; },
      AttributeValueFlag if spec.name == "json.fallback" => { self.json_fallback = true; },
      AttributeValueFlag if spec.name == "trace.redact" => { self.redact = true; },
      _ => drift(spec, self.position()),
    }
  }
}

// port: attrs.rs::impl AttributeCarrier for EnumVariantAttrs
implements AttributeCarrier for EnumVariantAttrs {
  function position(self) -> root.base.AttributePosition throws never {
    root.base.AttributePosition.EnumVariant
  }

  function record(self, spec: root.base.SchemaAttributeSpec, value: AttributeValue) -> void throws never {
    let rest = record_schema(self.schema, spec, value) ?? return;
    match (rest) {
      AttributeValueFlag if spec.name == "skip" => { self.skip = true; },
      let key: AttributeValueText if spec.name == "json.rename" => { self.json_rename = key.value; },
      _ => drift(spec, self.position()),
    }
  }
}

// port: attrs.rs::impl AttributeCarrier for ClassAttrs
implements AttributeCarrier for ClassAttrs {
  function position(self) -> root.base.AttributePosition throws never {
    root.base.AttributePosition.Class
  }

  function record(self, spec: root.base.SchemaAttributeSpec, value: AttributeValue) -> void throws never {
    let rest = record_schema(self.schema, spec, value) ?? return;
    match (rest) {
      AttributeValueFlag if spec.name == "stream.done" => { self.stream_done = true; },
      AttributeValueFlag if spec.name == "json.omit_nulls" => { self.json_omit_nulls = true; },
      AttributeValueFlag if spec.name == "trace.redact" => { self.redact = true; },
      _ => drift(spec, self.position()),
    }
  }
}

// port: attrs.rs::impl AttributeCarrier for EnumAttrs
implements AttributeCarrier for EnumAttrs {
  function position(self) -> root.base.AttributePosition throws never {
    root.base.AttributePosition.Enum
  }

  function record(self, spec: root.base.SchemaAttributeSpec, value: AttributeValue) -> void throws never {
    if (record_schema(self.schema, spec, value) != null) {
      drift(spec, self.position());
    }
  }
}

// port: attrs.rs::SerializedMember. A class field or enum variant as the
// serialized-key check sees it.
class SerializedMember {
    name: string,
    name_span: root.syntax.TextRange,
    alias: string?,
    skip: bool,
}

// port: baml_compiler2_hir/src/attrs.rs::json_key @ d9be6853b
// A member's JSON key where it isn't its declared name: its `@json.rename`,
// else, under aliased names, its `@alias`.
function json_key(rename: string?, alias: string?, aliased: bool) -> string? throws never {
    rename
        ?? (
            if (aliased) {
                alias
            } else {
                null
            }
        )
}

// port: baml_compiler2_hir/src/attrs.rs::check_serialized_keys @ d9be6853b
// Reject a class or enum whose members don't all serialize to distinct JSON
// keys. A member's effective key is its `@alias` if it carries one, else its
// declared name; an aliased member's real name is never used for matching, so
// two members with one effective key are indistinguishable in the serialized
// schema. Repeated identical names are reported by the duplicate-definition
// checks, so this fires only when two distinct names share a key. A `@skip`ped
// member has no key.
//
// deviation: buckets are reported in first-seen key order; Rust iterates an
// `FxHashMap`. Diagnostics are sorted by span downstream.
function check_serialized_keys(
    members: SerializedMember[],
    container: SerializedKeyContainer,
    diagnostics: Hir2Diagnostic[],
) -> void throws never {
    let buckets: map<string, SerializedMember[]> = {};
    for (
        let member in members.filter((m) -> {
            !m.skip
        })
    ) {
        let key = member.alias ?? member.name;
        if (!buckets.has(key)) {
            buckets[key] = [];
        }
        buckets[key].push(member);
    }
    for (let key in buckets.keys()) {
        let bucket = buckets[key];
        let distinct = bucket.some((m) -> {
            m.name != bucket[0].name
        });
        if (bucket.length() >= 2 && distinct) {
            diagnostics.push(
                Hir2DiagnosticDuplicateFieldAlias {
                    key: key,
                    sites: bucket.map((m) -> {
                        m.name_span
                    }),
                    container: container,
                },
            );
        }
    }
}
