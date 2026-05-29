# GPSQuiz

GPSQuiz ar en SwiftUI-app dar larare kan skapa GPS-baserade quizbanor for skola och demo.

## Demo

1. Oppna `GPSQuiz.xcodeproj` i Xcode.
2. Valj target `GPSQuiz` och en iPhone-simulator.
3. Tryck Run.
4. Startsidan ska visa en roterande hero-bild med city, skog och natur.
5. Las upp lararlaget med koden `2468`.
6. Skapa eller generera ett quiz.
7. Valj `Publicera quiz till Render`.
8. Valj `Visa QR-kod` for att dela quizet med spelare via QR-kod eller lank.
9. Valj `Testa banan direkt` om du vill demo-kora utan att ga till GPS-punkterna.

## Funktioner

- SwiftUI-granssnitt for quiz, karta, spelrunda, fragor, resultat och topplista.
- SwiftData for lokal lagring.
- CoreLocation och MapKit for GPS-banor.
- AI-stod for att skapa skolfragor efter amne, arskurs och tid.
- Stod for kombinerade amnen: matematik, historia, sprak, natur och anpassade teman.
- Lag med tva spelare.
- QR-kod och Render-lank for att dela quiz med spelare.
- App Intents for genvagar som att starta quiz och visa topplista.

## Render-backend for elever

Projektet innehaller en Render-redo backend i `backend/` och en Blueprint-fil i `render.yaml`.

1. Pusha projektet till GitHub.
2. Logga in pa Render.
3. Valj `New` -> `Blueprint`.
4. Koppla GitHub-repot `reca007/gpsQuiz`.
5. Render hittar `render.yaml` och skapar webbtjansten `gpsquiz-api`.
6. Kopiera Render-URL:en, till exempel `https://gpsquiz-api.onrender.com`.
7. I Xcode: oppna `GPSQuiz/Resources/Info.plist` och satt `GPSQuizBackendBaseURL` till Render-URL:en.
8. Kor appen igen.

Nar `GPSQuizBackendBaseURL` ar ifylld anvander appen Render for:

- publicerade quiz
- gemensam topplista
- AI-genererade quizfragor

Efter att lararen har publicerat ett quiz skapar appen elevlankar som:

`https://gpsquiz-api.onrender.com/q/<quiz-id>`

Spelaren oppnar lanken, trycker `Oppna i GPSQuiz` och ansluter som lag.

## GitHub-test

Repo:t har en GitHub Actions-check som bygger appen vid varje push till `main`. Den syns under fliken `Actions` pa GitHub.
