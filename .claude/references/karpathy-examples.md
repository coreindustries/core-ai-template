# Karpathy Principles — Code Examples

On-demand reference with before/after code examples demonstrating common LLM coding pitfalls and their fixes. Derived from [Andrej Karpathy's observations](https://x.com/karpathy/status/2015883857489522876).

**Source:** [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills)

---

## Think Before Coding

### Hidden Assumptions

**User:** "Add a feature to export user data"

**Wrong — silently assumes scope, format, location, fields:**
```python
def export_users(format='json'):
    users = User.query.all()  # All users? Privacy?
    if format == 'json':
        with open('users.json', 'w') as f:  # File location?
            json.dump([u.to_dict() for u in users], f)  # Which fields?
```

**Right — surface assumptions first:**
```
Before implementing, I need to clarify:
1. Scope: Export all users or filtered subset? (privacy implications)
2. Format: Download in browser? Background job? API endpoint?
3. Fields: Which user fields? (some might be sensitive)
4. Volume: How many users? (affects pagination approach)
```

### Multiple Interpretations

**User:** "Make the search faster"

**Wrong — picks one interpretation silently, adds 200 lines of optimization.**

**Right — present the options:**
```
"Make the search faster" could mean:
1. Faster response time → database indexes, query caching
2. Higher throughput → async, connection pooling
3. Faster perceived speed → partial results, progressive loading

Current search takes ~500ms. Which aspect matters most?
```

---

## Simplicity First

### Over-Abstraction

**User:** "Add a function to calculate discount"

**Wrong — Strategy pattern for a single calculation:**
```python
class DiscountStrategy(ABC):
    @abstractmethod
    def calculate(self, amount: float) -> float: ...

class PercentageDiscount(DiscountStrategy):
    def __init__(self, percentage: float):
        self.percentage = percentage
    def calculate(self, amount: float) -> float:
        return amount * (self.percentage / 100)

class FixedDiscount(DiscountStrategy): ...

@dataclass
class DiscountConfig:
    strategy: DiscountStrategy
    min_purchase: float = 0.0
    max_discount: float = float('inf')

class DiscountCalculator:
    def __init__(self, config: DiscountConfig):
        self.config = config
    def apply_discount(self, amount: float) -> float: ...

# 50+ lines for a single calculation
```

**Right — simple function:**
```python
def calculate_discount(amount: float, percent: float) -> float:
    """Calculate discount amount. percent should be 0-100."""
    return amount * (percent / 100)
```

Add complexity only when you actually need multiple discount types.

### Speculative Features

**User:** "Save user preferences to database"

**Wrong — adds caching, validation, merging, notifications nobody asked for:**
```python
class PreferenceManager:
    def __init__(self, db, cache=None, validator=None):
        self.db = db
        self.cache = cache or InMemoryCache()
        self.validator = validator or DefaultValidator()

    def save(self, user_id: int, prefs: dict,
             merge: bool = True, validate: bool = True,
             notify: bool = False) -> bool:
        # 40+ lines handling features nobody requested
```

**Right — just what was asked:**
```python
def save_preferences(db, user_id: int, preferences: dict):
    """Save user preferences to database."""
    db.execute(
        "UPDATE users SET preferences = ? WHERE id = ?",
        (json.dumps(preferences), user_id)
    )
```

---

## Surgical Changes

### Drive-By Refactoring

**User:** "Fix the bug where empty emails crash the validator"

**Wrong — fixes bug + adds docstring + improves email regex + adds username validation:**
```diff
  def validate_user(user_data):
-     # Check email format
-     if not user_data.get('email'):
+     """Validate user data."""
+     email = user_data.get('email', '').strip()
+     if not email:
          raise ValueError("Email required")
-     if '@' not in user_data['email']:
+     if '@' not in email or '.' not in email.split('@')[1]:
          raise ValueError("Invalid email")
-     if not user_data.get('username'):
+     username = user_data.get('username', '').strip()
+     if not username:
          raise ValueError("Username required")
+     if len(username) < 3:
+         raise ValueError("Username too short")
      return True
```

**Right — surgical fix for the reported bug only:**
```diff
  def validate_user(user_data):
      # Check email format
-     if not user_data.get('email'):
+     email = user_data.get('email', '')
+     if not email or not email.strip():
          raise ValueError("Email required")
-     if '@' not in user_data['email']:
+     if '@' not in email:
          raise ValueError("Invalid email")
      # Check username
      if not user_data.get('username'):
          raise ValueError("Username required")
      return True
```

### Style Drift

**User:** "Add logging to the upload function"

**Wrong — also changes quote style, adds type hints, reformats whitespace, restructures returns:**
```diff
- def upload_file(file_path, destination):
+ def upload_file(file_path: str, destination: str) -> bool:
+     """Upload file to destination with logging."""
```

**Right — add only logging, match existing style (single quotes, no type hints):**
```diff
+ import logging
+ logger = logging.getLogger(__name__)
+
  def upload_file(file_path, destination):
+     logger.info(f'Starting upload: {file_path}')
      try:
```

---

## Goal-Driven Execution

### Vague vs. Verifiable

**User:** "Fix the authentication system"

**Wrong:**
```
I'll fix the authentication system by:
1. Reviewing the code
2. Identifying issues
3. Making improvements
```

**Right — define success criteria:**
```
What specific auth issue are we solving?

If "users stay logged in after password change":

1. Write test: Change password → verify old session invalidated
   Verify: Test fails (reproduces bug)
2. Implement: Invalidate sessions on password change
   Verify: Test passes
3. Edge cases: Multiple sessions, concurrent changes
   Verify: Additional tests pass
4. Regression: Existing auth tests still pass
   Verify: Full test suite green
```

### Incremental with Verification

**User:** "Add rate limiting to the API"

**Wrong:** Implements full rate limiting with Redis, multiple strategies, config system, and monitoring in one 300-line commit.

**Right — incremental, each step independently verifiable:**
```
1. Basic in-memory rate limiting (single endpoint)
   Verify: 100 requests → first 10 succeed, rest get 429

2. Extract to middleware (all endpoints)
   Verify: Limits apply to /users and /posts, existing tests pass

3. Redis backend (multi-server)
   Verify: Limit persists across restarts, shared across instances

4. Per-endpoint configuration
   Verify: /search allows 10/min, /users allows 100/min
```

---

## Anti-Patterns Summary

| Principle | Anti-Pattern | Fix |
|-----------|-------------|-----|
| Think Before Coding | Silently assumes format, fields, scope | List assumptions explicitly, ask |
| Simplicity First | Strategy pattern for single calculation | One function until complexity is needed |
| Surgical Changes | Reformats quotes, adds type hints while fixing bug | Only change lines that fix the issue |
| Goal-Driven | "I'll review and improve the code" | "Write test for X → make it pass → verify" |

**Key insight:** The "overcomplicated" examples follow real design patterns — the problem is **timing**. They add complexity before it's needed, making code harder to understand, test, and maintain.
