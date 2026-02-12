# Android Development Rules

**These rules apply to native Android projects** built with Kotlin, Jetpack Compose, and the Android SDK. Follow these practices for modern, performant, and Play Store-ready applications.

## Quick Reference

- **Compose First**: Default to Jetpack Compose, use Views/XML only for legacy integration
- **Architecture**: MVVM with Hilt DI, Repository pattern, single-activity navigation
- **Concurrency**: Kotlin Coroutines + Flow, scope to `viewModelScope` / `lifecycleScope`
- **Data**: Room for local DB, DataStore for preferences, EncryptedSharedPreferences for secrets
- **Networking**: Retrofit or Ktor with kotlinx.serialization
- **Testing**: JUnit 5 + Turbine for Flow, Compose testing for UI, MockK for mocks
- **Build**: Kotlin DSL (`build.gradle.kts`), version catalogs, Gradle convention plugins

## 1. Jetpack Compose Patterns

### Composable Best Practices

```kotlin
// CORRECT: Stateless composable with hoisted state
@Composable
fun UserProfile(
    user: User,
    onEditClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.padding(16.dp)) {
        Avatar(url = user.avatarUrl)
        Text(user.name, style = MaterialTheme.typography.headlineMedium)
        Button(onClick = onEditClick) { Text("Edit") }
    }
}

// WRONG: Composable with ViewModel directly, hard to test/preview
@Composable
fun UserProfile(viewModel: UserViewModel = hiltViewModel()) { ... }
```

### State Management

| API | Use For |
|-----|---------|
| `remember` | Composable-local state |
| `rememberSaveable` | Survives config changes (rotation) |
| `StateFlow` in ViewModel | Screen-level state |
| `collectAsStateWithLifecycle()` | Observe Flow lifecycle-aware |
| `derivedStateOf` | Computed state from other state |

```kotlin
// ViewModel with sealed UI state
@HiltViewModel
class UserViewModel @Inject constructor(
    private val userRepository: UserRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow<UserUiState>(UserUiState.Loading)
    val uiState: StateFlow<UserUiState> = _uiState.asStateFlow()

    fun fetchUser(id: String) {
        viewModelScope.launch {
            _uiState.value = UserUiState.Loading
            userRepository.getUser(id)
                .onSuccess { _uiState.value = UserUiState.Success(it) }
                .onFailure { _uiState.value = UserUiState.Error(it.message) }
        }
    }
}

sealed interface UserUiState {
    data object Loading : UserUiState
    data class Success(val user: User) : UserUiState
    data class Error(val message: String?) : UserUiState
}

// In Composable
@Composable
fun UserScreen(viewModel: UserViewModel = hiltViewModel()) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

    when (val state = uiState) {
        is UserUiState.Loading -> CircularProgressIndicator()
        is UserUiState.Success -> UserProfile(user = state.user, ...)
        is UserUiState.Error -> ErrorMessage(state.message)
    }
}
```

### Navigation (Compose Navigation)

```kotlin
// Type-safe navigation with kotlinx.serialization
@Serializable data object HomeRoute
@Serializable data class UserRoute(val id: String)
@Serializable data object SettingsRoute

@Composable
fun AppNavigation() {
    val navController = rememberNavController()

    NavHost(navController, startDestination = HomeRoute) {
        composable<HomeRoute> {
            HomeScreen(onUserClick = { navController.navigate(UserRoute(it)) })
        }
        composable<UserRoute> { backStackEntry ->
            val route = backStackEntry.toRoute<UserRoute>()
            UserScreen(userId = route.id)
        }
        composable<SettingsRoute> { SettingsScreen() }
    }
}
```

## 2. Kotlin Coroutines & Flow

### Coroutine Scoping

```kotlin
// CORRECT: Scoped to ViewModel lifecycle
class MyViewModel : ViewModel() {
    fun loadData() {
        viewModelScope.launch {
            val result = repository.fetchData()
            // Update state
        }
    }
}

// CORRECT: Scoped to lifecycle in Activity/Fragment
lifecycleScope.launch {
    repeatOnLifecycle(Lifecycle.State.STARTED) {
        viewModel.uiState.collect { state -> /* update UI */ }
    }
}

// WRONG: GlobalScope (leaks, never cancelled)
GlobalScope.launch { ... }
```

### Flow Patterns

```kotlin
// Repository exposing Flow
class UserRepository @Inject constructor(
    private val userDao: UserDao,
    private val api: UserApi,
) {
    fun observeUser(id: String): Flow<User> = userDao.observeUser(id)

    suspend fun refreshUser(id: String): Result<User> = runCatching {
        val user = api.getUser(id)
        userDao.upsert(user.toEntity())
        user
    }
}
```

## 3. Dependency Injection (Hilt)

```kotlin
// Module
@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {
    @Provides
    @Singleton
    fun provideRetrofit(): Retrofit =
        Retrofit.Builder()
            .baseUrl(BuildConfig.API_BASE_URL)
            .addConverterFactory(Json.asConverterFactory("application/json".toMediaType()))
            .build()

    @Provides
    @Singleton
    fun provideUserApi(retrofit: Retrofit): UserApi =
        retrofit.create<UserApi>()
}

// Repository with constructor injection
class UserRepository @Inject constructor(
    private val api: UserApi,
    private val dao: UserDao,
)
```

## 4. Data Persistence

### Storage Decision Table

| Data Type | Storage | Example |
|-----------|---------|---------|
| User preferences | DataStore | Theme, language, onboarding |
| Structured data | Room | Users, posts, cached content |
| Secrets & tokens | EncryptedSharedPreferences | Auth tokens, API keys |
| Files & media | FileProvider / MediaStore | Downloads, images |
| Temporary cache | OkHttp cache / LruCache | API responses, bitmaps |

### Room Database

```kotlin
@Entity(tableName = "users")
data class UserEntity(
    @PrimaryKey val id: String,
    val name: String,
    val email: String,
    val updatedAt: Long = System.currentTimeMillis(),
)

@Dao
interface UserDao {
    @Query("SELECT * FROM users WHERE id = :id")
    fun observeUser(id: String): Flow<UserEntity?>

    @Upsert
    suspend fun upsert(user: UserEntity)

    @Query("DELETE FROM users WHERE id = :id")
    suspend fun delete(id: String)
}

@Database(entities = [UserEntity::class], version = 1)
abstract class AppDatabase : RoomDatabase() {
    abstract fun userDao(): UserDao
}
```

### Encrypted Storage for Secrets

```kotlin
// CORRECT: EncryptedSharedPreferences for tokens
val masterKey = MasterKey.Builder(context)
    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
    .build()

val securePrefs = EncryptedSharedPreferences.create(
    context, "secure_prefs", masterKey,
    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
)

securePrefs.edit().putString("auth_token", token).apply()

// WRONG: Plain SharedPreferences for secrets
// prefs.putString("auth_token", token) // NOT SECURE
```

## 5. Project Structure

```
app/
├── src/main/
│   ├── java/com/example/myapp/
│   │   ├── App.kt                  # Application class
│   │   ├── MainActivity.kt         # Single activity
│   │   ├── navigation/             # Nav graph, routes
│   │   ├── feature/
│   │   │   ├── auth/
│   │   │   │   ├── ui/             # Composables
│   │   │   │   ├── viewmodel/      # ViewModels
│   │   │   │   └── model/          # UI models
│   │   │   └── home/
│   │   ├── data/
│   │   │   ├── repository/         # Repository implementations
│   │   │   ├── local/              # Room DAOs, DataStore
│   │   │   ├── remote/             # Retrofit APIs
│   │   │   └── model/              # Data/entity models
│   │   ├── domain/
│   │   │   ├── model/              # Domain models
│   │   │   └── usecase/            # Use cases (optional)
│   │   ├── di/                     # Hilt modules
│   │   └── core/
│   │       ├── ui/                 # Shared composables, theme
│   │       └── util/               # Extensions, helpers
│   └── res/
│       ├── values/
│       └── drawable/
├── src/test/                        # Unit tests
├── src/androidTest/                 # Instrumented tests
└── build.gradle.kts
```

## 6. Testing

```kotlin
// ViewModel test with Turbine for Flow testing
@OptIn(ExperimentalCoroutinesApi::class)
class UserViewModelTest {
    @get:Rule
    val mainDispatcherRule = MainDispatcherRule()

    private val repository = mockk<UserRepository>()
    private lateinit var viewModel: UserViewModel

    @Test
    fun `fetchUser emits loading then success`() = runTest {
        coEvery { repository.getUser("123") } returns Result.success(User.stub())
        viewModel = UserViewModel(repository)

        viewModel.uiState.test {
            viewModel.fetchUser("123")
            assertThat(awaitItem()).isEqualTo(UserUiState.Loading)
            assertThat(awaitItem()).isInstanceOf(UserUiState.Success::class.java)
        }
    }
}

// Compose UI test
class UserProfileTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun displaysUserName() {
        composeRule.setContent {
            UserProfile(user = User.stub(), onEditClick = {})
        }
        composeRule.onNodeWithText("John Doe").assertIsDisplayed()
    }
}
```

## 7. Build Configuration

### Version Catalog (`gradle/libs.versions.toml`)

```toml
[versions]
kotlin = "2.1.0"
compose-bom = "2025.01.00"
hilt = "2.53"
room = "2.7.0"

[libraries]
compose-bom = { module = "androidx.compose:compose-bom", version.ref = "compose-bom" }
compose-material3 = { module = "androidx.compose.material3:material3" }
hilt-android = { module = "com.google.dagger:hilt-android", version.ref = "hilt" }
room-runtime = { module = "androidx.room:room-runtime", version.ref = "room" }
room-ktx = { module = "androidx.room:room-ktx", version.ref = "room" }

[plugins]
kotlin-android = { id = "org.jetbrains.kotlin.android", version.ref = "kotlin" }
hilt = { id = "com.google.dagger.hilt.android", version.ref = "hilt" }
```

### ProGuard / R8

```kotlin
// build.gradle.kts
android {
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}
```

## 8. Performance

- **Compose stability**: Mark classes as `@Stable` or `@Immutable` to skip recomposition
- **Lists**: Use `LazyColumn`/`LazyRow` with `key` parameter for efficient diffing
- **Images**: Use Coil with proper sizing and caching
- **Baseline Profiles**: Generate for faster startup
- **Strict Mode**: Enable in debug builds to catch disk/network on main thread
- **LeakCanary**: Include in debug builds for memory leak detection

## 9. Common Anti-Patterns

| Anti-Pattern | Fix |
|-------------|-----|
| `GlobalScope.launch` | Use `viewModelScope` or `lifecycleScope` |
| Mutable state in composable params | Hoist state, pass immutable data down |
| Secrets in `SharedPreferences` | Use `EncryptedSharedPreferences` |
| Network calls on main thread | Use `Dispatchers.IO` with coroutines |
| Not handling process death | Use `rememberSaveable`, `SavedStateHandle` |
| Hardcoded strings in UI | Use string resources for i18n |
| Missing ProGuard rules | Test release builds, add keep rules |

## See Also

- `.claude/rules/security-core.md` - Core security practices (always auto-loaded)
- `.claude/rules-available/security-owasp.md` - OWASP Top 10 standards
- [Android Developers](https://developer.android.com/)
- [Compose Documentation](https://developer.android.com/develop/ui/compose)
- [Kotlin Documentation](https://kotlinlang.org/docs/home.html)
