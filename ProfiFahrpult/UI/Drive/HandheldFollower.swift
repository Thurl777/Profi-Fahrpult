import Foundation

/// Lässt die Regler der App einer Multimaus folgen: Wird an einem Handregler eine Lok bedient,
/// die auf keinem Regler liegt, übernimmt sie der Regler, der am längsten nicht benutzt wurde.
final class HandheldFollower: NSObject, Z21ClientObserver {

    private let client = Z21Client.shared
    private let throttleCount: Int
    /// Zeitpunkt, zu dem dem Regler zuletzt eine Lok zugewiesen wurde
    private var assignedAt: [Date]
    /// Letzte Bedienung des Reglers in der App
    private var appUse: [Date]
    /// So lange nach einer Bedienung in der App wird der Regler nicht ersetzt
    private let appUseLock: TimeInterval = 3

    init(throttleCount: Int) {
        self.throttleCount = throttleCount
        assignedAt = Array(repeating: .distantPast, count: throttleCount)
        appUse = Array(repeating: .distantPast, count: throttleCount)
        super.init()
        client.addObserver(self)
        NotificationCenter.default.addObserver(self, selector: #selector(assignmentChanged(_:)),
                                               name: .throttleAssignmentChanged, object: nil)
    }

    deinit {
        client.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    /// Regler wurde in der App bedient
    func noteAppUse(throttle: Int) {
        guard throttle < throttleCount else { return }
        appUse[throttle] = Date()
    }

    @objc private func assignmentChanged(_ note: Notification) {
        if let throttle = note.userInfo?["throttle"] as? Int, throttle < throttleCount {
            assignedAt[throttle] = Date()
        } else if note.userInfo?["swapped"] as? Bool == true, throttleCount >= 2 {
            assignedAt.swapAt(0, 1)
            appUse.swapAt(0, 1)
        }
    }

    private func address(of throttle: Int) -> UInt16? {
        return LocoStore.shared.loco(id: AppSettings.shared.throttleLocoID(throttle))?.address
    }

    private func lastUse(of throttle: Int) -> Date {
        var last = max(assignedAt[throttle], appUse[throttle])
        if let a = address(of: throttle), let ext = client.lastExternalActivity[a] {
            last = max(last, ext)
        }
        return last
    }

    // MARK: Z21ClientObserver

    func z21Client(_ client: Z21Client, externalLocoActivity info: LocoInfo) {
        guard AppSettings.shared.followHandhelds else { return }
        let throttles = Array(0..<throttleCount)
        let now = Date()
        let locked = Set(throttles.filter { now.timeIntervalSince(appUse[$0]) < appUseLock })
        guard let target = HandheldFollow.throttleToReplace(addresses: throttles.map { address(of: $0) },
                                                            lastUse: throttles.map { lastUse(of: $0) },
                                                            newAddress: info.address,
                                                            locked: locked) else { return }
        let loco: Locomotive
        if let known = LocoStore.shared.loco(address: info.address) {
            loco = known
        } else {
            // Unbekannte Lok wie bei „Adresse direkt eingeben“ anlegen, mit den Fahrstufen der Zentrale
            loco = Locomotive(name: "Lok \(info.address)", address: info.address, speedSteps: info.speedSteps)
            LocoStore.shared.add(loco)
        }
        AppSettings.shared.setThrottleLocoID(loco.id, for: target)
    }
}
