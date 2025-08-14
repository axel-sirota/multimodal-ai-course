terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Security group - just open port 11434 for Ollama
resource "aws_security_group" "ollama_sg" {
  name        = "ollama-course-sg"
  description = "Security group for Ollama"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # HTTP access
    description = "HTTP"
  }
  
  ingress {
    from_port   = 11434
    to_port     = 11434
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Ollama API (backup)
    description = "Ollama API"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IAM role for EC2 instance to write to CloudWatch
resource "aws_iam_role" "ollama_role" {
  name = "ollama-course-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# IAM role policy for CloudWatch
resource "aws_iam_role_policy" "ollama_cloudwatch_policy" {
  name = "ollama-cloudwatch-policy"
  role = aws_iam_role.ollama_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

# Instance profile
resource "aws_iam_instance_profile" "ollama_profile" {
  name = "ollama-course-profile"
  role = aws_iam_role.ollama_role.name
}

# CloudWatch Log Group - single stream for simplicity
resource "aws_cloudwatch_log_group" "ollama_logs" {
  name              = "/aws/ec2/ollama-course"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_stream" "main" {
  name           = "main"
  log_group_name = aws_cloudwatch_log_group.ollama_logs.name
}

# Latest Deep Learning AMI
data "aws_ami" "deep_learning" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Deep Learning AMI GPU PyTorch * (Ubuntu 20.04)*"]
  }
}

# EC2 instance
resource "aws_instance" "ollama_server" {
  ami           = data.aws_ami.deep_learning.id
  instance_type = var.instance_type
  
  key_name = var.ssh_key_name
  
  vpc_security_group_ids = [aws_security_group.ollama_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ollama_profile.name
  
  root_block_device {
    volume_size = 100
    volume_type = "gp3"
  }

  user_data = file("${path.module}/startup_minimal.sh")

  tags = {
    Name = "ollama-course"
  }
  
  depends_on = [
    aws_cloudwatch_log_group.ollama_logs,
    aws_cloudwatch_log_stream.main
  ]
}

# Elastic IP
resource "aws_eip" "ollama_ip" {
  instance = aws_instance.ollama_server.id
}