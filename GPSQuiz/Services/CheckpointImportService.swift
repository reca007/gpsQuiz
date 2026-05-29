import Foundation

enum CheckpointImportService {
    static let template = """
    Namn;Latitud;Longitud;Radie meter;Fråga;Alternativ med |;Rätt svar
    Stadshuset;59.3275;18.0547;50;Vilken färg har byggnaden?;Röd|Blå|Grön;Röd
    """

    static func parse(_ text: String) throws -> [CheckpointImportRow] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var rows: [CheckpointImportRow] = []

        for (index, line) in lines.enumerated() {
            if index == 0, line.localizedCaseInsensitiveContains("latitud") {
                continue
            }

            let separator: Character = line.contains(";") ? ";" : "\t"
            let columns = line.split(separator: separator, omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

            guard columns.count >= 7 else {
                throw ImportError.invalidColumnCount(line: index + 1)
            }

            guard let latitude = Double(columns[1].replacingOccurrences(of: ",", with: ".")),
                  let longitude = Double(columns[2].replacingOccurrences(of: ",", with: ".")),
                  let radius = Double(columns[3].replacingOccurrences(of: ",", with: ".")) else {
                throw ImportError.invalidNumber(line: index + 1)
            }

            let options = columns[5]
                .split(separator: "|")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard options.count >= 2 else {
                throw ImportError.tooFewOptions(line: index + 1)
            }

            guard options.contains(columns[6]) else {
                throw ImportError.correctAnswerMissing(line: index + 1)
            }

            rows.append(
                CheckpointImportRow(
                    name: columns[0],
                    latitude: latitude,
                    longitude: longitude,
                    radius: max(5, radius),
                    question: columns[4],
                    options: options,
                    correctAnswer: columns[6]
                )
            )
        }

        return rows
    }

    enum ImportError: LocalizedError {
        case invalidColumnCount(line: Int)
        case invalidNumber(line: Int)
        case tooFewOptions(line: Int)
        case correctAnswerMissing(line: Int)

        var errorDescription: String? {
            switch self {
            case .invalidColumnCount(let line):
                return "Rad \(line) behöver sju kolumner."
            case .invalidNumber(let line):
                return "Rad \(line) har ogiltig latitud, longitud eller radie."
            case .tooFewOptions(let line):
                return "Rad \(line) behöver minst två svarsalternativ."
            case .correctAnswerMissing(let line):
                return "Rad \(line) har ett rätt svar som inte finns bland alternativen."
            }
        }
    }
}
