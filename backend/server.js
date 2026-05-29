import { createServer } from "node:http";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import crypto from "node:crypto";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT || 3000);
const DATA_FILE = process.env.DATA_FILE || join(__dirname, "data", "store.json");
const APP_INSTALL_URL = process.env.APP_INSTALL_URL || process.env.TESTFLIGHT_URL || "";

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

async function route(request, response) {
  if (request.method === "OPTIONS") {
    sendJSON(response, 204, {});
    return;
  }

  const url = new URL(request.url, `http://${request.headers.host}`);
  const publicURL = new URL(request.url, `${request.headers["x-forwarded-proto"] || "https"}://${request.headers.host}`);

  if (request.method === "GET" && url.pathname === "/") {
    sendHTML(response, 200, `<!doctype html><html lang="sv"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>GPSQuiz API</title><body style="font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:32px;line-height:1.5"><h1>GPSQuiz API</h1><p>Servern kör. Publicerade elevlänkar finns på <code>/q/&lt;quiz-id&gt;</code>.</p><p><a href="/health">Health check</a></p></body></html>`);
    return;
  }

  if (request.method === "GET" && url.pathname === "/health") {
    sendJSON(response, 200, { ok: true, service: "gpsquiz-api" });
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
    const payload = await readJSON(request);
    sendJSON(response, 200, { questions: generatedQuestions(payload) });
    return;
  }

  sendJSON(response, 404, { error: "Not found" });
}

createServer((request, response) => {
  route(request, response).catch((error) => {
    console.error(error);
    sendJSON(response, 500, { error: "Internal server error" });
  });
}).listen(PORT, () => {
  console.log(`GPSQuiz API listening on ${PORT}`);
});
