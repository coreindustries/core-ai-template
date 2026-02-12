# iOS Development Rules

**These rules apply to native iOS projects** built with Swift, SwiftUI, and the Apple platform SDK. Follow these practices for modern, performant, and App Store-ready applications.

## Quick Reference

- **SwiftUI First**: Default to SwiftUI, use UIKit only when SwiftUI lacks the capability
- **Concurrency**: Use Swift structured concurrency (`async/await`, actors) over GCD/closures
- **Architecture**: MVVM with `@Observable` (iOS 17+) or `ObservableObject` (iOS 16)
- **Data**: SwiftData for persistence, Keychain for secrets, `UserDefaults` for preferences only
- **Networking**: `URLSession` with `async/await`, `Codable` for JSON
- **Testing**: XCTest for unit tests, XCUITest for UI tests, Swift Testing for modern tests
- **Dependencies**: Swift Package Manager (SPM) over CocoaPods/Carthage

## 1. SwiftUI Patterns

### View Composition

```swift
// CORRECT: Small, composable views
struct UserProfileView: View {
    let user: User

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AvatarView(url: user.avatarURL)
            UserInfoSection(user: user)
            ActionButtonsSection(userId: user.id)
        }
    }
}

// WRONG: Massive view body with all logic inline
```

### State Management

| Property Wrapper | Use For |
|-----------------|---------|
| `@State` | View-local value types |
| `@Binding` | Two-way reference to parent's state |
| `@Observable` (iOS 17+) | Reference type models |
| `@ObservableObject` (iOS 16) | Reference type models (legacy) |
| `@Environment` | Dependency injection / shared values |
| `@AppStorage` | UserDefaults-backed preferences |

```swift
// iOS 17+ with @Observable
@Observable
final class UserViewModel {
    var user: User?
    var isLoading = false
    var error: Error?

    func fetchUser(id: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            user = try await userService.fetch(id: id)
        } catch {
            self.error = error
        }
    }
}

struct UserView: View {
    @State private var viewModel = UserViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
            } else if let user = viewModel.user {
                UserProfileView(user: user)
            }
        }
        .task { await viewModel.fetchUser(id: userId) }
    }
}
```

### Navigation

```swift
// Use NavigationStack (iOS 16+) with type-safe navigation
@Observable
final class Router {
    var path = NavigationPath()

    func navigate(to destination: AppDestination) {
        path.append(destination)
    }

    func popToRoot() {
        path.removeLast(path.count)
    }
}

enum AppDestination: Hashable {
    case userProfile(id: String)
    case settings
    case detail(Item)
}
```

## 2. Swift Concurrency

### Structured Concurrency

```swift
// CORRECT: async/await
func fetchDashboard() async throws -> Dashboard {
    async let profile = fetchProfile()
    async let posts = fetchPosts()
    async let notifications = fetchNotifications()

    return Dashboard(
        profile: try await profile,
        posts: try await posts,
        notifications: try await notifications
    )
}

// WRONG: Completion handlers / callback hell
func fetchDashboard(completion: @escaping (Result<Dashboard, Error>) -> Void) {
    fetchProfile { profileResult in
        fetchPosts { postsResult in ... }
    }
}
```

### Actors for Thread Safety

```swift
actor ImageCache {
    private var cache: [URL: UIImage] = [:]

    func image(for url: URL) -> UIImage? {
        cache[url]
    }

    func store(_ image: UIImage, for url: URL) {
        cache[url] = image
    }
}
```

### MainActor for UI Updates

```swift
@MainActor
final class ViewModel: Observable {
    var items: [Item] = []

    func refresh() async {
        // Safe to update @Published/UI-bound properties
        items = try await service.fetchItems()
    }
}
```

## 3. Data Persistence

### Storage Decision Table

| Data Type | Storage | Example |
|-----------|---------|---------|
| User preferences | `UserDefaults` / `@AppStorage` | Theme, language |
| Structured data | SwiftData / Core Data | Users, posts, orders |
| Secrets & tokens | Keychain | Auth tokens, API keys |
| Files & media | FileManager (Documents/Caches) | Images, downloads |
| Temporary cache | `NSCache` / URLCache | API responses, thumbnails |

### SwiftData (iOS 17+)

```swift
@Model
final class Task {
    var title: String
    var isCompleted: Bool
    var createdAt: Date

    init(title: String) {
        self.title = title
        self.isCompleted = false
        self.createdAt = .now
    }
}

struct TaskListView: View {
    @Query(sort: \Task.createdAt, order: .reverse) var tasks: [Task]
    @Environment(\.modelContext) var context

    var body: some View {
        List(tasks) { task in
            TaskRow(task: task)
        }
    }

    func addTask(title: String) {
        context.insert(Task(title: title))
    }
}
```

### Keychain for Secrets

```swift
import Security

enum KeychainHelper {
    static func save(_ data: Data, for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
}

// NEVER store tokens in UserDefaults
// UserDefaults.standard.set(token, forKey: "authToken") // WRONG
```

## 4. Networking

```swift
// Protocol-based API client
protocol APIClient: Sendable {
    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T
}

struct URLSessionAPIClient: APIClient {
    private let session: URLSession
    private let decoder: JSONDecoder

    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let (data, response) = try await session.data(for: endpoint.urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        return try decoder.decode(T.self, from: data)
    }
}
```

## 5. Project Structure

```
MyApp/
├── App/
│   ├── MyApp.swift              # @main entry point
│   └── AppDelegate.swift        # UIKit lifecycle (if needed)
├── Features/
│   ├── Auth/
│   │   ├── Views/
│   │   ├── ViewModels/
│   │   └── Models/
│   └── Home/
│       ├── Views/
│       ├── ViewModels/
│       └── Models/
├── Core/
│   ├── Network/                 # API client, endpoints
│   ├── Storage/                 # Keychain, SwiftData
│   ├── Extensions/              # Swift extensions
│   └── Utilities/               # Shared helpers
├── Resources/
│   ├── Assets.xcassets
│   └── Localizable.xcstrings
└── Tests/
    ├── UnitTests/
    └── UITests/
```

## 6. Testing

```swift
// Swift Testing (modern, preferred)
import Testing

@Suite("UserViewModel Tests")
struct UserViewModelTests {
    @Test("Fetches user successfully")
    func fetchUser() async throws {
        let mockService = MockUserService(result: .success(.stub))
        let viewModel = UserViewModel(service: mockService)

        await viewModel.fetchUser(id: "123")

        #expect(viewModel.user?.id == "123")
        #expect(viewModel.isLoading == false)
    }

    @Test("Handles fetch error")
    func fetchUserError() async {
        let mockService = MockUserService(result: .failure(APIError.notFound))
        let viewModel = UserViewModel(service: mockService)

        await viewModel.fetchUser(id: "invalid")

        #expect(viewModel.user == nil)
        #expect(viewModel.error != nil)
    }
}
```

## 7. Performance

- **Lazy loading**: Use `LazyVStack`/`LazyHStack` for large lists
- **Image caching**: Use `AsyncImage` with cache or a library like Kingfisher
- **Background tasks**: Use `BGTaskScheduler` for background processing
- **Memory**: Profile with Instruments, avoid retain cycles with `[weak self]` in closures
- **Launch time**: Defer non-critical work, minimize `@main` app init

## 8. Common Anti-Patterns

| Anti-Pattern | Fix |
|-------------|-----|
| Force unwrapping (`!`) everywhere | Use `guard let`, `if let`, or nil coalescing |
| Massive view controllers/views | Extract into smaller components |
| GCD for new code | Use `async/await` and actors |
| Storing secrets in `UserDefaults` | Use Keychain |
| Synchronous network calls | Use `async/await` with `URLSession` |
| Ignoring `@MainActor` | Annotate UI-mutating code |
| Not handling cancellation | Check `Task.isCancelled`, use `.task` modifier |

## See Also

- `.claude/rules/security-core.md` - Core security practices (always auto-loaded)
- `.claude/rules-available/security-mobile.md` - Mobile security (React Native, but patterns apply)
- [Swift Documentation](https://docs.swift.org/swift-book/)
- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
