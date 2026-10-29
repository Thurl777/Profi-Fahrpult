import Foundation

/// Zuordnung von Loks, die an einem Handregler (z.B. Roco Multimaus) bedient werden, zu den Reglern der App.
///
/// Die Z21 meldet nur, welche Lok bedient wurde, nicht an welchem Handregler. Wechselt man an einer
/// Multimaus die Lok, wird die alte Lok dort nicht mehr bedient. Deshalb übernimmt der Regler die neue
/// Lok, der am längsten nicht mehr benutzt wurde.
public enum HandheldFollow {

    /// - Parameters:
    ///   - addresses: Lokadresse je Regler (`nil` = keine Lok)
    ///   - lastUse: letzte Benutzung je Regler (Lok gewählt, in der App oder von außen bedient)
    ///   - newAddress: Adresse der Lok, die von außen bedient wurde
    ///   - locked: Regler, die gerade nicht ersetzt werden dürfen (z.B. wird in der App bedient)
    /// - Returns: Index des Reglers, der die Lok übernehmen soll, oder `nil`, wenn nichts zu tun ist.
    public static func throttleToReplace(addresses: [UInt16?], lastUse: [Date], newAddress: UInt16,
                                         locked: Set<Int> = []) -> Int? {
        guard newAddress > 0, !addresses.contains(newAddress) else { return nil }
        let candidates = addresses.indices.filter { !locked.contains($0) }
        if let empty = candidates.first(where: { addresses[$0] == nil }) {
            return empty
        }
        return candidates.min { a, b in
            let ua = a < lastUse.count ? lastUse[a] : .distantPast
            let ub = b < lastUse.count ? lastUse[b] : .distantPast
            return ua < ub
        }
    }
}
