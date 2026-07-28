#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  assertReleaseVersion,
  assertStableProtocolDependency,
  canonicalRepositoryVersion,
  compareReleaseVersions,
  synchronizeRepositoryVersion
} from "./versioning.mjs";

const scriptPath = fileURLToPath(import.meta.url);
const defaultProjectRoot = resolve(dirname(scriptPath), "..");

export function parseReleaseArgs(args) {
  if (args.length !== 1) {
    throw new Error("Usage: release-prepare.mjs <major.minor.patch>");
  }
  return { version: assertReleaseVersion(args[0]) };
}

export function prepareRelease({
  projectRoot,
  version,
  commandRunner = makeCommandRunner(projectRoot)
}) {
  assertReleaseVersion(version);
  requireCleanSynchronizedBranch(commandRunner, version);
  requireUnpublishedTag(commandRunner, version);

  const previousVersion = canonicalRepositoryVersion(projectRoot);
  if (compareReleaseVersions(version, previousVersion) <= 0) {
    throw new Error(`Release version must be greater than the current version: current=${previousVersion}, target=${version}`);
  }
  assertStableProtocolDependency(projectRoot, version);

  const updatedPaths = synchronizeRepositoryVersion(projectRoot, version);
  runRequired(commandRunner, "npm", ["test"]);
  runRequired(commandRunner, "swift", ["test", "--parallel"]);
  runRequired(
    commandRunner,
    "swift",
    ["build", "-c", "release", "--product", "AstrolabeRuntime"]
  );
  requireOnlyVersionChanges(commandRunner, updatedPaths);
  runRequired(commandRunner, "git", ["diff", "--check"]);
  runRequired(commandRunner, "git", ["add", "--", ...updatedPaths]);
  runRequired(commandRunner, "git", ["diff", "--staged", "--check"]);
  runRequired(commandRunner, "git", ["commit", "-m", `chore: release ${version}`]);
  runRequired(
    commandRunner,
    "git",
    ["tag", "-a", version, "-m", `Astrolabe Runtime iOS ${version}`]
  );

  return { previousVersion, version, tag: version };
}

function requireCleanSynchronizedBranch(commandRunner, version) {
  if (runRequired(commandRunner, "git", ["status", "--porcelain"]).stdout.trim()) {
    throw new Error("Working tree is not clean; commit or remove existing changes first");
  }
  const branch = runRequired(commandRunner, "git", ["branch", "--show-current"]).stdout.trim();
  if (!branch) {
    throw new Error("Cannot prepare a release from a detached HEAD");
  }
  const expectedBranch = `release/${version}`;
  if (branch !== expectedBranch) {
    throw new Error(`Release preparation must run from ${expectedBranch}`);
  }

  const localHead = runRequired(commandRunner, "git", ["rev-parse", "HEAD"]).stdout.trim();
  const releaseHead = remoteBranchHead(commandRunner, branch);
  if (releaseHead) {
    if (localHead !== releaseHead) {
      throw new Error(`Current HEAD does not match remote branch origin/${branch}`);
    }
    return;
  }

  const developHead = remoteBranchHead(commandRunner, "develop");
  if (!developHead) {
    throw new Error("Remote base branch origin/develop was not found");
  }
  if (localHead !== developHead) {
    throw new Error("A new release branch must start from current origin/develop");
  }
}

function remoteBranchHead(commandRunner, branch) {
  const remoteLine = runRequired(
    commandRunner,
    "git",
    ["ls-remote", "--heads", "origin", `refs/heads/${branch}`]
  ).stdout.trim();
  return remoteLine.split(/\s+/)[0] ?? "";
}

function requireUnpublishedTag(commandRunner, version) {
  if (runRequired(commandRunner, "git", ["tag", "--list", version]).stdout.trim()) {
    throw new Error(`Local tag already exists: ${version}`);
  }
  if (runRequired(
    commandRunner,
    "git",
    ["ls-remote", "--tags", "origin", `refs/tags/${version}`]
  ).stdout.trim()) {
    throw new Error(`Remote tag already exists: ${version}`);
  }
}

function requireOnlyVersionChanges(commandRunner, updatedPaths) {
  const changedPaths = outputLines(
    runRequired(commandRunner, "git", ["diff", "HEAD", "--name-only"]).stdout
  );
  const expectedPaths = [...updatedPaths].sort();
  const unexpectedPaths = changedPaths.filter((path) => !expectedPaths.includes(path));
  if (unexpectedPaths.length > 0) {
    throw new Error(`Unexpected non-version file changes: ${unexpectedPaths.join(", ")}`);
  }
  const missingPaths = expectedPaths.filter((path) => !changedPaths.includes(path));
  if (missingPaths.length > 0) {
    throw new Error(`Version files did not produce expected changes: ${missingPaths.join(", ")}`);
  }
  const untrackedPaths = outputLines(
    runRequired(commandRunner, "git", ["ls-files", "--others", "--exclude-standard"]).stdout
  );
  if (untrackedPaths.length > 0) {
    throw new Error(`Untracked files found: ${untrackedPaths.join(", ")}`);
  }
}

function makeCommandRunner(projectRoot) {
  return (command, args) => {
    const result = spawnSync(command, args, {
      cwd: projectRoot,
      encoding: "utf8",
      stdio: ["inherit", "pipe", "pipe"]
    });
    return {
      status: result.status,
      stdout: result.stdout ?? "",
      stderr: result.stderr ?? "",
      error: result.error
    };
  };
}

function runRequired(commandRunner, command, args) {
  const result = commandRunner(command, args);
  if (result.error || result.status !== 0) {
    const detail = result.stderr?.trim() || result.error?.message || "Unknown error";
    throw new Error(`Command failed: ${command} ${args.join(" ")}\n${detail}`);
  }
  return result;
}

function outputLines(output) {
  return output.split("\n").map((line) => line.trim()).filter(Boolean).sort();
}

if (resolve(process.argv[1] ?? "") === scriptPath) {
  try {
    const result = prepareRelease({
      projectRoot: defaultProjectRoot,
      version: parseReleaseArgs(process.argv.slice(2)).version
    });
    process.stdout.write(
      `Prepared Astrolabe Runtime iOS ${result.version}: commit and tag created but not pushed\n`
    );
  } catch (error) {
    console.error(`Failed: ${error instanceof Error ? error.message : String(error)}`);
    process.exit(1);
  }
}
