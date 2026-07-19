import test from "node:test";
import assert from "node:assert/strict";
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  assertStableProtocolDependency,
  synchronizeRepositoryVersion,
  versionConsistencyIssues
} from "../scripts/versioning.mjs";
import {
  parseReleaseArgs,
  prepareRelease
} from "../scripts/release-prepare.mjs";

test("version synchronization updates runtime release metadata", () => {
  const fixture = makeVersionFixture();
  try {
    const updatedPaths = synchronizeRepositoryVersion(fixture.root, "2.0.0");

    assert.deepEqual(updatedPaths, fixture.expectedVersionedPaths);
    assert.equal(readJSON(join(fixture.root, "package.json")).version, "2.0.0");
    assert.equal(readJSON(join(fixture.root, "package-lock.json")).version, "2.0.0");
    assert.match(
      readFileSync(join(fixture.root, fixture.swiftPath), "utf8"),
      /static let runtimeVersion = "2\.0\.0"/
    );
    assert.match(
      readFileSync(join(fixture.root, fixture.readmePath), "utf8"),
      /Current package release: `2\.0\.0`/
    );
    assert.deepEqual(versionConsistencyIssues(fixture.root), []);
  } finally {
    fixture.cleanup();
  }
});

test("version consistency reports runtime metadata drift", () => {
  const fixture = makeVersionFixture();
  try {
    writeFileSync(
      join(fixture.root, fixture.swiftPath),
      "public enum AstrolabeRuntimeSDK {\n    public static let runtimeVersion = \"0.1.2\"\n}\n"
    );

    assert.deepEqual(
      versionConsistencyIssues(fixture.root),
      [`${fixture.swiftPath}: expected 0.1.3, found 0.1.2`]
    );
  } finally {
    fixture.cleanup();
  }
});

test("stable runtime releases require a stable exact protocol dependency", () => {
  const fixture = makeVersionFixture();
  try {
    assert.equal(assertStableProtocolDependency(fixture.root, "2.0.0"), "2.0.0");
    writeFileSync(
      join(fixture.root, "Package.swift"),
      '.package(url: "https://github.com/regulusleow/astrolabe-protocol.git", exact: "2.0.0-rc.1")\n'
    );
    assert.throws(
      () => assertStableProtocolDependency(fixture.root, "2.0.0"),
      /stable Astrolabe Protocol version/
    );
    writeFileSync(
      join(fixture.root, "Package.swift"),
      '.package(url: "https://github.com/regulusleow/astrolabe-protocol.git", exact: "1.9.0")\n'
    );
    assert.throws(
      () => assertStableProtocolDependency(fixture.root, "2.0.0"),
      /same major version/
    );
  } finally {
    fixture.cleanup();
  }
});

test("release preparation verifies, commits, and tags without pushing", () => {
  const fixture = makeVersionFixture();
  const calls = [];
  const commandRunner = (command, args) => {
    calls.push([command, ...args]);
    const key = [command, ...args].join(" ");
    if (key === "git branch --show-current") {
      return { stdout: "develop\n", stderr: "", status: 0 };
    }
    if (key === "git rev-parse HEAD") {
      return { stdout: "abc123\n", stderr: "", status: 0 };
    }
    if (key === "git ls-remote --heads origin refs/heads/develop") {
      return { stdout: "abc123\trefs/heads/develop\n", stderr: "", status: 0 };
    }
    if (key === "git diff HEAD --name-only") {
      return {
        stdout: `${fixture.expectedVersionedPaths.join("\n")}\n`,
        stderr: "",
        status: 0
      };
    }
    return { stdout: "", stderr: "", status: 0 };
  };

  try {
    assert.deepEqual(parseReleaseArgs(["2.0.0"]), { version: "2.0.0" });
    const result = prepareRelease({
      projectRoot: fixture.root,
      version: "2.0.0",
      commandRunner
    });

    assert.deepEqual(result, {
      previousVersion: "0.1.3",
      version: "2.0.0",
      tag: "2.0.0"
    });
    assert.equal(calls.some((call) => call.includes("push")), false);
    assert.deepEqual(calls.slice(-4), [
      ["git", "add", "--", ...fixture.expectedVersionedPaths],
      ["git", "diff", "--staged", "--check"],
      ["git", "commit", "-m", "chore: release 2.0.0"],
      ["git", "tag", "-a", "2.0.0", "-m", "Astrolabe Runtime iOS 2.0.0"]
    ]);
  } finally {
    fixture.cleanup();
  }
});

function makeVersionFixture() {
  const root = mkdtempSync(join(tmpdir(), "astrolabe-runtime-version-test-"));
  const swiftPath = "Sources/AstrolabeRuntime/AstrolabeRuntime.swift";
  const readmePath = "README.md";
  const expectedVersionedPaths = [
    swiftPath,
    readmePath,
    "package-lock.json",
    "package.json"
  ];

  mkdirSync(join(root, "Sources/AstrolabeRuntime"), { recursive: true });
  writeJSON(join(root, "package.json"), {
    name: "astrolabe-runtime-ios-release",
    version: "0.1.3"
  });
  writeJSON(join(root, "package-lock.json"), {
    name: "astrolabe-runtime-ios-release",
    version: "0.1.3",
    lockfileVersion: 3,
    packages: {
      "": { name: "astrolabe-runtime-ios-release", version: "0.1.3" }
    }
  });
  writeFileSync(
    join(root, swiftPath),
    "public enum AstrolabeRuntimeSDK {\n    public static let runtimeVersion = \"0.1.3\"\n}\n"
  );
  writeFileSync(
    join(root, readmePath),
    "Current package release: `0.1.3`.\n"
  );
  writeFileSync(
    join(root, "Package.swift"),
    '.package(url: "https://github.com/regulusleow/astrolabe-protocol.git", exact: "2.0.0")\n'
  );

  return {
    root,
    swiftPath,
    readmePath,
    expectedVersionedPaths,
    cleanup: () => rmSync(root, { recursive: true, force: true })
  };
}

function readJSON(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function writeJSON(path, value) {
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);
}
