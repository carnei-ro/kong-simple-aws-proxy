local plugin = require("kong.plugins.base_plugin"):extend()
local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")
local access = require("kong.plugins." .. plugin_name .. ".access")

plugin.VERSION = "0.0.1-0"
plugin.PRIORITY = 751

function plugin:new()
  plugin.super.new(self, plugin_name)
end

function plugin:access(conf)
  plugin.super.access(self)
  access.execute(conf)
end

return plugin
