# Terraform Security Configuration

## ⚠️ CRITICAL SECURITY REQUIREMENTS

### 1. Never Commit Sensitive Data

The following files contain sensitive information and should **NEVER** be committed to git:

- `terraform.tfvars` - Contains your API tokens, SSH key names, and IP addresses
- `*.pem` files - Your SSH private keys
- `*.tfstate*` files - May contain sensitive outputs

### 2. Required Setup

1. **Copy the example file:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit terraform.tfvars with your actual values:**
   ```hcl
   # AWS Configuration
   aws_region = "us-east-1"
   instance_type = "g4dn.xlarge"
   
   # Security Configuration (SENSITIVE)
   api_token = "your-secure-random-64-character-token-here"
   ssh_key_name = "your-aws-keypair-name"
   allowed_ssh_cidr = "YOUR.IP.ADDRESS.HERE/32"
   ```

3. **Set environment variables for deployment:**
   ```bash
   export SSH_KEY=~/.ssh/your-key.pem
   export API_TOKEN="your-secure-token"
   ```

### 3. Terraform Variables Security

#### ✅ Secure Variables (in terraform.tfvars)
- `api_token` - Marked as `sensitive = true`
- `ssh_key_name` - Marked as `sensitive = true` 
- `allowed_ssh_cidr` - Marked as `sensitive = true`

#### ✅ Safe Variables (can have defaults)
- `aws_region` - Public configuration
- `instance_type` - Public configuration

### 4. Deployment Security

The `deploy.sh` script now requires environment variables instead of hardcoded defaults:

```bash
# ❌ OLD (insecure - hardcoded defaults)
SSH_KEY="${SSH_KEY:-~/.ssh/default_pem.pem}"
API_TOKEN="${API_TOKEN:-hardcoded-token}"

# ✅ NEW (secure - required environment variables)
if [ -z "$SSH_KEY" ]; then
    echo "Error: SSH_KEY environment variable is required"
    exit 1
fi

if [ -z "$API_TOKEN" ]; then
    echo "Error: API_TOKEN environment variable is required"
    exit 1
fi
```

### 5. .gitignore Protection

The following entries in `.gitignore` protect sensitive data:

```gitignore
# Terraform sensitive files
*.tfvars
*.tfvars.json
*.tfstate
*.tfstate.*

# SSH Keys
*.pem
*.key
*.pub

# API keys and secrets
*secret*
*token*
.env.local
```

### 6. Best Practices

1. **Generate Strong API Tokens:**
   ```bash
   # Generate a secure random token
   openssl rand -hex 32
   ```

2. **Restrict SSH Access:**
   - Use your specific IP: `203.0.113.1/32` 
   - Never use `0.0.0.0/0` for SSH

3. **Rotate Credentials Regularly:**
   - Change API tokens monthly
   - Rotate SSH keys quarterly

4. **Monitor Access:**
   - Check CloudWatch logs regularly
   - Monitor EC2 instance access logs

### 7. Emergency Response

If sensitive data is accidentally committed:

1. **Immediately rotate all credentials:**
   ```bash
   # Generate new API token
   openssl rand -hex 32
   
   # Create new AWS key pair
   aws ec2 create-key-pair --key-name new-key --query 'KeyMaterial' --output text > new-key.pem
   ```

2. **Remove from git history:**
   ```bash
   git filter-branch --force --index-filter \
   "git rm --cached --ignore-unmatch terraform.tfvars" \
   --prune-empty --tag-name-filter cat -- --all
   ```

3. **Update all systems with new credentials**

4. **Force push to remove history:**
   ```bash
   git push origin --force --all
   git push origin --force --tags
   ```

## Summary

This configuration follows Terraform security best practices:
- ✅ Sensitive variables marked with `sensitive = true`
- ✅ No default values for sensitive variables
- ✅ Requires explicit configuration via terraform.tfvars
- ✅ Environment variables for deployment scripts
- ✅ Comprehensive .gitignore protection
- ✅ Clear documentation and examples

**Remember: Security is not optional in infrastructure as code!**