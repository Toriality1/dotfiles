-- Add this to your init.lua or dap configuration file
-- Requires nvim-dap plugin
!!!!
-- local dap = require('dap')
!!!!
-- Godot DAP adapter configuration
dap.adapters.godot = {
  type = "server",
  host = "127.0.0.1",
  port = 6006, -- Godot's default DAP port
  executable = {
    command = "nc",
    args = { "127.0.0.1", "6006" }
  }
}

-- Godot DAP configuration
dap.configurations.gdscript = {
  {
    type = "godot",
    request = "launch",
    name = "Launch Godot Project",
    project = "${workspaceFolder}",
    launch_game_instance = true,
    launch_scene = false, -- Set to true if you want to launch a specific scene
  },
  {
    type = "godot",
    request = "launch",
    name = "Launch Current Scene",
    project = "${workspaceFolder}",
    launch_game_instance = true,
    launch_scene = true,
  },
  {
    type = "godot",
    request = "attach",
    name = "Attach to Running Godot",
    project = "${workspaceFolder}",
  }
}

-- Optional: Set up keymaps for debugging
vim.keymap.set('n', '<F5>', dap.continue, { desc = 'Debug: Start/Continue' })
vim.keymap.set('n', '<F10>', dap.step_over, { desc = 'Debug: Step Over' })
vim.keymap.set('n', '<F11>', dap.step_into, { desc = 'Debug: Step Into' })
vim.keymap.set('n', '<F12>', dap.step_out, { desc = 'Debug: Step Out' })
vim.keymap.set('n', '<leader>db', dap.toggle_breakpoint, { desc = 'Debug: Toggle Breakpoint' })
vim.keymap.set('n', '<leader>dB', function()
  dap.set_breakpoint(vim.fn.input('Breakpoint condition: '))
end, { desc = 'Debug: Set Conditional Breakpoint' })

-- Auto-open dap-ui when debugging starts (if you have nvim-dap-ui)
local dap_ui_ok, dapui = pcall(require, "dapui")
if dap_ui_ok then
  dap.listeners.after.event_initialized["dapui_config"] = function()
    dapui.open()
  end
  dap.listeners.before.event_terminated["dapui_config"] = function()
    dapui.close()
  end
  dap.listeners.before.event_exited["dapui_config"] = function()
    dapui.close()
  end
end

-- Debug function to test connection
local function test_godot_dap()
  local handle = io.popen("nc -z 127.0.0.1 6006 2>&1")
  local result = handle:read("*a")
  handle:close()

  if result:match("succeeded") or result == "" then
    print("✓ Godot DAP server is reachable on port 6006")
  else
    print("✗ Cannot reach Godot DAP server on port 6006")
    print("Make sure to enable DAP in Godot: Project Settings → Debug → Settings → Remote Port = 6006")
  end
end

-- Command to test DAP connection
vim.api.nvim_create_user_command('GodotDAPTest', test_godot_dap, {})
