local M = {}

-- Mason installs these alongside the servers managed by mason-lspconfig.
-- Pint and laravel-ls also need a PHP runtime on PATH.
local packages = { "laravel-ls", "stylua", "prettier", "pint", "blade-formatter" }

function M.setup(on_ready)
  local registry = require("mason-registry")
  local function install()
    for _, name in ipairs(packages) do
      local ok, package = pcall(registry.get_package, name)
      if not ok then
        vim.notify(
          "Mason package unavailable: " .. name .. ". Run :MasonUpdate and reopen Neovim.",
          vim.log.levels.WARN
        )
      elseif package:is_installed() then
        on_ready(name)
      else
        package:once(
          "install:success",
          vim.schedule_wrap(function()
            on_ready(name)
          end)
        )
        if not package:is_installing() then
          package:install()
        end
      end
    end
  end

  for _, name in ipairs(packages) do
    if not registry.has_package(name) then
      registry.refresh(vim.schedule_wrap(install))
      return
    end
  end
  install()
end

return M
