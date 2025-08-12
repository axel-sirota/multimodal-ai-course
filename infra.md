# AWS G4 Instance with Ollama - Simple Setup

## Instructions for Instructor
Minimal Terraform setup for a G4 instance running Ollama. HTTP endpoint with token authentication for 2-day course.

## File Structure
```
terraform/
├── main.tf
├── variables.tf
├── outputs.tf
└── startup_script.sh
```

## File 1: `variables.tf`
```hcl
variable "aws_region" {
  description = "AWS region"
  default     = "us-west-2"
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "g4dn.xlarge"  # 1 GPU, 16GB VRAM
}

variable "api_token" {
  description = "Simple token for API access"
  default     = "course-invoice-2024-token"  # Change this!
}
```

## File 2: `main.tf`
```hcl
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
    from_port   = 11434
    to_port     = 11434
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Open to all (protected by token)
    description = "Ollama API"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["YOUR_IP/32"]  # Your IP for SSH
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
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
  
  key_name = "your-key-pair"  # Replace with your key
  
  vpc_security_group_ids = [aws_security_group.ollama_sg.id]
  
  root_block_device {
    volume_size = 100
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/startup_script.sh", {
    api_token = var.api_token
  })

  tags = {
    Name = "ollama-course"
  }
}

# Elastic IP
resource "aws_eip" "ollama_ip" {
  instance = aws_instance.ollama_server.id
}
```

## File 3: `startup_script.sh`
```bash
#!/bin/bash
set -e

# Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# Configure Ollama to listen on all interfaces
mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf << 'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_ORIGINS=*"
Environment="OLLAMA_NUM_PARALLEL=4"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
EOF

# Start Ollama
systemctl daemon-reload
systemctl enable ollama
systemctl start ollama

# Wait for Ollama to start
sleep 10

# Pull Qwen model (7B for good balance)
ollama pull qwen2.5:7b-instruct

# Create simple Python wrapper for token validation
cat > /home/ubuntu/token_wrapper.py << 'EOF'
from flask import Flask, request, jsonify, Response
import requests
import os

app = Flask(__name__)
TOKEN = "${api_token}"
OLLAMA_URL = "http://localhost:11434"

@app.before_request
def check_token():
    if request.path == "/health":
        return
    auth = request.headers.get('Authorization')
    if not auth or auth != f"Bearer {TOKEN}":
        return jsonify({"error": "Invalid token"}), 401

@app.route('/<path:path>', methods=['GET', 'POST', 'PUT', 'DELETE'])
def proxy(path):
    # Forward to Ollama
    url = f"{OLLAMA_URL}/{path}"
    resp = requests.request(
        method=request.method,
        url=url,
        headers={key: value for key, value in request.headers if key != 'Host'},
        data=request.get_data(),
        cookies=request.cookies,
        allow_redirects=False,
        stream=True
    )
    
    # Stream response back
    return Response(
        resp.iter_content(chunk_size=1024),
        status=resp.status_code,
        headers=dict(resp.headers)
    )

@app.route('/health')
def health():
    return "OK"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=11434, threaded=True)
EOF

# Install Flask
apt-get update
apt-get install -y python3-pip
pip3 install flask requests

# Stop Ollama default service (we'll use our wrapper)
systemctl stop ollama

# Create systemd service for wrapper
cat > /etc/systemd/system/ollama-wrapper.service << 'EOF'
[Unit]
Description=Ollama Token Wrapper
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu
ExecStartPre=/usr/bin/systemctl start ollama
ExecStart=/usr/bin/python3 /home/ubuntu/token_wrapper.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Change Ollama to listen only on localhost
sed -i 's/0.0.0.0:11434/127.0.0.1:11434/' /etc/systemd/system/ollama.service.d/override.conf
systemctl daemon-reload
systemctl restart ollama

# Start wrapper service
systemctl enable ollama-wrapper
systemctl start ollama-wrapper

echo "Setup complete!" > /home/ubuntu/setup.log
```

## File 4: `outputs.tf`
```hcl
output "ollama_endpoint" {
  value = "http://${aws_eip.ollama_ip.public_ip}:11434"
}

output "api_token" {
  value = var.api_token
  sensitive = true
}

output "python_usage" {
  value = <<-EOT
    # Python usage in Colab:
    import requests
    
    OLLAMA_URL = "http://${aws_eip.ollama_ip.public_ip}:11434"
    TOKEN = "${var.api_token}"
    
    response = requests.post(
        f"{OLLAMA_URL}/api/generate",
        headers={"Authorization": f"Bearer {TOKEN}"},
        json={
            "model": "qwen2.5:7b-instruct",
            "prompt": "What is an invoice?",
            "stream": False
        }
    )
    print(response.json())
  EOT
}
```

## Deployment

1. **Deploy**:
   ```bash
   terraform init
   terraform apply
   # Takes ~5 minutes
   ```

2. **Test**:
   ```python
   import requests
   
   OLLAMA_URL = "http://YOUR_IP:11434"
   TOKEN = "course-invoice-2024-token"
   
   # Test connection
   response = requests.get(
       f"{OLLAMA_URL}/api/tags",
       headers={"Authorization": f"Bearer {TOKEN}"}
   )
   print(response.json())
   ```

3. **Share with Students**:
   - IP address: `XX.XX.XX.XX`
   - Token: `course-invoice-2024-token`
   - That's it!

## Student Usage in Colab

```python
import requests

# Connection details from instructor
OLLAMA_URL = "http://XX.XX.XX.XX:11434"
TOKEN = "course-invoice-2024-token"

def call_llm(prompt):
    response = requests.post(
        f"{OLLAMA_URL}/api/generate",
        headers={"Authorization": f"Bearer {TOKEN}"},
        json={
            "model": "qwen2.5:7b-instruct",
            "prompt": prompt,
            "stream": False
        }
    )
    return response.json()['response']

# Test
print(call_llm("Hello!"))
```

## Monitoring

```bash
# SSH into instance
ssh ubuntu@IP_ADDRESS

# Check wrapper logs
sudo journalctl -u ollama-wrapper -f

# Check Ollama logs
sudo journalctl -u ollama -f

# GPU usage
nvidia-smi -l 1

# Test locally
curl http://localhost:11434/api/tags
```

## Cost
- g4dn.xlarge: ~$0.53/hour
- 2-day course (16 hours): ~$8.50
- Auto-shutdown after hours to save money

## Cleanup
```bash
terraform destroy
```