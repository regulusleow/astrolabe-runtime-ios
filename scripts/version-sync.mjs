#!/usr/bin/env node

import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  canonicalRepositoryVersion,
  synchronizeRepositoryVersion,
  versionConsistencyIssues
} from "./versioning.mjs";

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);

try {
  if (args.length === 1 && args[0] === "--check") {
    const issues = versionConsistencyIssues(projectRoot);
    if (issues.length > 0) {
      throw new Error(`Version metadata mismatch:\n${issues.join("\n")}`);
    }
  } else if (args.length === 2 && args[0] === "--set") {
    synchronizeRepositoryVersion(projectRoot, args[1]);
  } else {
    throw new Error("Usage: version-sync.mjs --check | --set <major.minor.patch>");
  }
  process.stdout.write(`${canonicalRepositoryVersion(projectRoot)}\n`);
} catch (error) {
  console.error(`Failed: ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
}
