import { Request, Response, NextFunction } from "express";

// Simple API key auth for MVP
// In production, validate Supabase JWT tokens instead
export function authMiddleware(
  req: Request,
  res: Response,
  next: NextFunction
): void {
  const apiKey = req.headers["x-api-key"];
  const expectedKey = process.env.API_KEY;

  if (!expectedKey) {
    console.warn("API_KEY not set — auth disabled in development");
    next();
    return;
  }

  if (apiKey !== expectedKey) {
    res.status(401).json({ error: "Unauthorized" });
    return;
  }

  next();
}
