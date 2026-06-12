import { createServer } from "node:http";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import crypto from "node:crypto";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT || 3000);
const DATA_FILE = process.env.DATA_FILE || join(__dirname, "data", "store.json");
const APP_INSTALL_URL = process.env.APP_INSTALL_URL || process.env.TESTFLIGHT_URL || "";
const OPENAI_API_KEY = process.env.OPENAI_API_KEY || "";
const OPENAI_MODEL = process.env.OPENAI_MODEL || "gpt-5.4-mini";
const OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses";
const AI_RATE_LIMIT_WINDOW_MS = 15 * 60 * 1000;
const AI_RATE_LIMIT_REQUESTS = Math.max(1, Number(process.env.AI_RATE_LIMIT_REQUESTS || 12));
const aiRequestWindows = new Map();

const defaultStore = {
  quizzes: [],
  leaderboard: []
};

async function readStore() {
  try {
    const data = await readFile(DATA_FILE, "utf8");
    return { ...defaultStore, ...JSON.parse(data) };
  } catch {
    return { ...defaultStore };
  }
}

async function writeStore(store) {
  await mkdir(dirname(DATA_FILE), { recursive: true });
  await writeFile(DATA_FILE, JSON.stringify(store, null, 2));
}

function sendJSON(response, status, payload) {
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type"
  });
  response.end(JSON.stringify(payload));
}

function requestClientID(request) {
  const forwarded = String(request.headers["x-forwarded-for"] || "")
    .split(",")[0]
    .trim();
  return forwarded || request.socket.remoteAddress || "unknown";
}

function consumeAIRateLimit(clientID) {
  const now = Date.now();
  const existing = aiRequestWindows.get(clientID) || [];
  const active = existing.filter((timestamp) => now - timestamp < AI_RATE_LIMIT_WINDOW_MS);

  if (active.length >= AI_RATE_LIMIT_REQUESTS) {
    aiRequestWindows.set(clientID, active);
    return false;
  }

  active.push(now);
  aiRequestWindows.set(clientID, active);
  return true;
}

function sendHTML(response, status, html) {
  response.writeHead(status, {
    "Content-Type": "text/html; charset=utf-8",
    "Cache-Control": "no-store"
  });
  response.end(html);
}

function escapeHTML(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function base64URL(value) {
  return Buffer.from(JSON.stringify(value), "utf8")
    .toString("base64")
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function importURLForQuiz(quiz) {
  const payload = {
    quizID: quiz.quizID,
    title: quiz.title,
    summary: quiz.summary || "",
    checkpoints: quiz.checkpoints
  };
  return `gpsquiz://import?data=${base64URL(payload)}`;
}

function sharePage({ quiz, requestURL }) {
  const importURL = importURLForQuiz(quiz);
  const checkpointCount = Array.isArray(quiz.checkpoints) ? quiz.checkpoints.length : 0;
  const title = escapeHTML(quiz.title || "GPSQuiz");
  const summary = escapeHTML(quiz.summary || "Öppna quizet i GPSQuiz-appen.");
  const canonicalURL = escapeHTML(requestURL.href);
  const installURL = escapeHTML(APP_INSTALL_URL);
  const installButton = installURL
    ? `<a class="button secondary" href="${installURL}">Installera GPSQuiz</a>`
    : "";

  return `<!doctype html>
<html lang="sv">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${title} · GPSQuiz</title>
  <style>
    :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", sans-serif; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: linear-gradient(160deg, #eaf3ff, #f7f7fb 48%, #e7f8ef); color: #111827; }
    main { width: min(92vw, 520px); border-radius: 32px; padding: 28px; background: rgba(255,255,255,.82); box-shadow: 0 24px 70px rgba(15,23,42,.18); backdrop-filter: blur(18px); }
    .badge { display: inline-flex; gap: 8px; align-items: center; padding: 7px 11px; border-radius: 999px; background: #dbeafe; color: #1d4ed8; font-size: 13px; font-weight: 700; }
    h1 { margin: 22px 0 8px; font-size: clamp(32px, 8vw, 48px); line-height: .96; letter-spacing: 0; }
    p { color: #4b5563; font-size: 17px; line-height: 1.45; }
    .meta { display: flex; gap: 10px; flex-wrap: wrap; margin: 22px 0; }
    .pill { padding: 10px 12px; border-radius: 16px; background: #f3f4f6; color: #374151; font-weight: 700; }
    a.button { display: block; text-align: center; text-decoration: none; color: white; background: #2563eb; padding: 16px 18px; border-radius: 18px; font-size: 18px; font-weight: 800; }
    a.button.secondary { margin-top: 10px; color: #1f2937; background: #e5e7eb; }
    .small { font-size: 13px; color: #6b7280; margin-top: 16px; word-break: break-word; }
    @media (prefers-color-scheme: dark) {
      body { background: linear-gradient(160deg, #07111f, #111827 48%, #062116); color: #f9fafb; }
      main { background: rgba(17,24,39,.84); }
      p, .small { color: #cbd5e1; }
      .pill { background: rgba(255,255,255,.08); color: #e5e7eb; }
      .badge { background: rgba(59,130,246,.18); color: #93c5fd; }
      a.button.secondary { color: #f9fafb; background: rgba(255,255,255,.14); }
    }
  </style>
</head>
<body>
  <main>
    <div class="badge">GPSQuiz · Elevlänk</div>
    <h1>${title}</h1>
    <p>${summary}</p>
    <div class="meta">
      <div class="pill">${checkpointCount} checkpoints</div>
      <div class="pill">Lag om 2</div>
    </div>
    <a class="button" href="${escapeHTML(importURL)}">Öppna i GPSQuiz</a>
    ${installButton}
    <p class="small">Om inget händer behöver GPSQuiz vara installerad först. Läraren delar installationslänken via TestFlight. Quizlänk: ${canonicalURL}</p>
  </main>
</body>
</html>`;
}

function privacyPage() {
  return `<!doctype html>
<html lang="sv">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Integritetspolicy · GPSQuiz</title>
  <style>
    :root { color-scheme: dark; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif; }
    body { margin: 0; background: #070a0d; color: #f4f6f8; line-height: 1.6; }
    main { width: min(90vw, 720px); margin: 0 auto; padding: 48px 0 80px; }
    h1, h2 { line-height: 1.12; } h1 { font-size: 42px; } h2 { margin-top: 34px; }
    p, li { color: #a8b0b8; } a { color: #7cff00; }
    .badge { color: #070a0d; background: #7cff00; display: inline-block; padding: 7px 11px; border-radius: 999px; font-weight: 800; }
  </style>
</head>
<body>
  <main>
    <div class="badge">GPSQUIZ</div>
    <h1>Integritetspolicy</h1>
    <p>Senast uppdaterad: 9 juni 2026.</p>

    <h2>Vilka uppgifter behandlas?</h2>
    <p>GPSQuiz kan lagra publicerade quiz, checkpoint-positioner, lag- och spelarnamn, antal rätta svar, sluttid och tidpunkt för avslutad runda. Uppgifterna används för att genomföra quiz och visa topplistan.</p>

    <h2>Platsdata</h2>
    <p>Appen använder enhetens plats medan en runda pågår för att avgöra när en fråga ska låsas upp. Spelarens aktuella GPS-position skickas inte till GPSQuiz-servern. En lärare kan däremot publicera de checkpoint-positioner som ingår i en quizbana.</p>

    <h2>Delning och spårning</h2>
    <p>GPSQuiz säljer inte personuppgifter, använder inte data för reklam och spårar inte användare mellan appar eller webbplatser. Backend-tjänsten körs hos Render för att dela quiz och resultat mellan deltagare.</p>

    <h2>Lagring och borttagning</h2>
    <p>Data sparas så länge den behövs för quizfunktionen och kan tas bort av tjänstens administratör. Undvik att använda fullständiga personnamn för elever; använd helst lagnamn eller förnamn.</p>

    <h2>Barn och skolanvändning</h2>
    <p>Vid användning i skolan ansvarar läraren eller skolan för att användningen följer lokala regler och att elever får relevant information. Appen kräver inte att eleven skapar ett konto.</p>

    <h2>Kontakt</h2>
    <p>Frågor om integritet eller begäran om borttagning kan skickas via <a href="/support">GPSQuiz support</a> eller projektets <a href="https://github.com/reca007/gpsQuiz/issues">supportformulär</a>.</p>
  </main>
</body>
</html>`;
}

function supportPage() {
  return `<!doctype html>
<html lang="sv">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Support · GPSQuiz</title>
  <style>
    :root { color-scheme: dark; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #070a0d; color: #f4f6f8; }
    main { width: min(88vw, 620px); padding: 30px; border: 1px solid #252c33; border-radius: 24px; background: #101418; }
    h1 { font-size: 38px; margin: 0 0 12px; } p { color: #a8b0b8; line-height: 1.55; }
    a { color: #7cff00; } .accent { color: #7cff00; font-weight: 800; }
  </style>
</head>
<body>
  <main>
    <div class="accent">GPSQUIZ SUPPORT</div>
    <h1>Hur kan vi hjälpa?</h1>
    <p>Kontakta den lärare eller administratör som delade quizet om en bana, QR-kod eller spelrunda inte fungerar.</p>
    <p>Vid tekniska problem: ange enhet, iOS-version, quizets namn och vad som hände. Dela aldrig lösenord eller känsliga elevuppgifter.</p>
    <p><a href="https://github.com/reca007/gpsQuiz/issues">Skapa ett supportärende</a></p>
    <p><a href="/health">Kontrollera serverstatus</a> · <a href="/privacy">Integritetspolicy</a></p>
  </main>
</body>
</html>`;
}

async function readJSON(request) {
  const chunks = [];
  for await (const chunk of request) {
    chunks.push(chunk);
  }

  if (chunks.length === 0) {
    return {};
  }

  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

function isValidQuiz(payload) {
  return payload &&
    typeof payload.title === "string" &&
    Array.isArray(payload.checkpoints) &&
    payload.checkpoints.every((checkpoint) =>
      typeof checkpoint.name === "string" &&
      typeof checkpoint.latitude === "number" &&
      typeof checkpoint.longitude === "number" &&
      typeof checkpoint.radius === "number" &&
      typeof checkpoint.question === "string" &&
      Array.isArray(checkpoint.options) &&
      checkpoint.options.some((option) => option.isCorrect === true)
    );
}

function normalizeQuiz(payload) {
  const quizID = payload.quizID || crypto.randomUUID();
  return {
    quizID,
    title: payload.title.trim(),
    summary: typeof payload.summary === "string" ? payload.summary.trim() : "",
    checkpoints: payload.checkpoints.map((checkpoint) => ({
      name: checkpoint.name,
      latitude: checkpoint.latitude,
      longitude: checkpoint.longitude,
      radius: checkpoint.radius,
      question: checkpoint.question,
      options: checkpoint.options.map((option) => ({
        text: String(option.text || ""),
        isCorrect: option.isCorrect === true
      }))
    })),
    updatedAt: new Date().toISOString()
  };
}

function sortLeaderboard(entries) {
  return [...entries].sort((left, right) => {
    if (left.correctCount !== right.correctCount) {
      return right.correctCount - left.correctCount;
    }
    return left.totalSeconds - right.totalSeconds;
  });
}

function generatedQuestions(request) {
  const count = Math.max(1, Math.min(Number(request.questionCount || 6), 20));
  const minutes = Math.max(5, Number(request.minutes || 30));
  const centerLatitude = Number(request.centerLatitude || 59.3293);
  const centerLongitude = Number(request.centerLongitude || 18.0686);
  const radius = Math.max(80, Math.min(900, (minutes * 70) / (2 * Math.PI)));
  const activationRadiusMeters = Number(request.activationRadiusMeters || 60);
  const subjectAreas = Array.isArray(request.subjectAreas) && request.subjectAreas.length > 0
    ? request.subjectAreas
    : [request.subject || "Skolämne"];

  return Array.from({ length: count }, (_, index) => {
    const angle = (index / count) * Math.PI * 2;
    const latitude = centerLatitude + (Math.cos(angle) * radius) / 111_320;
    const longitude = centerLongitude + (Math.sin(angle) * radius) / (111_320 * Math.cos(centerLatitude * Math.PI / 180));
    const subject = subjectAreas[index % subjectAreas.length];
    const topic = topicFor(subject, request.gradeLevel || "Högstadiet", index);
    const correctAnswer = `${topic} hör ihop med ${subject}`;

    return {
      name: `${request.placeName || "Skolgården"} ${index + 1}`,
      latitude,
      longitude,
      activationRadiusMeters,
      question: `${request.gradeLevel || "Högstadiet"}: Vilket alternativ passar bäst med ${topic} i ${subject}?`,
      options: [
        correctAnswer,
        "Det handlar främst om slump",
        "Det saknar koppling till platsen"
      ],
      correctAnswer
    };
  });
}

function topicFor(subject, gradeLevel, index) {
  const normalized = `${subject} ${gradeLevel}`.toLowerCase();
  const upperSecondary = normalized.includes("gymnas");
  const topics = normalized.includes("mat")
    ? (upperSecondary ? ["funktioner", "modellering", "statistik"] : ["procent", "skala", "area"])
    : normalized.includes("hist")
      ? ["källkritik", "demokrati", "historiebruk"]
      : normalized.includes("natur") || normalized.includes("biologi")
        ? ["ekosystem", "hållbar utveckling", "energiflöden"]
        : normalized.includes("språk") || normalized.includes("svenska") || normalized.includes("engelska")
          ? ["begrepp", "argument", "ordförråd"]
          : ["begrepp", "samband", "analys"];
  return topics[index % topics.length];
}

function normalizedGenerationRequest(request) {
  const questionCount = Math.max(1, Math.min(Number(request.questionCount || 6), 20));
  const subjectAreas = Array.isArray(request.subjectAreas)
    ? request.subjectAreas
        .map((item) => String(item || "").trim())
        .filter(Boolean)
        .slice(0, 8)
    : [];

  return {
    subject: String(request.subject || subjectAreas[0] || "Skolämne").trim().slice(0, 120),
    subjectAreas: subjectAreas.length > 0 ? subjectAreas : [String(request.subject || "Skolämne").trim()],
    gradeLevel: String(request.gradeLevel || "Högstadiet").trim().slice(0, 120),
    placeName: String(request.placeName || "Skolgården").trim().slice(0, 160),
    locationDescription: String(request.locationDescription || "").trim().slice(0, 800),
    centerLatitude: Number(request.centerLatitude || 59.3293),
    centerLongitude: Number(request.centerLongitude || 18.0686),
    minutes: Math.max(5, Math.min(Number(request.minutes || 30), 180)),
    questionCount,
    activationRadiusMeters: Math.max(5, Math.min(Number(request.activationRadiusMeters || 60), 500)),
    language: ["en", "sv", "es"].includes(request.language) ? request.language : "sv",
    difficulty: ["easy", "medium", "hard"].includes(request.difficulty) ? request.difficulty : "medium",
    teacherInstructions: String(request.teacherInstructions || "").trim().slice(0, 1200)
  };
}

function languageName(language) {
  return {
    en: "English",
    sv: "Swedish",
    es: "Spanish"
  }[language] || "Swedish";
}

function questionContentSchema(questionCount) {
  return {
    type: "object",
    additionalProperties: false,
    required: ["questions"],
    properties: {
      questions: {
        type: "array",
        minItems: questionCount,
        maxItems: questionCount,
        items: {
          type: "object",
          additionalProperties: false,
          required: [
            "checkpointTitle",
            "subject",
            "category",
            "question",
            "options",
            "correctAnswer",
            "explanation"
          ],
          properties: {
            checkpointTitle: { type: "string" },
            subject: { type: "string" },
            category: { type: "string" },
            question: { type: "string" },
            options: {
              type: "array",
              minItems: 4,
              maxItems: 4,
              items: { type: "string" }
            },
            correctAnswer: { type: "string" },
            explanation: { type: "string" }
          }
        }
      }
    }
  };
}

function extractResponseText(responsePayload) {
  for (const output of responsePayload.output || []) {
    for (const content of output.content || []) {
      if (content.type === "output_text" && typeof content.text === "string") {
        return content.text;
      }
    }
  }
  throw new Error("OpenAI response did not contain structured text");
}

function routeCoordinates(request) {
  const radius = Math.max(80, Math.min(900, (request.minutes * 70) / (2 * Math.PI)));

  return Array.from({ length: request.questionCount }, (_, index) => {
    const angle = (index / request.questionCount) * Math.PI * 2;
    return {
      latitude: request.centerLatitude + (Math.cos(angle) * radius) / 111_320,
      longitude: request.centerLongitude +
        (Math.sin(angle) * radius) /
          (111_320 * Math.cos(request.centerLatitude * Math.PI / 180))
    };
  });
}

function validateGeneratedQuestion(question) {
  const options = Array.isArray(question.options)
    ? question.options.map((option) => String(option).trim()).filter(Boolean)
    : [];
  const correctAnswer = String(question.correctAnswer || "").trim();

  return String(question.question || "").trim().length >= 8 &&
    options.length === 4 &&
    new Set(options.map((option) => option.toLocaleLowerCase())).size === 4 &&
    options.includes(correctAnswer);
}

export async function generateQuestionsWithOpenAI(rawRequest) {
  if (!OPENAI_API_KEY) {
    throw new Error("OPENAI_API_KEY is not configured");
  }

  const request = normalizedGenerationRequest(rawRequest);
  const instructions = [
    "You create accurate, age-appropriate multiple-choice questions for GPSQuiz CityWalk.",
    `Write every user-facing field in ${languageName(request.language)}.`,
    "Generate exactly the requested number of questions.",
    "Each question must have exactly four plausible and distinct answer options.",
    "correctAnswer must exactly match one item in options.",
    "Vary cognitive skill, wording, category, and correct-option position.",
    "Avoid trick questions, ambiguous wording, repeated facts, and duplicated questions.",
    "Use the place context when educationally relevant, but never invent facts about the location.",
    "Questions must be suitable for teacher review before publishing.",
    "Do not include personal data, unsafe activities, advertising, or political persuasion."
  ].join(" ");

  const input = {
    task: "Generate a varied GPS quiz route question set.",
    route: {
      placeName: request.placeName,
      locationDescription: request.locationDescription,
      checkpointCount: request.questionCount
    },
    education: {
      primarySubject: request.subject,
      subjects: request.subjectAreas,
      gradeLevel: request.gradeLevel,
      difficulty: request.difficulty,
      language: request.language
    },
    teacherInstructions: request.teacherInstructions || "No additional instructions."
  };

  const apiResponse = await fetch(OPENAI_RESPONSES_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${OPENAI_API_KEY}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: OPENAI_MODEL,
      instructions,
      input: JSON.stringify(input),
      max_output_tokens: 6_000,
      text: {
        format: {
          type: "json_schema",
          name: "gpsquiz_questions",
          strict: true,
          schema: questionContentSchema(request.questionCount)
        }
      }
    }),
    signal: AbortSignal.timeout(45_000)
  });

  const responsePayload = await apiResponse.json();
  if (!apiResponse.ok) {
    const message = responsePayload?.error?.message || `OpenAI request failed (${apiResponse.status})`;
    throw new Error(message);
  }

  const generated = JSON.parse(extractResponseText(responsePayload));
  if (!Array.isArray(generated.questions) ||
      generated.questions.length !== request.questionCount ||
      !generated.questions.every(validateGeneratedQuestion)) {
    throw new Error("OpenAI returned invalid question data");
  }

  const coordinates = routeCoordinates(request);
  return generated.questions.map((question, index) => ({
    name: String(question.checkpointTitle || `${request.placeName} ${index + 1}`).trim(),
    latitude: coordinates[index].latitude,
    longitude: coordinates[index].longitude,
    activationRadiusMeters: request.activationRadiusMeters,
    question: String(question.question).trim(),
    options: question.options.map((option) => String(option).trim()),
    correctAnswer: String(question.correctAnswer).trim(),
    explanation: String(question.explanation).trim(),
    subject: String(question.subject).trim(),
    category: String(question.category).trim()
  }));
}

async function route(request, response) {
  if (request.method === "OPTIONS") {
    sendJSON(response, 204, {});
    return;
  }

  const url = new URL(request.url, `http://${request.headers.host}`);
  const publicURL = new URL(request.url, `${request.headers["x-forwarded-proto"] || "https"}://${request.headers.host}`);

  if (request.method === "GET" && url.pathname === "/") {
    sendHTML(response, 200, `<!doctype html><html lang="sv"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>GPSQuiz API</title><body style="font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:32px;line-height:1.5"><h1>GPSQuiz API</h1><p>Servern kör. Publicerade elevlänkar finns på <code>/q/&lt;quiz-id&gt;</code>.</p><p><a href="/health">Serverstatus</a> · <a href="/support">Support</a> · <a href="/privacy">Integritetspolicy</a></p></body></html>`);
    return;
  }

  if (request.method === "GET" && url.pathname === "/privacy") {
    sendHTML(response, 200, privacyPage());
    return;
  }

  if (request.method === "GET" && url.pathname === "/support") {
    sendHTML(response, 200, supportPage());
    return;
  }

  if (request.method === "GET" && url.pathname === "/health") {
    sendJSON(response, 200, {
      ok: true,
      service: "gpsquiz-api",
      ai: {
        configured: Boolean(OPENAI_API_KEY),
        model: OPENAI_MODEL
      }
    });
    return;
  }

  if (request.method === "GET" && url.pathname.startsWith("/q/")) {
    const quizID = decodeURIComponent(url.pathname.split("/").pop());
    const store = await readStore();
    const quiz = store.quizzes.find((item) => item.quizID === quizID);
    if (!quiz) {
      sendHTML(response, 404, `<!doctype html><html lang="sv"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Quiz saknas</title><body style="font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:32px;line-height:1.5"><h1>Quizet hittades inte</h1><p>Be läraren publicera quizet till Render igen och skicka en ny länk.</p></body></html>`);
      return;
    }

    sendHTML(response, 200, sharePage({ quiz, requestURL: publicURL }));
    return;
  }

  if (request.method === "GET" && url.pathname === "/api/quizzes") {
    const store = await readStore();
    sendJSON(response, 200, { quizzes: store.quizzes.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt)) });
    return;
  }

  if (request.method === "GET" && url.pathname.startsWith("/api/quizzes/")) {
    const quizID = decodeURIComponent(url.pathname.split("/").pop());
    const store = await readStore();
    const quiz = store.quizzes.find((item) => item.quizID === quizID);
    sendJSON(response, quiz ? 200 : 404, quiz ? { quiz } : { error: "Quiz not found" });
    return;
  }

  if (request.method === "POST" && url.pathname === "/api/quizzes") {
    const payload = await readJSON(request);
    if (!isValidQuiz(payload)) {
      sendJSON(response, 400, { error: "Invalid quiz payload" });
      return;
    }

    const quiz = normalizeQuiz(payload);
    const store = await readStore();
    store.quizzes = [quiz, ...store.quizzes.filter((item) => item.quizID !== quiz.quizID)];
    await writeStore(store);
    sendJSON(response, 201, { quiz });
    return;
  }

  if (request.method === "GET" && url.pathname === "/api/leaderboard") {
    const quizID = url.searchParams.get("quizID");
    const store = await readStore();
    const entries = quizID
      ? store.leaderboard.filter((entry) => entry.quizID === quizID)
      : store.leaderboard;
    sendJSON(response, 200, { entries: sortLeaderboard(entries).slice(0, 100) });
    return;
  }

  if (request.method === "POST" && url.pathname === "/api/leaderboard") {
    const payload = await readJSON(request);
    const entry = {
      id: payload.id || crypto.randomUUID(),
      quizID: payload.quizID,
      quizTitle: payload.quizTitle,
      playerName: payload.playerName,
      correctCount: Number(payload.correctCount || 0),
      totalSeconds: Number(payload.totalSeconds || 0),
      completedAt: payload.completedAt || new Date().toISOString()
    };

    if (!entry.quizID || !entry.quizTitle || !entry.playerName) {
      sendJSON(response, 400, { error: "Invalid leaderboard payload" });
      return;
    }

    const store = await readStore();
    store.leaderboard = [entry, ...store.leaderboard.filter((item) => item.id !== entry.id)];
    await writeStore(store);
    sendJSON(response, 201, { entry });
    return;
  }

  if (request.method === "POST" && url.pathname === "/api/ai/generate") {
    if (!consumeAIRateLimit(requestClientID(request))) {
      sendJSON(response, 429, {
        error: "Too many AI generation requests. Try again later."
      });
      return;
    }

    const payload = await readJSON(request);
    try {
      const questions = await generateQuestionsWithOpenAI(payload);
      sendJSON(response, 200, {
        questions,
        generationMode: "openai",
        model: OPENAI_MODEL
      });
    } catch (error) {
      console.error("AI generation fallback:", error.message);
      sendJSON(response, 200, {
        questions: generatedQuestions(payload),
        generationMode: "local-fallback"
      });
    }
    return;
  }

  sendJSON(response, 404, { error: "Not found" });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  createServer((request, response) => {
    route(request, response).catch((error) => {
      console.error(error);
      sendJSON(response, 500, { error: "Internal server error" });
    });
  }).listen(PORT, () => {
    console.log(`GPSQuiz API listening on ${PORT}`);
  });
}
