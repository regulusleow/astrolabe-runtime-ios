import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("iOS Simulator CI provisions and targets an available runtime", async () => {
  const [workflow, runner] = await Promise.all([
    readFile(".github/workflows/ci.yml", "utf8"),
    readFile("scripts/run-ios-simulator-tests.sh", "utf8")
  ]);

  assert.match(workflow, /scripts\/run-ios-simulator-tests\.sh/);
  assert.doesNotMatch(workflow, /name=iPhone/);
  assert.match(runner, /xcodebuild -downloadPlatform iOS/);
  assert.match(runner, /xcrun simctl create/);
  assert.match(runner, /platform=iOS Simulator,id=\$\{device_udid\}/);
  assert.match(runner, /xcrun simctl delete/);
});
