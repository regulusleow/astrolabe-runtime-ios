import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const runtimeMetadataPath = "Sources/AstrolabeRuntime/AstrolabeRuntime.swift";

export const versionedPaths = Object.freeze([
  runtimeMetadataPath,
  "README.md",
  "package-lock.json",
  "package.json"
]);

const releaseVersionPattern = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;
const swiftVersionPattern = /static let runtimeVersion = "(\d+\.\d+\.\d+)"/g;
const documentationVersionPattern = /Current package release: `(\d+\.\d+\.\d+)`/g;

export function assertReleaseVersion(version) {
  if (!releaseVersionPattern.test(version)) {
    throw new Error(`Invalid version format: ${version}; expected major.minor.patch`);
  }
  return version;
}

export function compareReleaseVersions(left, right) {
  const leftComponents = assertReleaseVersion(left).split(".").map(Number);
  const rightComponents = assertReleaseVersion(right).split(".").map(Number);
  for (let index = 0; index < leftComponents.length; index += 1) {
    if (leftComponents[index] !== rightComponents[index]) {
      return leftComponents[index] > rightComponents[index] ? 1 : -1;
    }
  }
  return 0;
}

export function canonicalRepositoryVersion(projectRoot) {
  return assertReleaseVersion(readJSON(join(projectRoot, "package.json")).version);
}

export function assertStableProtocolDependency(projectRoot, releaseVersion) {
  assertReleaseVersion(releaseVersion);
  const packageManifest = readFileSync(join(projectRoot, "Package.swift"), "utf8");
  const dependencyMatch = packageManifest.match(
    /url:\s*"[^"]*astrolabe-protocol(?:\.git)?",\s*exact:\s*"([^"]+)"/
  );
  const dependencyVersion = dependencyMatch?.[1];
  if (!dependencyVersion || !releaseVersionPattern.test(dependencyVersion)) {
    throw new Error(
      "A release must use an exact stable Astrolabe Protocol version, not an RC, branch, or revision"
    );
  }
  const releaseMajor = releaseVersion.split(".")[0];
  const protocolMajor = dependencyVersion.split(".")[0];
  if (releaseMajor !== protocolMajor) {
    throw new Error(
      `Runtime ${releaseVersion} must depend on a Protocol release with the same major version; current dependency is ${dependencyVersion}`
    );
  }
  return dependencyVersion;
}

export function synchronizeRepositoryVersion(projectRoot, version) {
  assertReleaseVersion(version);
  const updates = [
    packageVersionUpdate(join(projectRoot, "package.json"), version),
    packageLockVersionUpdate(join(projectRoot, "package-lock.json"), version),
    textVersionUpdate(
      join(projectRoot, runtimeMetadataPath),
      swiftVersionPattern,
      `static let runtimeVersion = "${version}"`
    ),
    textVersionUpdate(
      join(projectRoot, "README.md"),
      documentationVersionPattern,
      `Current package release: \`${version}\``
    )
  ];
  updates.forEach(({ path, content }) => writeFileSync(path, content));

  const issues = versionConsistencyIssues(projectRoot);
  if (issues.length > 0) {
    throw new Error(`Version mismatch remains after synchronization:\n${issues.join("\n")}`);
  }
  return [...versionedPaths];
}

export function versionConsistencyIssues(projectRoot) {
  const expectedVersion = canonicalRepositoryVersion(projectRoot);
  const issues = [];
  inspectJSONVersion(
    join(projectRoot, "package-lock.json"),
    "package-lock.json",
    expectedVersion,
    issues
  );
  inspectTextVersion(
    join(projectRoot, runtimeMetadataPath),
    runtimeMetadataPath,
    swiftVersionPattern,
    expectedVersion,
    issues
  );
  inspectTextVersion(
    join(projectRoot, "README.md"),
    "README.md",
    documentationVersionPattern,
    expectedVersion,
    issues
  );
  return issues;
}

function packageVersionUpdate(path, version) {
  const value = readJSON(path);
  value.version = version;
  return { path, content: jsonString(value) };
}

function packageLockVersionUpdate(path, version) {
  const value = readJSON(path);
  if (!value.packages?.[""]) {
    throw new Error(`Missing root package metadata in npm lockfile: ${path}`);
  }
  value.version = version;
  value.packages[""].version = version;
  return { path, content: jsonString(value) };
}

function textVersionUpdate(path, pattern, replacement) {
  const source = readFileSync(path, "utf8");
  const matches = [...source.matchAll(pattern)];
  if (matches.length !== 1) {
    throw new Error(`Unexpected version field count in ${path}: expected 1, found ${matches.length}`);
  }
  return { path, content: source.replace(pattern, replacement) };
}

function inspectJSONVersion(path, displayPath, expectedVersion, issues) {
  const value = readJSON(path);
  appendVersionIssue(displayPath, value.version, expectedVersion, issues);
  appendVersionIssue(
    `${displayPath}#packages[\"\"]`,
    value.packages?.[""]?.version,
    expectedVersion,
    issues
  );
}

function inspectTextVersion(path, displayPath, pattern, expectedVersion, issues) {
  const matches = [...readFileSync(path, "utf8").matchAll(pattern)];
  if (matches.length !== 1) {
    issues.push(`${displayPath}: expected one version field, found ${matches.length}`);
    return;
  }
  appendVersionIssue(displayPath, matches[0][1], expectedVersion, issues);
}

function appendVersionIssue(path, actualVersion, expectedVersion, issues) {
  if (actualVersion !== expectedVersion) {
    issues.push(`${path}: expected ${expectedVersion}, found ${actualVersion ?? "missing"}`);
  }
}

function readJSON(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function jsonString(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}
