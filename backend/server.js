import { createServer } from "node:http";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import crypto from "node:crypto";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT || 3000);
const DATA_FILE = process.env.DATA_FILE || join(__dirname, "data", "store.json");

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

  if (request.method === "GET" && url.pathname === "/health") {
    sendJSON(response, 200, { ok: true, service: "gpsquiz-api" });
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
