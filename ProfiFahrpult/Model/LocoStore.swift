import UIKit

extension Notification.Name {
    static let locoStoreChanged = Notification.Name("LocoStoreChanged")
    static let throttleAssignmentChanged = Notification.Name("ThrottleAssignmentChanged")
    static let accessoryStoreChanged = Notification.Name("AccessoryStoreChanged")
}

/// Lokbibliothek, gespeichert als JSON im Dokumentenordner der App.
final class LocoStore {

    static let shared = LocoStore()

    private(set) var locos: [Locomotive] = []
    private let fileURL: URL
    private let imageDirectory: URL
    private var imageCache: [String: UIImage] = [:]

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("locos.json")
        imageDirectory = docs.appendingPathComponent("LocoImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true, attributes: nil)
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([Locomotive].self, from: data) else {
            locos = [Locomotive(name: "BR 218", address: 3), Locomotive(name: "ICE 3", address: 4)]
            return
        }
        locos = list
    }

    private func save() {
        if let data = try? JSONEncoder().encode(locos) {
            try? data.write(to: fileURL, options: .atomic)
        }
        NotificationCenter.default.post(name: .locoStoreChanged, object: self)
    }

    var sortedLocos: [Locomotive] {
        return locos.sorted { a, b in
            if a.name.lowercased() == b.name.lowercased() { return a.address < b.address }
            return a.name.lowercased() < b.name.lowercased()
        }
    }

    func loco(id: String?) -> Locomotive? {
        guard let id = id else { return nil }
        return locos.first { $0.id == id }
    }

    func loco(address: UInt16) -> Locomotive? {
        return locos.first { $0.address == address }
    }

    /// Liefert die Lok mit dieser Adresse oder legt eine neue an.
    func locoCreatingIfNeeded(address: UInt16) -> Locomotive {
        if let l = loco(address: address) { return l }
        let l = Locomotive(name: "Lok \(address)", address: address)
        add(l)
        return l
    }

    func add(_ loco: Locomotive) {
        locos.append(loco)
        save()
    }

    func update(_ loco: Locomotive) {
        if let i = locos.firstIndex(where: { $0.id == loco.id }) {
            locos[i] = loco
        } else {
            locos.append(loco)
        }
        save()
    }

    func delete(id: String) {
        if let l = loco(id: id), let file = l.imageFile {
            try? FileManager.default.removeItem(at: imageDirectory.appendingPathComponent(file))
            imageCache[file] = nil
        }
        locos.removeAll { $0.id == id }
        let settings = AppSettings.shared
        for i in 0..<AppSettings.throttleCount where settings.throttleLocoID(i) == id {
            settings.setThrottleLocoID(nil, for: i)
        }
        save()
    }

    // MARK: Bilder

    func image(for loco: Locomotive) -> UIImage? {
        guard let file = loco.imageFile else { return nil }
        if let img = imageCache[file] { return img }
        let url = imageDirectory.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url), let img = UIImage(data: data) else { return nil }
        imageCache[file] = img
        return img
    }

    /// Speichert ein Bild (verkleinert) und liefert den Dateinamen.
    func storeImage(_ image: UIImage, for loco: Locomotive) -> String? {
        let maxWidth: CGFloat = 600
        var img = image
        if image.size.width > maxWidth {
            let scale = maxWidth / image.size.width
            let size = CGSize(width: maxWidth, height: (image.size.height * scale).rounded())
            UIGraphicsBeginImageContextWithOptions(size, false, 1)
            image.draw(in: CGRect(origin: .zero, size: size))
            img = UIGraphicsGetImageFromCurrentImageContext() ?? image
            UIGraphicsEndImageContext()
        }
        guard let data = img.jpegData(compressionQuality: 0.85) else { return nil }
        if let old = loco.imageFile {
            try? FileManager.default.removeItem(at: imageDirectory.appendingPathComponent(old))
            imageCache[old] = nil
        }
        let file = "\(loco.id)-\(Int(Date().timeIntervalSince1970)).jpg"
        do {
            try data.write(to: imageDirectory.appendingPathComponent(file), options: .atomic)
        } catch {
            return nil
        }
        imageCache[file] = img
        return file
    }
}
