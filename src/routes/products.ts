import { Router } from "express";
import { z } from "zod";
import { requireAuth } from "../auth.js";
import {
  createProduct,
  findProductById,
  listProducts,
  type PublicUser,
} from "../store.js";

const createProductSchema = z.object({
  name: z.string().trim().min(1).max(200),
  description: z.string().trim().max(2000).optional(),
  price: z.number().finite().nonnegative(),
});

export const productsRouter = Router();

productsRouter.post("/", requireAuth, (req, res) => {
  const parsed = createProductSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({
      error: "Invalid request",
      details: parsed.error.flatten().fieldErrors,
    });
    return;
  }

  const user = res.locals.user as PublicUser;
  const product = createProduct({
    name: parsed.data.name,
    description: parsed.data.description ?? "",
    price: parsed.data.price,
    createdBy: user.id,
  });
  res.status(201).json({ product });
});

productsRouter.get("/", (_req, res) => {
  res.json({ products: listProducts() });
});

productsRouter.get("/:id", (req, res) => {
  const product = findProductById(req.params.id);
  if (!product) {
    res.status(404).json({ error: "Product not found" });
    return;
  }
  res.json({ product });
});
