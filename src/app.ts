import express from "express";
import { authRouter } from "./routes/auth.js";
import { productsRouter } from "./routes/products.js";

export function createApp() {
  const app = express();
  app.use(express.json());

  app.get("/health", (_req, res) => {
    res.json({ ok: true });
  });

  app.use("/auth", authRouter);
  app.use("/products", productsRouter);

  return app;
}
