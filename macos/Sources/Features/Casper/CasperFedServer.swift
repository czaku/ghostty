import Foundation
import Network
import OSLog

/// Lightweight HTTP server that integrates Casper with the vykeai fed control plane.
///
/// Exposes the standard fed contract so Casper appears in the fed dashboard
/// alongside tools like Sweech, Keel, and Simemu:
///
///   GET /fed/info    — machine + service metadata
///   GET /fed/runs    — active terminal surfaces (cwd, title, process)
///   GET /fed/widget  — key-value summary panel
///
/// Also advertises on mDNS:
///   _casper._tcp.local  (tool-specific bus)
///   _vykeai._tcp.local  (shared discovery bus, same identity as Sweech)
///
/// Start once from AppDelegate.applicationDidFinishLaunching.
final class CasperFedServer {
    static let shared = CasperFedServer()
    static let port: UInt16 = 7856
    static let version = "0.1.0"
    static let identity = "luke"
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CasperFedServer")

    private var listener: NWListener?
    private var netServices: [NetService] = []
    private let queue = DispatchQueue(label: "casper.fed.server", qos: .utility)

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    Self.logger.info("Fed server listening on port \(Self.port)")
                case .failed(let error):
                    Self.logger.error("Fed server failed: \(error)")
                default:
                    break
                }
            }
            listener.start(queue: queue)
            advertiseMDNS()
        } catch {
            Self.logger.error("Failed to create fed server listener: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        netServices.forEach { $0.stop() }
        netServices.removeAll()
    }

    // MARK: - mDNS

    private func advertiseMDNS() {
        let txtRecord = NetService.data(fromTXTRecord: [
            "identity": Self.identity.data(using: .utf8)!,
            "version": Self.version.data(using: .utf8)!,
            "service": "casper".data(using: .utf8)!,
        ])

        // Tool-specific bus: _casper._tcp.local
        let casperService = NetService(
            domain: "local.",
            type: "_casper._tcp.",
            name: "casper",
            port: Int32(Self.port)
        )
        casperService.setTXTRecord(txtRecord)
        casperService.publish()
        netServices.append(casperService)

        // Shared vykeai bus: _vykeai._tcp.local (same bus used by Sweech, Keel, etc.)
        let vykeaiService = NetService(
            domain: "local.",
            type: "_vykeai._tcp.",
            name: "casper",
            port: Int32(Self.port)
        )
        vykeaiService.setTXTRecord(txtRecord)
        vykeaiService.publish()
        netServices.append(vykeaiService)
    }

    // MARK: - Connection handling

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self, let data, !data.isEmpty else {
                connection.cancel()
                return
            }
            let requestLine = String(data: data, encoding: .utf8) ?? ""
            let path = Self.parsePath(from: requestLine)
            let (status, body) = self.response(for: path)
            self.send(status: status, body: body, on: connection)
        }
    }

    private func send(status: Int, body: String, on connection: NWConnection) {
        let statusText = status == 200 ? "OK" : "Not Found"
        let response = [
            "HTTP/1.1 \(status) \(statusText)",
            "Content-Type: application/json",
            "Access-Control-Allow-Origin: *",
            "Content-Length: \(body.utf8.count)",
            "Connection: close",
            "",
            body,
        ].joined(separator: "\r\n")
        let data = response.data(using: .utf8)!
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: - Route handlers

    private func response(for path: String) -> (Int, String) {
        switch path {
        case "/fed/info":   return (200, fedInfo())
        case "/fed/runs":   return (200, fedRuns())
        case "/fed/widget": return (200, fedWidget())
        default:            return (404, "{\"error\":\"Not found\"}")
        }
    }

    private func fedInfo() -> String {
        let hostname = ProcessInfo.processInfo.hostName
        let machine = hostname.components(separatedBy: ".").first ?? hostname
        let info: [String: Any] = [
            "machine": machine,
            "identity": Self.identity,
            "service": "casper",
            "version": Self.version,
            "fedPort": Self.port,
            "platform": "darwin",
            "uptime": ProcessInfo.processInfo.systemUptime,
            "hostname": hostname,
            "capabilities": ["session-save", "session-restore", "process-detection", "sweech-integration"],
        ]
        return json(info)
    }

    private func fedRuns() -> String {
        // Collect active surfaces from all open terminal windows
        let runs: [[String: Any]] = TerminalController.all.flatMap { controller in
            controller.surfaceTree.map { surface -> [String: Any] in
                let cwd = surface.pwd ?? ""
                let process = surface.pwd.flatMap {
                    ProcessDetector.replayableProcess(inDirectory: $0)
                } ?? ""
                let sweech = process.isEmpty ? nil : SweechReader.profile(forCommand: process)
                var run: [String: Any] = [
                    "cwd": cwd,
                    "title": surface.title,
                    "process": process,
                ]
                if let p = sweech {
                    run["provider"] = p.provider
                    run["model"] = p.model ?? ""
                }
                return run
            }
        }
        return jsonArray(runs)
    }

    private func fedWidget() -> String {
        let sessions = SessionManager.shared.listSessions()
        let widget: [String: Any] = [
            "type": "key-value",
            "title": "Casper",
            "emoji": "👻",
            "data": [
                "openWindows": TerminalController.all.count,
                "savedSessions": sessions.count,
                "latestSession": sessions.first?.name ?? "none",
            ] as [String: Any],
        ]
        return json(widget)
    }

    // MARK: - Helpers

    private static func parsePath(from request: String) -> String {
        // "GET /fed/info HTTP/1.1\r\n..."
        let firstLine = request.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return "/" }
        // Strip query string if present
        return parts[1].components(separatedBy: "?").first ?? parts[1]
    }

    private func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    private func jsonArray(_ array: [[String: Any]]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: array),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }
}
