{
  description = "NixOS Flake для RAG-сервера Agent-MCP со всеми зависимостями";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils }:
    let
      systemOutputs = utils.lib.eachDefaultSystem (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          packages.default = pkgs.python313Packages.buildPythonApplication {
            pname = "agent-mcp";
            version = "0.1.0";
            src = ./.;

            format = "other";

            # Полный список системных Python-пакетов, необходимых для работы сервера
            propagatedBuildInputs = with pkgs.python313Packages; [
              click
              fastapi
              uvicorn
              requests
              pydantic
              python-dotenv     # ДОБАВЛЕНО: Решает ошибку "No module named 'dotenv'"
              anthropic         # ДОБАВЛЕНО: SDK для работы ИИ-агента
              mcp               # ДОБАВЛЕНО: Базовый протокол Model Context Protocol
              rich              # ДОБАВЛЕНО: Форматирование логов сервера
            ];

            nativeBuildInputs = [ pkgs.makeWrapper ];

            installPhase = ''
              runHook preInstall

              mkdir -p $out/${pkgs.python313.sitePackages}/agent_mcp
              mkdir -p $out/bin

              cp -r agent_mcp/* $out/${pkgs.python313.sitePackages}/agent_mcp/

              makeWrapper ${pkgs.python313}/bin/python $out/bin/agent-mcp \
                --add-flags "-m agent_mcp.cli" \
                --prefix PYTHONPATH : "$out/${pkgs.python313.sitePackages}" \
                --prefix PYTHONPATH : "$PYTHONPATH"

              runHook postInstall
            '';

            doCheck = false;
            meta.mainProgram = "agent-mcp";
          };

          apps.default = utils.lib.mkApp { drv = self.packages.${system}.default; };
        });
    in
    systemOutputs // {
      nixosModules.default = { config, lib, pkgs, ... }: 
        let
          cfg = config.services.agent-mcp;
        in {
          options.services.agent-mcp = {
            enable = lib.mkEnableOption "Agent-MCP Server";
          };

          config = lib.mkIf cfg.enable {
            environment.systemPackages = [
              self.packages.${pkgs.system}.default
            ];
          };
        };
    };
}
