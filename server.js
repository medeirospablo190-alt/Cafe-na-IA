import express from "express";
import OpenAI from "openai";

const app = express();
app.use(express.json({ limit: "20kb" }));

const client = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

const PORT = process.env.PORT || 10000;
const MODEL = process.env.OPENAI_MODEL || "gpt-5.4";

// Memória simples em RAM por usuário.
// Em reinícios do Render, essa memória é perdida.
const conversations = new Map();

app.get("/", (_req, res) => {
  res.json({
    ok: true,
    service: "CAFEINA AI",
    endpoint: "/chat",
  });
});

app.get("/health", (_req, res) => {
  res.json({ ok: true });
});

app.post("/chat", async (req, res) => {
  try {
    const { message, userId, username } = req.body ?? {};

    if (typeof message !== "string" || !message.trim()) {
      return res.status(400).json({
        message: "Mensagem inválida.",
      });
    }

    if (message.length > 2000) {
      return res.status(400).json({
        message: "Mensagem muito grande. Limite: 2000 caracteres.",
      });
    }

    const conversationKey = String(userId ?? username ?? "anonymous");
    const previousResponseId = conversations.get(conversationKey);

    const request = {
      model: MODEL,
      instructions:
        "Você é CAFEÍNA AI, uma assistente integrada a um menu Roblox. " +
        "Responda em português do Brasil por padrão. Seja clara, objetiva e útil. " +
        "Não afirme ter acesso ao servidor Roblox, Workspace, jogadores ou dados que não tenham sido enviados a você.",
      input: message.trim(),
      max_output_tokens: 800,
    };

    if (previousResponseId) {
      request.previous_response_id = previousResponseId;
    }

    const response = await client.responses.create(request);

    conversations.set(conversationKey, response.id);

    res.json({
      message: response.output_text || "A IA não retornou texto.",
      responseId: response.id,
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({
      message: "Erro ao consultar a IA.",
    });
  }
});

app.post("/reset", (req, res) => {
  const { userId, username } = req.body ?? {};
  const conversationKey = String(userId ?? username ?? "anonymous");

  conversations.delete(conversationKey);

  res.json({
    ok: true,
    message: "Conversa reiniciada.",
  });
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`CAFEÍNA AI online na porta ${PORT}`);
});
