import Foundation

enum BackendConfig {
    static var baseURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GPSQuizBackendBaseURL") as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    static func url(_ path: String) -> URL? {
        guard let baseURL else { return nil }
        return baseURL.appending(path: path)
    }
}
