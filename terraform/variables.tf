variable "aws_region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "g4dn.xlarge" # 1 GPU, 16GB VRAM
}

variable "api_token" {
  description = "Simple token for API access"
  default     = "4cbd67c87dd9080c464f0427547942eee4b1a9b76ddf6eec241f0ca60fbea2db"
}