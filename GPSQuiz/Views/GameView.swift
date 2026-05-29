import MapKit
import SwiftData
import SwiftUI

struct GameView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var locationService: LocationService

    let quiz: Quiz
    let round: GameRound

    @State private var unlockedCheckpoint: Checkpoint?
    @State private var unlockedAt = Date()
    @State private var unlockDistance: Double = 0
    @State private var showingResult = false
    @State private var camera: MapCameraPosition = .automatic

    private var checkpoints: [Checkpoint] {
        quiz.checkpoints.sorted { $0.sortIndex < $1.sortIndex }
    }

    private var answeredIDs: Set<UUID> {
        Set(round.responses.map(\.checkpointID))
    }

    private var nextCheckpoint: Checkpoint? {
        checkpoints.first { !answeredIDs.contains($0.id) }
    }

    private var isQuickTestRound: Bool {
        round.playerName.hasPrefix("Test: ")
    }

    var body: some View {
        VStack(spacing: 0) {
            permissionBanner

            Map(position: $camera) {
                UserAnnotation()
                ForEach(checkpoints) { checkpoint in
                    Marker(checkpoint.name, coordinate: CLLocationCoordinate2D(latitude: checkpoint.latitude, longitude: checkpoint.longitude))
                        .tint(answeredIDs.contains(checkpoint.id) ? .green : .orange)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .frame(minHeight: 280)

            List {
                Section("GPS-status") {
                    if isQuickTestRound {
                        Label("Testläge aktivt", systemImage: "play.circle.fill")
                        Text("Frågorna öppnas i ordning så att du kan granska banan utan GPS.")
                            .foregroundStyle(.secondary)
                    } else {
                        Label(locationService.gpsQuality.rawValue, systemImage: gpsSymbol)
                        if let accuracy = locationService.currentLocation?.horizontalAccuracy, accuracy >= 0 {
                            LabeledContent("Noggrannhet", value: "\(Int(accuracy)) m")
                        }
                        if let message = locationService.lastErrorMessage {
                            Text(message)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Nästa checkpoint") {
                    if let nextCheckpoint {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(nextCheckpoint.name)
                                .font(.headline)
                            if isQuickTestRound {
                                Text("Öppnas automatiskt i testläge.")
                                    .foregroundStyle(.secondary)
                            } else if let distance = locationService.distance(from: nextCheckpoint) {
                                ProgressView(
                                    value: min(1, nextCheckpoint.activationRadiusMeters / max(distance, 1))
                                )
                                Text("\(Int(distance)) m bort, låses upp vid \(Int(nextCheckpoint.activationRadiusMeters)) m")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Väntar på GPS-position.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Label("Alla frågor är besvarade", systemImage: "checkmark.seal")
                    }
                }

                Section("Besvarade frågor") {
                    ForEach(round.responses.sorted { $0.answeredAt < $1.answeredAt }) { response in
                        HStack {
                            Image(systemName: response.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(response.isCorrect ? .green : .red)
                            VStack(alignment: .leading) {
                                Text(response.checkpointNameSnapshot)
                                Text(response.selectedOptionTextSnapshot)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Spel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(round.correctCount)/\(checkpoints.count)")
                    .font(.headline.monospacedDigit())
            }
        }
        .onAppear {
            if !isQuickTestRound {
                locationService.requestPermission()
                locationService.startTracking()
            }
            updateCamera()
            evaluateUnlock()
        }
        .onReceive(locationService.$currentLocation) { _ in
            evaluateUnlock()
        }
        .sheet(item: $unlockedCheckpoint) { checkpoint in
            QuestionView(
                checkpoint: checkpoint,
                unlockedAt: unlockedAt,
                distanceAtUnlockMeters: unlockDistance
            ) { selectedOption in
                answer(checkpoint: checkpoint, selectedOption: selectedOption)
            }
            .interactiveDismissDisabled()
        }
        .navigationDestination(isPresented: $showingResult) {
            ResultView(round: round, questionCount: checkpoints.count)
        }
    }

    private var permissionBanner: some View {
        Group {
            if isQuickTestRound {
                Label("Testläge: nästa fråga öppnas automatiskt utan GPS.", systemImage: "play.circle.fill")
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.blue)
                    .padding()
                    .background(Color.blue.opacity(0.12))
            } else {
                switch locationService.permissionState {
                case .authorized:
                    EmptyView()
                case .notDetermined:
                    Button {
                        locationService.requestPermission()
                    } label: {
                        Label("Ge platsbehörighet för att låsa upp frågor", systemImage: "location")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                case .denied, .restricted:
                    Label("Platsbehörighet saknas. Öppna Inställningar för att tillåta GPSQuiz.", systemImage: "location.slash")
                        .foregroundStyle(.red)
                        .padding()
                }
            }
        }
    }

    private var gpsSymbol: String {
        switch locationService.gpsQuality {
        case .good: "location.fill"
        case .fair: "location"
        case .poor: "exclamationmark.triangle"
        case .unavailable: "location.slash"
        }
    }

    private func evaluateUnlock() {
        guard round.completedAt == nil, unlockedCheckpoint == nil, let checkpoint = nextCheckpoint else { return }
        guard !answeredIDs.contains(checkpoint.id) else { return }
        if isQuickTestRound {
            unlockedAt = .now
            unlockDistance = 0
            unlockedCheckpoint = checkpoint
            return
        }

        guard let distance = locationService.distance(from: checkpoint) else { return }
        guard distance <= checkpoint.activationRadiusMeters else { return }
        guard locationService.currentLocation?.horizontalAccuracy ?? .greatestFiniteMagnitude <= max(100, checkpoint.activationRadiusMeters * 2) else { return }

        unlockedAt = .now
        unlockDistance = distance
        unlockedCheckpoint = checkpoint
    }

    private func answer(checkpoint: Checkpoint, selectedOption: AnswerOption) {
        guard !answeredIDs.contains(checkpoint.id),
              let correctOption = checkpoint.options.first(where: \.isCorrect) else {
            unlockedCheckpoint = nil
            return
        }

        let response = QuestionResponse(
            checkpoint: checkpoint,
            selectedOption: selectedOption,
            correctOption: correctOption,
            unlockedAt: unlockedAt,
            distanceAtUnlockMeters: unlockDistance
        )
        response.round = round
        round.responses.append(response)

        if round.responses.count == checkpoints.count {
            round.completedAt = .now
            showingResult = true
            locationService.stopTracking()
        }

        try? modelContext.save()
        unlockedCheckpoint = nil
        evaluateUnlock()
    }

    private func updateCamera() {
        if let nextCheckpoint {
            camera = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: nextCheckpoint.latitude, longitude: nextCheckpoint.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            )
        }
    }
}
