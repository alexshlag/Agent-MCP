{
  description = "NixOS Flake для RAG-сервера Agent-MCP с корректным импортом зависимостей";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
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

            # Эти пакеты NixOS скачает и положит в изолированные папки python313Packages
            propagatedBuildInputs = with pkgs.python313Packages; [
              click
              fastapi
              uvicorn
              requests
              pydantic
            ];

            nativeBuildInputs = [ pkgs.makeWrapper ];

            installPhase = ''
              runHook preInstall

              # 1. Создаем структуру директорий в Nix-сторе
              mkdir -p $out/${pkgs.python313.sitePackages}/agent_mcp
              mkdir -p $out/bin

              # 2. Копируем исходный код
              cp -r agent_mcp/* $out/${pkgs.python313.sitePackages}/agent_mcp/

              # 3. КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Мы явно собираем пути до ВСЕХ зависимостей 
              # из propagatedBuildInputs (включая click, fastapi и т.д.) и передаем их в PYTHONPATH
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
