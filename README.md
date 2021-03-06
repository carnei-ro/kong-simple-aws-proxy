# Kong Simple AWS Proxy

## Description

summary: kong plugin to modify and assing requests (v4) for aws

## Default Values

```yaml
plugins:
- name: kong-simple-aws-proxy
  config:
    aws_key:
    aws_secret:
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
    - attribute_name: <name>
      payload_path: <key_in_payload>
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
