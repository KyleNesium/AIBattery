import Network

@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()
    private(set) var isConnected = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    func start() {
        // pathUpdateHandler fires on `queue` (background). Re-hop to MainActor
        // before touching `isConnected`. Capture `self` weakly outside the Task
        // and bind to a local before re-using inside — older Swift compilers
        // reject `self?.x = ...` inside a `Task` body when `self` is a `var`
        // capture from the enclosing closure (the closure is `var self` since
        // `[weak self]` makes it optional).
        monitor.pathUpdateHandler = { [weak self] path in
            let isUp = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.isConnected = isUp
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
