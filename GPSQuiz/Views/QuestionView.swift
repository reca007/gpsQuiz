import SwiftUI

struct QuestionView: View {
    let checkpoint: Checkpoint
    let unlockedAt: Date
    let distanceAtUnlockMeters: Double
    let onAnswer: (AnswerOption) -> Void

    @State private var selectedOption: AnswerOption?

    private var options: [AnswerOption] {
        checkpoint.options.sorted { $0.sortIndex < $1.sortIndex }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(checkpoint.name)
                            .font(.headline)
                        Text(checkpoint.question)
                            .font(.title3.bold())
                        Text("Upplåst \(Int(distanceAtUnlockMeters)) m från platsen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Svar") {
                    ForEach(options) { option in
                        Button {
                            selectedOption = option
                        } label: {
                            HStack {
                                Text(option.text)
                                Spacer()
                                if selectedOption?.id == option.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section {
                    Text("När svaret skickas in låses det och kan inte ändras efteråt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Fråga")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Skicka") {
                        if let selectedOption {
                            onAnswer(selectedOption)
                        }
                    }
                    .disabled(selectedOption == nil)
                }
            }
        }
    }
}
