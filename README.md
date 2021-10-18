# Kong Simple AWS Proxy

## Description

summary: kong plugin to modify and assing requests (v4) for aws

## Plugin Priority

Priority: **751**

## Plugin Version

Version: **0.0.8-0**

## config

| name | type | required | validations | default |
|-----|-----|-----|-----|-----|
| aws_key | string | <pre>false</pre> |  |  |
| aws_secret | string | <pre>false</pre> |  |  |
| body_service_key | string | <pre>true</pre> |  | <pre>AWSService</pre> |
| body_payload_key | string | <pre>true</pre> |  | <pre>RequestPayload</pre> |
| body_region_key | string | <pre>true</pre> |  | <pre>AWSRegion</pre> |
| override_path_via_body | boolean | <pre>false</pre> |  | <pre>false</pre> |
| api_prefix | boolean | <pre>false</pre> |  | <pre>false</pre> |
| force_content_type_amz_json | boolean | <pre>false</pre> |  | <pre>false</pre> |
| body_path_key | string | <pre>false</pre> |  | <pre>RequestPath</pre> |
| override_body | array of strings | <pre>false</pre> | <pre>- match: ^[^:]+:.*$</pre> |  |
| override_headers | array of strings | <pre>false</pre> | <pre>- match: ^[^:]+:.*$</pre> |  |
| querystring_to_payload | array of strings | <pre>false</pre> | <pre>- match: ^[^:]+:.*$</pre> |  |
| body_as_message_for_sns_sqs | boolean | <pre>false</pre> |  | <pre>true</pre> |
| message_attributes_from_payload | array of records** | <pre>false</pre> |  |  |

### record** of message_attributes_from_payload

| name | type | required | validations | default |
|-----|-----|-----|-----|-----|
| attribute_name | string | <pre>true</pre> |  |  |
| payload_path | string | <pre>true</pre> |  |  |
| nasted_path | boolean | <pre>true</pre> |  | <pre>false</pre> |
| fallback_value | string | <pre>false</pre> |  |  |
| attribute_data_type | string | <pre>true</pre> | <pre>- one_of:<br/>  - String<br/>  - String.Array<br/>  - Number<br/>  - Binary</pre> | <pre>String</pre> |
| erase_from_payload | boolean | <pre>true</pre> |  | <pre>false</pre> |

## Default Values

```yaml
plugins:
  - name: kong-simple-aws-proxy
    enabled: true
    config:
      aws_key: ''
      aws_secret: ''
      body_service_key: AWSService
      body_payload_key: RequestPayload
      body_region_key: AWSRegion
      override_path_via_body: false
      api_prefix: false
      force_content_type_amz_json: false
      body_path_key: RequestPath
      override_body: [] # ["bodyKey:value"]
      override_headers: [] # ["headerName:value"]
      querystring_to_payload: [] # ["qsName:payloadKey"]
      body_as_message_for_sns_sqs: true
      message_attributes_from_payload:
        - attribute_name: ''
          payload_path: ''
          nasted_path: false
          fallback_value: ''
          attribute_data_type: String
          erase_from_payload: false

```

## Use

### Configure plugin - SQS/SNS (maybe others)

```yaml
plugins:
- name: kong-simple-aws-proxy
  config:
    override_path_via_body: true # If false - Path from "Service" object - Needed if body contains RequestPath
    override_body:
    - Action=SendMessage # To SQS - Only allow send messages
    - RequestPath:/000000000000/test_queue # To SQS - Only allow send to this queue
```

### Send Message to SQS

```bash
http POST localhost:8000/ \
  AWSRegion='sa-east-1' \
  AWSService='sqs' \
  RequestPath='/000000000000/prod_queue' \
  Action='SendMessage' \
  MessageBody='It Works' \
  MessageAttribute.1.Name='my_attribute_name_1' \
  MessageAttribute.1.Value.StringValue='my_attribute_value_1' \
  MessageAttribute.1.Value.DataType='String' \
  DelaySeconds=45 \
  Version='2012-11-05'
```

### Post Message to Topic

```bash
http POST localhost:8000/ \
  AWSRegion='sa-east-1' \
  AWSService='sns' \
  RequestPath='/' \
  Message='{"it": "works"}' \
  Subject='kong message' \
  MessageAttributes.member.1.Name='my_attribute_name_1' \
  MessageAttributes.member.1.Value.StringValue='my_attribute_value_1' \
  MessageAttributes.member.1.Value.DataType='String' \
  Version='2010-03-31' \
  Action='Publish' \
  TopicArn='arn:aws:sns:sa-east-1:000000000000:testtopic'  
``` 

### Configure plugin - ECR

```yaml
plugins:
- name: kong-simple-aws-proxy
  config:
    api_prefix: true # Append "api." to target host
    force_content_type_amz_json: true
    override_body:
    - AWSService:ecr
    - AWSRegion:us-east-1
    override_headers:
    - X-Amz-Target:AmazonEC2ContainerRegistry_V20150921.ListImages # Only perform ListImages
```

### List Images

```bash
curl -X POST localhost:8000/ \
  -H content-type:application/json \
  -d '{ "RequestPayload": {"repositoryName": "my-repository", "registryId": "000000000000"} }'
```
