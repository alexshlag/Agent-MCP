{
  description = "NixOS Flake для RAG-сервера Agent-MCP";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils }:
    let
      systemOutputs = utils.lib.eachDefaultSystem (system:
        let
          pkgs = import nixpkgs { inherit system; };
          
          agent-mcp-pkg = pkgs.python313Packages.buildPythonApplication {
            pname = "agent-mcp";
            version = "0.1.0";
            src = ./.;

            # Указываем "other", чтобы Nix не искал pyproject.toml или setup.py
            format = "other";

            # Зависимости, которые Nix подтянет из репозитория
            propagatedBuildInputs = with pkgs.python313Packages; [
              click
              fastapi
              uvicorn
              requests
              pydantic
            ];

            # Вручную копируем файлы проекта в Nix-стор и создаем бинарник-обертку
            installPhase = ''
              runHook preInstall

              # Создаем структуру папок внутри хранилища Nix
              mkdir -p $out/${pkgs.python313.sitePackages}/agent_mcp
              mkdir -p $out/bin

              # Копируем исходный код сервера
              cp -r agent_mcp/* $out/${pkgs.python313.sitePackages}/agent_mcp/

              # Создаем нативный исполняемый файл для системы
              makeWrapper ${pkgs.python313}/bin/python $out/bin/agent-mcp \
                --add-flags "-m agent_mcp.cli" \
                --prefix PYTHONPATH : "$out/${pkgs.python313.sitePackages}" \
                --prefix PYTHONPATH : "$program_PYTHONPATH"

              runHook postInstall
            '';

            # Подключаем утилиту makeWrapper, необходимую для создания бинарника
            nativeBuildInputs = [ pkgs.makeWrapper ];

            doCheck = false;
            meta.mainProgram = "agent-mcp";
          };
        in
        {
          packages.default = agent-mcp-pkg;
          apps.default = utils.lib.mkApp { drv = agent-mcp-pkg; };
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
