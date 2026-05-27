import Foundation

/// Pure, stateless, thread-safe color identification service.
/// Loads ColorNames.json once at init and keeps LAB values pre-computed in memory.
final class ColorEngine: Sendable {

    // MARK: - Internal DB entry

    private struct ColorEntry: Sendable {
        let name: String
        let r: Int
        let g: Int
        let b: Int
        let lab: LAB          // pre-computed for nearest-neighbor search
    }

    private struct LAB: Sendable {
        let l: Double
        let a: Double
        let b: Double
    }

    // MARK: - State

    private let database: [ColorEntry]

    // MARK: - Init

    init() {
        database = Self.loadDatabase()
    }

    // MARK: - Simple color database (plain-English names for primary display)
    //
    // ~75 entries covering the full color space with names anyone would recognise.
    // A second LAB nearest-neighbor search against this DB produces `simpleName`.

    private static let simpleDB: [(name: String, lab: LAB)] = {
        let entries: [(String, Int, Int, Int)] = [
            // Achromatic
            ("Black",            0,   0,   0),
            ("Very Dark Gray",   30,  30,  30),
            ("Dark Gray",        64,  64,  64),
            ("Charcoal",         54,  69,  79),
            ("Gray",             128, 128, 128),
            ("Light Gray",       192, 192, 192),
            ("Silver",           211, 211, 211),
            ("Off-White",        240, 240, 235),
            ("White",            255, 255, 255),
            // Reds
            ("Very Dark Red",    80,  0,   0),
            ("Maroon",           128, 0,   0),
            ("Burgundy",         128, 0,   32),
            ("Dark Red",         170, 0,   0),
            ("Red",              220, 30,  30),
            ("Coral Red",        240, 90,  80),
            ("Salmon",           250, 128, 114),
            // Orange-reds
            ("Rust",             183, 65,  14),
            ("Orange-Red",       255, 69,  0),
            // Oranges
            ("Dark Orange",      200, 90,  0),
            ("Orange",           255, 140, 0),
            ("Light Orange",     255, 185, 80),
            ("Peach",            255, 200, 160),
            // Yellows
            ("Olive",            128, 128, 0),
            ("Dark Yellow",      180, 160, 0),
            ("Golden Yellow",    218, 165, 32),
            ("Yellow",           255, 215, 0),
            ("Light Yellow",     255, 245, 140),
            ("Cream",            255, 253, 208),
            // Yellow-greens
            ("Dark Olive Green", 85,  107, 47),
            ("Olive Green",      107, 142, 35),
            ("Yellow-Green",     154, 205, 50),
            // Greens
            ("Very Dark Green",  0,   60,  0),
            ("Dark Green",       0,   100, 0),
            ("Forest Green",     34,  139, 34),
            ("Green",            0,   160, 0),
            ("Sage Green",       140, 170, 130),
            ("Mint Green",       152, 255, 152),
            ("Light Green",      144, 238, 144),
            ("Pale Green",       200, 240, 200),
            // Teals
            ("Dark Teal",        0,   80,  80),
            ("Teal",             0,   128, 128),
            ("Teal-Green",       32,  178, 170),
            ("Light Teal",       150, 220, 220),
            // Blues
            ("Dark Navy",        0,   0,   80),
            ("Navy Blue",        0,   0,   128),
            ("Dark Blue",        0,   0,   180),
            ("Cobalt Blue",      0,   71,  171),
            ("Blue",             0,   90,  220),
            ("Royal Blue",       65,  105, 225),
            ("Steel Blue",       70,  130, 180),
            ("Cornflower Blue",  100, 149, 237),
            ("Sky Blue",         135, 206, 235),
            ("Light Blue",       173, 216, 230),
            ("Baby Blue",        137, 207, 240),
            ("Pale Blue",        210, 235, 255),
            // Blue-purples / indigo
            ("Indigo",           75,  0,   130),
            ("Blue-Purple",      100, 50,  200),
            // Purples
            ("Dark Purple",      50,  0,   80),
            ("Purple",           128, 0,   128),
            ("Medium Purple",    147, 112, 219),
            ("Lavender",         200, 180, 240),
            ("Light Purple",     210, 190, 220),
            // Pinks / magentas
            ("Dark Magenta",     139, 0,   139),
            ("Magenta",          255, 0,   255),
            ("Hot Pink",         255, 105, 180),
            ("Deep Pink",        255, 20,  147),
            ("Dark Rose",        200, 50,  100),
            ("Rose",             255, 100, 130),
            ("Dusty Rose",       200, 140, 155),
            ("Pink",             255, 182, 193),
            ("Light Pink",       255, 218, 225),
            ("Blush",            255, 200, 210),
            ("Mauve",            210, 150, 180),
            // Browns
            ("Dark Brown",       100, 50,  10),
            ("Chocolate",        123, 63,  0),
            ("Brown",            139, 69,  19),
            ("Caramel",          200, 120, 50),
            ("Medium Brown",     165, 100, 50),
            ("Light Brown",      190, 145, 90),
            ("Tan",              210, 180, 140),
            ("Sandy",            230, 210, 175),
            ("Beige",            245, 235, 220),
            ("Khaki",            195, 180, 130),
        ]
        return entries.map { name, r, g, b in
            (name: name, lab: rgbToLAB(r: r, g: g, b: b))
        }
    }()

    // MARK: - Public API

    /// Identifies the closest named color for the given 8-bit RGB values.
    /// Safe to call from any thread.
    func identify(r: UInt8, g: UInt8, b: UInt8, profile: CVDProfile = .load()) -> IdentifiedColor {
        let queryLAB   = Self.rgbToLAB(r: Int(r), g: Int(g), b: Int(b))
        let nearest    = nearestEntry(to: queryLAB)
        let simpleName = Self.nearestSimpleName(to: queryLAB)

        let hsl = Self.rgbToHSL(r: Int(r), g: Int(g), b: Int(b))
        let hex = String(format: "#%02X%02X%02X", r, g, b)
        let name = nearest?.name ?? simpleName   // fallback if DB somehow empty
        let cvdDesc = generateCVDDescription(name: name, simpleName: simpleName, hsl: hsl, profile: profile)

        return IdentifiedColor(
            simpleName: simpleName,
            name: name,
            hex: hex,
            rgb: .init(r: Int(r), g: Int(g), b: Int(b)),
            hsl: hsl,
            cvdDescription: cvdDesc
        )
    }

    // MARK: - Simple name lookup

    private static func nearestSimpleName(to query: LAB) -> String {
        var bestName = simpleDB[0].name
        var bestDist = squaredDeltaE(query, simpleDB[0].lab)
        for entry in simpleDB.dropFirst() {
            let d = squaredDeltaE(query, entry.lab)
            if d < bestDist { bestDist = d; bestName = entry.name }
        }
        return bestName
    }

    private static func squaredDeltaE(_ a: LAB, _ b: LAB) -> Double {
        let dl = a.l - b.l; let da = a.a - b.a; let db = a.b - b.b
        return dl*dl + da*da + db*db
    }

    // MARK: - Nearest-neighbor search

    private func nearestEntry(to query: LAB) -> ColorEntry? {
        // Linear scan — ~200 entries takes < 0.05ms. No spatial index needed for v1.
        guard let first = database.first else { return nil }
        var bestEntry = first
        var bestDist  = deltaE(query, first.lab)

        for entry in database.dropFirst() {
            let d = deltaE(query, entry.lab)
            if d < bestDist {
                bestDist  = d
                bestEntry = entry
            }
        }
        return bestEntry
    }

    /// Euclidean distance in LAB (a simplified ΔE).
    /// Good enough for nearest-neighbor; full CIE2000 isn't needed here.
    private func deltaE(_ a: LAB, _ b: LAB) -> Double {
        let dl = a.l - b.l
        let da = a.a - b.a
        let db = a.b - b.b
        return dl*dl + da*da + db*db   // skip sqrt — we only compare, never display the value
    }

    // MARK: - RGB → LAB

    private static func rgbToLAB(r: Int, g: Int, b: Int) -> LAB {
        // Step 1: normalize to 0–1
        var rr = Double(r) / 255.0
        var gg = Double(g) / 255.0
        var bb = Double(b) / 255.0

        // Step 2: sRGB gamma → linear
        rr = rr > 0.04045 ? pow((rr + 0.055) / 1.055, 2.4) : rr / 12.92
        gg = gg > 0.04045 ? pow((gg + 0.055) / 1.055, 2.4) : gg / 12.92
        bb = bb > 0.04045 ? pow((bb + 0.055) / 1.055, 2.4) : bb / 12.92

        // Step 3: linear RGB → XYZ (sRGB / D65)
        let x = (rr * 0.4124564 + gg * 0.3575761 + bb * 0.1804375) / 0.95047
        let y = (rr * 0.2126729 + gg * 0.7151522 + bb * 0.0721750) / 1.00000
        let z = (rr * 0.0193339 + gg * 0.1191920 + bb * 0.9503041) / 1.08883

        // Step 4: XYZ → LAB
        func f(_ t: Double) -> Double {
            t > 0.008856 ? pow(t, 1.0/3.0) : (7.787 * t + 16.0/116.0)
        }

        let fx = f(x)
        let fy = f(y)
        let fz = f(z)

        return LAB(
            l: max(0, 116.0 * fy - 16.0),
            a: 500.0 * (fx - fy),
            b: 200.0 * (fy - fz)
        )
    }

    // MARK: - RGB → HSL

    static func rgbToHSL(r: Int, g: Int, b: Int) -> IdentifiedColor.HSLComponents {
        let rr = Double(r) / 255.0
        let gg = Double(g) / 255.0
        let bb = Double(b) / 255.0

        let maxC = max(rr, gg, bb)
        let minC = min(rr, gg, bb)
        let delta = maxC - minC

        let l = (maxC + minC) / 2.0

        let s: Double
        if delta == 0 {
            s = 0
        } else {
            s = delta / (1.0 - abs(2.0 * l - 1.0))
        }

        let h: Double
        if delta == 0 {
            h = 0
        } else if maxC == rr {
            h = 60.0 * (((gg - bb) / delta).truncatingRemainder(dividingBy: 6))
        } else if maxC == gg {
            h = 60.0 * (((bb - rr) / delta) + 2)
        } else {
            h = 60.0 * (((rr - gg) / delta) + 4)
        }

        return .init(h: h < 0 ? h + 360 : h, s: s, l: l)
    }

    // MARK: - CVD description (v2: plain-language, per-profile)
    //
    // One or two short sentences that:
    //   • Lead with what the color IS — name first, then context.
    //   • Use real-world reference points for easy cross-checking.
    //   • Honestly acknowledge what may look different for that CVD type.
    //   • Stay concise so VoiceOver reads them in ≤ 3 seconds.

    private func generateCVDDescription(
        name: String,
        simpleName: String,
        hsl: IdentifiedColor.HSLComponents,
        profile: CVDProfile
    ) -> String {
        let h = hsl.h
        let s = hsl.s
        let l = hsl.l

        // Near-neutral colours: hue barely matters for any profile.
        if s < 0.12 {
            if l > 0.92 { return "White or near-white — no significant colour." }
            if l < 0.10 { return "Black or near-black — no significant colour." }
            return "\(lightnessLabel(l: l)) gray — unsaturated, no strong hue."
        }

        switch profile {

        // ── Normal vision ─────────────────────────────────────────────────────
        case .normal:
            let sat = s < 0.20 ? "muted " : s > 0.70 ? "vivid " : ""
            return "\(lightnessLabel(l: l).capitalized), \(sat)\(plainHue(h))."

        // ── Red-green (deuteranopia / protanopia) ─────────────────────────────
        // Blues (185–265°) and yellows (42–72°) are anchor colours — seen clearly.
        // Reds, greens, oranges, and browns are the confusion zone.
        case .deuteranopia, .protanopia:
            if s < 0.20 {
                return "\(name). Near-neutral — mostly \(lightnessLabel(l: l)) with very little colour."
            }
            if h > 185 && h < 265 {
                return "\(name). Blue — you see blues clearly. \(lightnessLabel(l: l).capitalized), similar to \(blueAnchor(h, l))."
            }
            if h > 42 && h < 72 {
                return "\(name). Yellow — you distinguish yellows well. \(lightnessLabel(l: l).capitalized), like \(yellowAnchor(l))."
            }
            if h > 265 && h < 310 {
                return "\(name). Purple — may look more blue-ish to you, but this is purple, not blue."
            }
            if (h > 310 || h < 12) && l > 0.68 {
                return "\(name). Light pink — may appear pale or grey-ish to you, but this is pink."
            }
            // Confusion zone: reds, greens, oranges, browns.
            return "\(name). \(redGreenZone(h: h, l: l))"

        // ── Blue-yellow (tritanopia) ───────────────────────────────────────────
        // Blues look greenish; yellows look pinkish or reddish.
        // Reds and greens are anchor colours.
        case .tritanopia:
            if s < 0.20 {
                return "\(name). Near-neutral — mostly \(lightnessLabel(l: l)) with very little colour."
            }
            if h > 180 && h < 260 {
                return "\(name). Blue — may appear greenish to you. This IS blue, not green. Similar to \(blueAnchor(h, l))."
            }
            if h > 155 && h <= 180 {
                return "\(name). Teal — sits on the blue-green boundary you find tricky. It leans blue."
            }
            if h > 42 && h < 72 {
                return "\(name). Yellow — may appear pinkish or reddish to you. This IS yellow, like a lemon or sunflower."
            }
            if h > 72 && h < 155 {
                return "\(name). Green — you see greens clearly. \(lightnessLabel(l: l).capitalized) green."
            }
            if h < 42 || h > 330 {
                return "\(name). \(h > 310 ? "Pink" : "Red") — you see reds and pinks clearly."
            }
            return "\(name). \(lightnessLabel(l: l).capitalized) \(plainHue(h))."

        // ── Full colour blindness (achromatopsia) ─────────────────────────────
        // No functional hue — only brightness is reliable.
        case .achromatopsia:
            let pct = Int(round(l * 100))
            return "\(name). Appears as \(lightnessLabel(l: l)) grey to you — about \(pct)% brightness on a greyscale."
        }
    }

    // MARK: - Description helpers

    private func lightnessLabel(l: Double) -> String {
        switch l {
        case ..<0.12: return "very dark"
        case ..<0.28: return "dark"
        case ..<0.45: return "medium-dark"
        case ..<0.58: return "medium"
        case ..<0.75: return "light"
        case ..<0.90: return "very light"
        default:      return "near-white"
        }
    }

    private func plainHue(_ h: Double) -> String {
        switch h {
        case 0..<15:    return "red"
        case 15..<38:   return "red-orange"
        case 38..<55:   return "orange"
        case 55..<75:   return "yellow"
        case 75..<105:  return "yellow-green"
        case 105..<150: return "green"
        case 150..<185: return "teal"
        case 185..<255: return "blue"
        case 255..<285: return "indigo"
        case 285..<320: return "purple"
        case 320..<345: return "pink"
        default:        return "red"
        }
    }

    private func blueAnchor(_ h: Double, _ l: Double) -> String {
        if l < 0.25 { return "deep ocean water or navy denim" }
        if l > 0.78 { return "a pale sky or light ice" }
        if h > 225  { return "a clear midday sky" }
        return "the sky or clean water"
    }

    private func yellowAnchor(_ l: Double) -> String {
        if l < 0.40 { return "dark mustard or old gold" }
        if l > 0.88 { return "cream or pale straw" }
        return "a lemon or sunflower"
    }

    /// Description for colours in the red-green confusion zone.
    private func redGreenZone(h: Double, l: Double) -> String {
        switch h {
        case 0..<20:
            let anchor = l < 0.38 ? "dark brick or dried blood" : "a stop sign or ripe tomato"
            return "Red — may look brownish or very dark to you. Real-world match: \(anchor)."
        case 20..<45:
            return "Orange-red — similar to rust or autumn leaves. May blend with browns for you."
        case 45..<75:
            return "Orange — like a pumpkin or carrot. May look tan or dull brown to you."
        case 75..<115:
            return "Yellow-green — may look similar to yellow or khaki. Think fresh lime or spring grass."
        case 115..<155:
            let anchor = l < 0.38 ? "dark forest or pine needles" : "cut grass or fresh leaves"
            return "Green — may look similar to reds or browns to you. Real-world match: \(anchor)."
        case 155..<185:
            return "Teal — leans blue-green. Slightly easier to distinguish than pure green or red."
        default:
            return "\(lightnessLabel(l: l).capitalized) warm tone — in the red-green range that can be difficult to distinguish."
        }
    }

    // MARK: - Database loading

    private static func loadDatabase() -> [ColorEntry] {
        guard let url = Bundle.main.url(forResource: "ColorNames", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("ColorNames.json not found in bundle")
            return []
        }

        struct RawEntry: Decodable {
            let name: String
            let r: Int
            let g: Int
            let b: Int
        }

        guard let raw = try? JSONDecoder().decode([RawEntry].self, from: data) else {
            assertionFailure("ColorNames.json failed to decode")
            return []
        }

        return raw.map { entry in
            ColorEntry(
                name: entry.name,
                r: entry.r,
                g: entry.g,
                b: entry.b,
                lab: rgbToLAB(r: entry.r, g: entry.g, b: entry.b)
            )
        }
    }
}
