# Authored by Antoine CICHOWICZ | Github: Yris Ops
# Copyright: Apache License 2.0

variable "aws_region" {
  description = "The AWS region in which resources will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "The name of the environment (e.g., development, production)."
  type        = string
  default     = "development"
}

variable "vpc_cidr" {
  description = "The CIDR block for the Virtual Private Cloud (VPC)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets_cidr" {
  description = "CIDR blocks for the public subnets within the VPC."
  type        = list(string)
  default     = ["10.0.0.0/20", "10.0.128.0/20"]
}

variable "private_subnets_cidr" {
  description = "CIDR blocks for the private subnets within the VPC."
  type        = list(string)
  default     = ["10.0.16.0/20", "10.0.144.0/20"]
}

variable "GitHubToken" {
  description = "GitHub Token for accessing the repository."
  type        = string
  sensitive   = true
}

variable "GitHubRepo" {
  description = "The name of the GitHub repository."
  type        = string
  default     = "aws-devops-continuous-docker-deployment-to-aws-fargate"
}

variable "GitHubOwner" {
  description = "The owner/organization of the GitHub repository."
  type        = string
  default     = "Yris-ops"
}

variable "GitHubBranch" {
  description = "The branch of the GitHub repository to use."
  type        = string
  default     = "main"
}

variable "BucketName" {
  description = "The name of the S3 bucket for storing artifacts."
  type        = string
}

variable "NotificationEmail" {
  description = "The email address to receive deployment notifications."
  type        = string
}

variable "codebuild_project_name" {
  description = "The name of the CodeBuild project for building code."
  type        = string
  default     = "CodeBuildProject"
}

variable "aws_account_id" {
  description = "The AWS Account ID associated with the resources."
  type        = string
}