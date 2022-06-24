local cjson = require("cjson.safe").new()
cjson.decode_array_with_array_mt(true)


local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")
local encode_args = require("ngx").encode_args
local decode_args = require("ngx").decode_args
local json_encode = cjson.encode
local json_decode = cjson.decode
local aws_v4      = require("kong.plugins." .. plugin_name .. ".v4")
local fmt         = string.format
local kong        = kong
local ipairs      = ipairs

local pairs    = pairs
local concat   = table.concat
local tostring = tostring

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

local function move_values(tbl1, tbl2, keys)
  for _,k in ipairs(keys) do
    tbl1[k] = tbl2[k] and tbl2[k] or nil
    tbl2[k] = nil
  end
  return tbl1, tbl2
end

local tbl_attributes = {
  '.Name',
  '.Value.StringValue',
  '.Value.DataType'
}

function _M.execute(conf)

  local override_content_type = false
  if kong.request.get_header("Content-Type") == "application/x-amz-json-1.1" then
    kong.service.request.set_header('Content-Type', 'application/json')
    override_content_type = true
  end

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

  if override_content_type then
    mimetype = "application/x-amz-json-1.1"
  end
  if conf.force_content_type_amz_json then
    mimetype = "application/x-amz-json-1.1"
  end

  if conf.querystring_to_payload then
    if not body[conf.body_payload_key] then
      body[conf.body_payload_key]={}
    end
    for _,map in pairs(conf.querystring_to_payload) do
      local qs, key = map:match("^([^:]+):*(.-)$")
      body[conf.body_payload_key][key] = kong.request.get_query_arg(qs)
      local tbl_qs=decode_args(kong.request.get_raw_query())
      tbl_qs[qs]=nil
      kong.service.request.set_raw_query(encode_args(tbl_qs))
    end
  end

  -- Override body with conf values
  if conf.override_body then
    for _,map in pairs(conf.override_body) do
      local key, value = map:match("^([^:]+):*(.-)$")
      body[key] = value
    end
  end

  -- Override headers with conf values
  if conf.override_headers then
    for _,map in pairs(conf.override_headers) do
      local key, value = map:match("^([^:]+):*(.-)$")
      kong.service.request.set_header(key, value)
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

  local request_payload = nil
  if body[conf.body_payload_key] then
    request_payload = json_encode(body[conf.body_payload_key])
    body[conf.body_payload_key]=nil
  end

  if conf.body_as_message_for_sns_sqs and ((service == "sqs" and body["Action"]=="SendMessage") or (service == "sns" and body["Action"]=="Publish")) then
    local new_body = {}
    new_body, body = move_values(new_body, body, { "Action", "Version", "X-Amz-Algorithm", "X-Amz-Credential", "X-Amz-Date", "X-Amz-Security-Token", "X-Amz-Signature", "X-Amz-SignedHeaders" })
    if service == 'sqs' then
      new_body, body = move_values(new_body, body, { "DelaySeconds", "MessageAttribute", "MessageDeduplicationId", "MessageGroupId", "MessageSystemAttribute", "QueueUrl" })
      new_body["MessageBody"]=json_encode(body)
    end
    if service == 'sns' then
      new_body, body = move_values(new_body, body, { "MessageAttributes", "MessageStructure", "PhoneNumber", "Subject", "TargetArn", "TopicArn" })
      new_body["Message"]=json_encode(body)
    end
    body=new_body
  end

  if (service == 'sqs' and not body["MessageBody"]) or (service == 'sns' and not body["Message"]) then
    kong.response.exit(400, "configure body_as_message_for_sns_sqs or send MessageBody for SQS or Message for SNS")
  end


  if ((conf['message_attributes_from_payload']) and (service == 'sqs' or service == 'sns')) then
    local attribute_prefix = (service == 'sqs') and 'MessageAttribute.' or 'MessageAttributes.member.'
    local body_key = (service == 'sqs') and 'MessageBody' or 'Message'
    local message_body = json_decode(body[body_key])
    local aux = {}
    for _,configs in ipairs(conf['message_attributes_from_payload']) do
      if (configs['nasted_path']) then
        kong.response.exit(400, 'nasted_path in message_attributes_from_payload is not implemented yet')
      end
      if (configs['attribute_data_type'] == 'Binary') then
        kong.response.exit(400, 'attribute_data_type in message_attributes_from_payload only supports "String", "String.Array" and "Number" for now')
      end

      if message_body[configs['payload_path']] then
        aux[(#aux+1)] = {
          ['attribute_prefix'] = attribute_prefix,
          [tbl_attributes[1]] = configs['attribute_name'],
          [tbl_attributes[2]] = tostring(message_body[configs['payload_path']]),
          [tbl_attributes[3]] = configs['attribute_data_type']
        }
      elseif configs['fallback_value'] then
        aux[(#aux+1)] = {
          ['attribute_prefix'] = attribute_prefix,
          [tbl_attributes[1]] = configs['attribute_name'],
          [tbl_attributes[2]] = tostring(configs['fallback_value']),
          [tbl_attributes[3]] = configs['attribute_data_type']
        }
      end
      if (configs['erase_from_payload']) then
        kong.response.exit(400, 'erase_from_payload in message_attributes_from_payload is not implemented yet')
      end
    end
    for index,tbl in ipairs(aux) do
      body[concat({tbl['attribute_prefix'], tostring(index), tbl_attributes[1]})] = tbl[tbl_attributes[1]]
      body[concat({tbl['attribute_prefix'], tostring(index), tbl_attributes[2]})] = tbl[tbl_attributes[2]]
      body[concat({tbl['attribute_prefix'], tostring(index), tbl_attributes[3]})] = tbl[tbl_attributes[3]]
    end
  end

  local query = encode_args(body)
  if (conf.force_content_type_form_urlencoded) and ((service == 'sns') or (service == 'sqs')) and (not request_payload) then
    if (service == 'sqs') then
      body['QueueUrl']='https://'..host..path
      path="/"
    end
    query = ""
    request_payload = encode_args(body)
    mimetype = "application/x-www-form-urlencoded; charset=utf-8"
  end

  local headers = {
    ["Content-Type"] = mimetype,
    ["Accept"] = "application/json"
  }

  if request_payload then
    headers["Content-Length"] = tostring(#request_payload)
  end

  -- Prepare "opts" table used in the request
  local opts = {
    region = region,
    service = service,
    method = AWS_METHOD,
    headers = headers,
    path = path,
    host = host,
    port = AWS_PORT,
    query = query,
    body = request_payload
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

  local header_target = kong.request.get_header("X-Amz-Target")
  if header_target then
    opts.headers['X-Amz-Target']=header_target
  end

  -- Prepare the request based on the "opts" table
  local req, err = aws_v4(opts)
  if err then
    return kong.response.exit(400, err)
  end

  kong.service.request.set_method(req.method)
  kong.service.request.set_scheme("https")
  if req.target == "/?" then 
    req.target = "/"
  end
  kong.service.request.set_path(req.target)

  if conf.api_prefix then
    kong.service.set_target('api.' .. req.host, req.port)
  else
    kong.service.set_target(req.host, req.port)
  end

  if request_payload then
    kong.service.request.set_raw_body(request_payload)
  else
    kong.service.request.set_raw_body('')
  end

  kong.service.request.set_headers(req.headers)

  -- Used for debug:
  -- kong.service.set_target("postman-echo.com", req.port)
  -- kong.service.request.set_path("/post" .. req.target)
  
  -- Used for debug without leaking keys
  -- kong.response.exit(200, req)

end

return _M
