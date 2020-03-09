local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")
local encode_args = require("ngx").encode_args
local aws_v4      = require("kong.plugins." .. plugin_name .. ".v4")
local fmt         = string.format
local kong        = kong

local _M = {}

local IAM_CREDENTIALS_CACHE_KEY = "plugin." .. plugin_name .. ".iam_role_temp_creds"
local AWS_PORT = 443
local AWS_METHOD = "POST"

local fetch_credentials
do
  local credential_sources = {
    require("kong.plugins." .. plugin_name .. ".iam-ecs-credentials"),
    -- The EC2 one will always return `configured == true`, so must be the last!
    require("kong.plugins." .. plugin_name .. ".iam-ec2-credentials"),
  }

  for _, credential_source in ipairs(credential_sources) do
    if credential_source.configured then
      fetch_credentials = credential_source.fetchCredentials
      break
    end
  end
end

function _M.execute(conf)

  -- Get body with specific Content-Type "application/json"
  local body, err, mimetype = kong.request.get_body()
  if err then
    if (err == 'missing content type' and not body) then
      -- It looks like a request without body, all parameters should be at conf.override_body
      body={}
      mimetype="application/json"
    else
      kong.response.exit(400, err)
    end
  end
  if not mimetype == "application/json" then
    kong.response.exit(400, { message="Only Content-Type application/json supported" })
  end

  -- Override body with conf values
  if conf.override_body then
    for _,map in pairs(conf.override_body) do
      local key, value = map:match("^([^:]+):*(.-)$")
      body[key] = value
    end
  end

  -- Set "service" and "region" from body
  if not (body[conf.body_service_key] and body[conf.body_region_key]) then
    kong.response.exit(400, { message="Payload does not contains " .. conf.body_service_key .. " and/or " .. conf.body_region_key })
  end
  local service = body[conf.body_service_key]
  local region = body[conf.body_region_key]
  body[conf.body_service_key] = nil
  body[conf.body_region_key]  = nil

  -- Set host and path based on the kong service
  local host = fmt("%s.%s.amazonaws.com", service, region)
  local kong_service = kong.router.get_service()
  local path = kong_service['path'] or '/'

  -- Override path
  if conf.override_path_via_body then
    path = body[conf.body_path_key]
    if not path then
      kong.response.exit(400, { message="override_path_via_body true but body does not contains " .. conf.body_path_key })
    end
  end

  if body[conf.body_path_key] then
    body[conf.body_path_key]=nil
  end

  -- Prepare "opts" table used in the request
  local opts = {
    region = region,
    service = service,
    method = AWS_METHOD,
    headers = {
      ["Content-Type"] = mimetype,
      ["Accept"] = "application/json"
    },
    path = path,
    host = host,
    port = AWS_PORT,
    query = encode_args(body),
  }

  -- Get AWS Access and Secret Key from conf or AWS Access, Secret Key and Token from cache or iam role
  if not conf.aws_key then
    -- no credentials provided, so try the IAM metadata service
    local iam_role_credentials = kong.cache:get(
      IAM_CREDENTIALS_CACHE_KEY,
      nil,
      fetch_credentials
    )

    if not iam_role_credentials then
      return kong.response.exit(500, {
        message = "Could not set access_key, secret_key and/or session_token"
      })
    end

    opts.access_key = iam_role_credentials.access_key
    opts.secret_key = iam_role_credentials.secret_key
    opts.headers["X-Amz-Security-Token"] = iam_role_credentials.session_token

  else
    opts.access_key = conf.aws_key
    opts.secret_key = conf.aws_secret
  end

  -- Prepare the request based on the "opts" table
  local req, err = aws_v4(opts)
  if err then
    return kong.response.exit(400, err)
  end

  kong.service.request.set_method(req.method)
  kong.service.request.set_scheme("https")
  kong.service.request.set_path(req.target)
  kong.service.set_target(req.host, req.port)
  kong.service.request.set_raw_body('')
  kong.service.request.set_headers(req.headers)

  -- Used for debug:
  -- kong.service.set_target("httpbin.org", req.port)
  -- kong.service.request.set_path("/anything" .. req.target)
  
  -- Used for debug without leaking keys
  -- kong.response.exit(200, req)

end

return _M
