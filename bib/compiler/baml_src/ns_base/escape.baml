// port: baml_base/src/escape.rs @ d9be6853b  (stub: types only, port pending)

class EscapeIssue {
  message: string,
}

function escape_issue_message(issue: EscapeIssue) -> string throws never {
  issue.message
}
