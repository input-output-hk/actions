/******/ (() => { // webpackBootstrap
/******/ 	var __webpack_modules__ = ({

/***/ 967:
/***/ ((module) => {

module.exports = eval("require")("@actions/core");


/***/ }),

/***/ 789:
/***/ ((module) => {

module.exports = eval("require")("@actions/exec");


/***/ }),

/***/ 376:
/***/ ((module) => {

module.exports = eval("require")("@actions/glob");


/***/ }),

/***/ 474:
/***/ ((module) => {

module.exports = eval("require")("@actions/http-client");


/***/ }),

/***/ 301:
/***/ ((module) => {

module.exports = eval("require")("@actions/tool-cache");


/***/ })

/******/ 	});
/************************************************************************/
/******/ 	// The module cache
/******/ 	var __webpack_module_cache__ = {};
/******/ 	
/******/ 	// The require function
/******/ 	function __nccwpck_require__(moduleId) {
/******/ 		// Check if module is in cache
/******/ 		var cachedModule = __webpack_module_cache__[moduleId];
/******/ 		if (cachedModule !== undefined) {
/******/ 			return cachedModule.exports;
/******/ 		}
/******/ 		// Create a new module (and put it into the cache)
/******/ 		var module = __webpack_module_cache__[moduleId] = {
/******/ 			// no module.id needed
/******/ 			// no module.loaded needed
/******/ 			exports: {}
/******/ 		};
/******/ 	
/******/ 		// Execute the module function
/******/ 		var threw = true;
/******/ 		try {
/******/ 			__webpack_modules__[moduleId](module, module.exports, __nccwpck_require__);
/******/ 			threw = false;
/******/ 		} finally {
/******/ 			if(threw) delete __webpack_module_cache__[moduleId];
/******/ 		}
/******/ 	
/******/ 		// Return the exports of the module
/******/ 		return module.exports;
/******/ 	}
/******/ 	
/************************************************************************/
/******/ 	/* webpack/runtime/compat */
/******/ 	
/******/ 	if (typeof __nccwpck_require__ !== 'undefined') __nccwpck_require__.ab = __dirname + "/";
/******/ 	
/************************************************************************/
var __webpack_exports__ = {};
// This entry need to be wrapped in an IIFE because it need to be in strict mode.
(() => {
"use strict";

;// CONCATENATED MODULE: external "path"
const external_path_namespaceObject = require("path");
;// CONCATENATED MODULE: external "fs"
const external_fs_namespaceObject = require("fs");
;// CONCATENATED MODULE: ./index.js



const core = __nccwpck_require__(967);
const httpm = __nccwpck_require__(474);
const tool_cache = __nccwpck_require__(301);
const exec = __nccwpck_require__(789);
const glob = __nccwpck_require__(376);

// Get the latest release of cabal-gild by querying the GitHub releases API.
async function getLatestVersion() {
  const apiUrl = "https://api.github.com/repos/tfausak/cabal-gild/releases";

  let _http = new httpm.HttpClient("run-cabal-gild github action");

  const response = await _http.getJson(apiUrl);

  const releases = response.result;

  if (releases === null) {
    core.setFailed('Failed to fetch releases from the tfausak/cabal-gild repository');
  }

  if (releases.length === 0) {
    core.setFailed('No releases found for the tfausak/cabal-gild repository');
  }

  // Sort releases by published date in descending order
  releases.sort((a, b) => new Date(b.published_at) - new Date(a.published_at));

  // Return the version number of the latest release
  return releases[0].tag_name;
}

const input_version = core.getInput('version');
const input_follow_symbolic_links = core.getInput('follow-symbolic-links').toUpperCase() !== 'FALSE';
const input_extra_args = core.getInput('extra-args');
const input_working_directory = core.getInput('working-directory');

async function run() {

  const cabal_gild_version = input_version === 'latest' ? await getLatestVersion() : input_version;

  core.info(`version input to run-cabal-gild: ${input_version}, version selected for use: ${cabal_gild_version}`);

  const cabal_gild_linux_url = `https://github.com/tfausak/cabal-gild/releases/download/${cabal_gild_version}/cabal-gild-${cabal_gild_version}-linux-x64.tar.gz`;

  // Declare originalCwd outside the try block so it's accessible in catch below for error handling
  let originalCwd = undefined;

  try {
    // Set working directory if specified
    if (input_working_directory) {
      originalCwd = process.cwd();

      const absoluteWorkingDir = external_path_namespaceObject.resolve(input_working_directory);
      core.info(`Attempting to change to directory: ${absoluteWorkingDir}`);

      if (!external_fs_namespaceObject.existsSync(absoluteWorkingDir)) {
        core.setFailed(`Working directory '${absoluteWorkingDir}' does not exist`);
        return;
      }

      process.chdir(absoluteWorkingDir);
      const newCwd = process.cwd();
      core.info(`Changed working directory to: ${newCwd}`);
    }

    // Download cabal-gild binary

    var cabal_gild_extracted_binary;

    if (process.platform === 'linux') {
        const downloaded_tar = await tool_cache.downloadTool(`https://github.com/tfausak/cabal-gild/releases/download/${cabal_gild_version}/cabal-gild-${cabal_gild_version}-linux-x64.tar.gz`);

        cabal_gild_extracted_binary = await tool_cache.extractTar(downloaded_tar);
    }
    // else if (process.platform === 'darwin') {
    //     cabal-gild_downloaded_binary = await tool_cache.downloadTool(cabal-gild_macos_url);
    // }
    // else if (process.platform === 'win32') {
    //     cabal-gild_downloaded_binary = await tool_cache.downloadTool(cabal-gild_windows_url);
    // }
    else {
        core.setFailed("no cabal-gild binary found for platform: " + process.platform);
    }

    // At this point, cabal_gild_extracted_dir is the cabal-gild binary we just
    // downloaded, but tool_cache.downloadTool() gives it a random UUID as a
    // name.  We rename it to `cabal-gild` here.
    const cabal_gild_binary = external_path_namespaceObject.join(external_path_namespaceObject.dirname(cabal_gild_extracted_binary), 'cabal-gild');
    external_fs_namespaceObject.renameSync(external_path_namespaceObject.join(cabal_gild_extracted_binary, 'cabal-gild'), cabal_gild_binary)
    // Cache cabal_gild executable

    const cabal_gild_cached_dir = await tool_cache.cacheDir(
        external_path_namespaceObject.dirname(cabal_gild_binary),
        'cabal-gild',
        cabal_gild_version
    );
    core.info(`${cabal_gild_cached_dir}`);
    const cabal_gild_cached_path = external_path_namespaceObject.join(cabal_gild_cached_dir, 'cabal-gild');

    // Set mode

    await exec.exec('chmod', ['+x', cabal_gild_cached_path], {silent: true});

    // Glob for the files to format

    const globber = await glob.create(
        "**/*.cabal",
        {
            followSymbolicLinks: input_follow_symbolic_links
        }
    );
    const files = await globber.glob();

    // Extra args

    var extra_args = [];

    if (input_extra_args) {
        extra_args = input_extra_args.split(' ');
    }

    // Run cabal-gild

    await exec.exec(cabal_gild_cached_path, ['--version']);

    if (files.length > 0) {
       for (const file of files) {
            await exec.exec(
                cabal_gild_cached_path,
                ['--mode=check', '-i', `${file}`]
            );
        };
    }
    else {
        core.warning("The glob patterns did not match any source files");
    }

    // Restore original working directory if it was changed
    if (originalCwd) {
      process.chdir(originalCwd);
      core.info(`Restored working directory to: ${originalCwd}`);
    }

  } catch (error) {
    // Restore original working directory even if there was an error
    if (originalCwd) {
      process.chdir(originalCwd);
      core.info(`Restored working directory to: ${originalCwd}`);
    }
      core.info(`${error}`);
    core.setFailed("cabal-gild detected unformatted files");
  }
}

run();

})();

module.exports = __webpack_exports__;
/******/ })()
;