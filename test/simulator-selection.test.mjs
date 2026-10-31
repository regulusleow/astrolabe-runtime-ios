import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

test("simulator tests select an iPhone supported by the chosen runtime", () => {
  for (const [supportedNames, expectedIdentifier] of [
    [["iPhone Duo"], "iPhone-Duo"],
    [["iPhone 18 Pro", "iPhone 16 Pro"], "iPhone-16-Pro"]
  ]) {
    const directory = mkdtempSync(join(tmpdir(), "astrolabe-simulator-selection-"));
    try {
      const device = (name) => ({ name, identifier: name.replaceAll(" ", "-") });
      const supported = supportedNames.map(device);
      const runtimes = { runtimes: [
        { identifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0", version: "27.0", isAvailable: true, supportedDeviceTypes: [device("iPhone 16 Pro")] },
        { identifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-1", version: "27.1", isAvailable: true, supportedDeviceTypes: supported }
      ] };
      writeFileSync(join(directory, "runtimes.json"), JSON.stringify(runtimes));
      writeFileSync(join(directory, "xcrun"), `#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");
const args = process.argv.slice(2);
const directory = process.env.SELECTION_FIXTURE;
if (args[1] === "list" && args[2] === "runtimes") {
  process.stdout.write(fs.readFileSync(path.join(directory, "runtimes.json")));
} else if (args[1] === "list" && args[2] === "devicetypes") {
  process.stdout.write(JSON.stringify({ devicetypes: [{ name: "iPhone 16 Pro", identifier: "iPhone-16-Pro" }] }));
} else if (args[1] === "create") {
  const runtime = JSON.parse(fs.readFileSync(path.join(directory, "runtimes.json"))).runtimes.find(item => item.identifier === args[4]);
  if (!runtime?.supportedDeviceTypes.some(item => item.identifier === args[3])) process.exit(7);
  fs.writeFileSync(path.join(directory, "created.json"), JSON.stringify(args));
  console.log("test-device-id");
} else if (args[1] === "delete") {
  fs.writeFileSync(path.join(directory, "deleted.json"), JSON.stringify(args));
} else {
  process.exit(99);
}
`, { mode: 0o755 });
      writeFileSync(join(directory, "xcodebuild"), `#!/usr/bin/env node
require("node:fs").writeFileSync(require("node:path").join(process.env.SELECTION_FIXTURE, "build.json"), JSON.stringify(process.argv.slice(2)));
process.exit(17);
`, { mode: 0o755 });

      const result = spawnSync("bash", ["scripts/run-ios-simulator-tests.sh"], {
        encoding: "utf8",
        env: { ...process.env, PATH: `${directory}:${process.env.PATH}`, SELECTION_FIXTURE: directory }
      });
      assert.equal(result.status, 17, result.stderr);
      const created = JSON.parse(readFileSync(join(directory, "created.json"), "utf8"));
      assert.equal(created[3], expectedIdentifier);
      assert.equal(created[4], "com.apple.CoreSimulator.SimRuntime.iOS-27-1");
      assert(JSON.parse(readFileSync(join(directory, "build.json"), "utf8")).includes("platform=iOS Simulator,id=test-device-id"));
      assert.deepEqual(JSON.parse(readFileSync(join(directory, "deleted.json"), "utf8")), ["simctl", "delete", "test-device-id"]);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  }
});
