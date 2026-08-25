output "result" {
  description = "Lambda invocation result."
  value       = aws_lambda_invocation.this.result
}
