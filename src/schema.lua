local typedefs = require "kong.db.schema.typedefs"
local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")

return {
  name = plugin_name,
  fields = {
    {
      config = {
        type = "record",
        fields = {
          { aws_key = {
            type = "string",
          } },
          { aws_secret = {
            type = "string",
          } },
          { body_service_key = {
            type = "string",
            default = "AWSService",
            required = true
          } },
          { body_region_key = {
            type = "string",
            default = "AWSRegion",
            required = true
          } },
          { override_path_via_body = {
            type = "boolean",
            default = false
          } },
          { body_path_key = {
            type = "string",
            default = "RequestPath"
          } },
          { override_body = {
            type = "array",
            elements = { type = "string", match = "^[^:]+:.*$" }
          } }
        },
      },
    },
  },
}
