 # Create an S3 bucket
 resource "aws_s3_bucket" "tfstate-bucket-Pat" {
   bucket = "my-tf-state-bucket2122"

   tags = {
     Name        = "tfstate bucket"
     Environment = "Dev"
   }
 }

 # Create versioning for the S3 bucket
 resource "aws_s3_bucket_versioning" "tfstate-versioning" {
   bucket = aws_s3_bucket.tfstate-bucket-Pat.id
   versioning_configuration {
     status = "Enabled"
   }
 }


#Create a VPC
resource "aws_vpc" "pat-vpc" {
cidr_block = "10.0.0.0/16"
tags = {
Name = "pat-vpc"
}
}

#create internet gateway
resource "aws_internet_gateway" "pat-gw" {
  vpc_id = aws_vpc.pat-vpc.id

  tags = {
    Name = "pat-gw"
  }
}


#create private subnet
resource "aws_subnet" "private-subnet" {
  vpc_id     = aws_vpc.pat-vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "private-subnet"
  }
}

#create public subnet A
resource "aws_subnet" "public-subA" {
  vpc_id     = aws_vpc.pat-vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone       = "us-east-1a"

  tags = {
    Name = "public-subA"
  }
}

#create public subnet B
resource "aws_subnet" "public-subB" {
  vpc_id     = aws_vpc.pat-vpc.id
  cidr_block = "10.0.3.0/24"
  availability_zone       = "us-east-1b"

  tags = {
    Name = "public-subB"
  }
}

# Create EIP
resource "aws_eip" "pat-eip" {
  # Removed vpc = true as it's deprecated
}

#Create NAT Gateway
resource "aws_nat_gateway" "nat-gw" {
  allocation_id = aws_eip.pat-eip.id
  subnet_id     = aws_subnet.public-subA.id
}


resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private-subnet.id
  route_table_id = aws_route_table.private.id
}

# Route Table for Private Subnet
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.pat-vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat-gw.id
  }
}

# Route Table for Public Subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.pat-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.pat-gw.id
  }
}

resource "aws_route_table_association" "public-subA" {
  subnet_id      = aws_subnet.public-subA.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public-subB" {
  subnet_id      = aws_subnet.public-subB.id
  route_table_id = aws_route_table.public.id
}


#Creare a security group
resource "aws_security_group" "pat-sg" {
 name        = "pat-sg"
 description = "Allow SSH and HTTP to web server"
 vpc_id      = aws_vpc.pat-vpc.id

 ingress {
   description = "HTTP ingress"
   from_port   = 80
   to_port     = 80
   protocol    = "tcp"
   cidr_blocks = ["0.0.0.0/0"]
 }

 ingress {
   description = "SSH ingress"
   from_port   = 22
   to_port     = 22
   protocol    = "tcp"
   cidr_blocks = ["0.0.0.0/0"]
 }

 egress {
   from_port   = 0
   to_port     = 0
   protocol    = "-1"
   cidr_blocks = ["0.0.0.0/0"]
 }
}

resource "aws_iam_role" "ec2_role" {
  name = "ec2_role"

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

# IAM Role Policy
resource "aws_iam_role_policy" "ec2_policy" {
  name = "ec2_policy"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:s3:::my-tf-state-bucket2122/*"  # Replace with your S3 bucket name
      }
    ]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2_instance_profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_launch_template" "web-server" {
  name_prefix   = "web-server"
  image_id      = "ami-005fc0f236362e99f" 
  instance_type = "t2.micro"
  key_name      = "pub KP"
  vpc_security_group_ids = [aws_security_group.pat-sg.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt update -y
              apt install -y apache2
              systemctl start apache2
              systemctl enable apache2
              echo "August batch class assessment." > /var/www/html/index.html
              EOF
              )

iam_instance_profile {
    name = aws_iam_instance_profile.ec2_instance_profile.name
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "web_asg" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = [aws_subnet.private-subnet.id]

  launch_template {
    id      = aws_launch_template.web-server.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "web-instance"
    propagate_at_launch = true
  }
}

# Auto Scaling Policy
resource "aws_autoscaling_policy" "scale_out" {
  name                   = "scale-out"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.web_asg.name
}

resource "aws_autoscaling_policy" "scale_in" {
  name                   = "scale-in"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.web_asg.name
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_actions       = [aws_autoscaling_policy.scale_out.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name          = "low-cpu"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 60
  alarm_actions       = [aws_autoscaling_policy.scale_in.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_asg.name
  }
}

# Load Balancer
resource "aws_lb" "main" {
  name               = "main-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.pat-sg.id]
  subnets            = [aws_subnet.public-subA.id, aws_subnet.public-subB.id]
}

# Target Group
resource "aws_lb_target_group" "pat-tg" {
  name     = "pat-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.pat-vpc.id
  health_check {
    path                = "/health"  # Make sure this matches your application's health endpoint
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.pat-tg.arn
  }
}

# Auto Scaling Group Attachment
resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.web_asg.name
  lb_target_group_arn   = aws_lb_target_group.pat-tg.arn
  depends_on = [
    aws_lb.main,
    aws_lb_target_group.pat-tg
  ]
}

output "load_balancer_dns_name" {
  value = aws_lb.main.dns_name
}







