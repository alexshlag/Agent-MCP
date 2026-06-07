{
  description = "NixOS Flake для RAG-сервера Agent-MCP";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      agent-mcp-pkg =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          # Создаем Python-окружение со всеми зависимостями
          pythonEnv = pkgs.python313.withPackages (
            ps: with ps; [
              anyio
              click
              openai
              starlette
              uvicorn
              jinja2
              python-dotenv
              sqlite-vec
              httpx
              tabulate
              pyperclip
              mcp
              requests
            ]
          );
        in
        pkgs.stdenv.mkDerivation {
          pname = "agent-mcp";
          version = "0.1.0";

          src = ./.;

          nativeBuildInputs = [ pkgs.makeWrapper ];

          installPhase = ''
            mkdir -p $out/bin
            mkdir -p $out/share/agent-mcp

            # Копируем все файлы из проекта (кроме скрытых и __pycache__)
            cp -r agent_mcp/* $out/share/agent-mcp/ 2>/dev/null || true
            find . -name "*.py" -type f ! -path "*/__pycache__/*" ! -name "*test*" | while read f; do
              cp "$f" $out/share/agent-mcp/ 2>/dev/null || true
            done

            # Создаем исполняемый бинарник-обертку
            makeWrapper ${pythonEnv}/bin/python $out/bin/agent-mcp \
              --add-flags "-m agent_mcp.cli" \
              --prefix PYTHONPATH : "$out/share/agent-mcp"
          '';

          meta = with pkgs.lib; {
            description = "Agent-MCP RAG Server";
            homepage = "https://github.com/alexshlag/Agent-MCP";
            license = licenses.mit;
            platforms = platforms.linux;
          };
        };
    in
    flake-utils.lib.eachSystem supportedSystems (system: {
      packages.default = agent-mcp-pkg system;
      apps.default = flake-utils.lib.mkApp { drv = agent-mcp-pkg system; };
    })
    // {

      # Модуль NixOS для декларативной интеграции
      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.services.agent-mcp;
          serverPkg = config.system.packageSets.nixpkgs.legacyPackages.${config.system}.agent-mcp;
        in
        {
          options.services.agent-mcp = {
            enable = lib.mkEnableOption "Agent-MCP Server";
            dataDir = lib.mkOption {
              type = lib.types.str;
              default = "/var/lib/agent-mcp";
              description = "Директория для хранения данных Agent-MCP";
            };
          };

          config = lib.mkIf cfg.enable {
            # Добавляем пакет в систему
            environment.systemPackages = [ serverPkg ];

            # Создаем systemd-службу
            systemd.services.agent-mcp = {
              description = "Agent-MCP Server Daemon";
              after = [ "network.target" ];
              wantedBy = [ "multi-user.target" ];

              environment = {
                AI_COMPANION_DATA_DIR = cfg.dataDir;
              };

              serviceConfig = {
                ExecStart = "${serverPkg}/bin/agent-mcp";
                Restart = "always";
                User = "mcp-agent";
                Group = "mcp-agent";
                StateDirectory = "agent-mcp";
                WorkingDirectory = cfg.dataDir;
                PrivateTmp = true;
                ProtectSystem = "full";
              };
            };

            # Создаем системного пользователя
            users.users.mcp-agent = {
              isSystemUser = true;
              group = "mcp-agent";
              home = cfg.dataDir;
              createHome = true;
            };
            users.groups.mcp-agent = { };
          };
        };
    };
}
