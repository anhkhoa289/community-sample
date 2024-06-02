terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4.2"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
  profile = "wewatt"
  default_tags {
    tags = {
      Environment = "mix"
      Project = "Zerus"
      Name = "Zerus resource"
    }
  }
}





data "aws_iam_policy_document" "aws_elasticbeanstalk_ec2_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}
resource "aws_iam_role" "aws_elasticbeanstalk_ec2_role" {
  name                = "aws-elasticbeanstalk-ec2-role"
  assume_role_policy  = data.aws_iam_policy_document.aws_elasticbeanstalk_ec2_assume_role.json
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkService",
    "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth",
  ]
}

resource "aws_iam_instance_profile" "aws_elasticbeanstalk_instance_profile" {
  name = "aws-elasticbeanstalk-instance-profile"
  role = aws_iam_role.aws_elasticbeanstalk_ec2_role.name
}

resource "aws_elastic_beanstalk_application" "zerus_app" {
  name        = "zerus-app"
  description = "zerus-app"
}

resource "aws_elastic_beanstalk_configuration_template" "zerus_docker_app_template" {
  name                = "zerus-docker-app-template"
  application         = aws_elastic_beanstalk_application.zerus_app.name
  # https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/concepts.platforms.html
  solution_stack_name = "64bit Amazon Linux 2023 v4.3.2 running Docker"

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.aws_elasticbeanstalk_instance_profile.name
  }
  # https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/command-options-general.html
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = "t3.small"
  }
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "RootVolumeType"
    value     = "gp3"
  }
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "RootVolumeSize"
    value     = "20"
  }
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "RootVolumeIOPS"
    value     = "3000"
  }
  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MinSize"
    value     = "1"
  }
  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MaxSize"
    value     = "1"
  }

  depends_on = [
    aws_elastic_beanstalk_application.zerus_app,
  ]
}




locals {
  zerus_app_version_name = "zerus-docker-app-v1"
}

resource "aws_s3_bucket" "app_bucket" {
  bucket = "zerus-app-version"
}

data "archive_file" "dockerzip" {
  type        = "zip"
  source_dir = "docker"
  output_path = "docker.zip"
}

resource "aws_s3_object" "dockerzip_object" {
  bucket        = aws_s3_bucket.app_bucket.id
  key           = "beanstalk/docker.zip"
  source        = data.archive_file.dockerzip.output_path
  etag          = data.archive_file.dockerzip.output_md5
  force_destroy = true
}

resource "aws_elastic_beanstalk_application_version" "zerus_docker_app_v1" {
  name        = local.zerus_app_version_name
  application = aws_elastic_beanstalk_application.zerus_app.name
  description = "application version created by terraform"
  bucket      = aws_s3_bucket.app_bucket.id
  key         = aws_s3_object.dockerzip_object.id

  depends_on = [
    aws_elastic_beanstalk_application.zerus_app,
    aws_s3_object.dockerzip_object
  ]
}

resource "aws_elastic_beanstalk_environment" "zerus_docker_app_dev" {
  name                   = "zerus-docker-app-dev"
  application            = aws_elastic_beanstalk_application.zerus_app.name
  template_name          = aws_elastic_beanstalk_configuration_template.zerus_docker_app_template.name

  version_label          = local.zerus_app_version_name
  wait_for_ready_timeout = "20m"
  depends_on = [
    aws_elastic_beanstalk_configuration_template.zerus_docker_app_template,
    aws_elastic_beanstalk_application_version.zerus_docker_v1,
  ]
}

output zerus_docker_app_dev_endpoint {
  value       = aws_elastic_beanstalk_environment.zerus_docker_app_dev.endpoint_url
  description = "Zerus App Dev Endpoint URL"
  depends_on  = [
    aws_elastic_beanstalk_environment.zerus_docker_app_dev
  ]
}
output zerus_docker_dev_cname  {
  value       = aws_elastic_beanstalk_environment.zerus_docker_app_dev.cname
  description = "Zerus App Dev CNAME"
  depends_on  = [
    aws_elastic_beanstalk_environment.zerus_docker_app_dev
  ]
}
