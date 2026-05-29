import CoreLocation
import Foundation

struct GeneratedCourseRequest {
    var subject: String
    var subjectAreas: [String] = []
    var gradeLevel: String
    var placeName: String
    var centerLatitude: Double
    var centerLongitude: Double
    var minutes: Int
    var questionCount: Int
    var activationRadiusMeters: Double
}

enum AIQuizGenerationService {
    static func previewRows(for request: GeneratedCourseRequest) -> [CheckpointImportRow] {
        generateLocalDraft(for: request)
    }

    static func generateRows(for request: GeneratedCourseRequest) async throws -> [CheckpointImportRow] {
        if let endpoint = aiEndpointURL {
            return try await generateRowsWithBackend(request: request, endpoint: endpoint)
        }

        return generateLocalDraft(for: request)
    }

    private static var aiEndpointURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GPSQuizAIEndpointURL") as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return URL(string: value)
    }

    private static func generateRowsWithBackend(request: GeneratedCourseRequest, endpoint: URL) async throws -> [CheckpointImportRow] {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request.payload)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw GenerationError.backendUnavailable
        }

        let payload = try JSONDecoder().decode(GeneratedCoursePayload.self, from: data)
        return payload.rows
    }

    private static func generateLocalDraft(for request: GeneratedCourseRequest) -> [CheckpointImportRow] {
        let count = max(1, min(request.questionCount, 20))
        let routeRadius = routeRadiusMeters(forMinutes: request.minutes)
        let angles = stride(from: 0.0, to: 360.0, by: 360.0 / Double(count)).map { $0 }

        return angles.enumerated().map { index, angle in
            let coordinate = coordinate(
                fromLatitude: request.centerLatitude,
                longitude: request.centerLongitude,
                distanceMeters: routeRadius,
                bearingDegrees: angle
            )
            let subject = subjectName(for: request, index: index)
            let topic = topicName(for: subject, gradeLevel: request.gradeLevel, index: index)
            let correct = correctAnswer(for: subject, topic: topic)

            return CheckpointImportRow(
                name: "\(request.placeName) \(index + 1)",
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                radius: request.activationRadiusMeters,
                question: "\(request.gradeLevel): \(questionStem(for: subject, topic: topic))",
                options: answerOptions(correctAnswer: correct),
                correctAnswer: correct
            )
        }
    }

    private static func routeRadiusMeters(forMinutes minutes: Int) -> Double {
        let walkingMetersPerMinute = 70.0
        let loopDistance = Double(max(5, minutes)) * walkingMetersPerMinute
        return max(80, min(900, loopDistance / (2 * .pi)))
    }

    private static func coordinate(fromLatitude latitude: Double, longitude: Double, distanceMeters: Double, bearingDegrees: Double) -> CLLocationCoordinate2D {
        let earthRadius = 6_371_000.0
        let bearing = bearingDegrees * .pi / 180
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180
        let angularDistance = distanceMeters / earthRadius

        let lat2 = asin(sin(lat1) * cos(angularDistance) + cos(lat1) * sin(angularDistance) * cos(bearing))
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(lat2)
        )

        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    private static func subjectName(for request: GeneratedCourseRequest, index: Int) -> String {
        let areas = request.subjectAreas.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !areas.isEmpty else { return request.subject }
        return areas[index % areas.count]
    }

    private static func topicName(for subject: String, gradeLevel: String, index: Int) -> String {
        let normalized = subject.lowercased()
        let isUpperSecondary = gradeLevel.lowercased().contains("gymnasiet") || gradeLevel.lowercased().contains("komvux")
        let topics: [String]

        if normalized.contains("hist") {
            topics = isUpperSecondary
                ? ["historiebruk", "källkritik", "industrialism", "ideologier", "förändringsprocesser"]
                : ["källkritik", "industrialisering", "demokrati", "migration", "lokalhistoria"]
        } else if normalized.contains("samh") {
            topics = ["demokrati", "lagar", "ekonomi", "mänskliga rättigheter", "medier"]
        } else if normalized.contains("geo") {
            topics = ["kartor", "stadsplanering", "klimat", "resurser", "migration"]
        } else if normalized.contains("relig") {
            topics = ["etik", "ritualer", "livsfrågor", "religionsfrihet", "symboler"]
        } else if normalized.contains("fys") {
            topics = ["kraft", "energi", "ljud", "ljus", "rörelse"]
        } else if normalized.contains("kemi") {
            topics = ["ämnen", "reaktioner", "pH", "material", "kretslopp"]
        } else if normalized.contains("natur") || normalized.contains("biologi") {
            topics = isUpperSecondary
                ? ["hållbar utveckling", "genetik", "ekosystemtjänster", "energiflöden", "vetenskaplig metod"]
                : ["ekosystem", "energi", "hållbarhet", "artkunskap", "vatten"]
        } else if normalized.contains("mat") {
            topics = isUpperSecondary
                ? ["funktioner", "sannolikhet", "derivata", "modellering", "statistik"]
                : ["procent", "area", "skala", "statistik", "hastighet"]
        } else if normalized.contains("engelska") {
            topics = ["vocabulary", "argument", "source", "description", "comparison"]
        } else if normalized.contains("filosofi") || normalized.contains("psykologi") {
            topics = ["perspektiv", "begrepp", "analys", "etik", "exempel"]
        } else if normalized.contains("svenska") {
            topics = ["argument", "ordklass", "källor", "berättande", "retorik"]
        } else {
            topics = ["begrepp", "orsak", "samband", "exempel", "analys"]
        }

        return topics[index % topics.count]
    }

    private static func questionStem(for subject: String, topic: String) -> String {
        "Vilket alternativ passar bäst med \(topic) i \(subject)?"
    }

    private static func correctAnswer(for subject: String, topic: String) -> String {
        "\(topic.capitalized) hör ihop med \(subject)"
    }

    private static func answerOptions(correctAnswer: String) -> [String] {
        [
            correctAnswer,
            "Det handlar främst om slump",
            "Det saknar koppling till platsen"
        ]
    }
}

private struct GeneratedCoursePayload: Decodable {
    let questions: [GeneratedQuestion]

    var rows: [CheckpointImportRow] {
        questions.map {
            CheckpointImportRow(
                name: $0.name,
                latitude: $0.latitude,
                longitude: $0.longitude,
                radius: $0.activationRadiusMeters,
                question: $0.question,
                options: $0.options,
                correctAnswer: $0.correctAnswer
            )
        }
    }
}

private struct GeneratedQuestion: Decodable {
    let name: String
    let latitude: Double
    let longitude: Double
    let activationRadiusMeters: Double
    let question: String
    let options: [String]
    let correctAnswer: String
}

private extension GeneratedCourseRequest {
    var payload: [String: EncodableValue] {
        [
            "subject": .string(subject),
            "subjectAreas": .strings(subjectAreas),
            "gradeLevel": .string(gradeLevel),
            "placeName": .string(placeName),
            "centerLatitude": .double(centerLatitude),
            "centerLongitude": .double(centerLongitude),
            "minutes": .int(minutes),
            "questionCount": .int(questionCount),
            "activationRadiusMeters": .double(activationRadiusMeters)
        ]
    }
}

private enum EncodableValue: Encodable {
    case string(String)
    case strings([String])
    case int(Int)
    case double(Double)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .strings(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        }
    }
}

enum GenerationError: LocalizedError {
    case backendUnavailable

    var errorDescription: String? {
        "AI-tjänsten kunde inte nås. Försök igen eller använd lokalt utkast."
    }
}
