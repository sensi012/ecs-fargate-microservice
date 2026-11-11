project    = "microapi"
env        = "dev"
aws_region = "us-east-1"

# Leave image empty for bootstrap.
# During real deploy, pass -var="image=..."
image           = ""
enable_service  = false

desired_count = 1
cpu           = 256
memory        = 512

min_tasks  = 1
max_tasks  = 2
target_cpu = 70

vpc_cidr            = "10.30.0.0/16"
public_subnet_cidrs = ["10.30.0.0/24", "10.30.1.0/24"]

app_environment = {
  LOG_LEVEL = "debug"
}

# Optional overrides
# container_port            = 3000
# health_check_path         = "/health"
# alb_listener_port         = 80
# log_retention_days        = 14
# ecr_image_tag_mutability  = "IMMUTABLE"
# assign_public_ip          = true
# enable_container_insights = true