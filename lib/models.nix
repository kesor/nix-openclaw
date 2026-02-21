{ lib }:

lib.types.submodule {
  options = {
    type = lib.mkOption {
      type = lib.types.enum [
        "anthropic"
        "openai-compatible"
        "ollama"
        "rocm"
        "remote"
      ];
      description = "Backend type for this model.";
    };
    modelName = lib.mkOption {
      type = lib.types.str;
      description = "Model identifier (e.g. `claude-sonnet-4-20250514`).";
    };
    endpoint = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "API endpoint URL. Leave empty for provider defaults.";
    };
    maxTokens = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
    };
    temperature = lib.mkOption {
      type = lib.types.nullOr lib.types.float;
      default = null;
    };
    isDefault = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Set as the default model when multiple are configured.";
    };
    extraConfig = lib.mkOption {
      type = lib.types.nullOr (lib.types.attrsOf lib.types.str);
      default = null;
      description = "Arbitrary extra key-values forwarded to the model config.";
    };
  };
}
