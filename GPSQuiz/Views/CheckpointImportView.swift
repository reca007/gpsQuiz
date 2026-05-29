import SwiftData
import SwiftUI

struct CheckpointImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let quiz: Quiz

    @State private var importText = CheckpointImportService.template
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextEditor(text: $importText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 260)
            } header: {
                Text("Lägg till flera frågor")
            } footer: {
                Text("Format: Namn;Latitud;Longitud;Radie meter;Fråga;Alternativ med |;Rätt svar")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Importera")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Lägg till") {
                    appendRows()
                }
            }
        }
    }

    private func appendRows() {
        do {
            let rows = try CheckpointImportService.parse(importText)
            let startIndex = quiz.checkpoints.count

            for (offset, row) in rows.enumerated() {
                let checkpoint = Checkpoint(
                    name: row.name,
                    latitude: row.latitude,
                    longitude: row.longitude,
                    activationRadiusMeters: row.radius,
                    question: row.question,
                    sortIndex: startIndex + offset
                )
                checkpoint.quiz = quiz

                for (optionIndex, optionText) in row.options.enumerated() {
                    let option = AnswerOption(
                        text: optionText,
                        sortIndex: optionIndex,
                        isCorrect: optionText == row.correctAnswer
                    )
                    option.checkpoint = checkpoint
                    checkpoint.options.append(option)
                }

                quiz.checkpoints.append(checkpoint)
            }

            quiz.updatedAt = .now
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
