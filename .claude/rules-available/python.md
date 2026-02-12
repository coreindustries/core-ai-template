# Python Development Rules

**These rules apply to Python projects** using modern tooling (uv, ruff, mypy) and frameworks (FastAPI, Django, Flask). Follow these practices for type-safe, performant, and production-ready Python code.

## Quick Reference

- **Package Manager**: uv (default) — fast, reliable, replaces pip/poetry/pipenv
- **Linting & Formatting**: ruff (replaces flake8, isort, black, pylint)
- **Type Checking**: mypy with strict mode
- **Testing**: pytest with pytest-cov, pytest-asyncio
- **Python Version**: 3.12+ (use latest stable)
- **Style**: PEP 8 via ruff, Google-style docstrings, type annotations everywhere

## 1. Project Setup with uv

### Initialize

```bash
uv init my-project
cd my-project
uv add fastapi uvicorn[standard]    # Add dependencies
uv add --dev pytest pytest-cov ruff mypy  # Add dev dependencies
```

### Key Commands

```bash
# Package management
uv sync                    # Install all dependencies from lock file
uv add <package>           # Add dependency
uv add --dev <package>     # Add dev dependency
uv remove <package>        # Remove dependency
uv lock                    # Update lock file

# Running
uv run python main.py      # Run with project's Python
uv run pytest              # Run tests
uv run ruff check .        # Lint
uv run mypy .              # Type check

# Environment
uv python install 3.13     # Install Python version
uv python pin 3.13         # Pin for project
```

### pyproject.toml

```toml
[project]
name = "my-project"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = [
    "fastapi>=0.115",
    "uvicorn[standard]>=0.34",
    "pydantic>=2.10",
    "sqlalchemy>=2.0",
]

[dependency-groups]
dev = [
    "pytest>=8.0",
    "pytest-cov>=6.0",
    "pytest-asyncio>=0.25",
    "ruff>=0.9",
    "mypy>=1.14",
    "httpx>=0.28",       # Async test client
]

[tool.ruff]
target-version = "py312"
line-length = 100

[tool.ruff.lint]
select = ["E", "F", "W", "I", "N", "UP", "S", "B", "A", "C4", "SIM", "TCH", "RUF"]

[tool.mypy]
python_version = "3.12"
strict = true
warn_return_any = true
warn_unused_configs = true

[tool.pytest.ini_options]
testpaths = ["tests"]
asyncio_mode = "auto"
addopts = "-ra --strict-markers"
```

## 2. Type Annotations

### Required Everywhere

```python
# CORRECT: Fully typed
def get_user(user_id: str, include_posts: bool = False) -> User | None:
    """Fetch a user by ID."""
    ...

async def create_user(data: CreateUserRequest) -> User:
    """Create a new user."""
    ...

# WRONG: Missing types
def get_user(user_id, include_posts=False):
    ...
```

### Modern Type Syntax (3.12+)

```python
# Use built-in generics (not typing.List, typing.Dict)
def process_items(items: list[str]) -> dict[str, int]:
    ...

# Union with pipe operator
def find_user(key: str) -> User | None:
    ...

# Type aliases with `type` statement (3.12+)
type UserId = str
type UserMap = dict[UserId, User]

# TypeVar with new syntax (3.12+)
def first[T](items: list[T]) -> T | None:
    return items[0] if items else None
```

### Pydantic Models

```python
from pydantic import BaseModel, Field, EmailStr

class CreateUserRequest(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    email: EmailStr
    role: UserRole = UserRole.USER

class UserResponse(BaseModel):
    id: str
    name: str
    email: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)
```

## 3. Error Handling

```python
# Custom domain exceptions
class AppError(Exception):
    """Base application error."""
    def __init__(self, message: str, code: str) -> None:
        self.message = message
        self.code = code
        super().__init__(message)

class NotFoundError(AppError):
    def __init__(self, resource: str, resource_id: str) -> None:
        super().__init__(
            message=f"{resource} not found: {resource_id}",
            code="NOT_FOUND",
        )

class ValidationError(AppError):
    def __init__(self, field: str, detail: str) -> None:
        super().__init__(
            message=f"Validation error on {field}: {detail}",
            code="VALIDATION_ERROR",
        )

# CORRECT: Specific exception handling
async def get_user(user_id: str) -> User:
    try:
        user = await db.users.find_one(user_id)
    except DatabaseError as e:
        logger.error("Database error fetching user %s", user_id, exc_info=e)
        raise ServiceError(f"Failed to fetch user: {user_id}") from e

    if user is None:
        raise NotFoundError("User", user_id)
    return user

# WRONG: Bare except or swallowing errors
try:
    user = await db.users.find_one(user_id)
except:  # noqa: E722 — never do this
    return None
```

## 4. Async Patterns

### FastAPI Endpoints

```python
from fastapi import FastAPI, Depends, HTTPException, status

app = FastAPI()

@app.get("/users/{user_id}", response_model=UserResponse)
async def get_user(
    user_id: str,
    service: UserService = Depends(get_user_service),
) -> UserResponse:
    try:
        user = await service.get_user(user_id)
    except NotFoundError:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return UserResponse.model_validate(user)
```

### Dependency Injection

```python
from functools import lru_cache
from typing import Annotated
from fastapi import Depends

@lru_cache
def get_settings() -> Settings:
    return Settings()

async def get_db(
    settings: Annotated[Settings, Depends(get_settings)],
) -> AsyncGenerator[AsyncSession, None]:
    async with async_session_factory() as session:
        yield session

async def get_user_service(
    db: Annotated[AsyncSession, Depends(get_db)],
) -> UserService:
    return UserService(db)
```

### Concurrent Operations

```python
import asyncio

# CORRECT: Run independent operations concurrently
async def fetch_dashboard(user_id: str) -> Dashboard:
    profile, posts, notifications = await asyncio.gather(
        fetch_profile(user_id),
        fetch_posts(user_id),
        fetch_notifications(user_id),
    )
    return Dashboard(profile=profile, posts=posts, notifications=notifications)

# WRONG: Sequential when operations are independent
async def fetch_dashboard(user_id: str) -> Dashboard:
    profile = await fetch_profile(user_id)
    posts = await fetch_posts(user_id)
    notifications = await fetch_notifications(user_id)
    ...
```

## 5. Project Structure

```
src/{project_name}/
├── __init__.py
├── main.py                  # FastAPI app, entry point
├── config.py                # Settings via pydantic-settings
├── api/
│   ├── __init__.py
│   ├── deps.py              # Shared dependencies
│   ├── middleware.py         # CORS, auth, logging middleware
│   └── routes/
│       ├── __init__.py
│       ├── users.py         # /users endpoints
│       └── health.py        # /health endpoint
├── services/
│   ├── __init__.py
│   └── user_service.py      # Business logic
├── models/
│   ├── __init__.py
│   ├── domain.py            # Domain models
│   ├── requests.py          # Pydantic request schemas
│   └── responses.py         # Pydantic response schemas
├── db/
│   ├── __init__.py
│   ├── session.py           # Database session factory
│   ├── models.py            # SQLAlchemy / ORM models
│   └── repositories/        # Data access layer
└── core/
    ├── __init__.py
    ├── errors.py             # Custom exceptions
    └── logging.py            # Structured logging setup
tests/
├── conftest.py              # Shared fixtures
├── unit/
│   └── test_user_service.py
└── integration/
    └── test_user_api.py
```

## 6. Testing

```python
import pytest
from httpx import AsyncClient, ASGITransport

from src.my_app.main import app

@pytest.fixture
async def client() -> AsyncGenerator[AsyncClient, None]:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client

# Unit test
async def test_create_user_validates_email(user_service: UserService) -> None:
    with pytest.raises(ValidationError, match="email"):
        await user_service.create_user(
            CreateUserRequest(name="Test", email="not-an-email")
        )

# Integration test
async def test_get_user_endpoint(client: AsyncClient, seed_user: User) -> None:
    response = await client.get(f"/users/{seed_user.id}")
    assert response.status_code == 200
    data = response.json()
    assert data["id"] == seed_user.id
    assert data["email"] == seed_user.email

# Parametrized tests
@pytest.mark.parametrize(
    "name,expected_valid",
    [
        ("Alice", True),
        ("", False),
        ("A" * 101, False),
    ],
)
async def test_user_name_validation(name: str, expected_valid: bool) -> None:
    if expected_valid:
        user = CreateUserRequest(name=name, email="test@example.com")
        assert user.name == name
    else:
        with pytest.raises(ValueError):
            CreateUserRequest(name=name, email="test@example.com")
```

### Coverage

```bash
uv run pytest --cov=src --cov-report=term-missing --cov-fail-under=80
```

## 7. Linting & Formatting

```bash
# Lint and auto-fix
uv run ruff check --fix .

# Format
uv run ruff format .

# Type check
uv run mypy .

# All at once
uv run ruff check --fix . && uv run ruff format . && uv run mypy .
```

### Ruff Rule Categories

| Code | Category | Catches |
|------|----------|---------|
| `E/W` | pycodestyle | Style violations |
| `F` | pyflakes | Unused imports, undefined names |
| `I` | isort | Import ordering |
| `N` | pep8-naming | Naming conventions |
| `UP` | pyupgrade | Modernize syntax for target Python |
| `S` | bandit | Security issues |
| `B` | bugbear | Common bugs and design issues |
| `SIM` | simplify | Simplifiable code |
| `TCH` | type-checking | Move imports to TYPE_CHECKING block |

## 8. Database (SQLAlchemy 2.0)

```python
from sqlalchemy import String, DateTime, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

class Base(DeclarativeBase):
    pass

class UserModel(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    name: Mapped[str] = mapped_column(String(100))
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

# Async session
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker

engine = create_async_engine(settings.database_url)
async_session = async_sessionmaker(engine, expire_on_commit=False)
```

## 9. Security

```bash
# Dependency vulnerabilities
uv run pip-audit

# Static security analysis
uv run bandit -r src/

# Known vulnerability check
uv run safety check
```

## 10. Common Anti-Patterns

| Anti-Pattern | Fix |
|-------------|-----|
| `from typing import List, Dict` | Use built-in `list`, `dict` (3.9+) |
| `Optional[X]` | Use `X \| None` (3.10+) |
| Mutable default arguments | Use `None` default + assign in body, or `field(default_factory=...)` |
| Bare `except:` | Catch specific exceptions |
| `os.path` for paths | Use `pathlib.Path` |
| `requests` for async code | Use `httpx` with async |
| `print()` for logging | Use `logging` or `structlog` |
| `requirements.txt` manually | Use `uv` with `pyproject.toml` + lock file |
| `setup.py` / `setup.cfg` | Use `pyproject.toml` |

## See Also

- `.claude/rules/security-core.md` - Core security practices (always auto-loaded)
- `.claude/rules-available/security-owasp.md` - OWASP Top 10 standards
- [uv Documentation](https://docs.astral.sh/uv/)
- [ruff Documentation](https://docs.astral.sh/ruff/)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
