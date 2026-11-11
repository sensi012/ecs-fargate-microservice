output "ecr_repository_name" {
  value = aws_ecr_repository.main.name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.main.repository_url
}

output "ecr_registry" {
  value = split("/", aws_ecr_repository.main.repository_url)[0]
}

output "alb_dns_name" {
  value = aws_lb.api.dns_name
}

output "api_url" {
  value = "http://${aws_lb.api.dns_name}"
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  value = var.enable_service ? aws_ecs_service.api[0].name : null
}

output "target_group_arn" {
  value = aws_lb_target_group.api.arn
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.api.name
}
