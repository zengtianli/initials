import AppKit

/// System document notifications instead of another polling timer. Neither
/// file coordination nor downloading runs in the key callback or main thread.
final class CloudSyncController: NSObject, NSFilePresenter {
    var onUpdate: ((String) -> Void)?
    private let worker = DispatchQueue(label: "cyou.tianli.initials.icloud", qos: .utility)
    let presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private(set) var presentedItemURL: URL?
    private var registered = false
    private var tokens: [NSObjectProtocol] = []

    func start() {
        tokens.append(NotificationCenter.default.addObserver(forName: .NSUbiquityIdentityDidChange,
                                                             object: nil, queue: .main) { [weak self] _ in self?.request() })
        tokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                                        object: nil, queue: .main) { [weak self] _ in self?.request() })
        request()
    }

    func request() {
        worker.async { [weak self] in
            guard let self else { return }
            do {
                let enabled = try CloudSyncStore.preferences().enabled
                let target = enabled ? CloudSyncStore.directory : nil
                if self.presentedItemURL != target {
                    if self.registered { NSFileCoordinator.removeFilePresenter(self); self.registered = false }
                    self.presentedItemURL = target
                    if let target {
                        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                        NSFileCoordinator.addFilePresenter(self)
                        self.registered = true
                    }
                }
                let note = try CloudSyncStore.sync(presenter: self)
                DispatchQueue.main.async { [weak self] in self?.onUpdate?(note) }
            } catch {
                let note = T("iCloud 同步暂未完成：", "iCloud sync pending: ") + error.localizedDescription
                DispatchQueue.main.async { [weak self] in self?.onUpdate?(note) }
            }
        }
    }

    func presentedItemDidChange() { request() }
    func presentedSubitemDidChange(at url: URL) {
        if url.lastPathComponent == "config.json" || url.lastPathComponent == ".config.json.icloud" { request() }
    }
    func presentedSubitemDidAppear(at url: URL) { presentedSubitemDidChange(at: url) }
    deinit {
        if registered { NSFileCoordinator.removeFilePresenter(self) }
        for token in tokens { NotificationCenter.default.removeObserver(token); NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }
}
