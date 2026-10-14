import PodlistKit
import SwiftData
import SwiftUI
import os

@main
struct PodlistApp: App {
    private let container: ModelContainer
    private let isUITesting: Bool
    /// `-screenshots`: like `-uiTesting`, with the made-up library for the website screenshots.
    private let isScreenshots: Bool
    @State private var playlistService: PlaylistService
    @State private var library: LibraryService
    @State private var upNext: UpNextService
    @State private var player: PlayerController
    @State private var downloads: DownloadService
    @State private var notifications: NotificationScheduler
    @State private var notificationHandler: NotificationHandler
    @State private var inbox: InboxService
    @State private var hiddenPlaylists = HiddenPlaylistsReveal()
    private let chapters: ChapterService
    private let directory: PodcastDirectory
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        isScreenshots = arguments.contains("-screenshots")
        isUITesting = arguments.contains("-uiTesting") || isScreenshots
        // UI tests wait for every transition; without animations they run much faster.
        if isUITesting { UIView.setAnimationsEnabled(false) }
        do {
            container = try PodlistStore.makeContainer(inMemory: isUITesting)
        } catch {
            Logger.store.fault("Model container failed: \(error.localizedDescription, privacy: .public)")
            fatalError("Model container failed: \(error)")
        }
        // Artwork comes via AsyncImage; a bigger cache keeps the library grid fast.
        URLCache.shared = URLCache(memoryCapacity: 50_000_000, diskCapacity: 300_000_000)

        let session = isUITesting ? UITestNetwork.session() : .shared
        let settings = Self.settings(isUITesting: isUITesting)
        let downloads = Self.makeDownloads(container: container, settings: settings, isUITesting: isUITesting)
        let playlistService = PlaylistService(context: container.mainContext, downloads: downloads)
        let notifications = NotificationScheduler(
            context: container.mainContext,
            center: isUITesting ? UITestNotificationCenter() : SystemNotificationCenter(), settings: settings)
        let library = LibraryService(
            container: container, loader: FeedLoader(session: session), downloads: downloads, notifications: notifications)
        // UI tests never read real audio files (offline, deterministic).
        let chapters = isUITesting
            ? ChapterService(context: container.mainContext, session: session, loadAudio: { _ in nil })
            : ChapterService(context: container.mainContext)
        let player = PlayerController(
            library: library, chapters: chapters, downloads: downloads, settings: settings,
            recorder: ListeningRecorder(context: container.mainContext))
        let upNext = UpNextService(context: container.mainContext, library: library, player: player)
        let inbox = InboxService(
            context: container.mainContext, playlists: playlistService, upNext: upNext, defaults: settings)
        let notificationHandler = NotificationHandler(context: container.mainContext, playlists: playlistService, upNext: upNext)
        notificationHandler.activate()
        _playlistService = State(initialValue: playlistService)
        _library = State(initialValue: library)
        _upNext = State(initialValue: upNext)
        _player = State(initialValue: player)
        _downloads = State(initialValue: downloads)
        _notifications = State(initialValue: notifications)
        _notificationHandler = State(initialValue: notificationHandler)
        _inbox = State(initialValue: inbox)
        self.chapters = chapters
        directory = PodcastDirectory(session: session)
        Self.prepareStore(
            container: container, playlistService: playlistService, library: library,
            isUITesting: isUITesting, isScreenshots: isScreenshots)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(playlistService)
                .environment(library)
                .environment(upNext)
                .environment(player)
                .environment(downloads)
                .environment(notifications)
                .environment(notificationHandler)
                .environment(inbox)
                .environment(hiddenPlaylists)
                .environment(\.chapterService, chapters)
                .environment(\.podcastDirectory, directory)
                .task {
                    upNext.restoreSession()
                    await downloads.restoreAfterLaunch()
                    guard !isUITesting else { return }
                    // The refresh does not wait for the answer to the permission prompt.
                    async let asked: Void = notifications.requestAuthorizationIfNeeded()
                    await library.refreshAll()
                    await asked
                }
        }
        .modelContainer(container)
        // Downloads finished while the app was not running (ADR 0007).
        .backgroundTask(.urlSession(Downloader.backgroundIdentifier)) {
            await downloads.handleBackgroundEvents()
        }
        // New episodes while the app is not open (A44).
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            Logger.feeds.notice("Background refresh started")
            BackgroundRefresh.schedule()
            await library.refreshAll(budget: RefreshSchedule.backgroundBudget)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player.saveProgress() }
            // Hidden playlists show until the app leaves the screen, also when locking (N66);
            // so do the inbox's episodes just done (N74).
            if phase == .background {
                hiddenPlaylists.isRevealed = false
                inbox.endSession()
            }
            guard !isUITesting else { return }
            if phase == .background { BackgroundRefresh.schedule() }
            // Back in the app (A63); the launch refreshes in the task above.
            if phase == .active { Task { await library.refreshAllIfDue() } }
        }
    }

    /// UI tests download from the offline network into a fresh folder.
    private static func makeDownloads(container: ModelContainer, settings: UserDefaults, isUITesting: Bool) -> DownloadService {
        guard isUITesting else {
            return DownloadService(context: container.mainContext, downloader: .background(), settings: settings)
        }
        let files = DownloadFiles(directory: URL.temporaryDirectory.appending(path: "UITestDownloads-\(UUID().uuidString)"))
        return DownloadService(
            context: container.mainContext, downloader: Downloader(configuration: UITestNetwork.configuration(), files: files),
            files: files, settings: settings)
    }

    /// Player and download settings; UI tests start from the defaults every time.
    private static func settings(isUITesting: Bool) -> UserDefaults {
        let suite = "com.podlistapp.podlist.uiTesting"
        guard isUITesting, let defaults = UserDefaults(suiteName: suite) else { return .standard }
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// First launch: default playlists. Every launch: the playlist "Alles". Once: notifications for the existing subscriptions
    /// (N36), auto-download for the existing playlists (N89). UI tests: a fresh in-memory store with sample data;
    /// screenshots: with the made-up library in the app's language.
    private static func prepareStore(
        container: ModelContainer, playlistService: PlaylistService, library: LibraryService,
        isUITesting: Bool, isScreenshots: Bool
    ) {
        let defaults = UserDefaults.standard
        let key = "didInsertDefaultPlaylists"
        let notificationsKey = "didEnableNotificationsForSubscriptions"
        let autoDownloadKey = "didTurnOnAutoDownloadForAllPlaylists"
        do {
            if isUITesting || !defaults.bool(forKey: key) {
                try playlistService.insertDefaultPlaylists()
                if !isUITesting { defaults.set(true, forKey: key) }
            }
            // Every launch, so stores from before "Alles" get it too (concept §4.1).
            try playlistService.ensureEverything()
            if !isUITesting, !defaults.bool(forKey: notificationsKey) {
                try library.enableNotificationsForSubscribedPodcasts()
                defaults.set(true, forKey: notificationsKey)
            }
            if !isUITesting, !defaults.bool(forKey: autoDownloadKey) {
                try playlistService.turnOnAutoDownloadForAllPlaylists()
                defaults.set(true, forKey: autoDownloadKey)
            }
            if isScreenshots {
                try SampleData.insertScreenshots(
                    into: container.mainContext, german: Bundle.main.preferredLocalizations.first == "de",
                    artwork: ScreenshotArtwork.url(for:))
            } else if isUITesting {
                try SampleData.insert(into: container.mainContext)
            }
        } catch {
            Logger.store.error("Preparing the store failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension EnvironmentValues {
    @Entry var podcastDirectory = PodcastDirectory()
    @Entry var chapterService: ChapterService?
}
