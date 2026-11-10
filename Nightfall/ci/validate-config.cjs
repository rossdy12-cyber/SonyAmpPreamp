// Validate resolved Expo configuration without generating or compiling native code.
const { createRequire } = require('node:module');
const path = require('node:path');
const fs = require('node:fs');
const mobile = createRequire(path.resolve(__dirname, '../packages/mobile/package.json'));
const expo = createRequire(mobile.resolve('expo/package.json'));
const cliRoot = path.dirname(expo.resolve('@expo/cli/package.json'));
const validator = require(path.join(cliRoot, 'build/src/utils/validateApplicationId.js'));
const raw = process.argv[2]
  ? JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
  : mobile('./app.json').expo;
const config = raw.expo || raw;
try {
  validator.assertValidBundleId(config.ios.bundleIdentifier);
  validator.assertValidPackage(config.android.package);
  console.log(`Expo configuration valid: iOS ${config.ios.bundleIdentifier}; Android ${config.android.package}`);
} catch (error) {
  console.error(`Configuration validation failed for iOS bundle ID ${JSON.stringify(config.ios?.bundleIdentifier)}.`);
  console.error('iOS identifiers must use letters, numbers, dots and hyphens — no underscores.');
  throw error;
}