#if os(macOS)
import Foundation
import Network

/// Rebuild only exact-address LAN listeners. Accepted sessions and the separate
/// embedded-tailnet listener have independent lifetimes.
@MainActor
final class LANListeners {
    private struct Entry {
        var id: UUID
        var primary: Bool
        var server: NWListener
        var pairing: LANPairing?
    }
    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private var retryAfter: [String: TimeInterval] = [:]
    private var secret = ""
    private let primaryPort: NWEndpoint.Port
    private let queue = DispatchQueue(label: "dev.chordesk.lan-listeners")
    var onChange: (([LANPairing]) -> Void)?
    var onConnection: ((NWConnection) -> Void)?
    var onFailure: ((String) -> Void)?
    var pairings: [LANPairing] { order.compactMap { entries[$0]?.pairing } }

    init(primaryPort: NWEndpoint.Port = NWEndpoint.Port(rawValue: LANPairing.defaultPort)!) {
        self.primaryPort = primaryPort
    }

    static func addresses(selected: String, interfaces: [RemoteInterfaceAddress]) -> [String] {
        let eligible = interfaces.filter {
            $0.isUp && LANPairing.isLocalHost($0.address) && !$0.address.hasPrefix("127.") && $0.address != "::1"
        }.sorted {
            ($0.name.hasPrefix("en") ? 0 : 1, $0.name, $0.address.contains(":") ? 1 : 0, $0.address)
            < ($1.name.hasPrefix("en") ? 0 : 1, $1.name, $1.address.contains(":") ? 1 : 0, $1.address)
        }
        guard let primary = eligible.first(where: { $0.address == selected }) ?? eligible.first else { return [] }
        let extra = eligible.filter { $0.name == primary.name && $0.address != primary.address && LANAddress.ipv6($0.address) != nil }
        return ([primary.address] + extra.map(\.address)).reduce(into: []) {
            if $0.count < 4 && !$0.contains($1) { $0.append($1) }
        }
    }

    func reconcile(addresses: [String], secret newSecret: String, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard LANPairing.isValidSecret(newSecret) else { stop(); return }
        if secret != newSecret { stop(); secret = newSecret }
        let desired = addresses.filter { LANPairing.isLocalHost($0) }.reduce(into: [String]()) {
            if $0.count < 4 && !$0.contains($1) { $0.append($1) }
        }
        let oldPairings = pairings
        order = desired
        for (address, entry) in entries where !desired.contains(address) || entry.primary != (desired.first == address) {
            entries.removeValue(forKey: address) // Invalidate before cancel delivers a queued callback.
            entry.server.cancel()
        }
        retryAfter = retryAfter.filter { desired.contains($0.key) }
        for (index, address) in desired.enumerated() where entries[address] == nil && now >= retryAfter[address, default: 0] {
            let id = UUID()
            do {
                let server = try LANTransport.listener(secret: secret, localAddress: address, port: index == 0 ? primaryPort : .any)
                entries[address] = Entry(id: id, primary: index == 0, server: server)
                server.newConnectionHandler = { [weak self] connection in
                    Task { @MainActor in
                        guard let self, self.entries[address]?.id == id,
                              let peer = LANAddress.host(of: connection.endpoint),
                              LANAddress.permitsPeer(peer, boundAddress: address) else { connection.cancel(); return }
                        self.onConnection?(connection)
                    }
                }
                server.stateUpdateHandler = { [weak self, weak server] state in
                    Task { @MainActor in
                        guard let self, let server, self.entries[address]?.id == id else { return }
                        switch state {
                        case .ready:
                            guard let port = server.port else { return }
                            self.entries[address]?.pairing = LANPairing(host: LANAddress.unscoped(address), port: port.rawValue, secret: self.secret)
                            self.retryAfter.removeValue(forKey: address)
                            self.onChange?(self.pairings)
                        case .failed(let error):
                            self.entries.removeValue(forKey: address)
                            self.retryAfter[address] = ProcessInfo.processInfo.systemUptime + 3
                            server.cancel()
                            self.onChange?(self.pairings)
                            self.onFailure?(error.localizedDescription)
                        default: break
                        }
                    }
                }
                server.start(queue: queue)
            } catch {
                retryAfter[address] = now + 3
                onFailure?(error.localizedDescription)
            }
        }
        if pairings != oldPairings { onChange?(pairings) }
    }

    func stop() {
        let old = entries.values.map(\.server)
        entries.removeAll(); order.removeAll(); retryAfter.removeAll(); secret = ""
        old.forEach { $0.cancel() }
        onChange?([])
    }
}
#endif
