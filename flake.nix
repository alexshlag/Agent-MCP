{
  description = "NixOS Flake для RAG-сервера Agent-MCP";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils }:
    let
      # Создаем выходы для стандартных систем
      systemOutputs = utils.lib.eachDefaultSystem (system:
        let
          pkgs = import nixpkgs { inherit system; };
          
          # Описываем сам Python-пакет и его зависимости из nixpkgs
          agent-mcp-pkg = pkgs.python313Packages.buildPythonApplication {
            pname = "agent-mcp";
            version = "0.1.0";
            src = ./.;

            # NixOS не требует requirements.txt, мы берем чистые пакеты из репозитория:
            propagatedBuildInputs = with pkgs.python313Packages; [
              click
              fastapi
              uvicorn
              requests
              # Если сервер использует pydantic или mcp, NixOS подтянет их:
              pydantic
            ];

            # Отключаем тесты при сборке пакета, чтобы ускорить процесс
            doCheck = false;

            # Указываем Nix, как именно запускать приложение. 
            # Скрипт создаст бинарник, выполняющий "python -m agent_mcp.cli"
            meta.mainProgram = "agent-mcp";
          };
        in
        {
          packages.default = agent-mcp-pkg;
          apps.default = utils.lib.mkApp { drv = agent-mcp-pkg; };
        });
    in
    # Добавляем модуль NixOS, чтобы вы могли подключить его точно так же, 
    # как и ваш long-term-memory-mcp
    systemOutputs // {
      nixosModules.default = { config, lib, pkgs, ... }: 
        let
          cfg = config.services.agent-mcp;
        in {
          options.services.agent-mcp = {
            enable = lib.mkEnableOption "Agent-MCP Server";
            # Здесь можно расширить опции (порты, папки баз данных и т.д.)
          };

          config = lib.mkIf cfg.enable {
            # Добавляем пакет в систему, чтобы команда была доступна глобально
            environment.systemPackages = [
              self.packages.${pkgs.system}.default
            ];
          };
        };
    };
}
