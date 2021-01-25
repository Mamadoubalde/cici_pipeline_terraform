provider "aws" {
  region = "us-east-1"
  access_key = ""
  secret_key = ""
}

# 1.Create S3 static site to host the content
resource "aws_s3_bucket" "codepipeline-artifacts-mamadou" {
  bucket = "pipeline-artifacts-mamadou"
  acl    = "public-read"
  policy = file("policy.json")

  website {
    index_document = "index.html"
    error_document = "error.html"

    routing_rules = <<EOF
[{
    "Condition": {
        "KeyPrefixEquals": "docs/"
    },
    "Redirect": {
        "ReplaceKeyPrefixWith": "documents/"
    }
}]
EOF
  }
}

# 2.Create cloudfront to distribute the content from S3
# 3.Create cloudfront default to not cache
# 4.Create cloudfront cache default /min /max TTL=30min
# 5.Create cloudfront SSL enable using the default cloudfront Cert

resource "aws_s3_bucket" "codepipeline-artifacts-mamadou2" {
  bucket = "pipeline-artifacts-baldedev"
  acl    = "private"
}
locals {
  s3_origin_id = "myS3Origin"
}

data "aws_acm_certificate" "baldedev" {
  provider = "aws"
  #provider = registry.terraform.io/hashicorp/aws.global

  domain = "baldedev.com"
  statuses = ["ISSUED"]
  most_recent = true
}

resource "aws_cloudfront_distribution" "cf-distribution" {
  provider = aws.global
  count = 1

  aliases = ["baldedev.com", "www.baldedev.com"]
  price_class = "PriceClass_100"
  tags { Name = "Portfolio CDN" }
  enabled = true
  is_ipv6_enabled = true

  viewer_certificate {
    cloudfront_default_certificate = true
    #ssl_support_method = "sni-only"
    #acm_certificate_arn = "${data.aws_acm_certificate.baldedev.arn}"
  }
  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  origin {
    origin_id = "{local.s3_origin_id}"
    domain_name = aws_s3_bucket.cf-distribution.website_endpoint

    custom_origin_config {
      http_port = 80
      https_port = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols = ["TLSv1", "TLSv1.0", "TLSv1.1"]
    }
  }

  default_cache_behavior {
    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS"]
    cached_methods = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id
    viewer_protocol_policy = "allow-all"
    compress = true
    min_ttl = 1800
    default_ttl = 1800
    max_ttl = 1800

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }
}
# 6.Create codepipeline to deploy/update files for site

resource "aws_codepipeline" "codepipeline" {
  name     = "tf-test-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_bucket.bucket
    type     = "S3"

    encryption_key {
      id   = data.aws_kms_alias.s3kmskey.arn
      type = "KMS"
    }
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.example.arn
        FullRepositoryId = "Mamadoubalde/stratusGridDemo"
        BranchName       = "master"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["tf-code"]
      output_artifacts = ["build_output"]
      version          = "1"

      configuration = {
        ProjectName = "test"
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["tf-code"]
      version         = "1"

      configuration = {
        ActionMode     = "REPLACE_ON_FAILURE"
        Capabilities   = "CAPABILITY_AUTO_EXPAND,CAPABILITY_IAM"
        OutputFileName = "CreateStackOutput.json"
        StackName      = "MyStack"
        TemplatePath   = "tf-code::sam-templated.yaml"
      }
    }
  }
}

resource "aws_codestarconnections_connection" "example" {
  name          = "example-connection"
  provider_type = "GitHub"
}

resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket = "test-bucket"
  acl    = "private"
}

resource "aws_iam_role" "codepipeline_role" {
  name = "test-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codepipeline.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "codepipeline_policy"
  role = aws_iam_role.codepipeline_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect":"Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetBucketVersioning",
        "s3:PutObject"
      ],
      "Resource": [
        "${aws_s3_bucket.codepipeline_bucket.arn}",
        "${aws_s3_bucket.codepipeline_bucket.arn}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "codebuild:BatchGetBuilds",
        "codebuild:StartBuild"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

data "aws_kms_alias" "s3kmskey" {
  name = "alias/myKmsKey"
}
