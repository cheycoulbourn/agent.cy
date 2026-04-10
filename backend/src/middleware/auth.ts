import { Request, Response, NextFunction } from "express";
import { createClient } from "@supabase/supabase-js";

const supabase = createClient(
  process.env.SUPABASE_URL || "",
  process.env.SUPABASE_SERVICE_ROLE_KEY || ""
);

export async function authMiddleware(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  // Option 1: API key auth (for MVP / testing)
  const apiKey = req.headers["x-api-key"];
  if (apiKey && apiKey === process.env.API_KEY) {
    next();
    return;
  }

  // Option 2: Supabase JWT auth (for production iOS app)
  const authHeader = req.headers.authorization;
  if (authHeader?.startsWith("Bearer ")) {
    const token = authHeader.slice(7);
    const { data, error } = await supabase.auth.getUser(token);

    if (error || !data.user) {
      res.status(401).json({ error: "Invalid token" });
      return;
    }

    // Attach user to request for downstream use
    (req as any).userId = data.user.id;
    next();
    return;
  }

  // No valid auth provided
  if (!process.env.API_KEY) {
    console.warn("No auth configured — allowing request in development");
    next();
    return;
  }

  res.status(401).json({ error: "Unauthorized" });
}
