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

## Render-backend for elever

Projektet innehaller en Render-redo backend i `backend/` och en Blueprint-fil i `render.yaml`.

1. Pusha projektet till GitHub.
2. Logga in pa Render.
3. Valj `New` -> `Blueprint`.
4. Koppla GitHub-repot `reca007/gpsQuiz`.
5. Render hittar `render.yaml` och skapar webbtjansten `gpsquiz-api`.
6. Kopiera Render-URL:en, till exempel `https://din-tjanst.onrender.com`.
7. I Xcode: oppna `GPSQuiz/Resources/Info.plist` och satt `GPSQuizBackendBaseURL` till Render-URL:en.
8. Kor appen igen.

Nar `GPSQuizBackendBaseURL` ar ifylld anvander appen Render for:

- publicerade quiz
- gemensam topplista
- AI-genererade quizfragor

Spelare ansluter fortfarande via QR-kod eller lank fran lararen.

## GitHub-test

Repo:t har en GitHub Actions-check som bygger appen vid varje push till `main`. Den syns under fliken `Actions` pa GitHub.
