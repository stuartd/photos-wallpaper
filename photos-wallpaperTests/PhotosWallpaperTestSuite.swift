import Testing
@testable import photos_wallpaper

@MainActor
/// App tests grouped across feature-specific extensions.
///
/// These stay at the orchestration layer: we are not testing Photos.framework or AppKit itself,
/// only that the app asks its collaborators for the right work at the right times.
///
/// Quick testing glossary:
/// - `@testable import`: lets the test target see internal symbols from the app target.
/// - fake: a small stand-in object used to observe calls without touching real system APIs.
struct PhotosWallpaperTests {}
