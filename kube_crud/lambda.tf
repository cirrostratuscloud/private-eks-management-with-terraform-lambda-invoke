resource "aws_security_group" "lambda" {
  name_prefix = "${var.name}-kube-crud-"
  description = "Kube CRUD Lambda (in-VPC access to the EKS private endpoint)"
  vpc_id      = var.vpc_id
  tags        = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "lambda_all" {
  security_group_id = aws_security_group.lambda.id
  description       = "Allow all egress (chart/image pulls, AWS APIs, EKS endpoint)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Allow the Lambda SG to reach the cluster API server on 443.
resource "aws_vpc_security_group_ingress_rule" "cluster_from_lambda" {
  security_group_id            = var.cluster_security_group_id
  description                  = "EKS API access from kube-crud Lambda"
  referenced_security_group_id = aws_security_group.lambda.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.name}-kube-crud"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_lambda_function" "this" {
  function_name = "${var.name}-kube-crud"
  description   = "Applies manifests/Helm to the private EKS cluster ${var.cluster_name}"
  role          = aws_iam_role.lambda.arn
  runtime       = var.runtime
  handler       = "handler.handler"
  architectures = [var.architecture]
  memory_size   = var.memory_size
  timeout       = var.timeout

  filename         = data.archive_file.handler.output_path
  source_code_hash = local.src_hash

  environment {
    variables = {
      CLUSTER_NAME = var.cluster_name
    }
  }

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.lambda.name
  }

  depends_on = [
    aws_iam_role_policy.lambda,
    aws_cloudwatch_log_group.lambda,
  ]

  tags = var.tags
}
