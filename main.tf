provider "aws" {
  region                  = "us-east-1"
  shared_credentials_file = "~/.aws/terraform"
  profile                 = "terraform"
}

data "aws_availability_zones" "all" {}

resource "aws_launch_configuration" "example" {
  image_id        = "ami-09dbd87d7fc293a64"
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.instance.id]
  user_data = <<-EOF
              #!/bin/bash
              apt install -y busybox apache2
              echo "Hello, World from $HOSTNAME" > index.html
              nohup busybox httpd -f -p "${var.server_port}" &
              EOF
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "instance" {
  name = "terraform-example-instance"
  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_autoscaling_group" "example" {
  launch_configuration = aws_launch_configuration.example.id
  availability_zones   = data.aws_availability_zones.all.names
  min_size = 3
  max_size = 10
  load_balancers    = [aws_elb.example.name]
  health_check_type = "ELB"
  tag {
    key                 = "Name"
    value               = "terraform-asg-example"
    propagate_at_launch = true
  }
}

resource "aws_elb" "example" {
  name               = "terraform-asg-example"
  security_groups    = [aws_security_group.elb.id]
  availability_zones = data.aws_availability_zones.all.names
  health_check {
    target              = "HTTP:${var.server_port}/"
    interval            = 30
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  # This adds a listener for incoming HTTP requests.
  listener {
    lb_port           = var.elb_port
    lb_protocol       = "http"
    instance_port     = var.server_port
    instance_protocol = "http"
  }
}

resource "aws_security_group" "elb" {
  name = "terraform-example-elb"
  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Inbound HTTP from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "clb_dns_name" {
  value       = aws_elb.example.dns_name
  description = "The domain name of the load balancer"
}
