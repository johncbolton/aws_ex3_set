provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "porknacho-vpc"
    owner = "Papi"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true 
  tags = {
    Name = "porknacho-public-subnet-1"
    owner = "Papi"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true 

  tags = {
    Name = "porknacho-public-subnet-2"
    owner = "Papi"
  }
}


resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "porknacho-igw"
    owner = "Papi"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0" 
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "porknacho-public-rt"
    owner = "Papi"
  }
}

resource "aws_route_table_association" "public_1_assoc" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}


resource "aws_route_table_association" "public_2_assoc" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb_sg" {
  name        = "porknacho-alb-sg"
  description = "Allow HTTP inbound traffic to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" 
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "porknacho-alb-sg"
    owner = "Papi"
  }
}

resource "aws_security_group" "ec2_sg" {
  name        = "porknacho-ec2-sg"
  description = "Allow HTTP from ALB and SSH to EC2 instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # WARNING: This allows SSH from anywhere. Restrict in production!
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # All protocols
    cidr_blocks = ["0.0.0.0/0"] # Allow all outbound traffic
  }

  tags = {
    Name = "porknacho-ec2-sg"
    owner = "Papi"
  }
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
resource "aws_key_pair" "web_app_key" {
  key_name   = "porknacho-key"
  public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB+S3wrjfIrlJcs6QE9cxHnIpWvNVjJPJdgmRi+8ILg+ john@LAPTOP-1B2MQN2-BOLTON"
}

resource "aws_launch_template" "webapp_lt" {
  name_prefix   = "porknacho-lt-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = "t2.micro" # Or "t3.micro" for general purpose

  key_name = aws_key_pair.web_app_key.key_name # Attach the key pair

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

# User data script to install httpd, stress, and configure index.html
user_data = base64encode(<<EOF
#!/bin/bash
yum update -y
yum install -y httpd stress

# Start and enable httpd
systemctl start httpd
systemctl enable httpd

# Create index.html with hostname and instance ID
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
HOSTNAME=$(hostname)
echo "<html><body><h1>Hello from EC2 Instance: $HOSTNAME ($INSTANCE_ID)</h1>" > /var/www/html/index.html
echo "<p>This page is served by Apache HTTP Server.</p></body></html>" >> /var/www/html/index.html

# Set appropriate permissions for index.html
chmod 644 /var/www/html/index.html
chown apache:apache /var/www/html/index.html

# You can manually run stress from SSH or uncomment below for automatic stress
# echo "Running stress for 300 seconds on one CPU core..." >> /var/log/user-data.log
# stress --cpu 1 --timeout 300 &
# echo "Stress command initiated." >> /var/log/user-data.log
EOF
  )

  tags = {
    Name = "porknacho-launch-template"
    owner = "Papi"
  }
}
resource "aws_lb_target_group" "webapp_tg" {
  name        = "porknacho-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200" # Expect HTTP 200 OK
    interval            = 30    # Check every 30 seconds
    timeout             = 5     # Timeout after 5 seconds
    healthy_threshold   = 2     # 2 consecutive successful checks for healthy
    unhealthy_threshold = 2     # 2 consecutive failed checks for unhealthy
  }

  tags = {
    Name = "porknacho-target-group"
    owner = "Papi"
  }
}


resource "aws_autoscaling_group" "webapp_asg" {
  name                      = "porknacho-asg"
  vpc_zone_identifier       = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  desired_capacity          = 2
  max_size                  = 4
  min_size                  = 1
  health_check_type         = "ELB" # Use ALB health checks
  health_check_grace_period = 300   # Give instances 5 minutes to become healthy

  # Attach the Launch Template
  launch_template {
    id      = aws_launch_template.webapp_lt.id
    version = "$Latest" # Always use the latest version of the launch template
  }

  # Attach to the Target Group
  target_group_arns = [aws_lb_target_group.webapp_tg.arn]

  # Add tags
  tag {
    key                 = "owner"
    value               = "Papi"
    propagate_at_launch = true
  }

  tag {
    key                 = "Name"
    value               = "Papi-alb-asg-instance"
    propagate_at_launch = true
  }

 enabled_metrics = ["GroupMinSize", "GroupMaxSize", "GroupDesiredCapacity", "GroupInServiceInstances", "GroupPendingInstances", "GroupTerminatingInstances", "GroupTotalInstances"]
  metrics_granularity = "1Minute"

  lifecycle {
    create_before_destroy = true 
  }
}

resource "aws_autoscaling_policy" "cpu_scaling_policy" {
  name                   = "cpu-utilization-scaling"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.webapp_asg.name
  estimated_instance_warmup  = 300

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value               = 50 # Scale out if average CPU > 50%
    disable_scale_in           = false
   
  }
}

output "vpc_id" {
  description = "ID of VPC"
  value       = aws_vpc.main.id
}
