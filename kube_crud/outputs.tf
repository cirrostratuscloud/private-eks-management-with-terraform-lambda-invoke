output "function_name" {
  description = "Name of the kube-crud Lambda function."
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN of the kube-crud Lambda function."
  value       = aws_lambda_function.this.arn
}

output "role_arn" {
  description = "ARN of the Lambda role (granted cluster-admin via EKS access entry)."
  value       = aws_iam_role.lambda.arn
}

output "security_group_id" {
  description = "Security group ID attached to the Lambda."
  value       = aws_security_group.lambda.id
}
