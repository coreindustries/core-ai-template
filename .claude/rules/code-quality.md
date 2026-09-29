# Code Quality Rules

**Scope:** Code quality standards (DRY, typing, naming, docs, project organization)

## Simplest complete solution

- **Fix root causes, not symptoms.** Establish the cause from evidence and correct
  it at the owning boundary. Temporary mitigation must be labeled with its
  limitation and follow-up; it is not a completed root-cause fix. Apply the
  retry/control requirements in `delivery-contract.md` before adding machinery.
- **Favor subtraction over addition.** Remove unnecessary code, states,
  dependencies and processes; prefer correction or reuse of the existing owner.
  Choose the simplest solution that meets every requested outcome. Justify added
  complexity with a concrete unmet need. Preserve correctness, security and
  required compatibility; deletion counts are not a success criterion.
- **Keep documentation concise.** Update the existing authoritative document.
  State the decision, rationale, usage and necessary caveats; retain evidence
  needed to verify consequential claims. Link to shared guidance instead of
  duplicating it, and remove obsolete instructions and unnecessary narration.
- **Leave one consistent, current truth.** Reconcile affected code, comments, CI,
  tests, ADRs, PRDs, skills and tools in the same change. Remove obsolete guidance
  and superseded mechanisms; verify that instructions, assertions and behavior
  agree. Mark historical decisions as superseded and link their replacement
  without rewriting historical evidence. Keep reconciliation within the affected
  responsibility; necessary coexistence follows `delivery-contract.md`.


## DRY Principle (Don't Repeat Yourself)

Search for existing implementations before creating new code. Reuse the owner of
the behavior instead of copying it. Consolidate duplication in the affected scope
when it prevents drift; do not create a universal abstraction for unrelated
behavior or expand a feature into opportunistic cleanup. Apply the ownership and
retirement requirements in `delivery-contract.md` before adding another mechanism.

## Static Typing Requirements

Type everything: function signatures, class attributes, and return types all carry
annotations, using the modern syntax for the language version. Type checking gates
the merge — a failing type check is a broken build, not a warning.

## Naming Conventions

Naming follows the table below, so a reader can infer what a symbol is from how it is written.

| Element             | Convention         | Example                                       |
| ------------------- | ------------------ | --------------------------------------------- |
| Functions/methods   | Language standard  | `processData`, `process_data`                 |
| Classes/Types       | PascalCase         | `DataProcessor`, `UserService`                |
| Constants           | UPPER_SNAKE_CASE   | `MAX_RETRY_COUNT`, `DEFAULT_TIMEOUT`          |
| Private members     | Language standard  | `_internal`, `#private`, `private`            |
| Modules/Files       | Language standard  | `dataUtils`, `data_utils`, `DataUtils`        |

## Code Documentation

Document what a reader cannot infer from the code itself.

- Modules and classes carry a docstring saying what they are for
- Public functions carry a docstring covering arguments, return, and what they raise
- Complex algorithms carry inline comments explaining *why*, not what

Keep required docstrings concise: explain purpose, contracts, non-obvious behavior
and necessary caveats without narrating the implementation. Use examples when
they clarify usage; do not pad every docstring with a full template.

## Project Organization

Keep the project root clean — it is the first thing a new contributor reads.

**Allowed in root:**
- Configuration files (package manager, linter, type checker)
- Documentation: `README.md`, `LICENSE`, `CONTRIBUTING.md`, `CLAUDE.md`
- CI/CD: `.github/workflows/`
- Environment: `.env.example`

**Must be in subdirectories:**
- Source code → `src/`
- Tests → `tests/`
- Scripts → `scripts/`
- Documentation → `docs/`
- PRDs → `prd/`

## Code Review Checklist

Code review verifies:
- [ ] Type annotations on all functions and attributes
- [ ] Docstrings on all public functions and classes
- [ ] DRY principle followed
- [ ] Naming conventions followed
- [ ] Duplication within the affected responsibility reconciled without needless abstraction
- [ ] Modern syntax used
- [ ] Project organization followed
