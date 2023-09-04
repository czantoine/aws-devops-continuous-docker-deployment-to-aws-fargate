# Authored by Antoine CICHOWICZ | Github: Yris Ops
# Copyright: Apache License 2.0

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.13.1"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.aws_region
}

locals {
  availability_zones = ["${var.aws_region}a", "${var.aws_region}b"]
}

resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.environment}-vpc"
    Environment = var.environment
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  count                   = length(var.public_subnets_cidr)
  cidr_block              = element(var.public_subnets_cidr, count.index)
  availability_zone       = element(local.availability_zones, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.environment}-${element(local.availability_zones, count.index)}-public-subnet"
    Environment = "${var.environment}"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  count                   = length(var.private_subnets_cidr)
  cidr_block              = element(var.private_subnets_cidr, count.index)
  availability_zone       = element(local.availability_zones, count.index)
  map_public_ip_on_launch = false

  tags = {
    Name        = "${var.environment}-${element(local.availability_zones, count.index)}-private-subnet"
    Environment = "${var.environment}"
  }
}

resource "aws_internet_gateway" "ig" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    "Name"        = "${var.environment}-igw"
    "Environment" = var.environment
  }
}

resource "aws_eip" "nat_eip" {
  vpc        = true
  depends_on = [aws_internet_gateway.ig]
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = element(aws_subnet.public_subnet.*.id, 0)

  tags = {
    Name        = "nat-gateway-${var.environment}"
    Environment = "${var.environment}"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name        = "${var.environment}-private-route-table"
    Environment = "${var.environment}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name        = "${var.environment}-public-route-table"
    Environment = "${var.environment}"
  }
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.ig.id
}

resource "aws_route" "private_internet_gateway" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnets_cidr)
  subnet_id      = element(aws_subnet.public_subnet.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnets_cidr)
  subnet_id      = element(aws_subnet.private_subnet.*.id, count.index)
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "app_sg" {
  name        = "app-security-group-alb"
  description = "Security group for the Flask app"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "Allow all traffic through port 5000"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    description = "Allow all traffic through port 80"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

   egress {
      description = "Allow all outbound traffic"
      from_port   = "0"
      to_port     = "0"
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
   }
}

resource "aws_lb" "app_alb" {
  name               = "app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.app_sg.id]
  subnets            = aws_subnet.public_subnet[*].id

  enable_deletion_protection = false

  enable_http2 = true

  enable_cross_zone_load_balancing = true
}

resource "aws_lb_target_group" "app_target_group" {
  name        = "app-target-group"
  target_type = "ip"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.vpc.id

  health_check {
    enabled             = true
    interval            = 300
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.app_target_group.arn
    type             = "forward"
  }
}

resource "aws_ecs_cluster" "app_cluster" {
  name = "app-cluster"
}

resource "aws_ecs_task_definition" "app_task" {
  family                   = "app-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name  = "app-container",
      image = "${aws_ecr_repository.ecr_repo.repository_url}",
      portMappings = [
        {
          containerPort = 5000,
          hostPort      = 5000,
        },
      ],
    },
  ])
}

data "aws_iam_policy" "aws_ecs_task_execution_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_policy" "policy" {
   name     = "ecs-Policy"
   policy   = jsonencode({
      "Version": "2012-10-17",
      "Statement": [
         {
            "Sid": "",
            "Effect": "Allow",
            "Action": [
               "ecs:ListClusters",
               "ecs:ListTaskDefinitions",
               "ecs:ListContainerInstances",
               "ecs:RunTask",
               "ecs:StopTask",
               "ecs:DescribeTasks",
               "ecs:DescribeContainerInstances",
               "ecs:DescribeTaskDefinition",
               "ecs:RegisterTaskDefinition",
               "ecs:DeregisterTaskDefinition",
               "iam:GetRole",
               "iam:PassRole"
            ],
            "Resource": "*"
         }
      ]
   })
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com",
        },
      },
    ],
  })
  
  managed_policy_arns = [
      data.aws_iam_policy.aws_ecs_task_execution_policy.arn, 
      aws_iam_policy.policy.arn
   ]
}

resource "aws_ecs_service" "app_service" {
  name            = "app-service"
  cluster         = aws_ecs_cluster.app_cluster.id
  task_definition = aws_ecs_task_definition.app_task.arn
  launch_type     = "FARGATE"
  desired_count   = 2

  network_configuration {
    subnets = aws_subnet.private_subnet[*].id

    security_groups = [aws_security_group.app_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app_target_group.arn
    container_name   = "app-container"
    container_port   = 5000
  }

  depends_on = [aws_lb_listener.app_listener]
}

resource "aws_ecr_repository" "ecr_repo" {
  name = "ecs-flaskapp"
}

locals {
  repo_endpoint = split("/", aws_ecr_repository.ecr_repo.repository_url)[0]
}

resource "null_resource" "build_and_push_image" {

  provisioner "local-exec" {
    command = <<EOF
      set -ex
      echo "--- Build image ---"
      aws ecr get-login-password --region ${var.aws_region} | \
      docker login --username AWS --password-stdin ${local.repo_endpoint} && \
      docker build -t ecs-flaskapp . --platform linux/amd64 && \
      docker tag ecs-flaskapp:latest ${aws_ecr_repository.ecr_repo.repository_url}:latest
      docker push ${aws_ecr_repository.ecr_repo.repository_url}:latest
      EOF
  }
}

resource "aws_s3_bucket" "bucket_arti" {
  bucket = var.BucketName
  acl    = "private"
}

resource "aws_iam_role" "CodePipelineRole" {
  name = "CodePipelineRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = ["codepipeline.amazonaws.com", "codebuild.amazonaws.com"]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role" "CodeBuildRole" {
  name = "CodeBuildRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = ["codebuild.amazonaws.com"]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

}

resource "aws_iam_policy" "CodePipelinePolicy" {
  name        = "CodePipelinePolicy"
  description = "IAM policy for S3, Cloudwatch Logs, SNS, ECR,  permissions for CodePipeline"

policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
          Effect   = "Allow",
          Resource = "*"
        },
        {
          Action   = ["ecr:GetAuthorizationToken","ecs:UpdateService","ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage","ecr:GetAuthorizationToken", "ecr:InitiateLayerUpload","ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage"],
          Effect   = "Allow",
          Resource = "*"
        },
        {
          Action   = ["sns:Publish"],
          Effect   = "Allow",
          Resource = "*"
        },
        {
          Action   = ["s3:*"],
          Effect   = "Allow",
          Resource = "*"
        },
        {
          Action   = ["codebuild:*"],
          Effect   = "Allow",
          Resource = "*"
        }
      ]
    }
  )
}


resource "aws_iam_policy" "CodeBuildPolicy" {
  name        = "CodeBuildPolicy"
  description = "IAM policy for S3, Cloudwatch Logs, SNS, ECR,  permissions for CodeBuild"

policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
          Effect   = "Allow",
          Resource = "*"
        },
        {
          Action   = ["ecr:GetAuthorizationToken","ecs:UpdateService","ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage","ecr:GetAuthorizationToken", "ecr:InitiateLayerUpload","ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage"],
          Effect   = "Allow",
          Resource = "*"
        },
        {
          Action   = ["sns:Publish"],
          Effect   = "Allow",
          Resource = "*"
        },
        {
          Action   = ["s3:*"],
          Effect   = "Allow",
          Resource = "*"
        }
      ]
    }
  )
}

resource "aws_iam_policy_attachment" "CodePipelinedAttachment" {
  name       = "CodePipelineAttachment"
  policy_arn = aws_iam_policy.CodePipelinePolicy.arn
  roles      = [aws_iam_role.CodePipelineRole.name]
}

resource "aws_iam_policy_attachment" "CodeBuildAttachment" {
  name       = "CodeBuildAttachment"
  policy_arn = aws_iam_policy.CodeBuildPolicy.arn
  roles      = [aws_iam_role.CodeBuildRole.name]
}

resource "aws_codebuild_project" "CodeBuildProject" {
  name     = "CodeBuildProject"
  service_role = aws_iam_role.CodeBuildRole.arn

  source {
    type      = "GITHUB"
    location  = "https://github.com/Yris-ops/aws-devops-continuous-docker-deployment-to-aws-fargate.git"
    buildspec = "buildspec.yml"
    report_build_status = "false"
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    type        = "LINUX_CONTAINER"
    compute_type = "BUILD_GENERAL1_SMALL"
    image       = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
    privileged_mode = true
  }

}

resource "aws_codebuild_webhook" "webhook" {
  project_name = aws_codebuild_project.CodeBuildProject.name
  build_type   = "BUILD"

  filter_group {
    filter {
      type    = "EVENT"
      pattern = "PUSH"
    }
  }
}

resource "aws_codepipeline_webhook" "GithubWebhook" {
  name            = "test-webhook-github"
  authentication = "GITHUB_HMAC"

  authentication_configuration {
    secret_token = var.GitHubToken
  }


  filter {
    json_path      = "$.ref"
    match_equals   = "refs/heads/{Branch}"
  }

  target_pipeline     = aws_codepipeline.CodePipeline.name
  target_action       = "Source"
}

resource "aws_codepipeline" "CodePipeline" {
  name     = "ECS-Pipeline"
  role_arn = aws_iam_role.CodePipelineRole.arn

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.bucket_arti.bucket
  }

  stage {
    name = "Source"

    action {
      name = "Source"

      category    = "Source"
      owner       = "ThirdParty"
      version     = "1"
      provider    = "GitHub"
      output_artifacts = ["SourceCode"]

      configuration = {
        Owner            = var.GitHubOwner
        Repo             = var.GitHubRepo
        Branch           = var.GitHubBranch
        OAuthToken       = var.GitHubToken
      }

      run_order = 1
    }
  }

  stage {
    name = "Build"

    action {
      name = "BuildAction"

      category    = "Build"
      owner       = "AWS"
      version     = "1"
      provider    = "CodeBuild"
      input_artifacts = ["SourceCode"]

      configuration = {
        ProjectName = aws_codebuild_project.CodeBuildProject.name
      }

      output_artifacts = ["BuildOutput"]
      run_order        = 2
    }
  }
  
}


resource "aws_sns_topic" "SnsTopicCodeBuild" {
  name = "SnsTopicCodeBuild"
}

resource "aws_iam_role" "SampleNotificationRuleRole" {
  name = "SampleNotificationRuleRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_sns_topic_policy" "SnsTopicPolicy" {
  arn    = aws_sns_topic.SnsTopicCodeBuild.arn

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sns:Publish",
        Effect = "Allow",
        Principal = {
          Service = "events.amazonaws.com"
        },
        Resource = aws_sns_topic.SnsTopicCodeBuild.arn
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "EventBridgeRule" {
  name          = "codebuild-notif"
  event_pattern = <<PATTERN
{
    "source": ["aws.codebuild"],
    "detail-type": ["CodeBuild Build State Change"],
    "detail": {
        "build-status": [
            "IN_PROGRESS",
            "SUCCEEDED", 
            "FAILED",
            "STOPPED"
        ]
    }
}
PATTERN

}

resource "aws_cloudwatch_event_target" "SnsTarget" {
  rule      = aws_cloudwatch_event_rule.EventBridgeRule.name
  target_id = "CodeBuildProject"
  arn       = aws_sns_topic.SnsTopicCodeBuild.arn
}

resource "aws_sns_topic_subscription" "SnsTopicSubscription" {
  topic_arn = aws_sns_topic.SnsTopicCodeBuild.arn
  protocol  = "email"
  endpoint  = var.NotificationEmail
}