import SwiftData
import SwiftUI

struct QuizEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title = ""
    @State private var summary = ""
    @State private var importText = CheckpointImportService.template
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Quiz") {
                TextField("Namn", text: $title)
                TextField("Beskrivning", text: $summary, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section {
                TextEditor(text: $importText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 220)
            } header: {
                Text("Importera flera frågor")
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
        .navigationTitle("Nytt quiz")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Spara") {
                    save()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        do {
            let rows = try CheckpointImportService.parse(importText)
            let quiz = Quiz(title: title.trimmingCharacters(in: .whitespacesAndNewlines), summary: summary)

            for (index, row) in rows.enumerated() {
                let checkpoint = Checkpoint(
                    name: row.name,
                    latitude: row.latitude,
                    longitude: row.longitude,
                    activationRadiusMeters: row.radius,
                    question: row.question,
                    sortIndex: index
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

            modelContext.insert(quiz)
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
