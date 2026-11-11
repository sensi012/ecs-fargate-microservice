############################################################
# General
############################################################

variable "project" {
  type = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.project))
    error_message = "Project must be lowercase alphanumeric and may include hyphens."
  }
}

variable "env" {
  type = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.env))
    error_message = "Environment must be lowercase alphanumeric and may include hyphens."
  }
}

variable "aws_region" {
  type = string
}

variable "common_tags" {
  type    = map(string)
  default = {}
}

############################################################
# Application / container
############################################################

variable "container_name" {
  type    = string
  default = "api"
}

variable "container_port" {
  type    = number
  default = 3000
}

variable "image" {
  description = "Real container image to deploy. If empty, bootstrap_image is used."
  type        = string
  default     = ""
}

variable "bootstrap_image" {
  description = "Placeholder image used when no real image is supplied yet."
  type        = string
  default     = "public.ecr.aws/nginx/nginx:alpine"
}

variable "app_environment" {
  type    = map(string)
  default = {}
}

############################################################
# Networking
############################################################

variable "vpc_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

variable "public_subnet_cidrs" {
  type = list(string)
  default = [
    "10.30.0.0/24",
    "10.30.1.0/24"
  ]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "ALB requires at least two subnets."
  }
}

variable "alb_ingress_cidr_blocks" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "alb_egress_cidr_blocks" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "ecs_egress_cidr_blocks" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "assign_public_ip" {
  type    = bool
  default = true
}

############################################################
# Load balancer
############################################################

variable "alb_internal" {
  type    = bool
  default = false
}

variable "alb_listener_port" {
  type    = number
  default = 80
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "health_check_matcher" {
  type    = string
  default = "200"
}

variable "health_check_interval" {
  type    = number
  default = 15
}

variable "health_check_timeout" {
  type    = number
  default = 5
}

variable "healthy_threshold" {
  type    = number
  default = 2
}

variable "unhealthy_threshold" {
  type    = number
  default = 3
}

############################################################
# ECS service
############################################################

variable "enable_service" {
  type    = bool
  default = true
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "deployment_minimum_healthy_percent" {
  type    = number
  default = 100
}

variable "deployment_maximum_percent" {
  type    = number
  default = 200
}

variable "enable_container_insights" {
  type    = bool
  default = true
}

############################################################
# Autoscaling
############################################################

variable "enable_autoscaling" {
  type    = bool
  default = true
}

variable "min_tasks" {
  type    = number
  default = 1
}

variable "max_tasks" {
  type    = number
  default = 2
}

variable "target_cpu" {
  type    = number
  default = 70
}

variable "scale_in_cooldown" {
  type    = number
  default = 60
}

variable "scale_out_cooldown" {
  type    = number
  default = 60
}

############################################################
# Logging / registry
############################################################

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "ecr_image_tag_mutability" {
  type    = string
  default = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.ecr_image_tag_mutability)
    error_message = "ecr_image_tag_mutability must be either MUTABLE or IMMUTABLE."
  }
}

variable "ecr_keep_last_images" {
  type    = number
  default = 20
}