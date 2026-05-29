# GPSQuiz

GPSQuiz ar en SwiftUI-app dar larare kan skapa GPS-baserade quizbanor for skola och demo.

## Demo

1. Oppna `GPSQuiz.xcodeproj` i Xcode.
2. Valj target `GPSQuiz` och en iPhone-simulator.
3. Tryck Run.
4. Startsidan ska visa en roterande hero-bild med city, skog och natur.
5. Oppna ett quiz och valj `Testa banan direkt` for demo utan att ga till GPS-punkterna.
6. Valj `Visa QR-kod` for att dela quizet med spelare via QR-kod eller lank.

## Funktioner

- SwiftUI-granssnitt for quiz, karta, spelrunda, fragor, resultat och topplista.
- SwiftData for lokal lagring.
- CoreLocation och MapKit for GPS-banor.
- AI-stod for att skapa skolfragor efter amne, arskurs och tid.
- Stod for kombinerade amnen: matematik, historia, sprak, natur och anpassade teman.
- Lag med tva spelare.
- QR-kod och `gpsquiz://import`-lank for att dela quiz.
- App Intents for genvagar som att starta quiz och visa topplista.

## CloudKit

CloudKit- och iCloud-delning kraver ett betalt Apple Developer-konto for riktig testning pa flera anvandare. Med Personal Team kor appen lokalt i debuglage, sa demo fungerar utan CloudKit.

## GitHub-test

Repo:t har en GitHub Actions-check som bygger appen vid varje push till `main`. Den syns under fliken `Actions` pa GitHub.
