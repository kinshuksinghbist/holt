import Foundation

public enum HoltCoreResources {
    public static let bundle: Bundle = {
        if let url = Bundle.main.url(forResource: "Holt_HoltCore", withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()
}
