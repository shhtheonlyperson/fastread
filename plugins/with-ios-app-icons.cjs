const fs = require("fs");
const path = require("path");
const { withDangerousMod, IOSConfig } = require("@expo/config-plugins");

const ICONSET_SOURCE = "assets/ios-app-icon";
const ICONSET_TARGET = "Images.xcassets/AppIcon.appiconset";

function withIosAppIcons(config) {
  return withDangerousMod(config, [
    "ios",
    async (config) => {
      const projectRoot = config.modRequest.projectRoot;
      const projectName = IOSConfig.XcodeUtils.getProjectName(projectRoot);
      const source = path.join(projectRoot, ICONSET_SOURCE);
      const target = path.join(projectRoot, "ios", projectName, ICONSET_TARGET);

      await fs.promises.rm(target, { force: true, recursive: true });
      await fs.promises.mkdir(path.dirname(target), { recursive: true });
      await fs.promises.cp(source, target, { recursive: true });

      return config;
    },
  ]);
}

module.exports = withIosAppIcons;
