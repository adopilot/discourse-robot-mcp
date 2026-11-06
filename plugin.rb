# frozen_string_literal: true

# name: discourse-robot-mcp
# about: MCP alati za IT tim: dokumentacija u IT-Wiki, javljanje, rješavanje, zatvaranje i prebacivanje dodijeljenih tema kroz Claude, bez lozinki
# version: 0.3.0
# authors: adopilot
# url: https://github.com/adopilot/discourse-robot-mcp

enabled_site_setting :robot_mcp_enabled

module ::RobotMcp
  PLUGIN_NAME = "discourse-robot-mcp"
end

require_relative "lib/robot_mcp/secret_scanner"

after_initialize do
  require_relative "lib/robot_mcp/tools"

  RobotMcp::Tools.register!(self)
end
