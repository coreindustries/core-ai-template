# TypeScript Rules

**Scope:** TypeScript projects — strict type safety, ESLint/typescript-eslint, tsconfig discipline

## Quick Reference

- **tsconfig**: `strict: true` — no negotiation
- **Linting**: ESLint with `@typescript-eslint` (recommended + strict)
- **Formatter**: Prettier or `prettier-plugin-tailwindcss` (if applicable)
- **Imports**: Node16 / bundler module resolution; `verbatimModuleSyntax: true`
- **Output**: declaration files emitted; `skipLibCheck: true` for perf

## 1. tsconfig Baseline

Every TypeScript project must start from this baseline. Do not turn off flags from `strict` individually — the entire `strict` bundle must remain on.

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022"],
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "exactOptionalPropertyTypes": true,
    "verbatimModuleSyntax": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "outDir": "./dist",
    "rootDir": "./src",
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "esModuleInterop": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist", "**/*.test.ts", "**/*.spec.ts"]
}
```

**For web/browser targets** (Next.js, Vite): swap `module`/`moduleResolution` for `"Bundler"` and adjust `lib` to include `"DOM"`.

**For tests** use a `tsconfig.test.json` that `extends` the root and adds `"include": ["src/**/*", "tests/**/*"]` — never relax `strict` in the test tsconfig.

## 2. ESLint / typescript-eslint

```jsonc
// eslint.config.mjs (flat config)
import tseslint from "typescript-eslint";

export default tseslint.config(
  tseslint.configs.strictTypeChecked,
  tseslint.configs.stylisticTypeChecked,
  {
    languageOptions: {
      parserOptions: { project: true, tsconfigRootDir: import.meta.dirname },
    },
    rules: {
      "@typescript-eslint/consistent-type-imports": "error",
      "@typescript-eslint/no-import-type-side-effects": "error",
      "@typescript-eslint/explicit-function-return-type": "error",
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/no-unsafe-assignment": "error",
    },
  }
);
```

Run in CI:

```bash
npx tsc --noEmit       # type check without emitting
npx eslint src/        # lint
```

## 3. Naming and Import Conventions

```typescript
// Types and interfaces — PascalCase
interface UserProfile { ... }
type UserId = string;

// Enums — PascalCase, members UPPER_SNAKE_CASE
enum UserRole { ADMIN = "admin", VIEWER = "viewer" }

// Type-only imports — always use `import type` for type-only positions
import type { User } from "./types.js";
import { createUser } from "./service.js";

// File extensions in imports — required with NodeNext resolution
import { foo } from "./foo.js";  // .js even for .ts sources
```

## 4. Strict Type Patterns

```typescript
// CORRECT: unknown over any at boundaries
async function fetchUser(id: string): Promise<User> {
  const data: unknown = await fetch(`/users/${id}`).then(r => r.json());
  return parseUser(data); // validate + narrow
}

// CORRECT: exhaustive switch via never
function handleStatus(status: "active" | "archived" | "suspended"): string {
  switch (status) {
    case "active": return "green";
    case "archived": return "gray";
    case "suspended": return "red";
    default: {
      const _: never = status;
      throw new Error(`Unhandled status: ${status}`);
    }
  }
}

// CORRECT: discriminated unions over optional fields
type Result<T> =
  | { ok: true; value: T }
  | { ok: false; error: string };

// WRONG: any, non-null assertion without guard, optional chaining as a crutch
const user = data as any;           // never
const name = user!.name;            // only after an explicit null-check
const val = obj?.prop?.nested;      // fine, but don't mask missing required fields
```

## 5. Declaration Files

- Always emit `.d.ts` and `.d.ts.map` for publishable packages: `"declaration": true, "declarationMap": true`.
- Do not hand-author `.d.ts` files for TypeScript-source packages — `tsc` generates them.
- For consuming un-typed third-party packages: create `src/types/<package>.d.ts` with the minimum surface used; never `declare module "*"`.

## 6. Module Resolution

Use `"moduleResolution": "NodeNext"` (or `"Bundler"` for build-tool projects). This requires:

- `.js` extensions on relative imports (the emitted `.js` extension, even for `.ts` sources)
- `package.json` `"exports"` field for any package that's published
- No "barrel" files (`index.ts` re-exporting everything) in large codebases — they kill tree-shaking and slow tsc

```typescript
// With NodeNext:
import { foo } from "./foo.js";      // correct
import { foo } from "./foo";         // error with NodeNext
```

## 7. Common Anti-Patterns

| Anti-pattern | Fix |
|---|---|
| `as any` | Narrow with type guards or use `unknown` + validate |
| `// @ts-ignore` | Fix the underlying type error; `// @ts-expect-error` only with a comment explaining why |
| `Object.keys(obj)` without typing | Cast: `(Object.keys(obj) as Array<keyof typeof obj>)` or use a typed helper |
| `declare module "*"` wildcard | Scope to the specific package |
| Circular imports | Extract shared types to a separate `types.ts` module |
| Loose `tsconfig` in `test/` | Extend root tsconfig; never loosen `strict` in tests |
| `export default` | Prefer named exports — better refactorability and tree-shaking |

## 8. CI Gates

```yaml
- name: Type check
  run: npx tsc --noEmit

- name: Lint
  run: npx eslint src/ --max-warnings 0
```

`--max-warnings 0` treats every ESLint warning as a failure — no warning debt accumulates.

## See Also

- `.claude/rules/code-quality.md` — language-agnostic quality rules (always auto-loaded)
- `.claude/rules-available/security-owasp.md` — OWASP Top 10 (enable with `make enable-ts`)
- [typescript-eslint](https://typescript-eslint.io/)
- [TypeScript tsconfig reference](https://www.typescriptlang.org/tsconfig)
