# Next.js Development Rules

**Use this rule when developing Next.js applications.** These guidelines prioritize modern Next.js 16+ patterns, React Server Components, and performance optimization.

## Quick Reference

- **Next.js 16+**: Async `params`, `searchParams`, `headers()`, `cookies()` - **MUST await**
- **Server Components**: Default to Server Components, use Client Components only when needed
- **Caching**: Use `'use cache'` directive with `cacheLife()` for Cache Components
- **Revalidation**: Use `updateTag()` in Server Actions, `revalidateTag()` in Route Handlers
- **TypeScript**: Prefer `interface` over `type` for objects, avoid `enum`
- **Forms**: React Hook Form + Zod for type-safe validation
- **Styling**: Tailwind CSS with Shadcn UI and Radix primitives

## Key Patterns

### Async Dynamic APIs (Next.js 16+)

```typescript
// CORRECT: Await params and searchParams
export default async function Page({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>
  searchParams: Promise<{ sort?: string }>
}) {
  const { id } = await params
  const { sort } = await searchParams
  return <div>Post {id}</div>
}
```

### Server vs Client Components

| Use Server Components For | Use Client Components For |
|---------------------------|---------------------------|
| Data fetching | Event handlers (onClick, onChange) |
| Database queries | Browser APIs (localStorage, geolocation) |
| Accessing backend resources | Stateful logic (useState, useReducer) |
| Rendering static content | Effects (useEffect) |
| SEO-critical content | Third-party client libraries |

### Caching with Cache Components

```typescript
// Enable in next.config.ts
const nextConfig = {
  cacheComponents: true,
  reactCompiler: true,
}

// Use 'use cache' directive
'use cache'
import { cacheLife } from 'next/cache'

export default async function BlogPage() {
  cacheLife('days')
  const posts = await getBlogPosts()
  return <div>{/* render posts */}</div>
}
```

### Server Actions with Revalidation

```typescript
'use server'
import { updateTag } from 'next/cache'

export async function createPost(formData: FormData) {
  const post = await db.post.create({...})
  
  // User sees changes immediately
  updateTag('posts')
  updateTag(`post-${post.id}`)
  
  redirect('/posts')
}
```

### TypeScript Standards

- Use `interface` for object shapes (extendable, better errors)
- Use object maps instead of `enum` (no runtime overhead)
- Use `unknown` instead of `any` (forces type checking)
- Explicit return types for better readability

### Forms with React Hook Form + Zod

```typescript
'use client'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'

const ContactSchema = z.object({
  name: z.string().min(2),
  email: z.string().email(),
})

export function ContactForm() {
  const { register, handleSubmit, formState: { errors } } = useForm({
    resolver: zodResolver(ContactSchema),
  })
  // ...
}
```

## Project Structure

```
src/
├── app/                    # App Router pages and layouts
│   ├── (auth)/             # Route groups
│   ├── api/                # API routes
│   ├── layout.tsx          # Root layout
│   └── page.tsx            # Home page
├── components/
│   ├── ui/                 # Reusable UI primitives
│   └── features/           # Feature-specific components
├── hooks/                  # Custom React hooks
├── lib/                    # Utility functions
├── types/                  # TypeScript types
└── styles/                 # Global styles
```

## File Naming

- Directories: `kebab-case` (e.g., `components/auth-wizard/`)
- Components: `kebab-case` file, `PascalCase` export (e.g., `user-profile.tsx` → `UserProfile`)
- Utilities: `kebab-case` (e.g., `format-date.ts`)
- Constants: `kebab-case` file, `SCREAMING_SNAKE_CASE` values

## Performance

- **Turbopack**: Enabled by default in Next.js 16 (5-10x faster dev builds)
- **Image Optimization**: Use `next/image` with proper dimensions
- **Font Optimization**: Use `next/font/google` with `display: 'swap'`
- **Dynamic Imports**: Lazy load heavy components
- **Suspense Boundaries**: Wrap async components for better UX

## Security

- Use environment variables for secrets (`process.env`)
- Implement CSRF protection for Server Actions
- Validate all user input with Zod
- Use `next/headers` for secure cookie handling (await!)
- Configure security headers in `next.config.js`

## See Also

- `.cursor/rules/nextjs.mdc` - Full Next.js rule with comprehensive examples
- [Next.js Documentation](https://nextjs.org/docs)
- [React Server Components](https://react.dev/reference/rsc/server-components)
