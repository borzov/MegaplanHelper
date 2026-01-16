# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MegaplanMenuBarApp is a native macOS menu bar application that displays notifications from Megaplan CRM directly in the macOS menu bar. Built with SwiftUI and targeting macOS 13.0+.

## Build Commands

### Build and Run
```bash
# Build universal binary (arm64 + x86_64) - recommended for distribution
./scripts/build-universal.sh

# Open in Xcode
open MegaplanHepler.xcodeproj

# Build via Xcode
# Product → Build (Cmd+B) - for current architecture
# Product → Archive - for universal binary

# Build via xcodebuild
xcodebuild archive \
    -project MegaplanHepler.xcodeproj \
    -scheme MegaplanHepler \
    -configuration Release \
    -archivePath build/MegaplanHepler.xcarchive \
    -destination "generic/platform=macOS"
```

### Linting
```bash
swiftlint lint
swiftlint --fix  # Auto-fix issues
```

SwiftLint enforces: no `print()` statements (use `AppLogger`), function body ≤50 lines, file length ≤500 lines.

### Testing
No automated tests are currently configured in this project.

### Release Process
```bash
# 1. Update MARKETING_VERSION in Xcode
# 2. Update Changelog in README.md
# 3. Create commit and tag
git add .
git commit -m "v1.3: Description of changes"
git tag -a v1.3 -m "Version 1.3: Description of changes"
git push origin master
git push origin v1.3

# 4. Create GitHub Release (triggers automatic build via GitHub Actions)
gh release create v1.3 --title "v1.3 - Release Name" --notes "Changelog description"
```

GitHub Actions: `build.yml` (on push to master), `release.yml` (on tag `v*` creates release with universal binary).

## Architecture

### MVVM Pattern with Reactive Updates
The app follows MVVM architecture with SwiftUI and Combine:

- **Views** (`Views/`) - SwiftUI views with minimal logic
- **ViewModels** (`ViewModels/`) - Business logic, state management
- **Models** (`Models/`) - Data models (MegaplanNotification, MegaplanCredentials)
- **Services** (`Services/`) - API clients, managers, utilities
- **Utils** (`Utils/`) - Helper classes, extensions, constants

### Core Components

#### AppState (Global State)
`AppState.swift` is the central @MainActor ObservableObject managing:
- Authentication flow and token management
- Notification loading and auto-refresh timer
- Offline mode with cached data fallback
- User preferences (refresh interval, auto-launch)
- Integration with ErrorRecoveryService for retry logic
- Brute-force protection (max 3 failed login attempts)

Key flows:
- `signIn()` → validates token → starts refresh timer → calls `refresh()`
- `refresh()` → fetches notifications with retry → updates UI → sends system notifications for new items
- `logout()` → clears credentials from Keychain → resets state → stops timer
- Offline mode: if network error, uses `lastSuccessfulNotifications` cache

#### MegaplanAPI (API Client)
`Services/MegaplanAPI.swift` implements two protocols:
- `AuthenticationService` - auth and token validation
- `NotificationService` - fetch notifications, mark as read

Authentication uses multipart/form-data POST to `/api/v3/auth/access_token`
All authenticated requests use Bearer token in Authorization header
Dynamic base URL set via `updateDomain()`

#### KeychainManager
`Services/KeychainManager.swift` - secure storage for:
- Access tokens (account: "MegaplanAccessToken")
- Cached passwords for auto-reauth (account: "MegaplanPassword_\(username)_\(domain)")

#### NotificationManager
`Services/NotificationManager.swift` - handles macOS UserNotifications:
- Requests authorization on app startup
- Sends notification for new unread items
- Tracks sent notification IDs to avoid duplicates
- Respects user preference for system notifications

#### ErrorRecoveryService
`Services/ErrorRecoveryService.swift` - retry mechanism:
- Max 3 retries with exponential backoff (1s → 2s → 4s, max 30s)
- Skips retry for unauthorized/validation errors
- Used in `AppState.refresh()` to handle transient network errors

#### UserInfoCache
`Services/UserInfoCache.swift` - caches user metadata (names, avatars)
Populated during notification fetch to avoid repeated API calls

### ViewModels

#### NotificationListViewModel
- Subscribes to `AppState.$notifications` via Combine
- Groups notifications using `NotificationGrouper`
- Supports "show only unread" filter
- Manages grouping toggle state

#### SettingsViewModel
- Manages settings UI state
- Delegates to AppState for actual changes

#### AuthViewModel
- Manages temporary credentials during sign-in flow
- Validates input (email format, non-empty fields)

### Key Patterns

1. **@MainActor for UI Classes**: All ViewModels and AppState are @MainActor
2. **Combine Publishers**: ViewModels subscribe to AppState published properties
3. **Secure Memory Management**: `clearCachedPassword()` zeros out password data before release
4. **Throttling**: `refreshNow()` has minimum 5s interval to prevent abuse
5. **Optimistic UI**: `markNotificationAsRead()` updates UI immediately, rolls back on error
6. **Offline Mode**: Network errors trigger `isOffline` flag, app uses cached data
7. **Auto-Launch**: Uses `SMAppService.mainApp` API (macOS 13.0+)

## Localization

Localized strings in `Resources/{en,ru}.lproj/Localizable.strings`. Date formatting uses system locale.

## Security Considerations

- Passwords/tokens stored in Keychain, never in UserDefaults
- Passwords cleared from memory on logout using `resetBytes()`
- Brute-force protection: max 3 login attempts per 60 seconds
- Admin permission check via `possibleActions` array from API

## Constants

`Utils/Constants.swift` defines:
- UserDefaults keys
- Keychain service/account names
- Admin permission identifiers
- Default settings values (refresh interval, etc.)

Never hardcode these values elsewhere - always reference Constants.

## Logging

Use `AppLogger` (defined in `Utils/Constants.swift`) instead of `print()`:
- `AppLogger.debug()`, `AppLogger.info()`, `AppLogger.warning()`, `AppLogger.error()`

Logs are written to both:
- macOS unified logging (view with Console.app or `log stream`)
- File: `~/Library/Logs/MegaplanApp.log`

## Common Tasks

### Adding New API Endpoint
1. Add method to `MegaplanAPI` (conform to relevant protocol or create new one)
2. Create request with `makeRequest(path:method:body:token:)`
3. Use `perform()` to execute and decode response
4. Handle errors with NetworkError enum
5. Call from AppState or ViewModel with proper error handling

### Adding New Setting
1. Add key to `Constants.UserDefaultsKeys`
2. Add @Published property to AppState
3. Save/load from UserDefaults in init/update methods
4. Add UI control in SettingsView
5. Update SettingsViewModel if complex logic needed

### Adding New Notification Feature
1. Update `MegaplanNotification` model if new fields needed
2. Modify `NotificationParser` to extract data from API response
3. Update `NotificationListView` to display new information
4. Consider caching strategy (UserInfoCache pattern)

## Project Naming Note

The Xcode project is named `MegaplanHepler.xcodeproj` (typo in "Helper"), but the app is correctly named "Megaplan Helper" in user-facing strings. This is historical and not worth changing.
