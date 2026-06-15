{{flutter_js}}
{{flutter_build_config}}

const buildVersion = '20260603-4';

if (_flutter.buildConfig?.builds) {
  for (const build of _flutter.buildConfig.builds) {
    if (build.mainJsPath) {
      build.mainJsPath = `${build.mainJsPath}?v=${buildVersion}`;
    }
  }
}

_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();
  }
});
