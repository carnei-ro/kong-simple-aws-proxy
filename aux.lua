local ngx = require("ngx")
local write = require("pl.pretty").write
local kong = kong

local kong_service = kong.router.get_service()
kong.response.exit(200, kong_service['path'])

--ngx.say("hello from aux - edit aux.lua and run make aux-patch")
--ngx.exit(200)
