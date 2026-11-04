import { randomUUID } from "node:crypto";

export type User = {
  id: string;
  email: string;
  name: string;
  passwordHash: string;
};

export type PublicUser = {
  id: string;
  email: string;
  name: string;
};

export type Product = {
  id: string;
  name: string;
  description: string;
  price: number;
  createdBy: string;
  createdAt: string;
};

const usersById = new Map<string, User>();
const usersByEmail = new Map<string, User>();
const products = new Map<string, Product>();

export function toPublicUser(user: User): PublicUser {
  return { id: user.id, email: user.email, name: user.name };
}

export function findUserByEmail(email: string): User | undefined {
  return usersByEmail.get(email);
}

export function findUserById(id: string): User | undefined {
  return usersById.get(id);
}

export function createUser(input: {
  email: string;
  name: string;
  passwordHash: string;
}): User {
  const user: User = {
    id: randomUUID(),
    email: input.email,
    name: input.name,
    passwordHash: input.passwordHash,
  };
  usersById.set(user.id, user);
  usersByEmail.set(user.email, user);
  return user;
}

export function createProduct(input: {
  name: string;
  description: string;
  price: number;
  createdBy: string;
}): Product {
  const product: Product = {
    id: randomUUID(),
    name: input.name,
    description: input.description,
    price: input.price,
    createdBy: input.createdBy,
    createdAt: new Date().toISOString(),
  };
  products.set(product.id, product);
  return product;
}

export function listProducts(): Product[] {
  return [...products.values()];
}

export function findProductById(id: string): Product | undefined {
  return products.get(id);
}
