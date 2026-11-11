project    = "microapi"
env        = "staging"
aws_region = "us-east-1"

image           = ""
enable_service  = false

desired_count = 2
cpu           = 512
memory        = 1024

min_tasks  = 2
max_tasks  = 4
target_cpu = 70

vpc_cidr            = "10.31.0.0/16"
public_subnet_cidrs = ["10.31.0.0/24", "10.31.1.0/24"]

app_environment = {
  LOG_LEVEL = "info"
}