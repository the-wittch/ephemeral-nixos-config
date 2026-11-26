# Decky Loader, built from its tagged source: the web frontend Steam loads, and the Python
# service that serves it and runs the plugins
{
  lib,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm_11,
  nodejs,
  python3,
  coreutils,
  psmisc,
}:
python3.pkgs.buildPythonApplication (finalAttrs: {
  pname = "decky-loader";
  version = "3.3.1";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "SteamDeckHomebrew";
    repo = "decky-loader";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Dm/O4ChRH3qKisJXdhiByTMOf4AfvBoEL8xroJ737tU=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_11;
    fetcherVersion = 4;
    sourceRoot = "${finalAttrs.src.name}/frontend";
    hash = "sha256-8vD7fInV+x3REDdlMXhZle8fRtqptOdEc0rPRKH2zLg=";
  };
  pnpmRoot = "frontend";

  nativeBuildInputs = [
    nodejs
    pnpm_11
    pnpmConfigHook
  ];

  # the frontend is built into the backend's static files, which the Python package ships
  preBuild = ''
    (cd frontend && pnpm build)
    cd backend
  '';

  build-system = with python3.pkgs; [
    poetry-core
    poetry-dynamic-versioning
  ];
  dependencies = with python3.pkgs; [
    aiohttp
    aiohttp-cors
    aiohttp-jinja2
    certifi
    multidict
    packaging
    setproctitle
    watchdog
  ];
  pythonRelaxDeps = [
    "aiohttp-cors"
    "packaging"
    "watchdog"
  ];

  # it restarts Steam's web helper with killall
  makeWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath [
      coreutils
      psmisc
    ])
  ];

  meta = {
    description = "Plugin loader for Steam's Game Mode";
    homepage = "https://github.com/SteamDeckHomebrew/decky-loader";
    license = lib.licenses.gpl2Only;
    mainProgram = "decky-loader";
    platforms = lib.platforms.linux;
  };
})
