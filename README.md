# tclcheck

`tclcheck` is a lightweight static checker for Tcl scripts.

## What Syntax Errors Are Scanned

When you run in syntax mode (`--syntax-only`), the checker focuses on structural parse errors and does not run semantic lint checks.

### Structural syntax checks

- Unbalanced braces (`{` / `}`)
- Unexpected closing braces (`}` with no matching opener)
- Unbalanced brackets (`[` / `]`)
- Unexpected closing brackets (`]` with no matching opener)
- Unclosed double-quoted strings
- Tokenizer/parser-level malformed command substitutions (for example, unclosed `[` in command words)

### Notes about scope

- Syntax scanning is intentionally superficial and conservative.
- The parser is tuned to avoid common false positives from regex-heavy Tcl code (for example, `regexp` patterns with `[]`, `()`, and escaped metacharacters inside brace-quoted words).
- In full mode (without `--syntax-only`), additional semantic checks run for expressions, variables, procs, imports, and style.

## Usage

Run syntax-only checks on one file:

```bash
tclsh tclcheck.tcl --syntax-only --severity error path/to/file.tcl
```

Run syntax-only checks recursively on a directory:

```bash
tclsh tclcheck.tcl --syntax-only --severity error --dir tests
```

Run full analysis (syntax + semantic checks):

```bash
tclsh tclcheck.tcl --severity warn --dir tests
```

## CI Example

```bash
#!/usr/bin/env bash
set -euo pipefail

tclsh tclcheck.tcl --syntax-only --severity error --dir tests
```

A non-zero exit code means at least one `ERROR` or `WARN` diagnostic was emitted.
