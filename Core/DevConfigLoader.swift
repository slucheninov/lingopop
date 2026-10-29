import Foundation

enum DevConfigLoader {

    static let path = ("~/.lingopop-dev.json" as NSString).expandingTildeInPath

    static func load() -> ProviderConfig? {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ProviderConfig.self, from: data)
    }
}
