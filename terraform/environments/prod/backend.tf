terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "my-terraform-state-bucket"
    key          = "prod/terraform.tfstate" # was "/terraform.tfstate" — leading slash created an object at the bucket root with a literal "/" in its name
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true
  }
}