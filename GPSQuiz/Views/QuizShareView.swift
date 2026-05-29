import SwiftUI

struct QuizShareView: View {
    @Environment(\.dismiss) private var dismiss
    let quiz: Quiz

    private var shareURL: URL {
        SharedQuizPayload.importURL(for: quiz) ?? URL(string: "gpsquiz://quiz/\(quiz.id.uuidString)")!
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let qrSize = min(max(proxy.size.width - 48, 280), 420)

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 8) {
                            Text(quiz.title)
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)
                            Text("\(quiz.checkpoints.count) checkpoints")
                                .foregroundStyle(.secondary)
                        }

                        QRCodeService.image(from: shareURL.absoluteString)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: qrSize, height: qrSize)
                            .padding(18)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)

                        Text("Spelare skannar QR-koden eller öppnar länken för att importera quizet i GPSQuiz och testa banan på sin enhet.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        ShareLink(item: shareURL) {
                            Label("Dela länk", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)

                        Spacer(minLength: 18)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Dela quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klar") {
                        dismiss()
                    }
                }
            }
        }
    }
}
