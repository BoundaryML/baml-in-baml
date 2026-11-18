// port: upstream #5719's baml_tests/projects/diagnostic_errors/duplicate_object_field
// (ported ahead of its merge). The expected values are the PR's
// `05_diagnostics.snap`. Replace with the corpus comparison once the oracle
// toolchain includes #5719.

const DUPLICATE_OBJECT_FIELD_SOURCE: string = `
  class Pair {
      a: int?
      b: int
  }

  // A field named twice in a class literal is an error.
  function twice() -> Pair {
      Pair { a: null, a: 1, b: 2 }
  }

  // Shorthand and explicit spellings of the same field collide too.
  function shorthand(a: int) -> Pair {
      Pair { a, b: 2, a: 3 }
  }

  // Every repeat is reported against the first site.
  function thrice() -> Pair {
      Pair { a: 1, b: 2, a: 3, a: 4 }
  }

  // An explicit field that overrides a spread is not a duplicate.
  function override_spread(p: Pair) -> Pair {
      Pair { a: 1, ...p }
  }
`;

// "<code> <headline> | <primary label> | <every annotation label>" for each
// diagnostic of `source`.
function duplicate_field_reports(source: string) -> string[] throws never {
  root.check({"duplicate_object_field.baml": source}).map((d) -> {
    `${d.code} ${d.headline} | ${d.primary_label ?? ""} | ${d.annotations.map((a) -> { a.message ?? "" }).join(", ")}`
  })
}

test "duplicate object field reports every repeat against the first site" {
  assert.equal(duplicate_field_reports(DUPLICATE_OBJECT_FIELD_SOURCE), [
    "E0012 duplicate field `a` in class literal | field `a` set again here | field `a` first set here",
    "E0012 duplicate field `a` in class literal | field `a` set again here | field `a` first set here",
    "E0012 duplicate field `a` in class literal | field `a` set again here | field `a` first set here, field `a` set again here",
  ])
}
