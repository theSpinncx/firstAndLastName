provider "aws" {
        region = var.region-master
        profile = var.profile
        alias = "region-master"
}

resource "null_resource" "compile" {
	triggers = {
		build_number = "${timestamp()}"
	}
	provisioner "local-exec" {
		command = "GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o ../target/firstLastName -ldflags '-w' ../src/firstLastName.go"
	}
}

data "archive_file" "zip" {
	type	= "zip"
	source_file = "../target/firstLastName"
	output_path = "../target/firstLastName.zip"
	depends_on = [null_resource.compile]
}
resource "aws_iam_role" "iam_for_lambda" {
name = "iam_for_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_lambda_function" "firstLastName-test-api-gateway" {
	function_name		= "firstLastName-api-gateway"
	handler				= "firstLastName"
	runtime				= "go1.x"
	role				= aws_iam_role.iam_for_lambda.arn
	filename			= data.archive_file.zip.output_path
	source_code_hash	= data.archive_file.zip.output_base64sha256
	memory_size			= 128
	timeout				= 10

	environment { 
		variables = {
			foo = "bar"
		}
	} 
}

 resource "aws_lambda_permission" "allow_api" {
  statement_id  = "AllowAPIgatewayInvokation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.firstLastName-test-api-gateway.function_name
  principal     = "apigateway.amazonaws.com"
}

################ API GATEWAY ################

resource "aws_api_gateway_rest_api" "test-firstLastName-api-gateway" {
  name = "test-firstLastName-api-gateway"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "person" {
  rest_api_id = aws_api_gateway_rest_api.test-firstLastName-api-gateway.id
  parent_id   = aws_api_gateway_rest_api.test-firstLastName-api-gateway.root_resource_id
  path_part   = "person"
}

// POST
resource "aws_api_gateway_method" "post" {
  rest_api_id       = aws_api_gateway_rest_api.test-firstLastName-api-gateway.id
  resource_id       = aws_api_gateway_resource.person.id
  http_method       = "POST"
  authorization     = "NONE"
  api_key_required  = false
}

resource "aws_api_gateway_integration" "integration" {
  rest_api_id             = aws_api_gateway_rest_api.test-firstLastName-api-gateway.id
  resource_id             = aws_api_gateway_resource.person.id
  http_method             = aws_api_gateway_method.post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.firstLastName-test-api-gateway.invoke_arn
}

// GET
resource "aws_api_gateway_method" "get" {
  rest_api_id       = aws_api_gateway_rest_api.test-firstLastName-api-gateway.id
  resource_id       = aws_api_gateway_resource.person.id
  http_method       = "GET"
  authorization     = "NONE"
  api_key_required  = false
}

resource "aws_api_gateway_integration" "integration-get" {
  rest_api_id             = aws_api_gateway_rest_api.test-firstLastName-api-gateway.id
  resource_id             = aws_api_gateway_resource.person.id
  http_method             = aws_api_gateway_method.get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.firstLastName-test-api-gateway.invoke_arn
}

################ Deployment of API gateway ################

resource "aws_api_gateway_deployment" "deployment1" {
  rest_api_id = aws_api_gateway_rest_api.test-firstLastName-api-gateway.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.test-firstLastName-api-gateway.body))
  }

  depends_on = [aws_api_gateway_integration.integration]
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "example" {
  deployment_id = aws_api_gateway_deployment.deployment1.id
  rest_api_id   = aws_api_gateway_rest_api.test-firstLastName-api-gateway.id
  stage_name    = var.profile
}

output "complete_unvoke_url"   {value = "${aws_api_gateway_deployment.deployment1.invoke_url}${aws_api_gateway_stage.example.stage_name}/${aws_api_gateway_resource.person.path_part}"}

