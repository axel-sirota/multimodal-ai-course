# Ollama Course Infrastructure

This Terraform configuration deploys an AWS EC2 instance with Ollama and Qwen3 models for an educational AI course.

## Prerequisites

- AWS CLI configured with credentials
- Terraform installed
- SSH key pair named `default_pem` in AWS us-east-1 region
- SSH private key at `~/.ssh/default_pem.pem`

## Architecture

- **EC2 Instance**: g4dn.xlarge with GPU (16GB VRAM)
- **Models**: Qwen3 8B and 4B-instruct
- **API**: Python Flask wrapper on port 8080
- **Proxy**: Nginx on port 80
- **Monitoring**: CloudWatch logs

## Deployment Steps

### 1. Deploy Infrastructure

```bash
cd terraform
terraform init
terraform apply -auto-approve
```

Wait for the instance to be created (about 2-3 minutes).

### 2. Configure Application

After the instance is running, get the hostname from terraform output and run:

```bash
# Get the instance hostname
terraform output ollama_endpoint

# Deploy the application (replace with your instance hostname)
./deploy.sh ec2-XX-XX-XX-XX.compute-1.amazonaws.com
```

### 3. Initialize Models

After deployment completes, pull the Qwen3 models (this takes 5-10 minutes):

```bash
# Get the API token
terraform output -raw api_token

# Initialize models
curl -X POST -H "Authorization: Bearer <token>" \
     http://<instance-hostname>/startup
```

### 4. Test the API

```bash
# Check health
curl http://<instance-hostname>/health

# Check GPU metrics
curl http://<instance-hostname>/metrics

# Run inference
curl -X POST -H "Authorization: Bearer <token>" \
     -H "Content-Type: application/json" \
     -d '{"prompt": "What is machine learning?"}' \
     http://<instance-hostname>/think
```

## API Endpoints

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/health` | GET | No | Health check and model list |
| `/metrics` | GET | No | GPU and system metrics |
| `/startup` | POST | Yes | Initialize default models |
| `/pull_model` | POST | Yes | Pull a specific model |
| `/serve_model` | POST | Yes | Load model into memory |
| `/think` | POST | Yes | Run inference |

## File Structure

```
terraform/
├── main.tf                 # Infrastructure definition
├── variables.tf            # Configuration variables
├── outputs.tf              # Output definitions
├── startup_minimal.sh      # EC2 user data script
├── deploy.sh              # Application deployment script
├── files/
│   ├── ollama_server.py   # Python API wrapper
│   ├── nginx.conf         # Nginx configuration
│   ├── ollama-app.service # Systemd service for Python app
│   └── ollama-override.conf # Ollama service configuration
└── README.md              # This file
```

## Monitoring

### CloudWatch Logs
```bash
aws logs tail /aws/ec2/ollama-course --follow --region us-east-1
```

### SSH Access
```bash
ssh -i ~/.ssh/default_pem.pem ubuntu@<instance-hostname>

# Check services
sudo systemctl status ollama
sudo systemctl status ollama-app
sudo systemctl status nginx

# Monitor GPU
nvidia-smi -l 1
```

## Cleanup

To destroy all resources:

```bash
terraform destroy -auto-approve
```

## Security Notes

- API token is required for inference endpoints
- Port 80 is open to all IPs (protected by token)
- Port 22 (SSH) is restricted to specific IP
- Ollama runs on localhost only (not exposed)
- All sensitive files are gitignored

## Troubleshooting

### Instance won't start
- Check AWS quotas for G4 instances
- Verify the AMI is available in us-east-1

### Models won't load
- Check GPU memory with `/metrics` endpoint
- Ensure instance has at least 16GB VRAM
- Monitor CloudWatch logs for errors

### Connection refused
- Verify security group allows port 80
- Check nginx is running: `sudo systemctl status nginx`
- Ensure deploy.sh completed successfully

## Cost Estimation

- **Instance**: g4dn.xlarge (~$0.526/hour)
- **Storage**: 100GB gp3 (~$8/month)
- **Data Transfer**: Varies by usage

Remember to stop or terminate the instance when not in use!