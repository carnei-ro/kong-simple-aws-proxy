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
          { body_payload_key = {
            type = "string",
            default = "RequestPayload",
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
          { api_prefix = {
            type = "boolean",
            default = false
          } },
          { force_content_type_amz_json = {
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
          } },
          { override_headers = {
            type = "array",
            elements = { type = "string", match = "^[^:]+:.*$" }
          } },
          { querystring_to_payload = {
            type = "array",
            elements = { type = "string", match = "^[^:]+:.*$" }
          } },
          { body_as_message_for_sns_sqs = {
            type = "boolean",
            default = true
          } },
          { message_attributes_from_payload = {
            type = "array",
            required = false,
            elements = {
              type = "record",
              required = false,
              fields = {
                  { attribute_name = { type = "string", required = true }, },
                  { payload_path = { type = "string", required = true }, },
                  { nasted_path = { type = "boolean", required = true, default = false }, },
                  { fallback_value = { type = "string", required = false }, },
                  { attribute_data_type = { type = "string", required = true, default='String', one_of = {
                    "String",
                    "String.Array",
                    "Number",
                    "Binary",
                    },},},
                  { erase_from_payload = { type = "boolean", default = false, required = true }, },
              }, },
            -- default = { { attribute_name = "my_attribute_name_1", payload_path = ""  } }
          } },
        },
      },
    },
  },
}
