import express from "express";
import cors from "cors";
import helmet from "helmet";
import rateLimit from "express-rate-limit";
import { aiRouter } from "./routes/ai";
import { authMiddleware } from "./middleware/auth";

const app = express();
const port = process.env.PORT || 3000;

// Security
app.use(helmet());
app.use(
  cors({
    origin: process.env.ALLOWED_ORIGINS?.split(",") || "*",
  })
);
app.use(express.json({ limit: "10mb" }));

// Rate limiting
const limiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 30, // 30 requests per minute per IP
  standardHeaders: true,
  legacyHeaders: false,
});
app.use("/api/", limiter);

// Health check (no auth)
app.get("/health", (_req, res) => {
  res.json({ status: "ok", service: "agentcy-backend" });
});

// Protected routes
app.use("/api", authMiddleware);
app.use("/api/ai", aiRouter);

app.listen(port, () => {
  console.log(`agent.cy backend running on port ${port}`);
});
