package = "kong-simple-aws-proxy"
version = "0.0.10-0"

source = {
 url    = "git@github.com:carnei-ro/kong-simple-aws-proxy.git",
 branch = "master"
}

description = {
  summary = "kong plugin to modify and assing requests (v4) for aws",
}

dependencies = {
  "lua ~> 5.1"
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.kong-simple-aws-proxy.iam-ecs-credentials"] = "src/iam-ecs-credentials.lua",
    ["kong.plugins.kong-simple-aws-proxy.iam-ec2-credentials"] = "src/iam-ec2-credentials.lua",
    ["kong.plugins.kong-simple-aws-proxy.v4"] = "src/v4.lua",
    ["kong.plugins.kong-simple-aws-proxy.access"] = "src/access.lua",
    ["kong.plugins.kong-simple-aws-proxy.schema"] = "src/schema.lua",
    ["kong.plugins.kong-simple-aws-proxy.handler"] = "src/handler.lua",
  }
}