import bcrypt from "bcryptjs";
import type { NextFunction, Request, Response } from "express";
import jwt from "jsonwebtoken";
import { findUserById, type PublicUser, toPublicUser } from "./store.js";

const TOKEN_TTL = "7d";

function jwtSecret(): string {
  const secret = process.env.JWT_SECRET;
  if (secret) return secret;
  if (process.env.NODE_ENV === "production") {
    throw new Error("JWT_SECRET is required in production");
  }
  return "dev-only-change-me";
}

export async function hashPassword(password: string): Promise<string> {
  return bcrypt.hash(password, 10);
}

export async function verifyPassword(
  password: string,
  passwordHash: string,
): Promise<boolean> {
  return bcrypt.compare(password, passwordHash);
}

export function signToken(user: PublicUser): string {
  return jwt.sign({ sub: user.id, email: user.email }, jwtSecret(), {
    expiresIn: TOKEN_TTL,
  });
}

export function requireAuth(req: Request, res: Response, next: NextFunction): void {
  const header = req.header("authorization");
  const token = header?.startsWith("Bearer ") ? header.slice("Bearer ".length) : undefined;
  if (!token) {
    res.status(401).json({ error: "Missing bearer token" });
    return;
  }

  try {
    const payload = jwt.verify(token, jwtSecret());
    if (typeof payload === "string" || typeof payload.sub !== "string") {
      res.status(401).json({ error: "Invalid token" });
      return;
    }
    const user = findUserById(payload.sub);
    if (!user) {
      res.status(401).json({ error: "Invalid token" });
      return;
    }
    res.locals.user = toPublicUser(user);
    next();
  } catch {
    res.status(401).json({ error: "Invalid token" });
  }
}
